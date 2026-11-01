extends Node2D
## Start menu — the game boots into this scene, so starting a run is a
## deliberate act instead of an instant drop into gameplay.
##
## Mirrors the game's procedural art style; palette and geometry come straight
## from scripts/main.gd constants (preloaded below) so the two can't drift.
## Any tap, click, or key — or the PLAY button — starts the game.

const G := preload("res://scripts/main.gd")

var best := 0
var elapsed := 0.0
var segments: Array = []

@onready var best_label: Label = $UI/BestPanel/BestLabel
@onready var play_button: Button = $UI/PlayButton
@onready var quit_button: Button = $UI/QuitButton


func _ready() -> void:
	# Harness first: it seeds the RNG that _build_tree consumes.
	_setup_debug_harness()
	best = _load_best()
	best_label.text = "BEST %d" % best
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	if OS.get_name() in ["Android", "iOS"]:
		quit_button.visible = false
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


func _unhandled_input(event: InputEvent) -> void:
	var tapped := false
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		tapped = true
	if event.is_action_pressed("ui_accept") or tapped \
			or (event is InputEventKey and event.pressed and not event.echo):
		_on_play_pressed()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


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
	print("MENU state=menu best=", best, " quit=", quit_button.visible,
		" segs(bottom-up)=", segments)
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
	for i in segments.size():
		_draw_segment(segments[i], ground - float(i + 1) * G.SEG_H, vw * 0.5)
	_draw_jack(Vector2(vw * 0.5 - G.JACK_X, ground))


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


func _draw_segment(branch: int, top: float, cx: float) -> void:
	_draw_block(Rect2(cx - G.TRUNK_W * 0.5, top, G.TRUNK_W, G.SEG_H), 22.0,
		G.TRUNK, G.TRUNK_D)
	var dir := -1.0 if branch == G.Side.LEFT else 1.0
	var by := top + G.SEG_H * 0.58
	var x0 := cx + dir * (G.TRUNK_W * 0.5 - 6.0)
	var x1 := x0 + dir * (G.BRANCH_LEN - 24.0)
	draw_line(Vector2(x0, by), Vector2(x1, by), G.BARK, 13.0)
	draw_circle(Vector2(x0, by), 6.5, G.BARK)
	draw_circle(Vector2(x1, by), 6.5, G.BARK)
	draw_circle(Vector2(x1 + dir * 12.0, by - 4.0), 21.0, G.LEAF)
	draw_circle(Vector2(x1 + dir * 30.0, by + 6.0), 26.0, G.LEAF)
	draw_circle(Vector2(x1 + dir * 16.0, by + 14.0), 15.0, G.LEAF_L)
	draw_circle(Vector2(x1 + dir * 22.0, by - 12.0), 12.0, G.LEAF_L)


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
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
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
