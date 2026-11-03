extends Node
## Online leaderboard client — talks to the Supabase PostgREST API over a
## plain HTTPRequest, so it needs no addon and survives the addons-free
## export flow. Identity is device-based (a generated UUID), not accounts:
## one name per device, one best score per device. The publishable key is
## safe to ship; all writes go through server-side RPCs that validate input.

signal leaderboard_loaded(ok: bool, data: Dictionary)  # all-time board (settings)
signal daily_loaded(ok: bool, data: Dictionary)  # today's board (main menu)

const G := preload("res://scripts/main.gd")

const SUPABASE_URL := "https://jckjbflijtwownhnewgz.supabase.co"
const API_KEY := "sb_publishable_0b2QHyYkpR_aIwCQ4aXf4A_RI4_cQ40"
const SAVE_PATH := "user://lumberjack_online.cfg"
const DEFAULT_NAME := "Lumberjack"
const NAME_MAX := 16
const REQUEST_TIMEOUT := 5.0

var device_id := ""
var player_name := DEFAULT_NAME
var pending_best := false  # a best that failed to upload; retried on next boot
# True while a rename failed to reach the server: the local name wins and is
# carried by the next submit instead of being overwritten by fetches.
var name_dirty := false


func _ready() -> void:
	_load_local()


## Submit a finished run. Fire-and-forget; if the upload fails the run's
## device stays flagged and retry_pending() re-uploads the local best when
## the menu next opens.
func submit(score: int) -> void:
	if score <= 0:
		return
	var res: Dictionary = await _rpc("submit_score", {
		"p_device_id": device_id,
		# Empty = "you pick": the server assigns/keeps the generated alias.
		"p_name": "" if player_name == DEFAULT_NAME else player_name,
		"p_score": score,
		# Minutes east of UTC: the server stamps the run with this device's
		# local calendar day, which drives the daily board.
		"p_offset_minutes": _tz_offset_minutes(),
	})
	if res.has("best"):
		if pending_best:
			pending_best = false
			_save_local()
	else:
		pending_best = true
		_save_local()


## Re-upload the local best after a failed submit (e.g. the run was played
## offline). Called when the menu opens.
func retry_pending() -> void:
	if not pending_best:
		return
	var best := _local_best()
	if best > 0:
		submit(best)


## Store a new display name locally and sync it to the server immediately.
## Returns "ok", "taken" (someone else owns that name) or "error" (offline).
func update_name(new_name: String) -> String:
	player_name = _sanitize_name(new_name)
	_save_local()
	var res: Dictionary = await _rpc("update_name", {
		"p_device_id": device_id,
		"p_name": player_name,
	})
	if res.has("name"):
		name_dirty = false
		var confirmed := _sanitize_name(str(res["name"]))
		if confirmed != player_name:
			player_name = confirmed
			_save_local()
		return "ok"
	if res.has("error"):
		return "taken"
	name_dirty = true
	return "error"


## Ask the server for a fresh generated alias (no write) for the NEW button.
func suggest_name() -> String:
	var res: Dictionary = await _rpc("suggest_name", {})
	return str(res["name"]) if res.has("name") else ""


## One round trip: all-time top 3 + this device's entry and rank. The server
## also assigns a generated alias to unseen devices, so adopt it as our name.
func fetch_leaderboard() -> void:
	var res: Dictionary = await _rpc("get_leaderboard", {"p_device_id": device_id})
	if res.has("top"):
		_adopt_server_name(res.get("me"))
	var ok := res.has("top")
	leaderboard_loaded.emit(ok, res if ok else {})


## Same round trip for the daily board, which resets at this device's own
## local midnight: today's top 3 + today's score and rank.
func fetch_daily_leaderboard() -> void:
	var res: Dictionary = await _rpc("get_daily_leaderboard", {
		"p_device_id": device_id,
		"p_offset_minutes": _tz_offset_minutes(),
	})
	if res.has("top"):
		_adopt_server_name(res.get("me"))
	var ok := res.has("top")
	daily_loaded.emit(ok, res if ok else {})


func _adopt_server_name(me: Variant) -> void:
	var server_name: Variant = me.get("name") if me is Dictionary else null
	if server_name is String and server_name != "" \
			and not name_dirty and str(server_name) != player_name:
		player_name = _sanitize_name(str(server_name))
		_save_local()


## Minutes east of UTC (Godot reports bias in minutes, verified on this
## machine). The server derives the client-local calendar day from it.
func _tz_offset_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))


func _rpc(func_name: String, payload: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + API_KEY,
		"Authorization: Bearer " + API_KEY,
	])
	var url := "%s/rest/v1/rpc/%s" % [SUPABASE_URL, func_name]
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[1] < 200 or result[1] >= 300:
		return {}
	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _load_local() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		device_id = str(config.get_value("player", "device_id", ""))
		player_name = str(config.get_value("player", "name", DEFAULT_NAME))
		pending_best = bool(config.get_value("player", "pending_best", false))
		name_dirty = bool(config.get_value("player", "name_dirty", false))
	if device_id.is_empty():
		device_id = _make_uuid()
	player_name = _sanitize_name(player_name)
	_save_local()


func _save_local() -> void:
	# Own config file: main.gd's _save_best rewrites its file from scratch,
	# so sharing one would clobber whichever side wrote last.
	var config := ConfigFile.new()
	config.set_value("player", "device_id", device_id)
	config.set_value("player", "name", player_name)
	config.set_value("player", "pending_best", pending_best)
	config.set_value("player", "name_dirty", name_dirty)
	config.save(SAVE_PATH)


func _sanitize_name(raw: String) -> String:
	var clean := raw.strip_edges().substr(0, NAME_MAX)
	return clean if clean != "" else DEFAULT_NAME


func _local_best() -> int:
	var config := ConfigFile.new()
	if config.load(G.SAVE_PATH) == OK:
		return int(config.get_value("game", "best", 0))
	return 0


func _make_uuid() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40  # version 4
	bytes[8] = (bytes[8] & 0x3f) | 0x80  # RFC 4122 variant
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
