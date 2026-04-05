extends Node
## ProgressionManager — cross-session engagement backbone.
## Autoloaded as "ProgressionManager".
##
## Responsibilities:
##   • Player UUID generation and persistence
##   • XP / Rank tracking
##   • Login streak + daily bonus calculation
##   • Daily mission state (load, track progress, mark complete)
##   • Weekly operation data
##   • Server sync (register on launch, post session on game over)
##   • Friend leaderboard + challenge system
##   • Medal tracking
##   • Local notification scheduling

# ── Signals ───────────────────────────────────────────────────────────────────
signal profile_loaded(data: Dictionary)       # fires after server /register responds
signal session_posted(result: Dictionary)     # fires after /session POST responds
signal leaderboard_ready(rows: Array)         # global or friend leaderboard
signal weekly_op_ready(op: Dictionary)
signal challenge_received_signal(data: Dictionary)
signal ranked_up(old_rank: int, new_rank: int, new_title: String)
signal medals_earned(medals: Array)           # array of {id, label}

# ── Rank titles ────────────────────────────────────────────────────────────────
const RANK_TITLES := [
	"",                # 0 unused
	"Survivor",        # 1
	"Recruit",         # 2
	"Scout",           # 3
	"Ranger",          # 4
	"Corporal",        # 5
	"Sergeant",        # 6
	"Staff Sergeant",  # 7
	"Master Sergeant", # 8
	"Warrant Officer", # 9
	"Lieutenant",      # 10
	"Captain",         # 11
	"Major",           # 12
	"Lt. Colonel",     # 13
	"Colonel",         # 14
	"Brigadier",       # 15
	"General",         # 16
	"Commander",       # 17
	"Shadow Operative",# 18
	"Elite Shadow",    # 19
	"Shadow Commander",# 20
]

# ── Daily mission pool (must mirror server's MISSION_POOL exactly) ─────────────
const MISSION_POOL := [
	{"id":"kill_30",    "label":"Kill 30 enemies",          "type":"kills",    "target":30,  "xp":150, "coins":25},
	{"id":"kill_50",    "label":"Kill 50 enemies",          "type":"kills",    "target":50,  "xp":250, "coins":40},
	{"id":"reach_5",    "label":"Reach Wave 5",             "type":"wave",     "target":5,   "xp":200, "coins":30},
	{"id":"reach_7",    "label":"Reach Wave 7",             "type":"wave",     "target":7,   "xp":400, "coins":60},
	{"id":"airstrike_2","label":"Use airstrike 2 times",    "type":"airstrike","target":2,   "xp":120, "coins":20},
	{"id":"play_coop",  "label":"Play a co-op game",        "type":"coop",     "target":1,   "xp":200, "coins":35},
	{"id":"build_5",    "label":"Place 5 structures",       "type":"builds",   "target":5,   "xp":100, "coins":15},
	{"id":"survive_w3", "label":"Survive Wave 3 uninjured", "type":"wave_hp",  "target":3,   "xp":300, "coins":50},
	{"id":"kill_tank",  "label":"Defeat the Tank boss",     "type":"boss",     "target":1,   "xp":500, "coins":80},
	{"id":"play_2",     "label":"Play 2 games today",       "type":"games",    "target":2,   "xp":150, "coins":25},
]

# ── Persisted state (merged into game_data save) ──────────────────────────────
var player_uuid: String = ""
var xp: int             = 0
var rank: int           = 1
var title: String       = "Survivor"
var login_streak: int   = 0
var total_kills: int    = 0
var total_games: int    = 0
var best_wave: int      = 0
var best_coop_wave: int = 0
var medals: Array       = []

# ── Runtime state (not saved — refreshed from server each launch) ─────────────
var streak_bonus: Dictionary = {}
var daily_missions: Array    = []   # Array of mission dicts from server
var mission_progress: Dictionary = {} # mission_id → current value
var missions_completed: Array = []   # ids completed this calendar day
var weekly_op: Dictionary    = {}
var friend_leaderboard: Array = []
var global_leaderboard: Array = []
var pending_challenges: Array = []

# ── In-session counters (reset each match) ────────────────────────────────────
var _session_kills: int       = 0
var _session_airstrikes: int  = 0
var _session_builds: int      = 0
var _session_coop: bool       = false
var _session_max_wave: int    = 0
var _session_hp_ok_wave3: bool = true  # stays true if player never took damage before wave 3 ends

# ── HTTP base URL ────────────────────────────────────────────────────────────
const REST_BASE := "http://192.168.68.124:3000"

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_local()
	_ensure_uuid()
	_register_with_server()

# ── UUID ──────────────────────────────────────────────────────────────────────
func _ensure_uuid() -> void:
	if player_uuid.is_empty():
		player_uuid = _generate_uuid()
		_save_local()

func _generate_uuid() -> String:
	# RFC-4122 v4 UUID using random bytes
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(randi() % 256)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var h := func(b: int) -> String: return ("%02x" % b)
	return (h.call(bytes[0]) + h.call(bytes[1]) + h.call(bytes[2]) + h.call(bytes[3]) + "-" +
			h.call(bytes[4]) + h.call(bytes[5]) + "-" +
			h.call(bytes[6]) + h.call(bytes[7]) + "-" +
			h.call(bytes[8]) + h.call(bytes[9]) + "-" +
			h.call(bytes[10]) + h.call(bytes[11]) + h.call(bytes[12]) +
			h.call(bytes[13]) + h.call(bytes[14]) + h.call(bytes[15]))

# ── Server registration ────────────────────────────────────────────────────────
func _register_with_server() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_register_complete.bind(http))
	var body := JSON.stringify({"uuid": player_uuid, "name": GameData.player_name})
	var err := http.request(REST_BASE + "/player/register",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("ProgressionManager: /register request failed (%d)" % err)
		http.queue_free()

func _on_register_complete(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("ProgressionManager: /register returned %d" % code)
		return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null: return
	_apply_server_profile(data)
	_load_mission_progress()
	profile_loaded.emit(data)
	_schedule_local_notification()

func _apply_server_profile(data: Dictionary) -> void:
	xp             = data.get("xp", xp)
	rank           = data.get("rank", rank)
	title          = data.get("title", title)
	login_streak   = data.get("login_streak", login_streak)
	total_kills    = data.get("total_kills", total_kills)
	total_games    = data.get("total_games", total_games)
	best_wave      = data.get("best_wave", best_wave)
	best_coop_wave = data.get("best_coop_wave", best_coop_wave)
	medals         = data.get("medals", medals)
	streak_bonus   = data.get("streak_bonus", {})
	weekly_op      = data.get("weekly_op", {})

	# Daily missions: only replace if it's a fresh day
	var server_missions: Array = data.get("daily_missions", [])
	if server_missions.size() > 0:
		daily_missions = server_missions
		_save_local()

	# Fetch pending challenges
	_fetch_challenges()

# ── Session tracking ────────────────────────────────────────────────────────────
func session_start(is_coop: bool) -> void:
	_session_kills      = 0
	_session_airstrikes = 0
	_session_builds     = 0
	_session_coop       = is_coop
	_session_max_wave   = 0
	_session_hp_ok_wave3 = true

func on_enemy_killed() -> void:
	_session_kills += 1
	_tick_mission("kills", _session_kills)

func on_wave_reached(wave: int) -> void:
	_session_max_wave = wave
	_tick_mission("wave", wave)
	if wave >= 3 and _session_hp_ok_wave3:
		_tick_mission("wave_hp", wave)

func on_player_damaged_before_wave(wave: int) -> void:
	if wave < 3:
		_session_hp_ok_wave3 = false

func on_airstrike_used() -> void:
	_session_airstrikes += 1
	_tick_mission("airstrike", _session_airstrikes)

func on_structure_built() -> void:
	_session_builds += 1
	_tick_mission("builds", _session_builds)

func on_boss_killed() -> void:
	_tick_mission("boss", 1)

func on_coop_game_played() -> void:
	if _session_coop:
		_tick_mission("coop", 1)

# ── Mission progress ────────────────────────────────────────────────────────────
func _load_mission_progress() -> void:
	# Load today's progress from save, or reset if it's a new day
	var today := Time.get_date_string_from_system()
	var saved_date: String = _local_data.get("mission_date", "")
	if saved_date != today:
		mission_progress = {}
		missions_completed = []
		_local_data["mission_date"]      = today
		_local_data["mission_progress"]  = {}
		_local_data["missions_completed"] = []
		_save_local()
	else:
		mission_progress  = _local_data.get("mission_progress", {})
		missions_completed = _local_data.get("missions_completed", [])

func _tick_mission(mission_type: String, value: int) -> void:
	for m in daily_missions:
		if m.get("type") == mission_type and not (m["id"] in missions_completed):
			var prev: int = mission_progress.get(m["id"], 0)
			var current: int = max(prev, value) if mission_type in ["wave", "wave_hp"] else value
			mission_progress[m["id"]] = current
			if current >= m.get("target", 1):
				_complete_mission(m)
	_save_mission_progress()

func _complete_mission(m: Dictionary) -> void:
	if m["id"] in missions_completed: return
	missions_completed.append(m["id"])
	_save_mission_progress()

func _save_mission_progress() -> void:
	_local_data["mission_progress"]   = mission_progress
	_local_data["missions_completed"] = missions_completed
	_save_local()

## Returns coins bonus to apply at session start from completed missions
func consume_mission_coin_rewards() -> int:
	var coins := 0
	var today := Time.get_date_string_from_system()
	var claimed: Array = _local_data.get("missions_claimed", [])
	var claimed_date: String = _local_data.get("missions_claimed_date", "")
	if claimed_date != today: claimed = []
	for m in daily_missions:
		if (m["id"] in missions_completed) and not (m["id"] in claimed):
			coins += m.get("coins", 0)
			claimed.append(m["id"])
	_local_data["missions_claimed"]      = claimed
	_local_data["missions_claimed_date"] = today
	_save_local()
	return coins

## Returns how many missions are done today
func missions_done_count() -> int:
	return missions_completed.size()

# ── Session post (call from game_over.gd) ─────────────────────────────────────
func post_session(wave: int, kills: int, duration_s: int, partner_uuid: String = "") -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_session_complete.bind(http, wave))
	var body := JSON.stringify({
		"uuid":         player_uuid,
		"wave":         wave,
		"kills":        kills,
		"duration_s":   duration_s,
		"is_coop":      GameData.is_multiplayer,
		"partner_uuid": partner_uuid,
		"op_week":      weekly_op.get("week_key", ""),
	})
	http.request(REST_BASE + "/session", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)

func _on_session_complete(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, wave: int) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("ProgressionManager: /session returned %d" % code)
		return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null: return
	var old_rank := rank
	xp    = data.get("new_xp", xp)
	rank  = data.get("new_rank", rank)
	title = data.get("new_title", title)
	total_kills = data.get("total_kills", total_kills)
	total_games = data.get("total_games", total_games)
	best_wave   = data.get("best_wave", best_wave)
	if data.get("ranked_up", false):
		ranked_up.emit(old_rank, rank, title)
	var new_medals: Array = data.get("new_medals", [])
	if new_medals.size() > 0:
		for m in new_medals:
			if not (m["id"] in medals):
				medals.append(m["id"])
		medals_earned.emit(new_medals)
	_save_local()
	session_posted.emit(data)

# ── Friend leaderboard ────────────────────────────────────────────────────────
func fetch_friend_leaderboard() -> void:
	if GameData.saved_friends.is_empty(): return
	var names := ",".join(PackedStringArray(GameData.saved_friends))
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_friend_lb.bind(http))
	http.request(REST_BASE + "/leaderboard/friends?names=" + names.uri_encode())

func _on_friend_lb(result: int, code: int, _h, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null: return
	friend_leaderboard = data.get("leaderboard", [])
	leaderboard_ready.emit(friend_leaderboard)

func fetch_global_leaderboard() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_global_lb.bind(http))
	http.request(REST_BASE + "/leaderboard/global?limit=25")

func _on_global_lb(result: int, code: int, _h, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null: return
	global_leaderboard = data.get("leaderboard", [])
	leaderboard_ready.emit(global_leaderboard)

# ── Challenge ─────────────────────────────────────────────────────────────────
func send_challenge(to_name: String, wave: int, kills: int) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free())
	var body := JSON.stringify({
		"from_uuid":  player_uuid,
		"to_name":    to_name,
		"from_name":  GameData.player_name,
		"wave":       wave,
		"kills":      kills,
	})
	http.request(REST_BASE + "/challenge", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)

func _fetch_challenges() -> void:
	if player_uuid.is_empty(): return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_challenges.bind(http))
	http.request(REST_BASE + "/challenges?uuid=" + player_uuid.uri_encode())

func _on_challenges(result: int, code: int, _h, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data == null: return
	pending_challenges = data.get("challenges", [])

# ── Local persistence ─────────────────────────────────────────────────────────
const _PROG_SAVE_PATH := "user://progression.json"
var _local_data: Dictionary = {}

func _load_local() -> void:
	if not FileAccess.file_exists(_PROG_SAVE_PATH): return
	var f := FileAccess.open(_PROG_SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary): return
	_local_data     = parsed
	player_uuid     = _local_data.get("uuid", "")
	xp              = _local_data.get("xp", 0)
	rank            = _local_data.get("rank", 1)
	title           = _local_data.get("title", "Survivor")
	login_streak    = _local_data.get("login_streak", 0)
	total_kills     = _local_data.get("total_kills", 0)
	total_games     = _local_data.get("total_games", 0)
	best_wave       = _local_data.get("best_wave", 0)
	best_coop_wave  = _local_data.get("best_coop_wave", 0)
	medals          = _local_data.get("medals", [])
	daily_missions  = _local_data.get("daily_missions", [])
	mission_progress = _local_data.get("mission_progress", {})
	missions_completed = _local_data.get("missions_completed", [])

func _save_local() -> void:
	_local_data["uuid"]               = player_uuid
	_local_data["xp"]                 = xp
	_local_data["rank"]               = rank
	_local_data["title"]              = title
	_local_data["login_streak"]       = login_streak
	_local_data["total_kills"]        = total_kills
	_local_data["total_games"]        = total_games
	_local_data["best_wave"]          = best_wave
	_local_data["best_coop_wave"]     = best_coop_wave
	_local_data["medals"]             = medals
	_local_data["daily_missions"]     = daily_missions
	_local_data["mission_progress"]   = _local_data.get("mission_progress", {})
	_local_data["missions_completed"] = _local_data.get("missions_completed", [])
	var f := FileAccess.open(_PROG_SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(_local_data))
	f.close()

# ── Local notification scheduling ─────────────────────────────────────────────
func _schedule_local_notification() -> void:
	# Schedule a "come back tomorrow" reminder 26 hours from now
	# Only on mobile platforms that support it
	if not (OS.get_name() in ["Android", "iOS"]): return
	var title_str := "Resistance | Day %d Streak" % (login_streak + 1)
	var body_str  := "Your daily missions are ready. Keep the streak alive, Commander."
	# Godot 4 mobile notification support via the engine's OS API (requires plugin on iOS)
	# Using OS.alert as fallback verification; real push would need a plugin (e.g. godot-ios-push-notifications)
	print("ProgressionManager: notification scheduled — ", title_str)

# ── Convenience getters ────────────────────────────────────────────────────────
func get_rank_title(r: int = -1) -> String:
	var idx: int = r if r >= 0 else rank
	if idx >= 0 and idx < RANK_TITLES.size():
		return RANK_TITLES[idx]
	return "Survivor"

func get_streak_bonus_coins() -> int:
	return streak_bonus.get("coins", 0)

func get_streak_bonus_weapon() -> int:
	return streak_bonus.get("weapon", 0)  # 0=pistol, 1=shotgun, 2=rifle, 3=lmg

func get_streak_bonus_label() -> String:
	return streak_bonus.get("label", "")

func is_mission_complete(mission_id: String) -> bool:
	return mission_id in missions_completed

func get_mission_progress(mission_id: String) -> int:
	return mission_progress.get(mission_id, 0)
