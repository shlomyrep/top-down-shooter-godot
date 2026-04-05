extends StaticBody2D

const MAX_HP := 55
var hp := MAX_HP
var cell: Vector2i

signal destroyed(cell: Vector2i)

const TEX_FULL := preload("res://assets/structures/sandbag_wall.png")
const TEX_D1   := preload("res://assets/structures/sandbag_wall_d1.png")
const TEX_D2   := preload("res://assets/structures/sandbag_wall_d2.png")
const TEX_D3   := preload("res://assets/structures/sandbag_wall_d3.png")

@onready var wall_body    := $WallBody
@onready var wall_overlay := $WallOverlay

var _tween: Tween

func _ready() -> void:
	wall_body.texture = TEX_FULL
	wall_overlay.modulate.a = 0.0

func _target_texture() -> Texture2D:
	if hp > 41:
		return TEX_FULL
	elif hp > 27:
		return TEX_D1
	elif hp > 13:
		return TEX_D2
	else:
		return TEX_D3

func _update_texture() -> void:
	var new_tex := _target_texture()
	if new_tex == wall_body.texture:
		return
	if _tween:
		_tween.kill()
	wall_overlay.texture = new_tex
	wall_overlay.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(wall_overlay, "modulate:a", 1.0, 0.35)
	_tween.tween_callback(func() -> void:
		wall_body.texture = new_tex
		wall_overlay.modulate.a = 0.0
		wall_overlay.texture = null
	)

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
	if _tween:
		_tween.kill()
	wall_overlay.modulate.a = 0.0
	wall_overlay.texture = null
	wall_body.texture = TEX_FULL

