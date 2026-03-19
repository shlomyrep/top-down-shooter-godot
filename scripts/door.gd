extends StaticBody2D

## Buildable door.  Closed by default — blocks movement.  toggle() flips state.
## The global HUD button toggles ALL nodes in group "doors" at once.

const MAX_HP := 100
var hp := MAX_HP
var cell: Vector2i
var is_open := false

signal destroyed(cell: Vector2i)

# Closed colours: green (healthy) → yellow → red (critical)
const CLOSED_COLORS: Array = [
	Color(0.82, 0.18, 0.10, 1.00),  # hp  1-33 — red
	Color(0.88, 0.68, 0.08, 1.00),  # hp 34-66 — yellow
	Color(0.20, 0.45, 0.88, 1.00),  # hp 67-100 — blue (full health)
]
const OPEN_COLOR := Color(0.20, 0.45, 0.88, 0.22)

@onready var door_body    := $DoorBody
@onready var col_shape    := $CollisionShape2D

func _ready() -> void:
	add_to_group("doors")

func toggle() -> void:
	is_open = !is_open
	col_shape.disabled = is_open
	if is_open:
		door_body.color = OPEN_COLOR
	else:
		_update_color()

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		destroyed.emit(cell)
		remove_from_group("doors")
		queue_free()
		return
	if not is_open:
		_update_color()

func _update_color() -> void:
	var idx := clampi((hp - 1) / 34, 0, 2)
	door_body.color = CLOSED_COLORS[idx]
