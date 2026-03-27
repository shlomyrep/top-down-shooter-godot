extends Node
## Minimal Socket.IO v4 (Engine.IO v4) client running over WebSocket.
## Connects to the relay server and exposes typed signals for game code.
##
## !!  Change SERVER_URL to your server's address before deploying  !!
##     For LAN testing on a device use your PC's local IP, e.g.:
##       ws://192.168.1.10:3000/socket.io/?EIO=4&transport=websocket
##     For editor / desktop testing localhost works:
##       ws://127.0.0.1:3000/socket.io/?EIO=4&transport=websocket

const SERVER_URL := "ws://192.168.68.124:3000/socket.io/?EIO=4&transport=websocket"

# ── Signals ────────────────────────────────────────────────────────────────────
signal connected_to_server
signal disconnected_from_server
signal match_found(room_id: String, partner_name: String, is_host: bool)
signal partner_ready
signal game_start
signal remote_player_state(data: Dictionary)
signal remote_bullet_fired(data: Dictionary)
signal partner_died
signal partner_disconnected
# Enemy sync
signal remote_enemy_spawned(data: Dictionary)
signal remote_enemies_sync(batch: Array)
signal remote_enemy_killed(data: Dictionary)
signal remote_enemy_hit(data: Dictionary)
# Wave / build
signal remote_wave_event(data: Dictionary)
signal remote_build_ready_vote(data: Dictionary)
signal remote_build_end_vote
# Structure sync
signal remote_structure_placed(data: Dictionary)
signal remote_structure_erased(data: Dictionary)
signal remote_door_toggled(data: Dictionary)
# Score
signal remote_score_sync(data: Dictionary)
# Support abilities
signal remote_squad_spawned(data: Dictionary)
signal remote_airstrike_used(data: Dictionary)
# Coin deduplication
signal remote_coin_collected(data: Dictionary)
# Revive mechanic
signal remote_player_downed(data: Dictionary)
signal remote_player_revived(data: Dictionary)
# Game over sync (carries kills count)
signal remote_game_over_sync(data: Dictionary)

# ── Private state ──────────────────────────────────────────────────────────────
var _socket:    WebSocketPeer
var _connected: bool   = false
var _room_id:   String = ""
var _connect_timer: float = 0.0
const _CONNECT_TIMEOUT := 10.0  # seconds before giving up

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_process(false)  # only poll while a socket exists

# ── Public API ─────────────────────────────────────────────────────────────────

func connect_to_server() -> void:
	if _socket:
		var s := _socket.get_ready_state()
		if s == WebSocketPeer.STATE_OPEN or s == WebSocketPeer.STATE_CONNECTING:
			return  # already connecting / connected
	_socket = WebSocketPeer.new()
	_connect_timer = 0.0
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		push_error("NetworkManager: connect_to_url failed – %s" % error_string(err))
		disconnected_from_server.emit()
		return
	set_process(true)

func disconnect_from_server() -> void:
	if _socket:
		_socket.close()
	_connected = false
	_room_id   = ""
	set_process(false)

func is_online() -> bool:
	return _connected

func get_room_id() -> String:
	return _room_id

# Matchmaking
func find_match(player_name: String) -> void:
	_emit_sio("find_match", {"player_name": player_name})

func cancel_search() -> void:
	_emit_sio("cancel_search", {})

func send_ready() -> void:
	_emit_sio("player_ready", {"room_id": _room_id})

# In-game
func send_player_state(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("player_state", data)

func send_bullet_fired(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("bullet_fired", data)

func send_player_died() -> void:
	_emit_sio("player_died", {"room_id": _room_id})

# Enemy sync (host → client)
func send_enemy_spawned(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("enemy_spawned", data)

func send_enemies_sync(batch: Array) -> void:
	_emit_sio("enemies_sync", {"room_id": _room_id, "batch": batch})

func send_enemy_killed(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("enemy_killed", data)

func send_enemy_hit(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("enemy_hit", data)

# Wave / build phase
func send_wave_event(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("wave_event", data)

func send_build_ready_vote() -> void:
	_emit_sio("build_ready_vote", {"room_id": _room_id})

# Structure sync
func send_structure_placed(type: String, cx: int, cy: int) -> void:
	_emit_sio("structure_placed", {"room_id": _room_id, "type": type, "cx": cx, "cy": cy})

func send_structure_erased(cx: int, cy: int) -> void:
	_emit_sio("structure_erased", {"room_id": _room_id, "cx": cx, "cy": cy})

func send_door_toggled(is_open: bool) -> void:
	_emit_sio("door_toggled", {"room_id": _room_id, "is_open": is_open})

# Score
func send_score_sync(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("score_sync", data)

# Support abilities
func send_squad_spawned(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("squad_spawned", data)

func send_airstrike_used(data: Dictionary) -> void:
	data["room_id"] = _room_id
	_emit_sio("airstrike_used", data)

func send_coin_collected(net_id: String) -> void:
	_emit_sio("coin_collected", {"room_id": _room_id, "net_id": net_id})

func send_player_downed() -> void:
	_emit_sio("player_downed", {"room_id": _room_id})

func send_player_revived() -> void:
	_emit_sio("player_revived", {"room_id": _room_id})

func send_game_over_sync(kills: int) -> void:
	_emit_sio("game_over_sync", {"room_id": _room_id, "kills": kills})

# ── Godot process loop ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _socket:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_connect_timer += delta
		if _connect_timer >= _CONNECT_TIMEOUT:
			push_warning("NetworkManager: connection timed out after %ds" % int(_CONNECT_TIMEOUT))
			_socket.close()
			_socket = null
			_connected = false
			_room_id   = ""
			set_process(false)
			disconnected_from_server.emit()
		return
	if state == WebSocketPeer.STATE_OPEN:
		_connect_timer = 0.0
		while _socket.get_available_packet_count() > 0:
			_handle_raw(_socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_connected := _connected
		_connected = false
		_room_id   = ""
		_socket    = null
		set_process(false)
		# Emit regardless of whether we were fully connected — 
		# covers the case where STATE_CONNECTING → STATE_CLOSED (server unreachable)
		disconnected_from_server.emit()
		if not was_connected:
			push_warning("NetworkManager: socket closed before connecting (server unreachable?)")

# ── Engine.IO / Socket.IO protocol ────────────────────────────────────────────

func _handle_raw(msg: String) -> void:
	if msg.is_empty():
		return
	match msg[0]:
		"0":  # EIO OPEN – respond with SIO namespace connect
			_raw_send("40")
		"2":  # EIO PING
			_raw_send("3")   # EIO PONG
		"4":  # EIO MESSAGE – forward to SIO handler
			_handle_sio(msg.substr(1))

func _handle_sio(msg: String) -> void:
	if msg.is_empty():
		return
	match msg[0]:
		"0":  # SIO CONNECT (namespace confirmed)
			_connected = true
			connected_to_server.emit()
		"1":  # SIO DISCONNECT
			_connected = false
			disconnected_from_server.emit()
		"2":  # SIO EVENT
			_dispatch(msg.substr(1))

func _dispatch(payload: String) -> void:
	var parsed = JSON.parse_string(payload)
	if not parsed is Array or parsed.is_empty():
		return
	var event_name: String = str(parsed[0])
	var data: Dictionary = parsed[1] if parsed.size() > 1 and parsed[1] is Dictionary else {}

	match event_name:
		"searching":
			pass  # server acknowledged; lobby handles UI
		"match_found":
			_room_id              = str(data.get("room_id", ""))
			GameData.room_id      = _room_id
			GameData.is_host      = bool(data.get("is_host", false))
			GameData.partner_name = str(data.get("partner_name", "UNKNOWN"))
			GameData.is_multiplayer = true
			match_found.emit(_room_id, GameData.partner_name, GameData.is_host)
		"partner_ready":
			partner_ready.emit()
		"game_start":
			game_start.emit()
		"remote_player_state":
			remote_player_state.emit(data)
		"remote_bullet_fired":
			remote_bullet_fired.emit(data)
		"partner_died":
			partner_died.emit()
		"partner_disconnected":
			partner_disconnected.emit()
		# Enemy sync
		"remote_enemy_spawned":
			remote_enemy_spawned.emit(data)
		"remote_enemies_sync":
			remote_enemies_sync.emit(data.get("batch", []))
		"remote_enemy_killed":
			remote_enemy_killed.emit(data)
		"remote_enemy_hit":
			remote_enemy_hit.emit(data)
		# Wave / build
		"remote_wave_event":
			remote_wave_event.emit(data)
		"remote_build_ready_vote":
			remote_build_ready_vote.emit(data)
		"remote_build_end_vote":
			remote_build_end_vote.emit()
		# Structure sync
		"remote_structure_placed":
			remote_structure_placed.emit(data)
		"remote_structure_erased":
			remote_structure_erased.emit(data)
		"remote_door_toggled":
			remote_door_toggled.emit(data)
		# Score
		"remote_score_sync":
			remote_score_sync.emit(data)
		# Support abilities
		"remote_squad_spawned":
			remote_squad_spawned.emit(data)
		"remote_airstrike_used":
			remote_airstrike_used.emit(data)
		"remote_coin_collected":
			remote_coin_collected.emit(data)
		"remote_player_downed":
			remote_player_downed.emit(data)
		"remote_player_revived":
			remote_player_revived.emit(data)
		"remote_game_over_sync":
			remote_game_over_sync.emit(data)

func _emit_sio(event_name: String, data: Dictionary) -> void:
	if not _socket or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_raw_send("42" + JSON.stringify([event_name, data]))

func _raw_send(msg: String) -> void:
	_socket.send_text(msg)
