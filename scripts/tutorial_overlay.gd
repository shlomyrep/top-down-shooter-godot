## TutorialOverlay — non-blocking first-time-player hints.
## Shown only in solo play, only for the first MAX_PLAYS new games.
## Add to UILayer in main.gd with:
##   _tutorial_overlay = TutorialOverlay.new()
##   $UILayer.add_child(_tutorial_overlay)
## Then call setup(hud) and start() if the conditions are met.
extends Control

const MAX_PLAYS        := 3
const SQUAD_DELAY_SECS := 15.0
const FINGER_W         := 72.0
const FINGER_H         := 90.0

## Step index constants — readable names used in match statements.
const STEP_CAMP   := 0   # wave-1 build: highlight CAMP / template button
const STEP_BUILD  := 1   # wave-1 build: highlight floating BUILD / place button
const STEP_DOORS  := 2   # wave-1 build: highlight door-toggle button
const STEP_SQUAD  := 4   # wave-2 combat: highlight SQUAD button
const STEP_DONE   := 99  # waiting state between wave-1 and wave-2

## Emitted so main.gd can pause/resume the build-phase countdown timer.
signal request_pause_build
signal request_resume_build

var _hud: Control
var _active: bool = false
var _step: int = -1
var _target_node: Control = null

var _finger: TextureRect
var _panel: PanelContainer
var _msg_label: Label
var _squad_delay: Timer


func _ready() -> void:
	# Span the full screen, swallow no input
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	visible = true

	# Finger sprite — points upward, so we place it BELOW the target button
	_finger = TextureRect.new()
	_finger.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_finger.custom_minimum_size = Vector2(FINGER_W, FINGER_H)
	_finger.size = Vector2(FINGER_W, FINGER_H)
	_finger.ignore_texture_size = true
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.visible = false
	add_child(_finger)

	var tex: Texture2D = load("res://assets/ui/finger_pointer.png")
	if tex:
		_finger.texture = tex

	# Message panel with semi-transparent dark background
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.06, 0.88)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_msg_label = Label.new()
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.40, 1.0))
	_msg_label.add_theme_font_size_override("font_size", 20)
	_msg_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.autowrap_mode          = TextServer.AUTOWRAP_WORD
	_msg_label.custom_minimum_size    = Vector2(210, 0)
	_msg_label.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_msg_label)

	# 15-second delay before showing the squad hint mid-wave
	_squad_delay = Timer.new()
	_squad_delay.one_shot  = true
	_squad_delay.wait_time = SQUAD_DELAY_SECS
	_squad_delay.timeout.connect(_on_squad_delay)
	add_child(_squad_delay)


## Called from main.gd once — wires up all HUD and BuildManager signals.
func setup(hud_ref: Control) -> void:
	_hud = hud_ref
	_hud.build_item_selected.connect(_on_build_item_selected)
	_hud.build_place_pressed.connect(_on_build_place_pressed)
	_hud.build_picker_selected.connect(_on_build_picker_selected)
	_hud.door_toggle_pressed.connect(_on_door_toggle_pressed)
	_hud.squad_pressed.connect(_on_squad_pressed)
	BuildManager.build_mode_ended.connect(_on_build_mode_ended)


## Called from main.gd _ready() — marks this session as active and increments
## the persistent counter so the tutorial won't show beyond MAX_PLAYS games.
func start() -> void:
	_active = true
	GameData.tutorial_plays += 1
	GameData.force_save()


## Called from main.gd _on_between_wave_timeout() with the wave number that
## just finished (e.g. wave==1 means the first build phase is starting).
func notify_build_phase_entered(wave_num: int) -> void:
	if not _active:
		return
	if wave_num == 1:
		_show_step(STEP_CAMP)


## Called from main.gd _begin_wave() with the incoming wave number.
func notify_wave_started(wave_num: int) -> void:
	if not _active:
		return
	if wave_num == 2:
		_squad_delay.start()


# ── Internal step machine ────────────────────────────────────────────────────

func _show_step(idx: int) -> void:
	_step = idx

	match idx:
		STEP_CAMP:
			_target_node = _hud.get_node_or_null("BuildPanel/VBox/Palette/TemplateBtn")
			_msg_label.text = tr("TUTORIAL_0")

		STEP_BUILD:
			_target_node = _hud.get_node_or_null("PlaceBtn")
			_msg_label.text = tr("TUTORIAL_1")

		STEP_DOORS:
			# Only show if the player actually has doors placed
			if get_tree().get_nodes_in_group("doors").is_empty():
				_hide()
				return
			_target_node = _hud.get_node_or_null("DoorToggleBtn")
			_msg_label.text = tr("TUTORIAL_2")

		STEP_SQUAD:
			_target_node = _hud.get_node_or_null("SupportPanel/VBox/SquadBtn")
			_msg_label.text = tr("TUTORIAL_4")

		_:
			_finish()
			return

	if _target_node == null:
		# The target button wasn't found — skip this step silently
		_step += 1
		_show_step(_step)
		return

	_set_pointer_visible(true)


func _process(_delta: float) -> void:
	if not _active or _target_node == null or not is_instance_valid(_target_node):
		return
	if not _finger.visible:
		return

	var screen: Vector2  = get_viewport_rect().size
	var rect: Rect2      = _target_node.get_global_rect()
	var cx: float        = rect.get_center().x

	# Gentle vertical bounce
	var bounce: float = sin(Time.get_ticks_msec() * 0.005) * 7.0

	var fw: float = FINGER_W
	var fh: float = FINGER_H

	# Finger points upward — place it BELOW the button so it points at it
	var fy: float = rect.position.y + rect.size.y + 6.0 + bounce - 10.0

	# If no room below, flip above so the finger still points at the button
	var flipped: bool = false
	if fy + fh + 70.0 > screen.y:
		fy = rect.position.y - fh - 6.0 - bounce
		flipped = true

	var fx: float = clamp(cx - fw * 0.5, 8.0, screen.x - fw - 8.0)
	_finger.position = Vector2(fx, fy)

	# Message panel stays on the far side of the finger — away from the button
	var pw: float = maxf(_panel.size.x, 200.0)
	var ph: float = maxf(_panel.size.y, 60.0)
	var panel_x: float = clamp(cx - pw * 0.5, 8.0, screen.x - pw - 8.0)
	var panel_y: float
	if flipped:
		panel_y = fy - ph - 6.0   # above the finger (finger is above button)
	else:
		panel_y = fy + fh + 6.0   # below the finger (finger is below button)
	_panel.position = Vector2(panel_x, panel_y)


func _set_pointer_visible(on: bool) -> void:
	_finger.visible = on
	_panel.visible = on
	if on:
		request_pause_build.emit()
	else:
		request_resume_build.emit()


func _hide() -> void:
	_set_pointer_visible(false)


func _finish() -> void:
	_active = false
	_step   = -1
	_hide()
	_squad_delay.stop()


# ── HUD / BuildManager signal handlers ──────────────────────────────────────

func _on_build_item_selected(item: String) -> void:
	if _step == STEP_CAMP and item == "template":
		_hide()
		_show_step(STEP_BUILD)


func _on_build_place_pressed() -> void:
	if _step == STEP_BUILD:
		_hide()
		_show_step(STEP_DOORS)


func _on_build_picker_selected(_item: String) -> void:
	if _step == STEP_BUILD:
		_hide()
		_show_step(STEP_DOORS)


func _on_door_toggle_pressed() -> void:
	if _step == STEP_DOORS:
		_hide()
		# Wave-1 tutorial done — enter waiting state until wave 2 build phase
		_step = STEP_DONE


func _on_squad_pressed() -> void:
	if _step == STEP_SQUAD:
		_finish()


func _on_build_mode_ended() -> void:
	if not _active:
		return
	# Build phase ended without the player completing the build steps
	# — dismiss current hint and enter waiting state for the next phase
	if _step in [STEP_CAMP, STEP_BUILD, STEP_DOORS]:
		_hide()
		_step = STEP_DONE


func _on_squad_delay() -> void:
	if not _active:
		return
	# 15 seconds into wave 2 — show squad hint
	_show_step(STEP_SQUAD)
