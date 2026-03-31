extends Control

@onready var wave_number_label: Label  = $CenterContainer/Panel/Margin/VBox/WaveRow/WaveNumberLabel
@onready var best_wave_label: Label    = $CenterContainer/Panel/Margin/VBox/BestRow/BestWaveNum
@onready var new_record_badge: Control = $CenterContainer/Panel/Margin/VBox/NewRecordBadge

func _ready() -> void:
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

	# Fade in panel
	var panel := $CenterContainer/Panel
	panel.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(panel, "modulate:a", 1.0, 0.5)

func _on_play_again_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_main_menu_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
