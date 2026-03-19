extends StaticBody2D

## Buildable wall.  HP 3 with colour-coded damage states (green → yellow → red).

var hp := 3
var cell: Vector2i

signal destroyed(cell: Vector2i)

const HP_COLORS: Array = [
	Color(0.82, 0.18, 0.10),  # hp 1 — red
	Color(0.88, 0.68, 0.08),  # hp 2 — yellow
	Color(0.28, 0.76, 0.28),  # hp 3 — green
]

@onready var wall_body   := $WallBody
@onready var wall_border := $WallBorder

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		destroyed.emit(cell)
		queue_free()
		return
	wall_body.color   = HP_COLORS[hp - 1]
	wall_border.color = HP_COLORS[hp - 1].darkened(0.45)
