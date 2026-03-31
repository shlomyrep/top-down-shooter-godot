extends Control

## Increment this every build so both devices can confirm they're on the same version.
const BUILD_NUMBER := 6

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

# ── Room-code state ───────────────────────────────────────────────────────────
var _mode: String = ""        ## "" | "creating" | "joining"
var _room_code: String = ""

# ── Dynamically-created UI nodes ─────────────────────────────────────────────
var _join_btn:         Button
var _code_display:     Label
var _join_input_row:   HBoxContainer
var _join_input:       LineEdit
var _friends_panel:    VBoxContainer
var _invite_banner:    PanelContainer

func _ready() -> void:
	GameData.reset_multiplayer()
	my_name_label.text = GameData.player_name
	start_btn.disabled = true
	_apply_slot_styles()
	_connect_network_signals()
	_add_build_label()
	_setup_create_join_ui()
	_setup_friends_panel()

func _add_build_label() -> void:
	var lbl := Label.new()
	lbl.text = "BUILD  %d" % BUILD_NUMBER
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	lbl.offset_right  = -12.0
	lbl.offset_bottom = -10.0
	var ls := LabelSettings.new()
	ls.font_size    = 16
	ls.font_color   = Color(1.0, 0.85, 0.2, 0.9)
	ls.outline_size  = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	lbl.label_settings = ls
	add_child(lbl)

func _connect_network_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_server_connected)
	NetworkManager.disconnected_from_server.connect(_on_server_disconnected)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.join_error.connect(_on_join_error)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.partner_ready.connect(_on_partner_ready)
	NetworkManager.game_start.connect(_on_game_start)
	NetworkManager.friends_online_status.connect(_on_friends_online_status)
	NetworkManager.friend_invite_received.connect(_on_friend_invite_received)

func _disconnect_network_signals() -> void:
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
	if NetworkManager.friends_online_status.is_connected(_on_friends_online_status):
		NetworkManager.friends_online_status.disconnect(_on_friends_online_status)
	if NetworkManager.friend_invite_received.is_connected(_on_friend_invite_received):
		NetworkManager.friend_invite_received.disconnect(_on_friend_invite_received)

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

# ─── Room-code UI setup ───────────────────────────────────────────────────────

func _setup_create_join_ui() -> void:
	# Repurpose the scene's FindBtn as "Create Room"
	find_btn.text = "🏠  Create Room"

	# Join Room button (added dynamically, same parent VBox)
	_join_btn = Button.new()
	_join_btn.text = "🔗  Join Room"
	_join_btn.pressed.connect(_on_join_btn_pressed)
	find_btn.get_parent().add_child(_join_btn)

	# Large code display label (hidden until room created)
	_code_display = Label.new()
	_code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_display.visible = false
	var cls := LabelSettings.new()
	cls.font_size    = 38
	cls.font_color   = Color(1.0, 0.9, 0.2, 1.0)
	cls.outline_size  = 3
	cls.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	_code_display.label_settings = cls
	find_btn.get_parent().add_child(_code_display)

	# Input row for joining (hidden by default)
	_join_input_row = HBoxContainer.new()
	_join_input_row.visible = false
	_join_input = LineEdit.new()
	_join_input.placeholder_text = "Enter code…"
	_join_input.max_length = 5
	_join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_input.text_changed.connect(_on_join_input_changed)
	_join_input_row.add_child(_join_input)
	var go_btn := Button.new()
	go_btn.text = "▶"
	go_btn.pressed.connect(_on_join_confirm_pressed)
	_join_input_row.add_child(go_btn)
	find_btn.get_parent().add_child(_join_input_row)

# ─── Server connection callbacks ──────────────────────────────────────────────

func _on_server_connected() -> void:
	connection_label.text = tr("LOBBY_CONNECTED")
	connection_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1.0))
	# Route to appropriate matchmaking call based on mode
	if _mode == "creating":
		NetworkManager.send_create_room()
	elif _mode == "joining":
		NetworkManager.send_join_room(_join_input.text.strip_edges().to_upper())

func _on_server_disconnected() -> void:
	_searching     = false
	_partner_found = false
	_mode          = ""
	_room_code     = ""
	find_btn.disabled = false
	if _join_btn: _join_btn.disabled = false
	if _dot_tween:
		_dot_tween.kill()
	if _code_display: _code_display.visible = false
	if _join_input_row: _join_input_row.visible = false
	partner_avatar_label.text = "✗"
	partner_name_label.text   = tr("LOBBY_NO_SERVER_NAME")
	partner_status_label.text = tr("LOBBY_RETRY_HINT")
	var ip := NetworkManager.SERVER_URL.get_slice("/", 2).get_slice(":", 0)
	connection_label.text = tr("LOBBY_NO_SERVER") % [ip]
	connection_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	start_btn.disabled = true

# ─── Create / Join handlers ───────────────────────────────────────────────────

func _on_find_btn_pressed() -> void:
	# This is the "Create Room" button (FindBtn repurposed)
	if _partner_found:
		return
	if _mode == "creating":
		# Already creating — treat as cancel
		NetworkManager.cancel_room()
		NetworkManager.disconnect_from_server()
		_reset_to_idle()
		return
	_mode = "creating"
	find_btn.text = "✕  Cancel"
	find_btn.disabled = false
	_join_btn.disabled = true
	_searching = true
	partner_avatar_label.text = "⏳"
	partner_name_label.text   = "Creating room…"
	partner_status_label.text = "Connecting to server"
	connection_label.text = tr("LOBBY_CONNECTING")
	connection_label.remove_theme_color_override("font_color")
	_dot_count = 0
	if _dot_tween: _dot_tween.kill()
	_dot_tween = create_tween().set_loops()
	_dot_tween.tween_callback(_pulse_dots).set_delay(0.5)
	NetworkManager.connect_to_server()

func _on_join_btn_pressed() -> void:
	if _partner_found or _mode != "":
		return
	# Show join input row, hide join button itself
	_join_btn.visible = false
	find_btn.disabled = true
	_join_input_row.visible = true
	_join_input.text = ""
	_join_input.grab_focus()
	partner_status_label.text = "Enter room code then tap ▶"

func _on_join_input_changed(_new_text: String) -> void:
	pass  # Could add real-time validation here

func _on_join_confirm_pressed() -> void:
	var code := _join_input.text.strip_edges().to_upper()
	if code.length() < 5:
		partner_status_label.text = "Code must be 5 characters"
		return
	_mode = "joining"
	_join_input.editable = false
	find_btn.disabled = true
	partner_avatar_label.text = "⏳"
	partner_name_label.text   = "Joining room…"
	partner_status_label.text = "Connecting to server"
	connection_label.text = tr("LOBBY_CONNECTING")
	connection_label.remove_theme_color_override("font_color")
	NetworkManager.connect_to_server()

func _on_room_created(code: String) -> void:
	_room_code = code
	if _dot_tween: _dot_tween.kill()
	partner_avatar_label.text = "🏠"
	partner_name_label.text   = "Waiting for partner…"
	partner_status_label.text = "Share your room code:"
	_code_display.text    = code
	_code_display.visible = true
	find_btn.text     = "✕  Cancel"
	find_btn.disabled = false
	# Refresh friend online status so Invite buttons light up
	if GameData.saved_friends.size() > 0:
		NetworkManager.send_check_friends_online(GameData.saved_friends)

func _on_join_error(message: String) -> void:
	_mode = ""
	_join_input.editable = true
	partner_avatar_label.text = "✗"
	partner_name_label.text   = "Error: " + message
	partner_status_label.text = "Check the code and try again"
	connection_label.text = "Connection failed"
	connection_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2, 1.0))
	NetworkManager.disconnect_from_server()
	_join_btn.visible = true
	find_btn.disabled = false

func _reset_to_idle() -> void:
	_mode          = ""
	_room_code     = ""
	_searching     = false
	_partner_found = false
	if _dot_tween: _dot_tween.kill()
	find_btn.text     = "🏠  Create Room"
	find_btn.disabled = false
	_join_btn.disabled = false
	_join_btn.visible  = true
	_code_display.visible    = false
	_join_input_row.visible  = false
	_join_input.editable     = true
	partner_avatar_label.text = "?"
	partner_name_label.text   = "—"
	partner_status_label.text = "Find a partner to play"
	start_btn.disabled = true

# ─── Find partner ─────────────────────────────────────────────────────────────

func _on_find_btn_pressed_legacy() -> void:
	# DEPRECATED – kept so nothing breaks if signal still fires in old builds
	_on_find_btn_pressed()

func _pulse_dots() -> void:
	if not _searching:
		return
	_dot_count = (_dot_count + 1) % 4
	partner_name_label.text = (partner_name_label.text.rstrip(".") if partner_name_label.text.ends_with(".") else partner_name_label.text) + ".".repeat(_dot_count)

func _on_match_found(_room_id: String, partner_name: String, _is_host: bool) -> void:
	_searching = false
	if _dot_tween:
		_dot_tween.kill()
	_partner_found = true
	# Hide room-code UI now that we have a partner
	_code_display.visible   = false
	_join_input_row.visible = false
	find_btn.text     = "🏠  Create Room"
	if _join_btn: _join_btn.visible = false
	partner_avatar_label.text = "🪖"
	partner_name_label.text   = partner_name
	partner_status_label.text = tr("LOBBY_PARTNER_CONNECTED")
	connection_label.text = tr("LOBBY_PARTNER_FOUND")
	connection_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1.0))
	var green_style := _make_slot_style(Color(0.06, 0.14, 0.1, 0.9), Color(0.2, 0.85, 0.3, 0.7), 2)
	$MainVBox/SlotRow/PartnerSlot.add_theme_stylebox_override("panel", green_style)
	_update_start_btn()

func _on_partner_ready() -> void:
	partner_status_label.text = tr("LOBBY_PARTNER_READY")
	partner_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))

# ─── Ready / Start ────────────────────────────────────────────────────────────

func _on_ready_btn_pressed() -> void:
	if not _partner_found:
		return
	_is_ready = not _is_ready
	if _is_ready:
		ready_btn.text = tr("LOBBY_READY_CHECKED")
		ready_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
		NetworkManager.send_ready()
	else:
		ready_btn.text = tr("LOBBY_READY_BTN")
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
	if _mode == "creating" and _room_code != "":
		NetworkManager.cancel_room()
	NetworkManager.disconnect_from_server()
	_disconnect_network_signals()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# Kept for legacy scene signal connection (timer is never started anymore)
func _on_search_timer_timeout() -> void:
	pass

# ─── Friends panel (Phase 2+3) ─────────────────────────────────────────────────

func _setup_friends_panel() -> void:
	if GameData.saved_friends.is_empty():
		return

	# Outer container added below BottomButtons in the MainVBox
	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	outer_style.corner_radius_top_left     = 8
	outer_style.corner_radius_top_right    = 8
	outer_style.corner_radius_bottom_left  = 8
	outer_style.corner_radius_bottom_right = 8
	outer.add_theme_stylebox_override("panel", outer_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)
	outer.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "👥  Friends"
	var hls := LabelSettings.new()
	hls.font_size    = 16
	hls.font_color   = Color(0.8, 0.8, 0.85, 1.0)
	hls.outline_size  = 1
	hls.outline_color = Color.BLACK
	header.label_settings = hls
	vbox.add_child(header)

	_friends_panel = vbox
	_rebuild_friend_rows()

	$MainVBox.add_child(outer)

	# Ask server for online status right away if we’re already connected
	if NetworkManager.is_online():
		NetworkManager.send_check_friends_online(GameData.saved_friends)

func _rebuild_friend_rows() -> void:
	if not _friends_panel:
		return
	# Remove all row children (keep the header at index 0)
	for i in range(_friends_panel.get_child_count() - 1, 0, -1):
		_friends_panel.get_child(i).queue_free()
	for f_name in GameData.saved_friends:
		_friends_panel.add_child(_make_friend_row(f_name, false))

func _make_friend_row(f_name: String, is_online: bool) -> HBoxContainer:
	var row := HBoxContainer.new()

	var dot := Label.new()
	dot.name = "Dot"
	dot.text = "•"
	var dls := LabelSettings.new()
	dls.font_size  = 20
	dls.font_color = Color(0.3, 0.9, 0.3, 1.0) if is_online else Color(0.45, 0.45, 0.45, 1.0)
	dot.label_settings = dls
	row.add_child(dot)

	var name_lbl := Label.new()
	name_lbl.name = "NameLbl"
	name_lbl.text = f_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nls := LabelSettings.new()
	nls.font_size    = 15
	nls.font_color   = Color(0.9, 0.9, 0.9, 1.0)
	name_lbl.label_settings = nls
	row.add_child(name_lbl)

	var invite_btn := Button.new()
	invite_btn.name = "InviteBtn"
	invite_btn.text = "✉️ Invite"
	invite_btn.disabled = not (is_online and _room_code != "")
	invite_btn.pressed.connect(_on_invite_friend_pressed.bind(f_name))
	row.add_child(invite_btn)

	return row

func _on_friends_online_status(online_names: Array) -> void:
	if not _friends_panel:
		return
	# Update dot colors and invite button states in existing rows
	# Row index 0 is the header; friends start at index 1
	for i in range(1, _friends_panel.get_child_count()):
		var row := _friends_panel.get_child(i) as HBoxContainer
		if not row:
			continue
		var name_lbl := row.get_node_or_null("NameLbl") as Label
		if not name_lbl:
			continue
		var is_online: bool = name_lbl.text in online_names
		var dot := row.get_node_or_null("Dot") as Label
		if dot:
			dot.label_settings.font_color = Color(0.3, 0.9, 0.3, 1.0) if is_online else Color(0.45, 0.45, 0.45, 1.0)
		var invite_btn := row.get_node_or_null("InviteBtn") as Button
		if invite_btn:
			invite_btn.disabled = not (is_online and _room_code != "")

func _on_invite_friend_pressed(f_name: String) -> void:
	if _room_code == "":
		return
	NetworkManager.send_ping_friend(f_name, _room_code)
	partner_status_label.text = "Invite sent to " + f_name + "!"

# ─── Invite banner (received an invite from a friend) ────────────────────────

func _on_friend_invite_received(data: Dictionary) -> void:
	var from_name: String = str(data.get("from_name", "Someone"))
	var room_code: String = str(data.get("room_code", ""))
	if room_code.is_empty() or _partner_found:
		return
	_show_invite_banner(from_name, room_code)

func _show_invite_banner(from_name: String, room_code: String) -> void:
	if _invite_banner and is_instance_valid(_invite_banner):
		_invite_banner.queue_free()

	_invite_banner = PanelContainer.new()
	_invite_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_invite_banner.offset_top    = 10
	_invite_banner.offset_bottom = 10 + 70
	_invite_banner.offset_left   = 20
	_invite_banner.offset_right  = -20
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.08, 0.22, 0.12, 0.95)
	bs.corner_radius_top_left     = 10
	bs.corner_radius_top_right    = 10
	bs.corner_radius_bottom_left  = 10
	bs.corner_radius_bottom_right = 10
	bs.border_width_bottom = 2
	bs.border_width_top    = 2
	bs.border_width_left   = 2
	bs.border_width_right  = 2
	bs.border_color = Color(0.2, 0.85, 0.3, 0.8)
	_invite_banner.add_theme_stylebox_override("panel", bs)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_invite_banner.add_child(hbox)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	hbox.add_child(margin)

	var inner_hbox := HBoxContainer.new()
	inner_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(inner_hbox)

	var msg := Label.new()
	msg.text = "🔔  " + from_name + " invited you! (" + room_code + ")"
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mls := LabelSettings.new()
	mls.font_size    = 16
	mls.font_color   = Color(0.95, 0.95, 0.95, 1.0)
	mls.outline_size  = 2
	mls.outline_color = Color.BLACK
	msg.label_settings = mls
	inner_hbox.add_child(msg)

	var accept_btn := Button.new()
	accept_btn.text = "✔ Join"
	accept_btn.pressed.connect(func():
		_invite_banner.queue_free()
		_invite_banner = null
		_accept_invite(room_code)
	)
	inner_hbox.add_child(accept_btn)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "✕"
	dismiss_btn.pressed.connect(func():
		_invite_banner.queue_free()
		_invite_banner = null
	)
	inner_hbox.add_child(dismiss_btn)

	add_child(_invite_banner)
	# Auto-dismiss after 15 s
	var t := get_tree().create_timer(15.0)
	t.timeout.connect(func():
		if _invite_banner and is_instance_valid(_invite_banner):
			_invite_banner.queue_free()
			_invite_banner = null
	)

func _accept_invite(room_code: String) -> void:
	# Pre-fill join input and kick off join flow
	if _mode != "":
		return  # already in a room
	find_btn.disabled = true
	_join_btn.visible = false
	_join_input_row.visible = true
	_join_input.text = room_code
	_on_join_confirm_pressed()
