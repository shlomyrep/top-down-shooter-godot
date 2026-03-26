extends Control

@onready var wave_number_label: Label  = $CenterContainer/Panel/Margin/VBox/WaveRow/WaveNumberLabel
@onready var best_wave_label: Label    = $CenterContainer/Panel/Margin/VBox/BestRow/BestWaveNum
@onready var new_record_badge: Control = $CenterContainer/Panel/Margin/VBox/NewRecordBadge

func _ready() -> void:
	var last_wave := GameData.get_last_wave()
	var record    := GameData.record_wave
	wave_number_label.text = str(last_wave) if last_wave > 0 else "—"
	best_wave_label.text   = str(record)    if record > 0    else "—"
	new_record_badge.visible = (last_wave > 0 and last_wave == record)
	# Fade in panel
	var panel := $CenterContainer/Panel
	panel.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(panel, "modulate:a", 1.0, 0.5)

func _on_play_again_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_main_menu_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
