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
# The menu shows the DAILY board; the all-time board lives behind settings.
var scores_api: Node = null
var board_top: Array = []
var board_me: Dictionary = {}
var board_group: Control
var top_name_labels: Array = []
var top_score_labels: Array = []
var me_rank_label: Label
var me_name_label: Label
var me_score_label: Label
var countdown_label: Label
var countdown_next_ms := 0
var countdown_secs := -1  # -1 until the first tick, so the boot tick can't refetch
var name_dialog: Control
var name_edit: LineEdit
var name_hint: Label

# --- all-time board dialog (opened from the trophy button under the gear) ---
var alltime_dialog: Control
var alltime_open := false
var ranks_button: Button
var alltime_top: Array = []
var alltime_me: Dictionary = {}
var alltime_names: Array = []
var alltime_scores: Array = []
var alltime_rank_label: Label
var alltime_name_label: Label
var alltime_score_label: Label
var alltime_sub_label: Label

# --- settings (sound/haptics toggles, persisted with the best score) ---
var sound_on := true
var haptics_on := true
var settings_dialog: Control
var sound_toggle: ToggleSwitch
var haptic_toggle: ToggleSwitch

var best := 0
var elapsed := 0.0
var segments: Array = []

@onready var title_card: Panel = $UI/TitleCard
@onready var play_button: Button = $UI/PlayButton


func _ready() -> void:
	# Harness first: it seeds the RNG that _build_tree consumes.
	_setup_debug_harness()
	best = _load_best()
	_load_settings()
	play_button.pressed.connect(_on_play_pressed)
	_build_tree()
	_setup_leaderboard()
	_build_settings()
	_build_ranks_button()


func _build_tree() -> void:
	# Same fair-start rule as the game: the lumberjack stands on the left, so
	# the bottom branch must be on the right.
	segments = [G.Side.RIGHT]
	for i in 9:
		segments.append(G.Side.LEFT if randi() % 2 == 0 else G.Side.RIGHT)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	# Tick the reset countdown once a second; keep the pill text honest while
	# the menu sits open past midnight.
	if countdown_label and Time.get_ticks_msec() >= countdown_next_ms:
		countdown_next_ms = Time.get_ticks_msec() + 1000
		_tick_countdown()


func _tick_countdown() -> void:
	var secs := _seconds_until_midnight()
	if countdown_secs >= 0 and secs > countdown_secs and scores_api:
		scores_api.fetch_daily_leaderboard()  # the day rolled over on screen
	countdown_secs = secs
	countdown_label.text = _countdown_text(secs)


func _countdown_text(secs: int) -> String:
	if secs <= 0:
		return "DAILY · RESETS NOW"
	if secs < 60:
		return "DAILY · RESETS SOON"
	var h := secs / 3600
	var m := (secs % 3600) / 60
	if h > 0:
		return "DAILY · RESETS IN %dH %02dM" % [h, m]
	return "DAILY · RESETS IN %dM" % m


func _seconds_until_midnight() -> int:
	# Same clock the server uses for the daily key (bias = minutes east of
	# UTC): the board resets when this hits zero, at the local midnight.
	var bias_min := float(Time.get_time_zone_from_system().get("bias", 0))
	var local_now := Time.get_unix_time_from_system() + bias_min * 60.0
	return int(ceil((floor(local_now / 86400.0) + 1.0) * 86400.0 - local_now))


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _load_best() -> int:
	var config := ConfigFile.new()
	if config.load(G.SAVE_PATH) == OK:
		return config.get_value("game", "best", 0)
	return 0


# ---------------------------------------------------------------- settings ---

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(G.SAVE_PATH) == OK:
		sound_on = config.get_value("settings", "sound", true)
		haptics_on = config.get_value("settings", "haptics", true)


func _save_settings() -> void:
	# Load first: the best score lives in the same file.
	var config := ConfigFile.new()
	config.load(G.SAVE_PATH)
	config.set_value("settings", "sound", sound_on)
	config.set_value("settings", "haptics", haptics_on)
	config.save(G.SAVE_PATH)


func _build_settings() -> void:
	_build_settings_button()
	_build_settings_dialog()


func _build_settings_button() -> void:
	# Invisible tappable area: the icon itself floats on the sky, no card.
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -104.0
	button.offset_top = 20.0
	button.offset_right = -20.0
	button.offset_bottom = 104.0
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_open_settings)
	$UI.add_child(button)

	var gear := SettingsGear.new()
	gear.set_anchors_preset(Control.PRESET_FULL_RECT)
	gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(gear)


func _build_settings_dialog() -> void:
	settings_dialog = Control.new()
	settings_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_dialog.visible = false
	$UI.add_child(settings_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_dialog.add_child(dim)

	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -240.0
	card.offset_top = -164.0
	card.offset_right = 240.0
	card.offset_bottom = 164.0
	card.add_theme_stylebox_override("panel", _card_style())
	settings_dialog.add_child(card)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26.0
	box.offset_top = 24.0
	box.offset_right = -26.0
	box.offset_bottom = -24.0
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)

	var title := _board_label("SETTINGS", 28, G.UI_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_settings_row("SOUND", sound_on, _on_sound_toggled))
	box.add_child(_settings_row("HAPTICS", haptics_on, _on_haptic_toggled))

	box.add_child(_dialog_button("DONE", 24, 60.0, true, func() -> void:
		settings_dialog.visible = false))


func _open_alltime() -> void:
	alltime_open = true
	alltime_top = []
	alltime_me = {}
	alltime_sub_label.text = ""
	_refresh_alltime()
	alltime_dialog.visible = true
	if scores_api:
		scores_api.fetch_leaderboard()


func _build_alltime_dialog() -> void:
	alltime_dialog = Control.new()
	alltime_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	alltime_dialog.visible = false
	$UI.add_child(alltime_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	alltime_dialog.add_child(dim)

	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -250.0
	card.offset_top = -244.0
	card.offset_right = 250.0
	card.offset_bottom = 244.0
	card.add_theme_stylebox_override("panel", _card_style())
	alltime_dialog.add_child(card)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 30.0
	box.offset_top = 24.0
	box.offset_right = -30.0
	box.offset_bottom = -24.0
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	var title := _board_label("ALL-TIME", 28, G.UI_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	alltime_sub_label = _board_label("", 15, G.UI_GREY_D)
	alltime_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(alltime_sub_label)

	for i in 3:
		box.add_child(_make_top_pill(i, alltime_names, alltime_scores))

	var you := _make_you_pill(false)
	alltime_rank_label = you["rank"]
	alltime_name_label = you["name"]
	alltime_score_label = you["score"]
	box.add_child(you["pill"])

	box.add_child(_dialog_button("CLOSE", 18, 46.0, false, func() -> void:
		alltime_open = false
		alltime_dialog.visible = false))


func _settings_row(text: String, initial: bool, handler: Callable) -> Panel:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 64.0)
	row.add_theme_stylebox_override("panel", _pill_style())

	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20.0
	content.offset_right = -14.0
	content.add_theme_constant_override("separation", 12)
	row.add_child(content)

	var label := _board_label(text, 24, G.UI_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(label)

	var toggle := ToggleSwitch.new()
	toggle.on = initial
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.flipped.connect(handler)
	content.add_child(toggle)
	if text == "SOUND":
		sound_toggle = toggle
	else:
		haptic_toggle = toggle
	return row


func _open_settings() -> void:
	sound_toggle.on = sound_on
	haptic_toggle.on = haptics_on
	settings_dialog.visible = true


func _build_ranks_button() -> void:
	# Invisible tappable area like the settings gear: the trophy icon floats
	# on the sky right under the gear and opens the all-time board.
	ranks_button = Button.new()
	ranks_button.focus_mode = Control.FOCUS_NONE
	ranks_button.anchor_left = 1.0
	ranks_button.anchor_right = 1.0
	ranks_button.offset_left = -104.0
	ranks_button.offset_top = 112.0
	ranks_button.offset_right = -20.0
	ranks_button.offset_bottom = 196.0
	for state in ["normal", "hover", "pressed", "focus"]:
		ranks_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	ranks_button.pressed.connect(_open_alltime)
	$UI.add_child(ranks_button)

	var icon := LeaderboardIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ranks_button.add_child(icon)


func _on_sound_toggled(on: bool) -> void:
	sound_on = on
	sound_toggle.on = on  # keep the widget in sync when set programmatically
	_save_settings()


func _on_haptic_toggled(on: bool) -> void:
	haptics_on = on
	haptic_toggle.on = on
	_save_settings()


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
	var open_settings := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			prefix = arg.substr(4)
		elif arg.begins_with("settings="):
			open_settings = arg.substr(9) == "1"
	await get_tree().create_timer(0.6).timeout
	# The board fetches over the network; give it a moment so shots are
	# data-rich instead of placeholders.
	await _wait_daily_data(4.0)
	await _shot(prefix + "_menu.png")
	print("MENU state=menu best=", best, " countdown=", _countdown_text(_seconds_until_midnight()),
		" segs(bottom-up)=", segments)
	if open_settings:
		_open_settings()
		await get_tree().create_timer(0.3).timeout
		await _shot(prefix + "_settings.png")
		_on_sound_toggled(false)
		_on_haptic_toggled(false)
		await get_tree().create_timer(0.2).timeout
		await _shot(prefix + "_settings_off.png")
		print("SETTINGS sound=", sound_on, " haptics=", haptics_on)
		# Restore so the harness never leaves the user's save muted.
		_on_sound_toggled(true)
		_on_haptic_toggled(true)
		settings_dialog.visible = false
		# Open the all-time board through the real trophy button wiring.
		ranks_button.pressed.emit()
		await _wait_alltime_data(4.0)
		await get_tree().create_timer(0.3).timeout
		await _shot(prefix + "_ranks.png")
		print("RANKS sub=", alltime_sub_label.text)
		alltime_open = false
		alltime_dialog.visible = false
	_on_play_pressed()


func _wait_daily_data(timeout: float) -> void:
	var waited := 0.0
	while waited < timeout and board_top.is_empty():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


func _wait_alltime_data(timeout: float) -> void:
	var waited := 0.0
	while waited < timeout and alltime_top.is_empty():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


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
# The DAILY board: a reset-countdown badge, three slim white pills for
# today's top 3 and a green tappable "YOU" row that opens the rename dialog.
# The Scores autoload handles device identity and all HTTP; this section is
# display only.

func _setup_leaderboard() -> void:
	scores_api = get_node_or_null("/root/Scores")
	_build_board()
	_build_name_dialog()
	_build_alltime_dialog()
	if scores_api:
		scores_api.daily_loaded.connect(_on_daily_loaded)
		scores_api.leaderboard_loaded.connect(_on_alltime_loaded)
		_refresh_board()
		scores_api.retry_pending()
		scores_api.fetch_daily_leaderboard()


func _on_daily_loaded(ok: bool, data: Dictionary) -> void:
	if not ok:
		return  # keep whatever is on screen; offline shows placeholders
	board_top = data.get("top", [])
	var me: Variant = data.get("me")
	board_me = me if me is Dictionary else {}
	_refresh_board()


func _on_alltime_loaded(ok: bool, data: Dictionary) -> void:
	if not alltime_open or not ok:
		return
	alltime_top = data.get("top", [])
	var me: Variant = data.get("me")
	alltime_me = me if me is Dictionary else {}
	# JSON numbers decode as float, so accept any numeric total here.
	var total: Variant = data.get("total")
	if total != null:
		var n := int(total)
		alltime_sub_label.text = "NO SCORES YET" if n == 0 \
			else "TOP %d OF %d LUMBERJACKS" % [mini(alltime_top.size(), 3), n]
	_refresh_alltime()


func _build_board() -> void:
	# No enclosing card: a floating countdown badge, three slim white pills
	# for the top 3 and a green pill for this device, all hovering over the
	# world. Bottom sits above the lumberjack so he stays fully visible on
	# the grass.
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

	# The badge is what makes the board read as "daily": clock icon plus a
	# live countdown to the reset, ticking in _process.
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _badge_style())
	rows.add_child(badge)

	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 8)
	badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_row)
	badge_row.add_child(ClockIcon.new())
	countdown_label = _board_label("", 15, G.UI_GREY_D)
	badge_row.add_child(countdown_label)

	for i in 3:
		rows.add_child(_make_top_pill(i, top_name_labels, top_score_labels))

	var you := _make_you_pill(true)
	me_rank_label = you["rank"]
	me_name_label = you["name"]
	me_score_label = you["score"]
	rows.add_child(you["pill"])


## One medal pill; appends its labels to the given arrays so the daily board
## and the all-time dialog can each own a set.
func _make_top_pill(place: int, names: Array, scores: Array) -> Panel:
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

	names.append(name_label)
	scores.append(score_label)
	return pill


## The green "YOU" row. On the menu it's a tappable button that opens the
## rename dialog; in the all-time dialog it's a plain panel.
func _make_you_pill(tappable: bool) -> Dictionary:
	var pill: Control
	if tappable:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 64.0)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(_open_name_dialog)
		button.add_theme_stylebox_override("normal", _you_style())
		button.add_theme_stylebox_override("hover", _you_style())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var pressed := _you_style()
		pressed.bg_color = G.BAR_GREEN_D
		button.add_theme_stylebox_override("pressed", pressed)
		pill = button
	else:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0.0, 64.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _you_style())
		pill = panel

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

	var rank_label := _board_label("–", 20, G.BAR_GREEN)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle.add_child(rank_label)
	rank_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	var name_label := _board_label("—", 26, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)

	if tappable:
		row.add_child(_board_label("EDIT", 15, Color(1.0, 1.0, 1.0, 0.75)))

	var score_label := _board_label("", 26, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(score_label)
	return {"pill": pill, "rank": rank_label, "name": name_label, "score": score_label}


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
			scores_api.fetch_daily_leaderboard()
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
	# Daily semantics: "–" until this device's first run TODAY (a best from
	# yesterday must not leak in).
	_fill_board(top_name_labels, top_score_labels, board_top, board_me,
		me_rank_label, me_name_label, me_score_label, "–")


func _refresh_alltime() -> void:
	# All-time: before the first submitted run, the local best is the honest
	# stand-in for the score column.
	_fill_board(alltime_names, alltime_scores, alltime_top, alltime_me,
		alltime_rank_label, alltime_name_label, alltime_score_label, str(best))


func _fill_board(names: Array, scores: Array, top: Array, me: Dictionary,
		rank_label: Label, name_label: Label, score_label: Label,
		me_fallback: String) -> void:
	for i in names.size():
		if i < top.size() and top[i] is Dictionary:
			var entry: Dictionary = top[i]
			names[i].text = str(entry.get("name", "—"))
			scores[i].text = str(int(entry.get("score", 0)))
		else:
			names[i].text = "—"
			scores[i].text = ""
	name_label.text = scores_api.player_name if scores_api else S.DEFAULT_NAME
	# score/rank are null until this device has a run on the board
	var me_rank: Variant = me.get("rank")
	var me_score: Variant = me.get("score")
	rank_label.text = str(int(me_rank)) if me_rank != null else "–"
	score_label.text = str(int(me_score)) if me_score != null else me_fallback


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


func _badge_style() -> StyleBoxFlat:
	# Slimmer cousin of the pill style for the countdown badge.
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(16.0)
	style.set_border_width_all(2)
	style.border_color = Color("e5e5e5")
	style.content_margin_left = 14.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
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


# Custom-drawn widgets for the settings UI, matching the procedural art style.

class ClockIcon extends Control:
	const G := preload("res://scripts/main.gd")

	func _init() -> void:
		custom_minimum_size = Vector2(22.0, 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# Tiny wall clock on a green disc: the "resets at midnight" badge icon.
		var c := size * 0.5
		draw_circle(c, size.x * 0.5, G.BAR_GREEN)
		draw_line(c, c + Vector2(0.0, -size.x * 0.26), Color.WHITE, 2.0)
		draw_line(c, c + Vector2(size.x * 0.22, 0.0), Color.WHITE, 2.0)


class ToggleSwitch extends Control:
	const G := preload("res://scripts/main.gd")

	signal flipped(on: bool)

	var on := true:
		set(value):
			on = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(96.0, 52.0)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		# Duolingo pill track: flat fill on a darker bottom edge, white knob.
		var track := StyleBoxFlat.new()
		track.bg_color = G.BAR_GREEN if on else G.UI_GREY
		track.set_corner_radius_all(size.y * 0.5)
		track.border_width_bottom = 5
		track.border_color = G.BAR_GREEN_D if on else G.UI_GREY_D
		track.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		var r := size.y * 0.5 - 6.0
		var knob_x := size.x - r - 7.0 if on else r + 7.0
		draw_circle(Vector2(knob_x, size.y * 0.5), r, Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			on = not on
			flipped.emit(on)


class LeaderboardIcon extends Control:
	# Icon for the all-time leaderboard button, drawn in the game's plush
	# block style: flat fill on a darker bottom edge plus a soft highlight.
	# Four candidates; "trophy" is the shipped look.
	const G := preload("res://scripts/main.gd")

	var style := "trophy":
		set(value):
			style = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(84.0, 84.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var unit := minf(size.x, size.y)
		match style:
			"podium":
				_draw_podium(c, unit)
			"medal":
				_draw_medal(c, unit)
			"crown":
				_draw_crown(c, unit)
			_:
				_draw_trophy(c, unit)

	func _draw_trophy(c: Vector2, unit: float) -> void:
		for layer in [[Vector2(0.0, unit * 0.05), G.HAT_D], [Vector2.ZERO, G.HAT]]:
			var off: Vector2 = layer[0]
			var col: Color = layer[1]
			# Handles first: they tuck behind the bowl.
			draw_arc(c + Vector2(-unit * 0.33, -unit * 0.18) + off, unit * 0.11,
				PI * 0.4, PI * 1.6, 12, col, unit * 0.05)
			draw_arc(c + Vector2(unit * 0.33, -unit * 0.18) + off, unit * 0.11,
				-PI * 0.6, PI * 0.6, 12, col, unit * 0.05)
			# Bowl: rect rim over a round bottom.
			draw_rect(Rect2(c.x - unit * 0.27 + off.x, c.y - unit * 0.34 + off.y,
				unit * 0.54, unit * 0.26), col)
			draw_circle(c + Vector2(0.0, -unit * 0.08) + off, unit * 0.27, col)
			# Stem and pill base.
			draw_rect(Rect2(c.x - unit * 0.05 + off.x, c.y + unit * 0.14 + off.y,
				unit * 0.10, unit * 0.16), col)
			draw_rect(Rect2(c.x - unit * 0.14 + off.x, c.y + unit * 0.28 + off.y,
				unit * 0.28, unit * 0.12), col)
			draw_circle(c + Vector2(-unit * 0.14, unit * 0.34) + off, unit * 0.06, col)
			draw_circle(c + Vector2(unit * 0.14, unit * 0.34) + off, unit * 0.06, col)
		draw_circle(c + Vector2(-unit * 0.13, -unit * 0.22), unit * 0.055,
			Color(G.CANOPY_HL, 0.85))

	func _draw_podium(c: Vector2, unit: float) -> void:
		# Silver-gold-bronze pillars, bottom aligned, numbers on the front.
		var pillars := [
			[unit * -0.26, unit * 0.36, Color("b0bec5"), Color("93a3ab"), "2"],
			[0.0, unit * 0.52, G.HAT, G.HAT_D, "1"],
			[unit * 0.26, unit * 0.26, G.CHIP2, Color("cc7a00"), "3"],
		]
		var font := G.UI_FONT
		var bottom := c.y + unit * 0.34
		var w := unit * 0.24
		for p in pillars:
			var cx: float = c.x + p[0]
			var top: float = bottom - float(p[1])
			for layer in [[Vector2(0.0, unit * 0.05), p[3]], [Vector2.ZERO, p[2]]]:
				var off: Vector2 = layer[0]
				var col: Color = layer[1]
				draw_rect(Rect2(cx - w * 0.5 + off.x, top + w * 0.5 + off.y,
					w, float(p[1]) - w * 0.5), col)
				draw_circle(Vector2(cx, top + w * 0.5) + off, w * 0.5, col)
			draw_string(font, Vector2(cx - w * 0.5, bottom - float(p[1]) * 0.5 + unit * 0.06),
				str(p[4]), HORIZONTAL_ALIGNMENT_CENTER, w, int(unit * 0.17), Color.WHITE)

	func _draw_medal(c: Vector2, unit: float) -> void:
		for layer in [[Vector2(0.0, unit * 0.04), G.BAR_RED_D], [Vector2.ZERO, G.BAR_RED]]:
			var off: Vector2 = layer[0]
			var col: Color = layer[1]
			for side in [-1.0, 1.0]:
				draw_set_transform(c + Vector2(side * unit * 0.12, -unit * 0.30) + off,
					side * 0.3, Vector2.ONE)
				draw_rect(Rect2(-unit * 0.07, 0.0, unit * 0.14, unit * 0.34), col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for layer in [[Vector2(0.0, unit * 0.05), G.HAT_D], [Vector2.ZERO, G.HAT]]:
			draw_circle(c + Vector2(0.0, unit * 0.08) + layer[0], unit * 0.28, layer[1])
		draw_string(G.UI_FONT, Vector2(c.x - unit * 0.28, c.y + unit * 0.16),
			"1", HORIZONTAL_ALIGNMENT_CENTER, unit * 0.56, int(unit * 0.22), Color.WHITE)
		draw_circle(c + Vector2(-unit * 0.10, -unit * 0.02), unit * 0.05,
			Color(G.CANOPY_HL, 0.85))

	func _draw_crown(c: Vector2, unit: float) -> void:
		var pts := PackedVector2Array([
			Vector2(-unit * 0.32, unit * 0.10), Vector2(-unit * 0.22, -unit * 0.24),
			Vector2(-unit * 0.11, 0.0), Vector2(0.0, -unit * 0.30),
			Vector2(unit * 0.11, 0.0), Vector2(unit * 0.22, -unit * 0.24),
			Vector2(unit * 0.32, unit * 0.10),
		])
		for layer in [[Vector2(0.0, unit * 0.05), G.HAT_D], [Vector2.ZERO, G.HAT]]:
			var off: Vector2 = layer[0]
			var shifted := PackedVector2Array()
			for p in pts:
				shifted.append(c + p + off)
			draw_colored_polygon(shifted, layer[1])
			for i in [1, 3, 5]:
				draw_circle(c + pts[i] + off, unit * 0.05, layer[1])
			# Band as a soft pill across the bottom.
			draw_rect(Rect2(c.x - unit * 0.24 + off.x, c.y + unit * 0.08 + off.y,
				unit * 0.48, unit * 0.16), layer[1])
			draw_circle(c + Vector2(-unit * 0.24, unit * 0.16) + off, unit * 0.08, layer[1])
			draw_circle(c + Vector2(unit * 0.24, unit * 0.16) + off, unit * 0.08, layer[1])
		draw_circle(c + Vector2(-unit * 0.18, unit * 0.16), unit * 0.04,
			Color(G.CANOPY_HL, 0.85))


class SettingsGear extends Control:
	const G := preload("res://scripts/main.gd")

	var style := "green":
		set(value):
			style = value
			queue_redraw()

	func _draw() -> void:
		if style == "sliders":
			_draw_sliders()
		else:
			_draw_gear()

	func _draw_gear() -> void:
		# Puffy gear in the game's block style: fat rounded lobes on a flat
		# fill sitting on a darker bottom edge, with a plush highlight.
		var c := size * 0.5
		var unit := minf(size.x, size.y)
		var fill := G.TRUNK
		var edge := G.TRUNK_D
		var shine := Color(0.0, 0.0, 0.0, 0.0)
		if style == "steel":
			fill = G.STEEL
			edge = G.UI_GREY_D
		elif style == "green":
			fill = G.BAR_GREEN
			edge = G.BAR_GREEN_D
			shine = Color(G.CANOPY_HL, 0.85)
		for layer in [[Vector2(0.0, unit * 0.07), edge], [Vector2.ZERO, fill]]:
			var off: Vector2 = layer[0]
			var col: Color = layer[1]
			for i in 8:
				draw_set_transform(c + off, TAU * i / 8.0, Vector2.ONE)
				# Rounded lobes with visible notches between them: soft but
				# still a gear, not a flower.
				draw_rect(Rect2(unit * 0.19, -unit * 0.09, unit * 0.15, unit * 0.18), col)
				draw_circle(Vector2(unit * 0.19, 0.0), unit * 0.09, col)
				draw_circle(Vector2(unit * 0.34, 0.0), unit * 0.09, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(c + off, unit * 0.28, col)
		draw_circle(c, unit * 0.17, Color.WHITE)
		if shine.a > 0.0:
			# Soft plush highlight, upper-left like the canopy highlights.
			draw_circle(c + Vector2(-unit * 0.13, -unit * 0.13), unit * 0.055, shine)
		if style == "wood":
			# Light bark streak, like the trunk's growth stripes.
			draw_rect(Rect2(c.x - unit * 0.03, c.y - unit * 0.25, unit * 0.06, unit * 0.13),
				G.TRUNK_L)

	func _draw_sliders() -> void:
		# Mixer-style settings icon: three tracks with chunky knobs in the
		# combo-badge colors.
		var unit := minf(size.x, size.y)
		var edge := unit * 0.045
		var knob_pos := [0.0, 0.72, 0.34]
		var knob_fill := [G.BAR_GREEN, G.HAT, G.BAR_RED]
		var knob_edge := [G.BAR_GREEN_D, G.HAT_D, G.BAR_RED_D]
		for i in 3:
			var y := size.y * (0.22 + 0.26 * i)
			var track_h := unit * 0.10
			draw_rect(Rect2(size.x * 0.06, y + edge, size.x * 0.88, track_h), G.UI_GREY_D)
			draw_rect(Rect2(size.x * 0.06, y, size.x * 0.88, track_h), G.UI_GREY)
			var center := Vector2(size.x * (0.20 + 0.60 * knob_pos[i]),
				y + track_h * 0.5)
			draw_circle(center + Vector2(0.0, edge), unit * 0.135, knob_edge[i])
			draw_circle(center, unit * 0.135, knob_fill[i])
