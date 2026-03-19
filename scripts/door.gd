extends StaticBody2D

## Buildable door.  Closed by default — blocks movement.  toggle() flips state.
## The global HUD button toggles ALL nodes in group "doors" at once.

var hp := 3
var cell: Vector2i
var is_open := false

signal destroyed(cell: Vector2i)

const CLOSED_COLOR := Color(0.20, 0.45, 0.88, 1.00)
const OPEN_COLOR   := Color(0.20, 0.45, 0.88, 0.22)

@onready var door_body    := $DoorBody
@onready var col_shape    := $CollisionShape2D

func _ready() -> void:
	add_to_group("doors")

func toggle() -> void:
	is_open = !is_open
	col_shape.disabled = is_open
	door_body.color    = OPEN_COLOR if is_open else CLOSED_COLOR

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		destroyed.emit(cell)
		remove_from_group("doors")
		queue_free()
