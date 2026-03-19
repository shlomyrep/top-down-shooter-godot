extends Control

@onready var health_bar := $TopBar/HealthBar
@onready var health_label := $TopBar/HealthBar/HealthLabel
@onready var score_label := $TopBar/ScoreLabel
@onready var wave_label := $TopBar/WaveLabel
@onready var coin_label := $TopBar/CoinLabel
@onready var wave_transition_panel := $WaveTransitionPanel
@onready var wave_complete_title := $WaveTransitionPanel/CenterContainer/VBox/WaveCompleteTitle
@onready var story_label := $WaveTransitionPanel/CenterContainer/VBox/StoryLabel
@onready var countdown_label := $WaveTransitionPanel/CenterContainer/VBox/CountdownLabel

func update_health(current: int, maximum: int) -> void:
	health_bar.value = float(current) / float(maximum) * 100.0
	health_label.text = str(current) + " / " + str(maximum)

func update_score(score: int) -> void:
	score_label.text = "SCORE: " + str(score)

func update_coins(amount: int) -> void:
	coin_label.text = "COINS: " + str(amount)

func update_wave(wave: int) -> void:
	wave_label.text = "WAVE " + str(wave)
	wave_label.modulate = Color(1, 1, 0, 1)
	var tween: Tween = create_tween()
	tween.tween_property(wave_label, "modulate", Color.WHITE, 0.8)

func show_wave_transition(config: Dictionary) -> void:
	wave_complete_title.text = config["title"] + " COMPLETE"
	story_label.text = config["subtitle"]
	countdown_label.text = "Next wave in: 5..."
	wave_transition_panel.modulate = Color(1, 1, 1, 0)
	wave_transition_panel.visible = true
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color.WHITE, 0.5)

func update_countdown(seconds: int) -> void:
	countdown_label.text = "Next wave in: " + str(seconds) + "..."

func hide_wave_transition() -> void:
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	tween.tween_callback(wave_transition_panel.hide)

