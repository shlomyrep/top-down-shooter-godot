extends Control

@onready var partner_avatar_label: Label = $MainVBox/SlotRow/PartnerSlot/SlotMargin/SlotVBox/AvatarLabel
@onready var partner_name_label: Label   = $MainVBox/SlotRow/PartnerSlot/SlotMargin/SlotVBox/NameLabel
@onready var partner_status_label: Label = $MainVBox/SlotRow/PartnerSlot/SlotMargin/SlotVBox/StatusLabel
@onready var find_btn: Button            = $MainVBox/SlotRow/PartnerSlot/SlotMargin/SlotVBox/FindBtn
@onready var my_name_label: Label        = $MainVBox/SlotRow/MySlot/SlotMargin/SlotVBox/NameLabel
@onready var ready_btn: Button           = $MainVBox/BottomButtons/ReadyBtn
@onready var start_btn: Button           = $MainVBox/BottomButtons/StartBtn
@onready var connection_label: Label     = $Header/HeaderMargin/HeaderHBox/ConnectionLabel

var _is_ready      := false
var _partner_found := false
var _searching     := false
var _dot_count     := 0
var _dot_tween: Tween

func _ready() -> void:
	GameData.reset_multiplayer()
	my_name_label.text = GameData.player_name
	start_btn.disabled = true
	_apply_slot_styles()
	_connect_network_signals()

func _connect_network_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_server_connected)
	NetworkManager.disconnected_from_server.connect(_on_server_disconnected)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.partner_ready.connect(_on_partner_ready)
	NetworkManager.game_start.connect(_on_game_start)

func _disconnect_network_signals() -> void:
	if NetworkManager.connected_to_server.is_connected(_on_server_connected):
		NetworkManager.connected_to_server.disconnect(_on_server_connected)
	if NetworkManager.disconnected_from_server.is_connected(_on_server_disconnected):
		NetworkManager.disconnected_from_server.disconnect(_on_server_disconnected)
	if NetworkManager.match_found.is_connected(_on_match_found):
		NetworkManager.match_found.disconnect(_on_match_found)
	if NetworkManager.partner_ready.is_connected(_on_partner_ready):
		NetworkManager.partner_ready.disconnect(_on_partner_ready)
	if NetworkManager.game_start.is_connected(_on_game_start):
		NetworkManager.game_start.disconnect(_on_game_start)

func _apply_slot_styles() -> void:
	var my_style := _make_slot_style(Color(0.06, 0.14, 0.1, 0.9), Color(0.2, 0.85, 0.3, 0.7), 2)
	$MainVBox/SlotRow/MySlot.add_theme_stylebox_override("panel", my_style)
	var pt_style := _make_slot_style(Color(0.1, 0.1, 0.18, 0.9), Color(0.3, 0.35, 0.55, 0.6), 1)
	$MainVBox/SlotRow/PartnerSlot.add_theme_stylebox_override("panel", pt_style)

func _make_slot_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left     = 10
	s.corner_radius_top_right    = 10
	s.corner_radius_bottom_left  = 10
	s.corner_radius_bottom_right = 10
	s.border_width_bottom = border_w
	s.border_width_top    = border_w
	s.border_width_left   = border_w
	s.border_width_right  = border_w
	s.border_color = border
	return s

# ─── Server connection callbacks ──────────────────────────────────────────────

func _on_server_connected() -> void:
	connection_label.text = "● CONNECTED TO SERVER"
	connection_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1.0))
	# Now send the matchmaking request
	NetworkManager.find_match(GameData.player_name)

func _on_server_disconnected() -> void:
	_searching     = false
	_partner_found = false
	find_btn.disabled = false
	if _dot_tween:
		_dot_tween.kill()
	partner_avatar_label.text = "✗"
	partner_name_label.text   = "NO SERVER"
	partner_status_label.text = "tap FIND to retry"
	var ip := NetworkManager.SERVER_URL.get_slice("/", 2).get_slice(":", 0)
	connection_label.text = "✗ CAN'T REACH SERVER  (%s:3000)" % ip
	connection_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	start_btn.disabled = true

# ─── Find partner ─────────────────────────────────────────────────────────────

func _on_find_btn_pressed() -> void:
	if _searching or _partner_found:
		return
	_searching = true
	find_btn.disabled = true
	partner_avatar_label.text = "⏳"
	partner_name_label.text   = "SEARCHING"
	partner_status_label.text = "connecting..."
	connection_label.text = "CONNECTING TO SERVER..."
	connection_label.remove_theme_color_override("font_color")
	# Animated dots while waiting
	_dot_count = 0
	if _dot_tween:
		_dot_tween.kill()
	_dot_tween = create_tween().set_loops()
	_dot_tween.tween_callback(_pulse_dots).set_delay(0.5)
	# Connect to server → _on_server_connected fires → sends find_match
	NetworkManager.connect_to_server()

func _pulse_dots() -> void:
	if not _searching:
		return
	_dot_count = (_dot_count + 1) % 4
	partner_name_label.text = "SEARCHING" + ".".repeat(_dot_count)

func _on_match_found(_room_id: String, partner_name: String, _is_host: bool) -> void:
	_searching = false
	if _dot_tween:
		_dot_tween.kill()
	_partner_found = true
	partner_avatar_label.text = "🪖"
	partner_name_label.text   = partner_name
	partner_status_label.text = "✓ CONNECTED"
	connection_label.text = "✓ PARTNER FOUND"
	connection_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1.0))
	var green_style := _make_slot_style(Color(0.06, 0.14, 0.1, 0.9), Color(0.2, 0.85, 0.3, 0.7), 2)
	$MainVBox/SlotRow/PartnerSlot.add_theme_stylebox_override("panel", green_style)
	_update_start_btn()

func _on_partner_ready() -> void:
	partner_status_label.text = "✓ READY"
	partner_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))

# ─── Ready / Start ────────────────────────────────────────────────────────────

func _on_ready_btn_pressed() -> void:
	if not _partner_found:
		return
	_is_ready = not _is_ready
	if _is_ready:
		ready_btn.text = "✓  READY"
		ready_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
		NetworkManager.send_ready()
	else:
		ready_btn.text = "READY"
		ready_btn.remove_theme_color_override("font_color")
	_update_start_btn()

func _update_start_btn() -> void:
	# Start button stays hidden; game_start event from server drives scene change.
	# Keep as manual fallback only when both local conditions are met.
	start_btn.disabled = not (_is_ready and _partner_found)

func _on_start_btn_pressed() -> void:
	_launch_game()

func _on_game_start() -> void:
	_launch_game()

func _launch_game() -> void:
	_disconnect_network_signals()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_back_btn_pressed() -> void:
	if _searching:
		NetworkManager.cancel_search()
	NetworkManager.disconnect_from_server()
	_disconnect_network_signals()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Kept for legacy scene signal connection (timer is never started anymore)
func _on_search_timer_timeout() -> void:
	pass
