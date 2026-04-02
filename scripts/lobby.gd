extends Control
## Multiplayer lobby — 4-state machine:
##   MATCHMAKING  →  initial screen (Create / Join buttons)
##   CREATING     →  waiting for partner (shows room code)
##   JOINING      →  enter code then tap JOIN
##   PRE_GAME     →  both players visible, press Ready to start

const BUILD_NUMBER := 7

enum State { MATCHMAKING, CREATING, JOINING, PRE_GAME }
var _state: State = State.MATCHMAKING

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var connection_label:    Label          = $Header/HeaderMargin/HeaderHBox/ConnectionLabel
@onready var matchmake_panel:     PanelContainer = $Content/MatchmakePanel
@onready var create_panel:        PanelContainer = $Content/CreatePanel
@onready var join_panel:          PanelContainer = $JoinPanel
@onready var pregame_panel:       PanelContainer = $Content/PreGamePanel
# Create panel
@onready var code_label:          Label    = $Content/CreatePanel/CR_Margin/CR_VBox/CodeLabel
@onready var loading_label:       Label    = $Content/CreatePanel/CR_Margin/CR_VBox/LoadingLabel
# Join panel
@onready var code_input:          LineEdit = $JoinPanel/JP_Margin/JP_VBox/CodeInput
@onready var join_confirm_btn:    Button   = $JoinPanel/JP_Margin/JP_VBox/JoinConfirmBtn
@onready var jp_status:           Label    = $JoinPanel/JP_Margin/JP_VBox/JP_Status
# Pre-game panel
@onready var my_name_label:       Label  = $Content/PreGamePanel/PG_Margin/PG_VBox/SlotRow/MySlot/MyMargin/MyVBox/MyNameLabel
@onready var partner_name_label:  Label  = $Content/PreGamePanel/PG_Margin/PG_VBox/SlotRow/PartnerSlot/PartnerMargin/PartnerVBox/PartnerNameLabel
@onready var partner_status_label:Label  = $Content/PreGamePanel/PG_Margin/PG_VBox/SlotRow/PartnerSlot/PartnerMargin/PartnerVBox/PartnerStatusLabel
@onready var ready_btn:           Button = $Content/PreGamePanel/PG_Margin/PG_VBox/PG_Buttons/ReadyBtn

var _room_code: String = ""
var _is_ready:  bool   = false
var _dot_count: int    = 0
var _dot_tween: Tween

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	GameData.reset_multiplayer()
	my_name_label.text = GameData.player_name
	_set_state(State.MATCHMAKING)
	_add_build_label()
	_connect_signals()
	NetworkManager.connect_to_server()  # connect eagerly in background

func _set_state(s: State) -> void:
	_state = s
	matchmake_panel.visible = (s == State.MATCHMAKING)
	create_panel.visible    = (s == State.CREATING)
	join_panel.visible      = (s == State.JOINING)
	pregame_panel.visible   = (s == State.PRE_GAME)

func _add_build_label() -> void:
	var lbl := Label.new()
	lbl.text = "BUILD  %d" % BUILD_NUMBER
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	lbl.offset_right  = -12.0
	lbl.offset_bottom = -10.0
	var ls := LabelSettings.new()
	ls.font_size     = 16
	ls.font_color    = Color(1.0, 0.85, 0.2, 0.9)
	ls.outline_size  = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	lbl.label_settings = ls
	add_child(lbl)

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_server_connected)
	NetworkManager.disconnected_from_server.connect(_on_server_disconnected)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.join_error.connect(_on_join_error)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.partner_ready.connect(_on_partner_ready)
	NetworkManager.game_start.connect(_on_game_start)

func _disconnect_signals() -> void:
	if NetworkManager.connected_to_server.is_connected(_on_server_connected):
		NetworkManager.connected_to_server.disconnect(_on_server_connected)
	if NetworkManager.disconnected_from_server.is_connected(_on_server_disconnected):
		NetworkManager.disconnected_from_server.disconnect(_on_server_disconnected)
	if NetworkManager.room_created.is_connected(_on_room_created):
		NetworkManager.room_created.disconnect(_on_room_created)
	if NetworkManager.join_error.is_connected(_on_join_error):
		NetworkManager.join_error.disconnect(_on_join_error)
	if NetworkManager.match_found.is_connected(_on_match_found):
		NetworkManager.match_found.disconnect(_on_match_found)
	if NetworkManager.partner_ready.is_connected(_on_partner_ready):
		NetworkManager.partner_ready.disconnect(_on_partner_ready)
	if NetworkManager.game_start.is_connected(_on_game_start):
		NetworkManager.game_start.disconnect(_on_game_start)

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	_set_state(State.CREATING)
	code_label.text    = "-----"
	loading_label.text = "Connecting..."
	if NetworkManager.is_online():
		NetworkManager.send_create_room()
	else:
		NetworkManager.connect_to_server()

func _on_join_pressed() -> void:
	_set_state(State.JOINING)
	jp_status.text            = ""
	code_input.text           = ""
	code_input.editable       = true
	join_confirm_btn.disabled = false
	code_input.grab_focus()

func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_server()
	_disconnect_signals()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_cancel_pressed() -> void:
	if _room_code != "":
		NetworkManager.cancel_room()
	_room_code = ""
	_stop_loading_dots()
	_set_state(State.MATCHMAKING)

func _on_join_back_pressed() -> void:
	jp_status.text = ""
	_set_state(State.MATCHMAKING)

func _on_code_submitted(_text: String) -> void:
	_on_join_confirm_pressed()

func _on_join_confirm_pressed() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() < 5:
		jp_status.text = "Code must be 5 characters"
		return
	jp_status.text            = "Connecting..."
	join_confirm_btn.disabled = true
	code_input.editable       = false
	if NetworkManager.is_online():
		NetworkManager.send_join_room(code)
	else:
		NetworkManager.connect_to_server()

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	if _is_ready:
		ready_btn.text = "\u2713  READY \u2713"
		ready_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
		NetworkManager.send_ready()
	else:
		ready_btn.text = "\u2713  READY"
		ready_btn.remove_theme_color_override("font_color")

func _on_pregame_back_pressed() -> void:
	if _room_code != "":
		NetworkManager.cancel_room()
	NetworkManager.disconnect_from_server()
	_room_code = ""
	_is_ready  = false
	ready_btn.text = "\u2713  READY"
	ready_btn.remove_theme_color_override("font_color")
	partner_status_label.remove_theme_color_override("font_color")
	_set_state(State.MATCHMAKING)

# ── Network callbacks ─────────────────────────────────────────────────────────

func _on_server_connected() -> void:
	connection_label.text = "\u25cf CONNECTED TO SERVER"
	connection_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1.0))
	match _state:
		State.CREATING:
			NetworkManager.send_create_room()
		State.JOINING:
			var code := code_input.text.strip_edges().to_upper()
			if code.length() == 5:
				NetworkManager.send_join_room(code)

func _on_server_disconnected() -> void:
	connection_label.text = "\u25cf OFFLINE"
	connection_label.remove_theme_color_override("font_color")
	if _state == State.CREATING:
		_stop_loading_dots()
		loading_label.text = "Connection lost"
		_set_state(State.MATCHMAKING)
	elif _state == State.JOINING:
		jp_status.text            = "Connection lost — try again"
		join_confirm_btn.disabled = false
		code_input.editable       = true

func _on_room_created(code: String) -> void:
	_room_code      = code
	code_label.text = code
	_set_state(State.CREATING)
	_start_loading_dots()

func _on_join_error(message: String) -> void:
	jp_status.text            = "Error: " + message
	join_confirm_btn.disabled = false
	code_input.editable       = true

func _on_match_found(_room_id: String, partner_name: String, _is_host: bool) -> void:
	_stop_loading_dots()
	_room_code = ""
	partner_name_label.text   = partner_name
	partner_status_label.text = "CONNECTED"
	partner_status_label.remove_theme_color_override("font_color")
	_set_state(State.PRE_GAME)

func _on_partner_ready() -> void:
	partner_status_label.text = "READY \u2713"
	partner_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))

func _on_game_start() -> void:
	_disconnect_signals()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ── Dot animation ─────────────────────────────────────────────────────────────

func _start_loading_dots() -> void:
	_dot_count = 0
	if _dot_tween:
		_dot_tween.kill()
	_dot_tween = create_tween().set_loops()
	_dot_tween.tween_callback(_pulse_dots).set_delay(0.5)

func _stop_loading_dots() -> void:
	if _dot_tween:
		_dot_tween.kill()
	loading_label.text = ""

func _pulse_dots() -> void:
	_dot_count = (_dot_count + 1) % 4
	loading_label.text = "Waiting" + ".".repeat(_dot_count)
