extends Control

@onready var record_wave_label: Label = $CenterContainer/MainPanel/PanelMargin/InnerVBox/RecordPanel/Margin/HBox/RecordWaveLabel
@onready var player_name_label: Label = $BottomBar/PlayerNameLabel
@onready var solo_btn: Button = $CenterContainer/MainPanel/PanelMargin/InnerVBox/Buttons/SoloBtn
@onready var multi_btn: Button = $CenterContainer/MainPanel/PanelMargin/InnerVBox/Buttons/MultiBtn
@onready var tutorial_toggle_btn: Button = $CenterContainer/MainPanel/PanelMargin/InnerVBox/Buttons/TutorialToggleBtn
@onready var name_dialog: Control = $NameDialog
@onready var name_edit: LineEdit = $NameDialog/DialogCenter/DialogPanel/DialogMargin/DialogVBox/NameEdit

func _ready() -> void:
	_apply_styles()
	_refresh_labels()
	_refresh_tutorial_btn()
	tutorial_toggle_btn.pressed.connect(_on_tutorial_toggle_btn_pressed)
	SoundManager.play_music("menu_bg")
	# Animate panel fade-in
	var panel: Control = $CenterContainer/MainPanel
	panel.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(panel, "modulate:a", 1.0, 0.55)

func _refresh_labels() -> void:
	var rec: int = GameData.record_wave
	record_wave_label.text = (tr("WAVE_RECORD") % rec) if rec > 0 else tr("NO_RECORD")
	player_name_label.text = "@" + GameData.player_name

func _apply_styles() -> void:
	# Solo button – gold
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.76, 0.52, 0.04, 1.0)
	sn.corner_radius_top_left    = 8
	sn.corner_radius_top_right   = 8
	sn.corner_radius_bottom_left = 8
	sn.corner_radius_bottom_right = 8
	sn.content_margin_left   = 24
	sn.content_margin_right  = 24
	sn.content_margin_top    = 14
	sn.content_margin_bottom = 14
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1.0, 0.72, 0.08, 1.0)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.56, 0.38, 0.02, 1.0)
	solo_btn.add_theme_stylebox_override("normal",  sn)
	solo_btn.add_theme_stylebox_override("hover",   sh)
	solo_btn.add_theme_stylebox_override("pressed", sp)
	solo_btn.add_theme_color_override("font_color", Color(0.1, 0.06, 0.0, 1.0))
	solo_btn.add_theme_font_size_override("font_size", 26)

	# Multiplayer button – steel blue
	var mn := StyleBoxFlat.new()
	mn.bg_color = Color(0.1, 0.22, 0.42, 1.0)
	mn.corner_radius_top_left    = 8
	mn.corner_radius_top_right   = 8
	mn.corner_radius_bottom_left = 8
	mn.corner_radius_bottom_right = 8
	mn.content_margin_left   = 24
	mn.content_margin_right  = 24
	mn.content_margin_top    = 14
	mn.content_margin_bottom = 14
	mn.border_width_bottom = 2
	mn.border_width_top    = 2
	mn.border_width_left   = 2
	mn.border_width_right  = 2
	mn.border_color = Color(0.25, 0.52, 0.9, 1.0)
	var mh := mn.duplicate() as StyleBoxFlat
	mh.bg_color = Color(0.16, 0.32, 0.56, 1.0)
	multi_btn.add_theme_stylebox_override("normal",  mn)
	multi_btn.add_theme_stylebox_override("hover",   mh)
	multi_btn.add_theme_stylebox_override("pressed", mn)
	multi_btn.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0, 1.0))
	multi_btn.add_theme_font_size_override("font_size", 26)

func _on_solo_btn_pressed() -> void:
	GameData.reset_multiplayer()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_multi_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_edit_name_btn_pressed() -> void:
	name_edit.text = GameData.player_name
	name_dialog.visible = true
	name_edit.grab_focus()
	name_edit.select_all()

func _on_confirm_btn_pressed() -> void:
	GameData.set_player_name(name_edit.text)
	name_dialog.visible = false
	_refresh_labels()

func _on_cancel_btn_pressed() -> void:
	name_dialog.visible = false

func _refresh_tutorial_btn() -> void:
	if GameData.tutorial_enabled:
		tutorial_toggle_btn.text = "📖 TUTORIAL: ON"
		tutorial_toggle_btn.add_theme_color_override("font_color", Color(0.62, 0.78, 0.55, 0.9))
	else:
		tutorial_toggle_btn.text = "📖 TUTORIAL: OFF"
		tutorial_toggle_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 0.7))

func _on_tutorial_toggle_btn_pressed() -> void:
	GameData.tutorial_enabled = not GameData.tutorial_enabled
	if GameData.tutorial_enabled:
		GameData.tutorial_plays = 0
	GameData.force_save()
	_refresh_tutorial_btn()
