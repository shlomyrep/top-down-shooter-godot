extends StaticBody2D

const MAX_HP := 55
var hp := MAX_HP
var cell: Vector2i

signal destroyed(cell: Vector2i)

const TEX_FULL := preload("res://assets/structures/sandbag_wall.png")
const TEX_D1   := preload("res://assets/structures/sandbag_wall_d1.png")
const TEX_D2   := preload("res://assets/structures/sandbag_wall_d2.png")
const TEX_D3   := preload("res://assets/structures/sandbag_wall_d3.png")

@onready var wall_body := $WallBody

func _ready() -> void:
	wall_body.texture = TEX_FULL

func _update_texture() -> void:
	if hp > 41:
		wall_body.texture = TEX_FULL
	elif hp > 27:
		wall_body.texture = TEX_D1
	elif hp > 13:
		wall_body.texture = TEX_D2
	else:
		wall_body.texture = TEX_D3

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		GameData.spawn_structure_explosion(global_position)
		destroyed.emit(cell)
		queue_free()
		return
	_update_texture()

func repair() -> void:
	hp = MAX_HP
	wall_body.texture = TEX_FULL
