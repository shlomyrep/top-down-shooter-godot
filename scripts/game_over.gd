extends Control

@onready var wave_number_label: Label  = $CenterContainer/Panel/Margin/VBox/WaveRow/WaveNumberLabel
@onready var best_wave_label: Label    = $CenterContainer/Panel/Margin/VBox/BestRow/BestWaveNum
@onready var new_record_badge: Control = $CenterContainer/Panel/Margin/VBox/NewRecordBadge

var _session_start_time: float = 0.0

func _ready() -> void:
	_session_start_time = Time.get_ticks_msec() / 1000.0

	var last_wave := GameData.get_last_wave()
	var record    := GameData.record_wave
	wave_number_label.text = str(last_wave) if last_wave > 0 else tr("NO_RECORD")
	best_wave_label.text   = str(record)    if record > 0    else tr("NO_RECORD")
	new_record_badge.visible = (last_wave > 0 and last_wave == record)

	# Multiplayer: show each player's kill count + Add Friend button
	if GameData.is_multiplayer:
		var kills_lbl := Label.new()
		kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kills_lbl.text = "%s: %d kills    %s: %d kills" % [
			GameData.player_name,  GameData.my_kills,
			GameData.partner_name, GameData.partner_kills
		]
		var ls := LabelSettings.new()
		ls.font_size    = 18
		ls.font_color   = Color(0.9, 0.9, 0.9)
		ls.outline_size  = 2
		ls.outline_color = Color(0.0, 0.0, 0.0, 0.8)
		kills_lbl.label_settings = ls
		$CenterContainer/Panel/Margin/VBox.add_child(kills_lbl)

		# Add Friend button
		var add_btn := Button.new()
		var p_name := GameData.partner_name
		if GameData.has_friend(p_name):
			add_btn.text = "✓ Already friends with " + p_name
			add_btn.disabled = true
		else:
			add_btn.text = "➕ Add " + p_name + " as Friend"
			add_btn.pressed.connect(func():
				GameData.add_friend(p_name)
				add_btn.text = "✓ Added " + p_name
				add_btn.disabled = true
			)
		$CenterContainer/Panel/Margin/VBox.add_child(add_btn)

		# Quick reinvite button
		if not GameData.partner_name.is_empty():
			var reinvite_btn := Button.new()
			reinvite_btn.text = "⚡ Play Again with " + GameData.partner_name
			reinvite_btn.pressed.connect(_on_reinvite_pressed)
			$CenterContainer/Panel/Margin/VBox.add_child(reinvite_btn)

	# ── Commander rank display ────────────────────────────────────────────────
	var rank_lbl := Label.new()
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.text = "🎖 %s  |  Rank %d  |  XP: %d" % [
		ProgressionManager.title,
		ProgressionManager.rank,
		ProgressionManager.xp,
	]
	var rls := LabelSettings.new()
	rls.font_size    = 16
	rls.font_color   = Color(1.0, 0.85, 0.2)
	rls.outline_size = 2
	rls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
	rank_lbl.label_settings = rls
	$CenterContainer/Panel/Margin/VBox.add_child(rank_lbl)

	# ── Daily missions progress ───────────────────────────────────────────────
	var done := ProgressionManager.missions_done_count()
	var total := ProgressionManager.daily_missions.size()
	if total > 0:
		var mission_lbl := Label.new()
		mission_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mission_lbl.text = "📋 Daily Missions: %d / %d complete" % [done, total]
		var mls := LabelSettings.new()
		mls.font_size    = 14
		mls.font_color   = Color(0.6, 1.0, 0.6) if done == total else Color(0.8, 0.8, 0.8)
		mls.outline_size = 2
		mls.outline_color = Color(0.0, 0.0, 0.0, 0.6)
		mission_lbl.label_settings = mls
		$CenterContainer/Panel/Margin/VBox.add_child(mission_lbl)

	# ── Post session to server ────────────────────────────────────────────────
	var duration_s := int(Time.get_ticks_msec() / 1000.0 - _session_start_time)
	ProgressionManager.post_session(last_wave, GameData.my_kills, duration_s)
	ProgressionManager.session_posted.connect(_on_session_posted, CONNECT_ONE_SHOT)
	ProgressionManager.medals_earned.connect(_on_medals_earned, CONNECT_ONE_SHOT)
	ProgressionManager.ranked_up.connect(_on_ranked_up, CONNECT_ONE_SHOT)

	# ── Challenge friends button (solo or after coop) ─────────────────────────
	if not GameData.saved_friends.is_empty() and last_wave > 0:
		var challenge_btn := Button.new()
		challenge_btn.text = "⚔ Challenge Friends (Wave %d)" % last_wave
		challenge_btn.pressed.connect(_on_challenge_friends_pressed.bind(last_wave, GameData.my_kills))
		$CenterContainer/Panel/Margin/VBox.add_child(challenge_btn)

	# Fade in panel
	var panel := $CenterContainer/Panel
	panel.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(panel, "modulate:a", 1.0, 0.5)

# ── Session result callbacks ──────────────────────────────────────────────────

func _on_session_posted(data: Dictionary) -> void:
	var xp_gained: int = data.get("xp_gained", 0)
	if xp_gained <= 0: return
	var xp_lbl := Label.new()
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_lbl.text = "+%d XP earned" % xp_gained
	var ls := LabelSettings.new()
	ls.font_size    = 14
	ls.font_color   = Color(0.4, 0.9, 1.0)
	ls.outline_size = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.6)
	xp_lbl.label_settings = ls
	$CenterContainer/Panel/Margin/VBox.add_child(xp_lbl)

func _on_ranked_up(_old: int, new_rank: int, new_title: String) -> void:
	var ru_lbl := Label.new()
	ru_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ru_lbl.text = "🏆 RANK UP! → %s (Rank %d)" % [new_title, new_rank]
	var ls := LabelSettings.new()
	ls.font_size    = 18
	ls.font_color   = Color(1.0, 0.75, 0.0)
	ls.outline_size = 3
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	ru_lbl.label_settings = ls
	$CenterContainer/Panel/Margin/VBox.add_child(ru_lbl)

func _on_medals_earned(medals: Array) -> void:
	for m in medals:
		var m_lbl := Label.new()
		m_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m_lbl.text = "🎖 Medal Unlocked: %s" % m.get("label", "")
		var ls := LabelSettings.new()
		ls.font_size    = 14
		ls.font_color   = Color(1.0, 0.9, 0.3)
		ls.outline_size = 2
		ls.outline_color = Color(0.0, 0.0, 0.0, 0.7)
		m_lbl.label_settings = ls
		$CenterContainer/Panel/Margin/VBox.add_child(m_lbl)

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_challenge_friends_pressed(wave: int, kills: int) -> void:
	for friend_name in GameData.saved_friends:
		ProgressionManager.send_challenge(friend_name, wave, kills)
	# Visual confirmation
	for child in $CenterContainer/Panel/Margin/VBox.get_children():
		if child is Button and "Challenge Friends" in child.text:
			child.text = "✓ Challenge sent to %d friend(s)!" % GameData.saved_friends.size()
			child.disabled = true

func _on_reinvite_pressed() -> void:
	# Re-use the existing friend ping path via NetworkManager
	if not GameData.partner_name.is_empty():
		NetworkManager.send_ping_friend(GameData.partner_name, "REJOIN")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_play_again_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_main_menu_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
