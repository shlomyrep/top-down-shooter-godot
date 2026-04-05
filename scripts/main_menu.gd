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

	# Wait for ProgressionManager to have server data, then show engagement UI
	if ProgressionManager.login_streak > 0 or not ProgressionManager.streak_bonus.is_empty():
		_show_engagement_ui()
	else:
		ProgressionManager.profile_loaded.connect(_on_profile_loaded, CONNECT_ONE_SHOT)

func _on_profile_loaded(_data: Dictionary) -> void:
	_show_engagement_ui()

func _show_engagement_ui() -> void:
	_show_streak_banner()
	_show_mission_board()
	_show_weekly_op_badge()
	_show_friend_leaderboard()
	_refresh_labels()

func _refresh_labels() -> void:
	var rec: int = GameData.record_wave
	record_wave_label.text = (tr("WAVE_RECORD") % rec) if rec > 0 else tr("NO_RECORD")
	player_name_label.text = "@" + GameData.player_name + "  " + ProgressionManager.title + "  Rank " + str(ProgressionManager.rank)

# ── Streak banner ─────────────────────────────────────────────────────────────
func _show_streak_banner() -> void:
	var streak := ProgressionManager.login_streak
	if streak <= 0: return

	var container: VBoxContainer = $CenterContainer/MainPanel/PanelMargin/InnerVBox
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.6, 0.4, 0.0, 0.85)
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 8; style.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bonus_label := ProgressionManager.get_streak_bonus_label()
	lbl.text = "🔥 Day %d Streak!  Bonus: %s" % [streak, bonus_label] if bonus_label else "🔥 Day %d Streak!" % streak
	var ls := LabelSettings.new()
	ls.font_size    = 15
	ls.font_color   = Color(1.0, 0.9, 0.3)
	ls.outline_size = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.8)
	lbl.label_settings = ls
	banner.add_child(lbl)
	container.add_child(banner)
	container.move_child(banner, 0)

# ── Mission board ─────────────────────────────────────────────────────────────
func _show_mission_board() -> void:
	var missions := ProgressionManager.daily_missions
	if missions.is_empty(): return

	var container: VBoxContainer = $CenterContainer/MainPanel/PanelMargin/InnerVBox
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "📋 Daily Missions"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hls := LabelSettings.new()
	hls.font_size = 14; hls.font_color = Color(0.7, 1.0, 0.7)
	header.label_settings = hls
	board.add_child(header)

	for m in missions:
		var done := ProgressionManager.is_mission_complete(m["id"])
		var prog := ProgressionManager.get_mission_progress(m["id"])
		var target: int = m.get("target", 1)
		var row := Label.new()
		var prog_text := "  [%d/%d]" % [prog, target] if not done else ""
		row.text = ("✅ " if done else "○ ") + m.get("label", "") + prog_text + "  +" + str(m.get("coins", 0)) + "c"
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var rls := LabelSettings.new()
		rls.font_size = 12
		rls.font_color = Color(0.5, 0.5, 0.5) if done else Color(0.9, 0.9, 0.9)
		row.label_settings = rls
		board.add_child(row)

	container.add_child(board)

# ── Weekly operation badge ────────────────────────────────────────────────────
func _show_weekly_op_badge() -> void:
	var op := ProgressionManager.weekly_op
	if op.is_empty(): return

	var container: VBoxContainer = $CenterContainer/MainPanel/PanelMargin/InnerVBox
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "⚡ WEEKLY OP: %s" % op.get("title", "")
	var ls := LabelSettings.new()
	ls.font_size    = 13
	ls.font_color   = Color(0.4, 0.85, 1.0)
	ls.outline_size = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	lbl.label_settings = ls
	container.add_child(lbl)

	var desc_lbl := Label.new()
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.text = op.get("description", "")
	var dls := LabelSettings.new()
	dls.font_size = 11; dls.font_color = Color(0.65, 0.65, 0.65)
	desc_lbl.label_settings = dls
	container.add_child(desc_lbl)

# ── Friend leaderboard ────────────────────────────────────────────────────────
func _show_friend_leaderboard() -> void:
	if GameData.saved_friends.is_empty(): return
	ProgressionManager.fetch_friend_leaderboard()
	ProgressionManager.leaderboard_ready.connect(_on_friend_leaderboard_ready, CONNECT_ONE_SHOT)

func _on_friend_leaderboard_ready(rows: Array) -> void:
	if rows.is_empty(): return
	var container: VBoxContainer = $CenterContainer/MainPanel/PanelMargin/InnerVBox

	var header := Label.new()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.text = "🏆 Friends Leaderboard"
	var hls := LabelSettings.new()
	hls.font_size = 14; hls.font_color = Color(1.0, 0.85, 0.2)
	header.label_settings = hls
	container.add_child(header)

	var shown := 0
	for row in rows:
		if shown >= 5: break
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var marker := "→ " if row.get("name") == GameData.player_name else "   "
		lbl.text = "%s#%d  %s  Wave %d  [%s]" % [marker, shown + 1, row.get("name","?"), row.get("best_wave",0), row.get("title","")]
		var ls := LabelSettings.new()
		ls.font_size = 12
		ls.font_color = Color(1.0, 0.9, 0.3) if row.get("name") == GameData.player_name else Color(0.85, 0.85, 0.85)
		lbl.label_settings = ls
		container.add_child(lbl)
		shown += 1

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
