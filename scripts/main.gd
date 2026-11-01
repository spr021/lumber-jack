extends Node2D
## Lumberjack — Timberman-style reaction game.
##
## The tree is an endless stack of segments and every segment grows one branch,
## either left or right. A time bar constantly drains; each correct chop (from
## the side without a branch) refills it a little, and the drain speeds up with
## the score. When the bar runs dry the lumberjack drops — the clock is the
## only killer, chopping into a branch simply earns nothing.

const SEG_H := 150.0
const SEG_COUNT := 12
const TRUNK_W := 130.0
const BRANCH_LEN := 125.0
const GROUND_MARGIN := 240.0
const JACK_X := 172.0
const SLIDE_TIME := 0.09
const SAVE_PATH := "user://lumberjack.cfg"

# Time bar: the bar holds seconds of life, drains in real time, and each
# correct chop pays back TIME_REWARD. Drain grows with score up to DRAIN_MAX.
const TIME_START := 1.0
const TIME_MAX := 2.0
const TIME_REWARD := 0.45
const DRAIN_BASE := 0.9
const DRAIN_PER_SCORE := 0.01
const DRAIN_MAX := 1.8
const BAR_W := 460.0
const BAR_H := 30.0

enum Side { LEFT, RIGHT }
enum State { PLAYING, DYING, GAME_OVER }

const SKY := Color("d9f1ff")
const CLOUD := Color(1.0, 1.0, 1.0, 0.95)
const GRASS := Color("8ee000")
const GRASS_LIGHT := Color("a9f043")
const TRUNK := Color("b98a5e")
const TRUNK_D := Color("96683f")
const TRUNK_L := Color("cba571")
const BAND := 16.0
const CANOPY_D := Color("7cb342")
const CANOPY := Color("9ccc65")
const CANOPY_L := Color("aed581")
const CANOPY_HL := Color("c5e1a5")
# Legacy foliage names kept for menu.gd's decorative sprigs.
const BARK := Color("8a5e3c")
const LEAF := CANOPY_D
const LEAF_L := CANOPY
const SHIRT := Color("ff4b4b")
const SHIRT_D := Color("d63d3d")
const PANTS := Color("1cb0f6")
const BOOT := Color("8a5e3c")
const SKIN := Color("ffc29e")
const HAT := Color("ffc800")
const HAT_D := Color("e5a400")
const HANDLE_WOOD := Color("b98a5e")
const STEEL := Color("e5e5e5")
const STEEL_EDGE := Color("ffffff")
const CHIP := Color("ffc800")
const CHIP2 := Color("ff9600")
const UI_TEXT := Color("4b4b4b")
const BAR_GREEN := Color("58cc02")
const BAR_GREEN_D := Color("58a700")
const BAR_YELLOW := Color("ffc800")
const BAR_YELLOW_D := Color("e5a400")
const BAR_RED := Color("ff4b4b")
const BAR_RED_D := Color("d63d3d")

var segments: Array = []
var jack_side: int = Side.LEFT
var score := 0
var best := 0
var state: int = State.PLAYING
var slide_offset := 0.0
var shake := 0.0
var swing_t := 0.0
var fall_rot := 0.0
var death_timer := 0.0
var elapsed := 0.0
var time_left := 1.0
var miss_flash := 0.0
var game_over_at := 0.0
var flying: Array = []
var chips: Array = []

@onready var score_panel: Panel = $UI/ScorePanel
@onready var score_label: Label = $UI/ScorePanel/ScoreLabel
@onready var hint_label: Label = $UI/HintLabel
@onready var dim: ColorRect = $UI/Dim
@onready var game_over_card: Panel = $UI/GameOverCard
@onready var final_label: Label = $UI/GameOverCard/FinalLabel
@onready var restart_button: Button = $UI/GameOverCard/RestartButton
@onready var menu_button: Button = $UI/GameOverCard/MenuButton


func _ready() -> void:
	best = _load_best()
	_setup_debug_harness()
	_reset()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)


func _on_restart_pressed() -> void:
	if state == State.GAME_OVER and elapsed - game_over_at >= 0.35:
		_reset()


func _on_menu_pressed() -> void:
	if state == State.GAME_OVER and elapsed - game_over_at >= 0.35:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _apply_safe_area() -> void:
	# Keep score and hint text clear of notches and home indicators.
	var safe := DisplayServer.get_display_safe_area()
	var win_rect := Rect2(Vector2(DisplayServer.window_get_position()),
		Vector2(DisplayServer.window_get_size()))
	if win_rect.size.x <= 0.0 or win_rect.size.y <= 0.0:
		return
	var clipped := safe.intersection(win_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	var vp_size := get_viewport_rect().size
	var top: float = clampf((clipped.position.y - win_rect.position.y) * vp_size.y / win_rect.size.y,
		0.0, vp_size.y * 0.15)
	var bottom: float = clampf((win_rect.end.y - clipped.end.y) * vp_size.y / win_rect.size.y,
		0.0, vp_size.y * 0.15)
	score_panel.offset_top = 52.0 + top
	score_panel.offset_bottom = 128.0 + top
	hint_label.offset_top = -150.0 - bottom
	hint_label.offset_bottom = -96.0 - bottom


func _reset() -> void:
	segments.clear()
	# Fair start: the lumberjack begins on the left, so the first branch is on
	# the right and cannot touch him.
	segments.append(Side.RIGHT)
	for i in SEG_COUNT - 1:
		segments.append(_rand_side())
	jack_side = Side.LEFT
	score = 0
	state = State.PLAYING
	time_left = TIME_START
	miss_flash = 0.0
	slide_offset = 0.0
	shake = 0.0
	swing_t = 0.0
	fall_rot = 0.0
	death_timer = 0.0
	flying.clear()
	chips.clear()
	score_label.text = "0"
	hint_label.visible = true
	dim.visible = false
	game_over_card.visible = false


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.PLAYING:
			var side := _side_from_event(event)
			if side != -1:
				chop(side)
		State.GAME_OVER:
			if _is_confirm(event):
				_reset()


func _side_from_event(event: InputEvent) -> int:
	if event.is_action_pressed("ui_left") or _key(event, KEY_A):
		return Side.LEFT
	if event.is_action_pressed("ui_right") or _key(event, KEY_D):
		return Side.RIGHT
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		return Side.LEFT if event.position.x < _vw() * 0.5 else Side.RIGHT
	return -1


func _is_confirm(event: InputEvent) -> bool:
	# Ignore taps landing in the first moments after the game-over screen
	# shows up: on touch devices the fatal last tap often still lingers.
	if elapsed - game_over_at < 0.35:
		return false
	if event.is_action_pressed("ui_accept"):
		return true
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		return true
	return false


func _key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode


func chop(side: int) -> void:
	if state != State.PLAYING:
		return
	jack_side = side
	_spawn_flying_log()
	_spawn_chips()
	segments.pop_front()
	segments.append(_rand_side())
	slide_offset = SEG_H
	swing_t = 1.0
	hint_label.visible = false
	if segments[0] == jack_side:
		# Chopped into a branch: no reward, and the clock keeps draining.
		miss_flash = 0.3
		shake = 11.0
	else:
		score += 1
		score_label.text = str(score)
		time_left = minf(time_left + TIME_REWARD, TIME_MAX)
		shake = 7.0


func _die() -> void:
	state = State.DYING
	death_timer = 0.0
	shake = 12.0
	if score > best:
		best = score
		_save_best(best)


func _show_game_over() -> void:
	state = State.GAME_OVER
	game_over_at = elapsed
	dim.visible = true
	game_over_card.visible = true
	final_label.text = "SCORE %d\nBEST %d" % [score, best]


func _process(delta: float) -> void:
	elapsed += delta
	if state == State.PLAYING:
		time_left -= minf(DRAIN_BASE + DRAIN_PER_SCORE * score, DRAIN_MAX) * delta
		if time_left <= 0.0:
			time_left = 0.0
			_die()
	miss_flash = move_toward(miss_flash, 0.0, delta)
	slide_offset = move_toward(slide_offset, 0.0, SEG_H * delta / SLIDE_TIME)
	shake = move_toward(shake, 0.0, 46.0 * delta)
	swing_t = move_toward(swing_t, 0.0, delta / 0.12)
	_update_flying(delta)
	_update_chips(delta)
	if state == State.DYING:
		death_timer += delta
		fall_rot = -1.9 * _back_ease(minf(death_timer / 0.4, 1.0))
		if death_timer >= 0.9:
			_show_game_over()
	queue_redraw()


func _rand_side() -> int:
	return Side.LEFT if randi() % 2 == 0 else Side.RIGHT


func _back_ease(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _spawn_flying_log() -> void:
	# The chopped log kicks off away from the lumberjack's axe.
	var dir := 1.0 if jack_side == Side.LEFT else -1.0
	flying.append({
		"pos": Vector2(_vw() * 0.5, _ground_y() - SEG_H * 0.5),
		"vel": Vector2(dir * randf_range(420.0, 640.0), -randf_range(260.0, 480.0)),
		"rot": 0.0,
		"rot_vel": dir * randf_range(5.0, 9.0),
		"branch": segments[0],
	})


func _spawn_chips() -> void:
	var dir := -1.0 if jack_side == Side.LEFT else 1.0
	var origin := Vector2(
		_vw() * 0.5 + dir * (TRUNK_W * 0.5 - 6.0),
		_ground_y() - SEG_H * 0.55
	)
	for i in 12:
		chips.append({
			"pos": origin,
			"vel": Vector2(dir * randf_range(60.0, 520.0), -randf_range(120.0, 700.0)),
			"size": randf_range(4.0, 10.0),
			"life": randf_range(0.35, 0.7),
			"rot": randf() * TAU,
		})


func _update_flying(delta: float) -> void:
	for i in range(flying.size() - 1, -1, -1):
		var piece: Dictionary = flying[i]
		piece.pos += piece.vel * delta
		piece.vel.y += 2100.0 * delta
		piece.rot += piece.rot_vel * delta
		if piece.pos.y > _vh() + 200.0 or piece.pos.x < -300.0 or piece.pos.x > _vw() + 300.0:
			flying.remove_at(i)


func _update_chips(delta: float) -> void:
	for i in range(chips.size() - 1, -1, -1):
		var chip: Dictionary = chips[i]
		chip.pos += chip.vel * delta
		chip.vel.y += 2500.0 * delta
		chip.rot += 6.0 * delta
		chip.life -= delta
		if chip.life <= 0.0:
			chips.remove_at(i)


func _load_best() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		return config.get_value("game", "best", 0)
	return 0


func _save_best(value: int) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "best", value)
	config.save(SAVE_PATH)


# ---------------------------------------------------------- debug harness ---
# Test automation only; inactive unless the game is started with user args:
#   godot --path . ++ seed=12345 seq=LLRR out=/tmp/shot
# `seq` auto-chops that side sequence (0.15s apart) and saves a screenshot
# after every chop, so scripted runs can be inspected visually.

func _setup_debug_harness() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		randomize()
		return
	var prefix := "/tmp/lj_shot"
	var seq := ""
	var wait := 1.2
	for arg in args:
		if arg.begins_with("seed="):
			seed(arg.substr(5).to_int())
		elif arg.begins_with("seq="):
			seq = arg.substr(4)
		elif arg.begins_with("out="):
			prefix = arg.substr(4)
		elif arg.begins_with("wait="):
			wait = arg.substr(5).to_float()
	_run_harness_sequence.call_deferred(prefix, seq, wait)


func _run_harness_sequence(prefix: String, seq: String, wait: float) -> void:
	await get_tree().create_timer(0.5).timeout
	await _shot(prefix + "_start.png")
	if seq == "auto":
		# Bot: always chop from the side the next branch is not on.
		for i in 8:
			chop(Side.RIGHT if segments[1] == Side.LEFT else Side.LEFT)
			await get_tree().create_timer(0.15).timeout
			await _shot("%s_%02d.png" % [prefix, i + 1])
	else:
		for i in seq.length():
			chop(Side.LEFT if seq[i] == "L" else Side.RIGHT)
			await get_tree().create_timer(0.15).timeout
			await _shot("%s_%02d.png" % [prefix, i + 1])
	await get_tree().create_timer(wait).timeout
	await _shot(prefix + "_end.png")
	if state == State.GAME_OVER:
		# Exercise the real restart path: inject an Enter press.
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.2).timeout
		await _shot(prefix + "_restart.png")
		print("RESTART state=", state, " score=", score, " jack=",
			"L" if jack_side == Side.LEFT else "R")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	_verify_pixels(img)


func _verify_pixels(img: Image) -> void:
	# The window backbuffer is the canvas scaled down; convert game
	# coordinates to image pixels before sampling.
	var vp_size := get_viewport_rect().size
	var s := Vector2(img.get_size()) / vp_size
	var jack_x := vp_size.x * 0.5 + (JACK_X if jack_side == Side.RIGHT else -JACK_X)
	var checks: Array = [
		["sky", Vector2(30.0, 30.0), SKY],
		["trunk", Vector2(vp_size.x * 0.5 - 24.0, _ground_y() - 90.0), TRUNK],
		["grass", Vector2(vp_size.x * 0.5, vp_size.y - 50.0), GRASS],
		["shirt", Vector2(jack_x - 10.0, _ground_y() - 75.0), SHIRT],
	]
	for check in checks:
		var got: Color = img.get_pixel(int(check[1].x * s.x), int(check[1].y * s.y))
		var expect: Color = check[2]
		var close := absf(got.r - expect.r) < 0.05 and absf(got.g - expect.g) < 0.05 \
			and absf(got.b - expect.b) < 0.05
		print("PIXEL ", check[0], " expect=", expect.to_html(false),
			" got=", got.to_html(false), " ", "OK" if close else "MISMATCH")
	print("STATE score=", score, " jack=", "L" if jack_side == Side.LEFT else "R",
		" phase=", state, " time_left=%.2f" % time_left,
		" segs(bottom-up)=", segments)


# ---------------------------------------------------------------- drawing ---

func _vw() -> float:
	return get_viewport_rect().size.x


func _vh() -> float:
	return get_viewport_rect().size.y


func _ground_y() -> float:
	return _vh() - GROUND_MARGIN


func _rounded_points(rect: Rect2, radius: float, seg := 5) -> PackedVector2Array:
	# The 0.01 shave keeps the two arcs on each side from sharing one center
	# when the radius is exactly half the height: that collapses the first
	# and last arc points into duplicates and breaks triangulation.
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5 - 0.01)
	var pts := PackedVector2Array()
	var arcs := [
		[Vector2(rect.position.x + r, rect.position.y + r), PI, PI * 1.5],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5, TAU],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0, PI * 0.5],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5, PI],
	]
	for arc in arcs:
		for i in seg + 1:
			var a: float = arc[1] + (arc[2] - arc[1]) * i / seg
			pts.append(arc[0] + Vector2.from_angle(a) * r)
	return pts


func _draw_block(rect: Rect2, radius: float, color: Color, edge_color: Color, edge := 7.0) -> void:
	# Duolingo-style solid block: flat fill sitting on a darker bottom edge.
	draw_polygon(_rounded_points(Rect2(rect.position + Vector2(0.0, edge), rect.size), radius),
		PackedColorArray([edge_color]))
	draw_polygon(_rounded_points(rect, radius), PackedColorArray([color]))


func _draw() -> void:
	var sh := Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	var vw := _vw()
	var ground := _ground_y()
	draw_rect(Rect2(0.0, 0.0, vw, ground), SKY)
	_draw_clouds()
	draw_rect(Rect2(0.0, ground + sh.y, vw, _vh() - ground + 40.0), GRASS)
	draw_rect(Rect2(0.0, ground + sh.y, vw, 14.0), GRASS_LIGHT)
	_draw_bushes(ground + sh.y, vw)
	# The trunk is one continuous column; only the branches carry the slide
	# motion, so the tree reads as a single shape instead of stacked parts.
	var cx := vw * 0.5 + sh.x
	draw_rect(Rect2(cx - TRUNK_W * 0.5, -80.0, TRUNK_W, ground + 80.0 + sh.y), TRUNK_D)
	for i in segments.size():
		var top := ground - float(i + 1) * SEG_H + slide_offset + sh.y
		if top > _vh() + 40.0:
			continue
		if top + SEG_H < -180.0:
			break
		var dir := -1.0 if segments[i] == Side.LEFT else 1.0
		_branch_assembly(dir, top + SEG_H * 0.58, cx + dir * (TRUNK_W * 0.5))
	# Lighter main face over the branch roots, leaving a dark edge band.
	draw_rect(Rect2(cx - TRUNK_W * 0.5 + BAND, -80.0, TRUNK_W - BAND, ground + 80.0 + sh.y), TRUNK)
	_draw_trunk_stripes(cx, ground + sh.y)
	_draw_chips(sh)
	_draw_flying_logs(sh)
	_draw_jack(sh)
	_draw_time_bar()


func _draw_bushes(ground: float, vw: float) -> void:
	for k in 5:
		var x := vw * (0.12 + 0.19 * k)
		var r := 26.0 if k % 2 == 0 else 18.0
		draw_circle(Vector2(x, ground + 4.0), r, GRASS_LIGHT)


func _draw_time_bar() -> void:
	var x := (_vw() - BAR_W) * 0.5
	var y := 240.0
	var track := Rect2(x, y, BAR_W, BAR_H)
	draw_polygon(_rounded_points(track, BAR_H * 0.5), PackedColorArray([STEEL]))
	var frac := time_left / TIME_MAX
	# Skip the fill when it is thinner than one capsule corner radius, so the
	# rounded polygon never degenerates. The true threshold is where the fill
	# width (minus the 2 px inset) meets the capsule seam: below it the two
	# rounded ends touch and produce duplicate points, which fails
	# triangulation sporadically depending on where frames land.
	if frac > (BAR_H + 2.0) / BAR_W:
		var pulse := 1.0
		if time_left < 0.5:
			pulse = 0.65 + 0.35 * absf(sin(elapsed * 9.0))
		var fill := BAR_GREEN
		var edge := BAR_GREEN_D
		if frac <= 0.2:
			fill = BAR_RED
			edge = BAR_RED_D
		elif frac <= 0.4:
			fill = BAR_YELLOW
			edge = BAR_YELLOW_D
		if miss_flash > 0.0:
			fill = BAR_RED
			edge = BAR_RED_D
		var fill_rect := Rect2(track.position, Vector2(track.size.x * frac, track.size.y))
		# Duolingo progress bar: green fill riding on a darker bottom edge.
		draw_polygon(_rounded_points(Rect2(fill_rect.position + Vector2(0.0, 5.0),
			Vector2(fill_rect.size.x - 2.0, fill_rect.size.y)), BAR_H * 0.5),
			PackedColorArray([Color(edge, pulse)]))
		draw_polygon(_rounded_points(Rect2(fill_rect.position,
			Vector2(fill_rect.size.x - 2.0, fill_rect.size.y - 4.0)), BAR_H * 0.5),
			PackedColorArray([Color(fill, pulse)]))


func _draw_clouds() -> void:
	var span := _vw() + 360.0
	var drift := fmod(elapsed * 10.0, span) - 180.0
	_draw_cloud(Vector2(drift, 190.0), 1.0)
	_draw_cloud(Vector2(fmod(drift + span * 0.55, span) - 180.0, 340.0), 0.7)


func _draw_cloud(center: Vector2, s: float) -> void:
	draw_circle(center + Vector2(-40.0 * s, 8.0 * s), 24.0 * s, CLOUD)
	draw_circle(center + Vector2(0.0, -10.0 * s), 34.0 * s, CLOUD)
	draw_circle(center + Vector2(42.0 * s, 8.0 * s), 24.0 * s, CLOUD)
	draw_rect(Rect2(center + Vector2(-40.0 * s, 8.0 * s), Vector2(82.0 * s, 22.0 * s)), CLOUD)


func _draw_trunk_stripes(cx: float, ground: float) -> void:
	# Rounded vertical highlights, like growth streaks on the bark.
	draw_polygon(_rounded_points(Rect2(cx + 2.0, -80.0, 13.0, ground + 56.0), 6.5),
		PackedColorArray([TRUNK_L]))
	draw_polygon(_rounded_points(Rect2(cx + 27.0, -80.0, 11.0, ground - 210.0), 5.5),
		PackedColorArray([TRUNK_L]))


func _branch_points(edge: float, by: float) -> PackedVector2Array:
	# Branch silhouette growing out of the trunk edge toward +x: concave
	# fillets where it meets the trunk and a convex rounded tip.
	var h := 18.0
	var rf := 16.0
	var rb := 24.0
	var rc := 18.0
	var tip := edge + BRANCH_LEN
	var pts := PackedVector2Array()
	pts.append(Vector2(edge, by - h - rf))
	var c_top := Vector2(edge + rf, by - h - rf)
	for i in range(1, 6):
		var a: float = PI - (PI * 0.5) * i / 5.0
		pts.append(c_top + Vector2.from_angle(a) * rf)
	for i in 8:
		var a: float = -PI * 0.5 + PI * i / 7.0
		pts.append(Vector2(tip - rc, by) + Vector2.from_angle(a) * rc)
	var c_bot := Vector2(edge + rb, by + h + rb)
	for i in 6:
		var a: float = PI * 0.5 + (PI * 0.5) * i / 5.0
		pts.append(c_bot + Vector2.from_angle(a) * rb)
	return pts


func _draw_branch_poly(edge: float, by: float, dir: float) -> void:
	var pts := _branch_points(edge, by)
	if dir < 0.0:
		for i in pts.size():
			pts[i] = Vector2(2.0 * edge - pts[i].x, pts[i].y)
	draw_polygon(pts, PackedColorArray([TRUNK]))


func _span_rect(x1: float, x2: float, y: float, h: float) -> Rect2:
	return Rect2(minf(x1, x2), y, absf(x2 - x1), h)


func _draw_pill(center: Vector2, w: float, h: float, color: Color) -> void:
	draw_polygon(_rounded_points(Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), h * 0.5),
		PackedColorArray([color]))


func _draw_canopy(dir: float, by: float, tip: float) -> void:
	# Layered blob canopy riding on the branch tip, brightest on top.
	_draw_pill(Vector2(tip - dir * 10.0, by - 40.0), 150.0, 54.0, CANOPY_D)
	_draw_pill(Vector2(tip - dir * 24.0, by - 72.0), 114.0, 52.0, CANOPY)
	_draw_pill(Vector2(tip - dir * 34.0, by - 101.0), 76.0, 46.0, CANOPY_L)
	_draw_pill(Vector2(tip - dir * 52.0, by - 46.0), 18.0, 9.0, CANOPY_HL)
	_draw_pill(Vector2(tip - dir * 20.0, by - 64.0), 16.0, 8.0, CANOPY_HL)
	_draw_pill(Vector2(tip - dir * 40.0, by - 96.0), 14.0, 8.0, CANOPY_HL)


func _branch_assembly(dir: float, by: float, edge: float) -> void:
	_draw_branch_poly(edge, by, dir)
	# Subtle darker underside along the branch, flowing into the elbow.
	var shade_to := edge + dir * (BRANCH_LEN - 44.0)
	draw_polygon(_rounded_points(_span_rect(edge + dir * 12.0, shade_to, by + 5.0, 10.0), 5.0),
		PackedColorArray([TRUNK_D]))
	_draw_canopy(dir, by, edge + dir * BRANCH_LEN)


func _draw_flying_logs(sh: Vector2) -> void:
	for piece in flying:
		draw_set_transform(piece.pos + sh, piece.rot, Vector2.ONE)
		var rect := Rect2(-TRUNK_W * 0.5, -SEG_H * 0.5, TRUNK_W, SEG_H)
		draw_polygon(_rounded_points(rect, 20.0), PackedColorArray([TRUNK]))
		# Same bark detailing as the standing trunk, clipped to the piece.
		draw_polygon(_rounded_points(
			Rect2(rect.position.x + 4.0, rect.position.y + 9.0, BAND - 2.0, SEG_H - 18.0), 7.0),
			PackedColorArray([TRUNK_D]))
		draw_polygon(_rounded_points(
			Rect2(2.0, -SEG_H * 0.5 + 16.0, 12.0, SEG_H * 0.52), 6.0),
			PackedColorArray([TRUNK_L]))
		draw_polygon(_rounded_points(
			Rect2(24.0, -SEG_H * 0.5 + 34.0, 10.0, SEG_H * 0.3), 5.0),
			PackedColorArray([TRUNK_L]))
		var dir := -1.0 if piece.branch == Side.LEFT else 1.0
		_branch_assembly(dir, -SEG_H * 0.5 + SEG_H * 0.58, dir * (TRUNK_W * 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chips(sh: Vector2) -> void:
	for i in chips.size():
		var chip: Dictionary = chips[i]
		var color := CHIP if i % 2 == 0 else CHIP2
		draw_set_transform(chip.pos + sh, chip.rot, Vector2.ONE)
		var rect := Rect2(-chip.size * 0.5, -chip.size * 0.5, chip.size, chip.size)
		draw_polygon(_rounded_points(rect, chip.size * 0.35, 3),
			PackedColorArray([color]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_jack(sh: Vector2) -> void:
	var base := Vector2(
		_vw() * 0.5 + (JACK_X if jack_side == Side.RIGHT else -JACK_X),
		_ground_y()
	)
	var mirror := Vector2(1.0, 1.0) if jack_side == Side.LEFT else Vector2(-1.0, 1.0)
	draw_set_transform(base + sh, fall_rot, mirror)
	# Local space: origin at the feet, facing +x toward the trunk.
	# Legs and rounded boots.
	draw_block_local(Rect2(-17.0, -54.0, 14.0, 42.0), 7.0, PANTS)
	draw_block_local(Rect2(3.0, -54.0, 14.0, 42.0), 7.0, PANTS)
	draw_block_local(Rect2(-21.0, -15.0, 19.0, 15.0), 7.0, BOOT)
	draw_block_local(Rect2(1.0, -15.0, 21.0, 15.0), 7.0, BOOT)
	# Torso: flat coral block on a darker edge.
	_draw_block(Rect2(-22.0, -106.0, 44.0, 58.0), 16.0, SHIRT, SHIRT_D)
	# Head, hard hat, and a friendly face.
	draw_circle(Vector2(4.0, -121.0), 19.0, SKIN)
	draw_block_local(Rect2(-14.0, -148.0, 38.0, 17.0), 8.0, HAT)
	draw_block_local(Rect2(-19.0, -134.0, 48.0, 9.0), 4.5, HAT_D)
	draw_circle(Vector2(9.0, -122.0), 2.5, UI_TEXT)
	draw_circle(Vector2(17.0, -122.0), 2.5, UI_TEXT)
	draw_arc(Vector2(12.0, -114.0), 5.0, PI * 0.18, PI * 0.82, 8, UI_TEXT, 2.0)
	# Arm and axe recoil back for a moment after each chop.
	var ang := -1.3 * swing_t
	var shoulder := Vector2(8.0, -92.0)
	var hand := shoulder + Vector2(35.0, 12.0).rotated(ang)
	draw_line(shoulder, hand, SKIN, 12.0)
	draw_circle(shoulder, 9.0, SHIRT)
	draw_circle(hand, 7.0, SKIN)
	var tip := hand + Vector2(34.0, 8.0).rotated(ang)
	draw_line(hand, tip, HANDLE_WOOD, 9.0)
	var dir2 := (tip - hand).normalized()
	var perp := Vector2(-dir2.y, dir2.x)
	var blade := PackedVector2Array([
		tip + dir2 * 3.0 + perp * 17.0,
		tip + dir2 * 17.0 + perp * 14.0,
		tip + dir2 * 17.0 - perp * 5.0,
		tip + dir2 * 3.0 - perp * 3.0,
	])
	draw_polygon(blade, PackedColorArray([STEEL, STEEL, STEEL_EDGE, STEEL_EDGE]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_block_local(rect: Rect2, radius: float, color: Color) -> void:
	draw_polygon(_rounded_points(rect, radius), PackedColorArray([color]))
