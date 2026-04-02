extends Control

@onready var fade: ColorRect = $FadeOverlay
@onready var content_vbox: VBoxContainer = $CenterContainer/VBox
@onready var fist_label: Label = $CenterContainer/VBox/TitleLabel

var _transitioning := false

func _ready() -> void:
	fade.color = Color(0.04, 0.04, 0.1, 1.0)
	content_vbox.modulate.a = 0.0
	_run_intro()

func _run_intro() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Reveal background
	tw.tween_property(fade, "color:a", 0.0, 1.2)
	# Fade in text
	tw.tween_property(content_vbox, "modulate:a", 1.0, 0.7)
	# Pulse the fist colour bright then settle
	tw.tween_property(fist_label, "theme_override_colors/font_color",
			Color(1.0, 0.92, 0.22, 1.0), 0.35)
	tw.tween_property(fist_label, "theme_override_colors/font_color",
			Color(1.0, 0.68, 0.1, 1.0), 0.35)
	# Hold
	tw.tween_interval(1.8)
	# Fade to black then transition
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.tween_callback(_go_to_menu)

func _go_to_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		_skip()
	elif event is InputEventScreenTouch and event.pressed:
		_skip()

func _skip() -> void:
	_transitioning = true
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
