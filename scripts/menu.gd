extends Node2D
## Start menu — the game boots into this scene, so starting a run is a
## deliberate act instead of an instant drop into gameplay.
##
## Mirrors the game's procedural art style; palette and geometry come straight
## from scripts/main.gd constants (preloaded below) so the two can't drift.
## The wooden title sign and its leaf sprigs are drawn to match the tree art.
## The game starts only through the PLAY button.

const G := preload("res://scripts/main.gd")

var best := 0
var elapsed := 0.0
var segments: Array = []

@onready var title_card: Panel = $UI/TitleCard
@onready var best_label: Label = $UI/BestPanel/BestLabel
@onready var play_button: Button = $UI/PlayButton


func _ready() -> void:
	# Harness first: it seeds the RNG that _build_tree consumes.
	_setup_debug_harness()
	best = _load_best()
	best_label.text = "BEST %d" % best
	play_button.pressed.connect(_on_play_pressed)
	_build_tree()


func _build_tree() -> void:
	# Same fair-start rule as the game: the lumberjack stands on the left, so
	# the bottom branch must be on the right.
	segments = [G.Side.RIGHT]
	for i in 9:
		segments.append(G.Side.LEFT if randi() % 2 == 0 else G.Side.RIGHT)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _load_best() -> int:
	var config := ConfigFile.new()
	if config.load(G.SAVE_PATH) == OK:
		return config.get_value("game", "best", 0)
	return 0


# ---------------------------------------------------------- debug harness ---
# Mirrors the harness in scripts/main.gd. With user args, saves one screenshot
# of the menu and then starts the game, so the game-side harness (which sees
# the same user args) takes over and produces its usual shots.

func _setup_debug_harness() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		randomize()
		return
	for arg in args:
		if arg.begins_with("seed="):
			seed(arg.substr(5).to_int())
	_run_harness.call_deferred()


func _run_harness() -> void:
	var prefix := "/tmp/lj_shot"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			prefix = arg.substr(4)
	await get_tree().create_timer(0.6).timeout
	await _shot(prefix + "_menu.png")
	print("MENU state=menu best=", best, " segs(bottom-up)=", segments)
	_on_play_pressed()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


# ---------------------------------------------------------------- drawing ---

func _draw() -> void:
	var vw := get_viewport_rect().size.x
	var vh := get_viewport_rect().size.y
	var ground := vh - G.GROUND_MARGIN
	draw_rect(Rect2(0.0, 0.0, vw, ground), G.SKY)
	_draw_clouds(vw)
	draw_rect(Rect2(0.0, ground, vw, vh - ground + 40.0), G.GRASS)
	draw_rect(Rect2(0.0, ground, vw, 14.0), G.GRASS_LIGHT)
	_draw_bushes(ground, vw)
	# Same continuous-trunk tree as the game scene, so menu and gameplay
	# read as one world.
	var cx := vw * 0.5
	draw_rect(Rect2(cx - G.TRUNK_W * 0.5, -80.0, G.TRUNK_W, ground + 80.0), G.TRUNK_D)
	for i in segments.size():
		var dir := -1.0 if segments[i] == G.Side.LEFT else 1.0
		_branch_assembly(dir, ground - float(i + 1) * G.SEG_H + G.SEG_H * 0.58,
			cx + dir * (G.TRUNK_W * 0.5))
	draw_rect(Rect2(cx - G.TRUNK_W * 0.5 + G.BAND, -80.0, G.TRUNK_W - G.BAND, ground + 80.0),
		G.TRUNK)
	_draw_trunk_stripes(cx, ground)
	_draw_jack(Vector2(cx - G.JACK_X, ground))
	_draw_sign_sprigs()


func _draw_sign_sprigs() -> void:
	# Leaf clusters peeking out from behind the wooden title sign. They live
	# in the world layer, so they render above the tree but behind the sign.
	var rect := title_card.get_global_rect()
	_leaf_sprig(rect.position + Vector2(42.0, 16.0), -1.0)
	_leaf_sprig(rect.position + Vector2(rect.size.x - 42.0, 16.0), 1.0)


func _leaf_sprig(center: Vector2, dir: float) -> void:
	draw_circle(center + Vector2(dir * 12.0, -16.0), 20.0, G.LEAF)
	draw_circle(center + Vector2(dir * 36.0, -4.0), 15.0, G.LEAF)
	draw_circle(center + Vector2(dir * 24.0, -30.0), 13.0, G.LEAF_L)
	draw_circle(center + Vector2(dir * 46.0, -18.0), 9.0, G.LEAF_L)


func _draw_bushes(ground: float, vw: float) -> void:
	for k in 5:
		var x := vw * (0.12 + 0.19 * k)
		var r := 26.0 if k % 2 == 0 else 18.0
		draw_circle(Vector2(x, ground + 4.0), r, G.GRASS_LIGHT)


func _draw_clouds(vw: float) -> void:
	var span := vw + 360.0
	var drift := fmod(elapsed * 10.0, span) - 180.0
	_draw_cloud(Vector2(drift, 190.0), 1.0)
	_draw_cloud(Vector2(fmod(drift + span * 0.55, span) - 180.0, 340.0), 0.7)


func _draw_cloud(center: Vector2, s: float) -> void:
	draw_circle(center + Vector2(-40.0 * s, 8.0 * s), 24.0 * s, G.CLOUD)
	draw_circle(center + Vector2(0.0, -10.0 * s), 34.0 * s, G.CLOUD)
	draw_circle(center + Vector2(42.0 * s, 8.0 * s), 24.0 * s, G.CLOUD)
	draw_rect(Rect2(center + Vector2(-40.0 * s, 8.0 * s), Vector2(82.0 * s, 22.0 * s)), G.CLOUD)


func _draw_trunk_stripes(cx: float, ground: float) -> void:
	draw_polygon(_rounded_points(Rect2(cx + 2.0, -80.0, 13.0, ground + 56.0), 6.5),
		PackedColorArray([G.TRUNK_L]))
	draw_polygon(_rounded_points(Rect2(cx + 27.0, -80.0, 11.0, ground - 210.0), 5.5),
		PackedColorArray([G.TRUNK_L]))


func _branch_points(edge: float, by: float) -> PackedVector2Array:
	var h := 18.0
	var rf := 16.0
	var rb := 24.0
	var rc := 18.0
	var tip := edge + G.BRANCH_LEN
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
	draw_polygon(pts, PackedColorArray([G.TRUNK]))


func _span_rect(x1: float, x2: float, y: float, h: float) -> Rect2:
	return Rect2(minf(x1, x2), y, absf(x2 - x1), h)


func _draw_pill(center: Vector2, w: float, h: float, color: Color) -> void:
	draw_polygon(_rounded_points(Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), h * 0.5),
		PackedColorArray([color]))


func _draw_canopy(dir: float, by: float, tip: float) -> void:
	_draw_pill(Vector2(tip - dir * 10.0, by - 40.0), 150.0, 54.0, G.CANOPY_D)
	_draw_pill(Vector2(tip - dir * 24.0, by - 72.0), 114.0, 52.0, G.CANOPY)
	_draw_pill(Vector2(tip - dir * 34.0, by - 101.0), 76.0, 46.0, G.CANOPY_L)
	_draw_pill(Vector2(tip - dir * 52.0, by - 46.0), 18.0, 9.0, G.CANOPY_HL)
	_draw_pill(Vector2(tip - dir * 20.0, by - 64.0), 16.0, 8.0, G.CANOPY_HL)
	_draw_pill(Vector2(tip - dir * 40.0, by - 96.0), 14.0, 8.0, G.CANOPY_HL)


func _branch_assembly(dir: float, by: float, edge: float) -> void:
	_draw_branch_poly(edge, by, dir)
	var shade_to := edge + dir * (G.BRANCH_LEN - 44.0)
	draw_polygon(_rounded_points(_span_rect(edge + dir * 12.0, shade_to, by + 5.0, 10.0), 5.0),
		PackedColorArray([G.TRUNK_D]))
	_draw_canopy(dir, by, edge + dir * G.BRANCH_LEN)


func _draw_jack(base: Vector2) -> void:
	# Idle pose of the game's lumberjack, breathing with a tiny bob.
	draw_set_transform(base + Vector2(0.0, sin(elapsed * 2.6) * 2.0), 0.0, Vector2.ONE)
	_block_local(Rect2(-17.0, -54.0, 14.0, 42.0), 7.0, G.PANTS)
	_block_local(Rect2(3.0, -54.0, 14.0, 42.0), 7.0, G.PANTS)
	_block_local(Rect2(-21.0, -15.0, 19.0, 15.0), 7.0, G.BOOT)
	_block_local(Rect2(1.0, -15.0, 21.0, 15.0), 7.0, G.BOOT)
	_draw_block(Rect2(-22.0, -106.0, 44.0, 58.0), 16.0, G.SHIRT, G.SHIRT_D)
	draw_circle(Vector2(4.0, -121.0), 19.0, G.SKIN)
	_block_local(Rect2(-14.0, -148.0, 38.0, 17.0), 8.0, G.HAT)
	_block_local(Rect2(-19.0, -134.0, 48.0, 9.0), 4.5, G.HAT_D)
	draw_circle(Vector2(9.0, -122.0), 2.5, G.UI_TEXT)
	draw_circle(Vector2(17.0, -122.0), 2.5, G.UI_TEXT)
	draw_arc(Vector2(12.0, -114.0), 5.0, PI * 0.18, PI * 0.82, 8, G.UI_TEXT, 2.0)
	# Arm and axe resting against the trunk.
	var hand := Vector2(43.0, -80.0)
	var tip := hand + Vector2(34.0, 8.0)
	draw_line(Vector2(8.0, -92.0), hand, G.SKIN, 12.0)
	draw_circle(Vector2(8.0, -92.0), 9.0, G.SHIRT)
	draw_circle(hand, 7.0, G.SKIN)
	draw_line(hand, tip, G.HANDLE_WOOD, 9.0)
	var dir2 := Vector2(34.0, 8.0).normalized()
	var perp := Vector2(-dir2.y, dir2.x)
	var blade := PackedVector2Array([
		tip + dir2 * 3.0 + perp * 17.0,
		tip + dir2 * 17.0 + perp * 14.0,
		tip + dir2 * 17.0 - perp * 5.0,
		tip + dir2 * 3.0 - perp * 3.0,
	])
	draw_polygon(blade, PackedColorArray([G.STEEL, G.STEEL, G.STEEL_EDGE, G.STEEL_EDGE]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_block(rect: Rect2, radius: float, color: Color, edge_color: Color,
		edge := 7.0) -> void:
	draw_polygon(_rounded_points(Rect2(rect.position + Vector2(0.0, edge), rect.size), radius),
		PackedColorArray([edge_color]))
	draw_polygon(_rounded_points(rect, radius), PackedColorArray([color]))


func _block_local(rect: Rect2, radius: float, color: Color) -> void:
	draw_polygon(_rounded_points(rect, radius), PackedColorArray([color]))


func _rounded_points(rect: Rect2, radius: float, seg := 5) -> PackedVector2Array:
	# Same degenerate-arc guard as main.gd: shave a hair off the clamp so
	# pill shapes never produce duplicate arc points.
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
