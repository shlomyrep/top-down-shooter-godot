extends StaticBody2D

## Buildable door.  Closed by default — blocks movement.  toggle() flips state.
## Sprite-based with 7-frame open/close animation (0.05s/frame).
## Orientation (0° = top/bottom wall, 90° = left/right wall) is set by:
##   1. set_orientation() — called by main.gd for template builds
##   2. _detect_orientation() — deferred neighbor check for manual builds

const MAX_HP := 140
var hp        := MAX_HP
var cell      : Vector2i
var is_open   := false

signal destroyed(cell: Vector2i)

const TEX_CLOSED := preload("res://assets/structures/door_closed.png")
const TEX_A1     := preload("res://assets/structures/door_anim_1.png")
const TEX_A2     := preload("res://assets/structures/door_anim_2.png")
const TEX_A3     := preload("res://assets/structures/door_anim_3.png")
const TEX_A4     := preload("res://assets/structures/door_anim_4.png")
const TEX_A5     := preload("res://assets/structures/door_anim_5.png")
const TEX_OPEN   := preload("res://assets/structures/door_open.png")

const FRAMES: Array = [TEX_CLOSED, TEX_A1, TEX_A2, TEX_A3, TEX_A4, TEX_A5, TEX_OPEN]

@onready var door_sprite := $DoorSprite
@onready var col_shape   := $CollisionShape2D

var _anim_timer  : Timer
var _anim_step   : int   = 0
var _anim_opening: bool  = true
var _orientation_set := false

func _ready() -> void:
	add_to_group("doors")
	door_sprite.texture = TEX_CLOSED

	_anim_timer = Timer.new()
	_anim_timer.wait_time = 0.05
	_anim_timer.one_shot = false
	_anim_timer.timeout.connect(_on_anim_tick)
	add_child(_anim_timer)

	# Deferred so BuildManager.occupied_cells is populated first (manual builds)
	call_deferred("_detect_orientation")

func set_orientation(vertical: bool) -> void:
	_orientation_set = true
	door_sprite.rotation_degrees = 90.0 if vertical else 0.0

func _detect_orientation() -> void:
	if _orientation_set:
		return
	# Check left/right neighbors — if occupied, this door runs vertically
	var left  := BuildManager.is_occupied(cell + Vector2i(-1, 0))
	var right := BuildManager.is_occupied(cell + Vector2i(1, 0))
	var top   := BuildManager.is_occupied(cell + Vector2i(0, -1))
	var bot   := BuildManager.is_occupied(cell + Vector2i(0, 1))
	# Prefer vertical if more horizontal neighbors; tie → horizontal
	var vertical := (left or right) and not (top or bot)
	door_sprite.rotation_degrees = 90.0 if vertical else 0.0

func toggle() -> void:
	is_open = !is_open
	_play_animation(is_open)

func _play_animation(opening: bool) -> void:
	_anim_opening = opening
	if opening:
		_anim_step = 0          # start from CLOSED → OPEN
		col_shape.disabled = true
	else:
		_anim_step = FRAMES.size() - 1  # start from OPEN → CLOSED
		col_shape.disabled = false
	door_sprite.texture = FRAMES[_anim_step]
	_anim_timer.start()

func _on_anim_tick() -> void:
	if _anim_opening:
		_anim_step += 1
		if _anim_step >= FRAMES.size():
			_anim_timer.stop()
			return
	else:
		_anim_step -= 1
		if _anim_step < 0:
			_anim_timer.stop()
			return
	door_sprite.texture = FRAMES[_anim_step]

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		GameData.spawn_structure_explosion(global_position)
		destroyed.emit(cell)
		remove_from_group("doors")
		queue_free()
