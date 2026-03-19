extends StaticBody2D

## Buildable wall.  HP 39 with colour-coded damage states (green → yellow → red).

const MAX_HP := 55
var hp := MAX_HP
var cell: Vector2i

signal destroyed(cell: Vector2i)

const HP_COLORS: Array = [
	Color(0.82, 0.18, 0.10),  # hp  1-18 — red
	Color(0.88, 0.68, 0.08),  # hp 19-36 — yellow
	Color(0.28, 0.76, 0.28),  # hp 37-55 — green
]

@onready var wall_body   := $WallBody
@onready var wall_border := $WallBorder

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		destroyed.emit(cell)
		queue_free()
		return
	var color_idx := clampi((hp - 1) / 18, 0, 2)
	wall_body.color   = HP_COLORS[color_idx]
	wall_border.color = HP_COLORS[color_idx].darkened(0.45)

func repair() -> void:
	hp = MAX_HP
	wall_body.color   = HP_COLORS[2]
	wall_border.color = HP_COLORS[2].darkened(0.45)
