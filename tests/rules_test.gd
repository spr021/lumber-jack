extends SceneTree
## Headless rules check: godot --headless --path . --script res://tests/rules_test.gd

func _initialize() -> void:
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Run once the scene has gone through a frame, so _ready is guaranteed.
	process_frame.connect(_run_checks.bind(game), CONNECT_ONE_SHOT)


func _advance(game: Node2D) -> void:
	# Step past the chop debounce without waiting for real frames.
	game.elapsed += game.CHOP_COOLDOWN + 0.01


func _run_checks(game: Node2D) -> void:
	var failures: Array[String] = []

	# Fair start: the branch at the lumberjack's height is on the other side.
	if game.segments[0] == game.Side.LEFT:
		failures.append("start: branch sits on the lumberjack's side (left)")
	if not is_equal_approx(game.time_left, game.TIME_START):
		failures.append("start: time_left should be TIME_START")

	# Chop inputs are debounced: a second chop inside CHOP_COOLDOWN is ignored.
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.score != 1 or game.combo != 1:
		failures.append("first chop should score 1 and start the combo")
	game.chop(game.Side.LEFT)
	if game.score != 1 or game.combo != 1:
		failures.append("chop inside the debounce window must be ignored")

	# A correct chop scores and pays the time reward.
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	var before: float = game.time_left
	game.chop(game.Side.LEFT)
	if game.state == game.State.DYING:
		failures.append("correct chop should not trigger death")
	if game.score != 2:
		failures.append("correct chop at combo 2 should score 1 more")
	if game.combo != 2:
		failures.append("correct chop did not build the combo")
	if game.time_left <= before:
		failures.append("correct chop did not grant time reward")

	# Chopping into a branch survives, scores nothing, drains TIME_PENALTY
	# and breaks the combo.
	_advance(game)
	game.segments[1] = game.Side.LEFT
	before = game.time_left
	game.chop(game.Side.LEFT)
	if game.state != game.State.PLAYING:
		failures.append("chop into the branch must no longer kill")
	if game.score != 2:
		failures.append("wrong chop must not score")
	if game.combo != 0:
		failures.append("wrong chop must break the combo")
	if not is_equal_approx(game.time_left, maxf(before - game.TIME_PENALTY, 0.0)):
		failures.append("wrong chop must drain TIME_PENALTY from the bar")

	# The penalty on an almost empty bar kills.
	game.time_left = 0.3
	_advance(game)
	game.segments[1] = game.Side.LEFT
	game.chop(game.Side.LEFT)
	await process_frame
	if game.state != game.State.DYING:
		failures.append("wrong chop on an almost empty bar must kill")

	# Combo multiplier tiers: every correct chop scores its multiplier, so
	# 5 chops score 1+1+1+1+2, the x3 tier starts at 10 and x4 at 20.
	game._reset()
	for i in 21:
		_advance(game)
		game.segments[1] = game.Side.RIGHT
		game.chop(game.Side.LEFT)
		match i + 1:
			5:
				if game.score != 6:
					failures.append("combo 5: expected score 6, got %d" % game.score)
			10:
				if game.score != 17:
					failures.append("combo 10: expected score 17, got %d" % game.score)
			20:
				if game.score != 48:
					failures.append("combo 20: expected score 48, got %d" % game.score)
			21:
				if game.score != 52:
					failures.append("combo 21: expected score 52, got %d" % game.score)
	if game.combo != 21:
		failures.append("21 correct chops should hold combo 21")

	# One wrong chop drops the combo back to zero...
	_advance(game)
	game.segments[1] = game.Side.LEFT
	game.chop(game.Side.LEFT)
	if game.combo != 0:
		failures.append("wrong chop must reset the combo to 0")
	# ...and the next correct chop scores only its base value again.
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.score != 53:
		failures.append("after the reset the next chop must score 1, got %d" % game.score)

	# The reward is capped at TIME_MAX.
	game.time_left = game.TIME_MAX
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.time_left > game.TIME_MAX + 0.0001:
		failures.append("time reward exceeded TIME_MAX")

	# A bare segment (no branch on either side) is safe from both sides: a
	# chop from either side scores and keeps the combo.
	game._reset()
	_advance(game)
	game.segments[1] = game.Side.NONE
	game.chop(game.Side.LEFT)
	if game.score != 1 or game.combo != 1:
		failures.append("chop left on a bare segment must score")
	_advance(game)
	game.segments[1] = game.Side.NONE
	game.chop(game.Side.RIGHT)
	if game.score != 2 or game.combo != 2:
		failures.append("chop right on a bare segment must score too")

	# Bare segments are rare: ~1 in 10 rolls on average, and never two in a
	# row so the trunk never reads as broken. The loop appends every roll like
	# the real stack does, since the guard reads the previous segment.
	game.segments = [game.Side.RIGHT]
	seed(12345)
	var bare := 0
	var consecutive := false
	for i in 20000:
		var s: int = game._rand_side()
		if s == game.Side.NONE:
			bare += 1
			if game.segments.back() == game.Side.NONE:
				consecutive = true
		game.segments.append(s)
	if bare < 1500 or bare > 2500:
		failures.append("bare frequency %d/20000 is outside ~1 in 10" % bare)
	if consecutive:
		failures.append("two bare segments appeared in a row")

	# A drained bar kills: with almost no time left, death follows within a
	# few frames of real-time drain.
	game.time_left = 0.001
	for i in 5:
		await process_frame
	if game.state != game.State.DYING:
		failures.append("empty time bar did not cause death")

	# Restart returns to a clean playing state.
	game._reset()
	if game.state != game.State.PLAYING or game.score != 0 or game.segments.size() != game.SEG_COUNT:
		failures.append("reset did not restore the initial state")
	if not is_equal_approx(game.time_left, game.TIME_START):
		failures.append("reset did not restore time_left")
	if game.combo != 0:
		failures.append("reset did not clear the combo")
	if game.segments[0] == game.Side.LEFT:
		failures.append("reset: unfair start segment")

	# Pausing freezes the clock, blocks chops, and resume returns to play.
	game._pause()
	if game.state != game.State.PAUSED:
		failures.append("pause did not enter the paused state")
	if not game.pause_card.visible or game.pause_button.visible:
		failures.append("pause did not swap the button for the pause card")
	game.time_left = 1.0
	for i in 5:
		await process_frame
	if not is_equal_approx(game.time_left, 1.0):
		failures.append("the time bar drained while paused")
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.score != 0 or game.combo != 0:
		failures.append("chops must be ignored while paused")
	game._unpause()
	if game.state != game.State.COUNTDOWN:
		failures.append("resume must start the countdown, not play instantly")
	if game.pause_card.visible or game.pause_button.visible:
		failures.append("resume must hide the pause card and button")
	game.time_left = 1.0
	for i in 5:
		await process_frame
	if not is_equal_approx(game.time_left, 1.0):
		failures.append("the time bar drained during the countdown")
	_advance(game)
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.score != 0 or game.combo != 0:
		failures.append("chops must be ignored during the countdown")
	# Rush the countdown to its last moment: play resumes when it runs out.
	game.countdown_t = game.COUNTDOWN_TIME - 0.01
	await process_frame
	await process_frame
	if game.state != game.State.PLAYING:
		failures.append("countdown did not return to the playing state")
	if not game.pause_button.visible:
		failures.append("countdown did not restore the pause button")
	_advance(game)
	await process_frame
	if game.time_left >= 1.0:
		failures.append("the time bar did not resume draining")

	for failure in failures:
		print("FAIL: ", failure)
	if failures.is_empty():
		print("OK: all rules checks passed")
	quit(0 if failures.is_empty() else 1)
