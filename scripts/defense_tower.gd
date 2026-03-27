extends StaticBody2D

## Auto-targeting defense tower.  Scans for the nearest enemy within scan_radius
## and fires a bullet every shoot_interval seconds.

var hp            := 5
var cell          : Vector2i
var _target       : Node2D = null

signal destroyed(cell: Vector2i)

@export var scan_radius    := 220.0
@export var shoot_interval := 0.8

@onready var scan_area    := $ScanArea
@onready var barrel_pivot := $BarrelPivot

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var _shoot_timer: Timer

func _ready() -> void:
	_shoot_timer = Timer.new()
	_shoot_timer.wait_time = shoot_interval
	_shoot_timer.timeout.connect(_try_shoot)
	add_child(_shoot_timer)
	_shoot_timer.start()

	scan_area.body_entered.connect(_on_body_entered)
	scan_area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _target and is_instance_valid(_target):
		barrel_pivot.look_at(_target.global_position)
	elif _target:
		_target = null

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") and not _target:
		_target = body

func _on_body_exited(body: Node) -> void:
	if body == _target:
		_target = null
		# Pick another enemy still in range
		for b in scan_area.get_overlapping_bodies():
			if b.is_in_group("enemies"):
				_target = b
				break

func _try_shoot() -> void:
	if not _target or not is_instance_valid(_target):
		_target = null
		return
	var dir := (_target.global_position - global_position).normalized()
	var bullet := bullet_scene.instantiate() as Area2D
	bullet.global_position = global_position + dir * 32.0
	bullet.rotation        = dir.angle()
	bullet.damage          = 18
	bullet.speed           = 750.0
	bullet.hit_color       = Color(0.3, 1.0, 0.5)
	get_tree().current_scene.add_child(bullet)

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		GameData.spawn_structure_explosion(global_position)
		destroyed.emit(cell)
		queue_free()
