extends Node2D
## Start menu — the game boots into this scene, so starting a run is a
## deliberate act instead of an instant drop into gameplay.
##
## Mirrors the game's procedural art style; palette and geometry come straight
## from scripts/main.gd constants (preloaded below) so the two can't drift.
## The wooden title sign and its leaf sprigs are drawn to match the tree art.
## The game starts only through the PLAY button.

const G := preload("res://scripts/main.gd")
const S := preload("res://scripts/scores_api.gd")

# --- online leaderboard (all UI built in code, see bottom section) ---
var scores_api: Node = null
var board_top: Array = []
var board_me: Dictionary = {}
var board_group: Control
var top_name_labels: Array[Label] = []
var top_score_labels: Array[Label] = []
var me_rank_label: Label
var me_name_label: Label
var me_score_label: Label
var name_dialog: Control
var name_edit: LineEdit
var name_hint: Label

var best := 0
var elapsed := 0.0
var segments: Array = []

@onready var title_card: Panel = $UI/TitleCard
@onready var play_button: Button = $UI/PlayButton


func _ready() -> void:
	# Harness first: it seeds the RNG that _build_tree consumes.
	_setup_debug_harness()
	best = _load_best()
	play_button.pressed.connect(_on_play_pressed)
	_build_tree()
	_setup_leaderboard()


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


# ------------------------------------------------------------- leaderboard ---
# Top-3 card between the title sign and BEST, plus a tappable "YOU" row that
# opens the rename dialog. The Scores autoload handles device identity and
# all HTTP; this section is display only.

func _setup_leaderboard() -> void:
	scores_api = get_node_or_null("/root/Scores")
	_build_board()
	_build_name_dialog()
	if scores_api:
		scores_api.leaderboard_loaded.connect(_on_leaderboard_loaded)
		_refresh_board()
		scores_api.retry_pending()
		scores_api.fetch_leaderboard()


func _on_leaderboard_loaded(ok: bool, data: Dictionary) -> void:
	if not ok:
		return  # keep whatever is on screen; offline shows placeholders
	board_top = data.get("top", [])
	var me: Variant = data.get("me")
	board_me = me if me is Dictionary else {}
	_refresh_board()


func _build_board() -> void:
	# No enclosing card: a floating header, three slim white pills for the
	# top 3 and a green pill for this device, all hovering over the world.
	# Bottom sits above the lumberjack so he stays fully visible on the grass.
	board_group = Control.new()
	board_group.anchor_left = 0.5
	board_group.anchor_right = 0.5
	board_group.anchor_top = 1.0
	board_group.anchor_bottom = 1.0
	board_group.offset_left = -260.0
	board_group.offset_top = -768.0
	board_group.offset_right = 260.0
	board_group.offset_bottom = -420.0
	board_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(board_group)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 12)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_group.add_child(rows)

	for i in 3:
		rows.add_child(_top_pill(i))

	rows.add_child(_you_pill())


func _top_pill(place: int) -> Panel:
	var pill := Panel.new()
	pill.custom_minimum_size = Vector2(0.0, 64.0)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _pill_style())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -18.0
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	var medal := Panel.new()
	medal.custom_minimum_size = Vector2(40.0, 40.0)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var medal_style := StyleBoxFlat.new()
	medal_style.bg_color = _medal_color(place)
	medal_style.set_corner_radius_all(20.0)
	medal.add_theme_stylebox_override("panel", medal_style)
	row.add_child(medal)

	var number := _board_label(str(place + 1), 22, Color.WHITE)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.add_child(number)
	number.set_anchors_preset(Control.PRESET_FULL_RECT)

	var name_label := _board_label("—", 26, G.UI_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)

	var score_label := _board_label("", 26, G.UI_GREY_D)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(score_label)

	top_name_labels.append(name_label)
	top_score_labels.append(score_label)
	return pill


func _you_pill() -> Button:
	var pill := Button.new()
	pill.custom_minimum_size = Vector2(0.0, 64.0)
	pill.focus_mode = Control.FOCUS_NONE
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.pressed.connect(_open_name_dialog)
	pill.add_theme_stylebox_override("normal", _you_style())
	pill.add_theme_stylebox_override("hover", _you_style())
	pill.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var pressed := _you_style()
	pressed.bg_color = G.BAR_GREEN_D
	pill.add_theme_stylebox_override("pressed", pressed)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	# A Button doesn't lay out its children: pin the row to the button rect.
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -18.0

	row.add_child(_board_label("YOU", 16, Color(1.0, 1.0, 1.0, 0.9)))

	var circle := Panel.new()
	circle.custom_minimum_size = Vector2(36.0, 36.0)
	circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_style := StyleBoxFlat.new()
	circle_style.bg_color = Color.WHITE
	circle_style.set_corner_radius_all(18.0)
	circle.add_theme_stylebox_override("panel", circle_style)
	row.add_child(circle)

	me_rank_label = _board_label("–", 20, G.BAR_GREEN)
	me_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle.add_child(me_rank_label)
	me_rank_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	me_name_label = _board_label("—", 26, Color.WHITE)
	me_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me_name_label.clip_text = true
	row.add_child(me_name_label)

	row.add_child(_board_label("EDIT", 15, Color(1.0, 1.0, 1.0, 0.75)))

	me_score_label = _board_label("", 26, Color.WHITE)
	me_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(me_score_label)
	return pill


func _build_name_dialog() -> void:
	name_dialog = Control.new()
	name_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_dialog.visible = false
	$UI.add_child(name_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	name_dialog.add_child(dim)

	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -240.0
	card.offset_top = -180.0
	card.offset_right = 240.0
	card.offset_bottom = 180.0
	card.add_theme_stylebox_override("panel", _card_style())
	name_dialog.add_child(card)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 30.0
	box.offset_top = 26.0
	box.offset_right = -30.0
	box.offset_bottom = -26.0
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var title := _board_label("YOUR NAME", 28, G.UI_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	name_edit = LineEdit.new()
	name_edit.max_length = S.NAME_MAX
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.placeholder_text = S.DEFAULT_NAME
	name_edit.custom_minimum_size = Vector2(0.0, 56.0)
	name_edit.add_theme_font_size_override("font_size", 28)
	name_edit.add_theme_stylebox_override("normal", _edit_style(false))
	name_edit.add_theme_stylebox_override("focus", _edit_style(true))
	name_edit.text_submitted.connect(func(_text: String) -> void: _on_name_save())
	box.add_child(name_edit)

	name_hint = _board_label("", 17, G.BAR_RED)
	name_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var save := _dialog_button("SAVE", 26, 60.0, true, _on_name_save)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(save)
	var reroll := _dialog_button("NEW", 20, 60.0, false, _on_name_reroll)
	reroll.custom_minimum_size = Vector2(110.0, 60.0)
	buttons.add_child(reroll)
	box.add_child(buttons)

	box.add_child(_dialog_button("CANCEL", 18, 46.0, false, func() -> void:
		name_dialog.visible = false))


func _dialog_button(text: String, font_size: int, height: float, primary: bool,
		handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, height)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	if primary:
		button.add_theme_stylebox_override("normal", _fill_style(G.BAR_GREEN, G.BAR_GREEN_D))
		button.add_theme_stylebox_override("hover", _fill_style(G.BAR_GREEN, G.BAR_GREEN_D))
		button.add_theme_stylebox_override("pressed", _fill_style(G.BAR_GREEN_D, G.BAR_GREEN_D))
	else:
		button.add_theme_stylebox_override("normal", _fill_style(G.UI_GREY, G.UI_GREY_D))
		button.add_theme_stylebox_override("hover", _fill_style(G.UI_GREY, G.UI_GREY_D))
		button.add_theme_stylebox_override("pressed", _fill_style(G.UI_GREY_D, G.UI_GREY_D))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(handler)
	return button


func _open_name_dialog() -> void:
	if scores_api:
		name_edit.text = scores_api.player_name
	name_hint.visible = false
	name_dialog.visible = true
	name_edit.grab_focus()
	name_edit.select_all()


func _on_name_save() -> void:
	if scores_api == null:
		name_dialog.visible = false
		return
	name_hint.visible = false
	var status: String = await scores_api.update_name(name_edit.text)
	match status:
		"ok":
			name_dialog.visible = false
			_refresh_board()
			scores_api.fetch_leaderboard()
		"taken":
			name_hint.text = "NAME TAKEN — TRY ANOTHER"
			name_hint.visible = true
		_:
			name_hint.text = "NO CONNECTION"
			name_hint.visible = true


func _on_name_reroll() -> void:
	if scores_api == null:
		return
	var suggested: String = await scores_api.suggest_name()
	if suggested != "":
		name_edit.text = suggested


func _refresh_board() -> void:
	for i in top_name_labels.size():
		if i < board_top.size() and board_top[i] is Dictionary:
			var entry: Dictionary = board_top[i]
			top_name_labels[i].text = str(entry.get("name", "—"))
			top_score_labels[i].text = str(int(entry.get("score", 0)))
		else:
			top_name_labels[i].text = "—"
			top_score_labels[i].text = ""
	var display_name: String = scores_api.player_name if scores_api else S.DEFAULT_NAME
	me_name_label.text = display_name
	# score/rank are null until this device's first submitted run
	var me_rank: Variant = board_me.get("rank")
	var me_score: Variant = board_me.get("score")
	me_rank_label.text = str(int(me_rank)) if me_rank != null else "–"
	me_score_label.text = str(int(me_score)) if me_score != null else str(best)


func _board_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _medal_color(place: int) -> Color:
	if place == 0:
		return G.HAT  # gold
	if place == 1:
		return Color("b0bec5")  # silver
	return G.CHIP2  # bronze


func _pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(32.0)
	style.set_border_width_all(2)
	style.border_color = Color("e5e5e5")
	return style


func _you_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = G.BAR_GREEN
	style.set_corner_radius_all(32.0)
	style.border_width_bottom = 5
	style.border_color = G.BAR_GREEN_D
	return style


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(28)
	style.shadow_color = Color(0.294, 0.294, 0.294, 0.18)
	style.shadow_size = 10
	return style


func _fill_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(16)
	style.border_width_bottom = 6
	style.border_color = edge
	return style


func _edit_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = G.BAR_GREEN if focused else G.UI_GREY
	return style
