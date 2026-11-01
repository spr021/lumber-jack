extends SceneTree
## Headless rules check: godot --headless --path . --script res://tests/rules_test.gd

func _initialize() -> void:
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Run once the scene has gone through a frame, so _ready is guaranteed.
	process_frame.connect(_run_checks.bind(game), CONNECT_ONE_SHOT)


func _run_checks(game: Node2D) -> void:
	var failures: Array[String] = []

	# Fair start: the branch at the lumberjack's height is on the other side.
	if game.segments[0] == game.Side.LEFT:
		failures.append("start: branch sits on the lumberjack's side (left)")
	if not is_equal_approx(game.time_left, game.TIME_START):
		failures.append("start: time_left should be TIME_START")

	# A correct chop scores and pays the time reward.
	game.segments[1] = game.Side.RIGHT
	var before: float = game.time_left
	game.chop(game.Side.LEFT)
	if game.state == game.State.DYING:
		failures.append("correct chop should not trigger death")
	if game.score != 1:
		failures.append("correct chop did not score")
	if game.time_left <= before:
		failures.append("correct chop did not grant time reward")

	# Chopping into a branch survives but earns nothing.
	game.segments[1] = game.Side.LEFT
	before = game.time_left
	game.chop(game.Side.LEFT)
	if game.state != game.State.PLAYING:
		failures.append("chop into the branch must no longer kill")
	if game.score != 1:
		failures.append("wrong chop must not score")
	if not is_equal_approx(game.time_left, before):
		failures.append("wrong chop must not grant a time reward")

	# The reward is capped at TIME_MAX.
	game.time_left = game.TIME_MAX
	game.segments[1] = game.Side.RIGHT
	game.chop(game.Side.LEFT)
	if game.time_left > game.TIME_MAX + 0.0001:
		failures.append("time reward exceeded TIME_MAX")

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
	if game.segments[0] == game.Side.LEFT:
		failures.append("reset: unfair start segment")

	for failure in failures:
		print("FAIL: ", failure)
	if failures.is_empty():
		print("OK: all rules checks passed")
	quit(0 if failures.is_empty() else 1)
