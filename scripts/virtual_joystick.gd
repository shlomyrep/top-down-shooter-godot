extends Control

## Virtual joystick — visual only.  Touch input is handled by main.gd.

@export var joystick_radius := 64.0

@onready var base := $Base
@onready var knob := $Base/Knob

@export var knob_color := Color(0.9, 0.9, 0.9, 0.5)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = knob_color
	for corner in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left"]:
		style.set(corner, 28)
	knob.add_theme_stylebox_override("panel", style)

func update_knob(direction: Vector2) -> void:
	var center: Vector2 = base.size / 2.0
	var clamped := direction * joystick_radius
	knob.position = center + clamped - knob.size / 2.0

func reset_knob() -> void:
	var center: Vector2 = base.size / 2.0
	knob.position = center - knob.size / 2.0
