extends Control

@onready var health_bar := $TopBar/HealthBar
@onready var health_label := $TopBar/HealthBar/HealthLabel
@onready var score_label := $TopBar/ScoreLabel
@onready var wave_label := $TopBar/WaveLabel

func update_health(current: int, maximum: int) -> void:
	health_bar.value = float(current) / float(maximum) * 100.0
	health_label.text = str(current) + " / " + str(maximum)

func update_score(score: int) -> void:
	score_label.text = "SCORE: " + str(score)

func update_wave(wave: int) -> void:
	wave_label.text = "WAVE " + str(wave)
	# Flash the wave label
	wave_label.modulate = Color(1, 1, 0, 1)
	var tween: Tween = create_tween()
	tween.tween_property(wave_label, "modulate", Color.WHITE, 0.8)
