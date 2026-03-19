extends Control

## Virtual joystick for mobile touch controls (Brawl Stars style)

signal joystick_input(direction: Vector2)
signal joystick_released

@export var joystick_radius := 64.0
@export var dead_zone := 10.0

var is_pressed := false
var touch_index := -1
var joystick_center := Vector2.ZERO

@onready var base := $Base
@onready var knob := $Base/Knob

func _ready() -> void:
	joystick_center = base.size / 2.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed:
			is_pressed = true
			touch_index = touch_event.index
			_update_knob(touch_event.position)
		elif touch_event.index == touch_index:
			_reset()
	elif event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if drag_event.index == touch_index:
			_update_knob(drag_event.position)

func _update_knob(touch_pos: Vector2) -> void:
	var center: Vector2 = base.size / 2.0
	var direction: Vector2 = touch_pos - center
	var distance: float = direction.length()

	if distance > joystick_radius:
		direction = direction.normalized() * joystick_radius

	knob.position = center + direction - knob.size / 2.0

	if distance > dead_zone:
		joystick_input.emit(direction / joystick_radius)
	else:
		joystick_input.emit(Vector2.ZERO)

func _reset() -> void:
	is_pressed = false
	touch_index = -1
	knob.position = base.size / 2.0 - knob.size / 2.0
	joystick_released.emit()
