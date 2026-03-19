extends CharacterBody2D

## Allied squad member.  Follows the player and auto-shoots the nearest enemy.
## shielded=true doubles max_health and adds a visible shield ring.

@export var speed         := 180.0
@export var shoot_range   := 280.0
@export var shoot_interval := 0.55
@export var shielded      := false

var player: Node2D = null
var _target: Node2D = null
var _shoot_timer: Timer
var _lifetime_timer: Timer
# Each member orbits the player at a unique offset — creates a loose formation
var _follow_offset: Vector2 = Vector2.ZERO

signal expired

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")

@onready var body_poly  := $BodyPoly
@onready var scan_area  := $ScanArea
@onready var shield_ring := $ShieldRing

func _ready() -> void:
	add_to_group("squad")
	# Random offset in a ring (50–90 px) so members spread around the player
	var angle := randf() * TAU
	var radius := randf_range(50.0, 90.0)
	_follow_offset = Vector2.RIGHT.rotated(angle) * radius

	if shielded:
		var hp_max := 120
		shield_ring.visible = true
	else:
		var hp_max := 60
		shield_ring.visible = false

	_shoot_timer = Timer.new()
	_shoot_timer.wait_time = shoot_interval
	_shoot_timer.timeout.connect(_try_shoot)
	add_child(_shoot_timer)
	_shoot_timer.start()

	_lifetime_timer = Timer.new()
	_lifetime_timer.one_shot = true
	_lifetime_timer.timeout.connect(_on_expired)
	add_child(_lifetime_timer)
	_lifetime_timer.start(60.0)  # despawn after 60 s

	scan_area.body_entered.connect(_on_body_entered)
	scan_area.body_exited.connect(_on_body_exited)

func _physics_process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	var follow_pos := player.global_position + _follow_offset
	var dist := global_position.distance_to(follow_pos)
	if dist > 55.0:
		velocity = (follow_pos - global_position).normalized() * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	if _target and is_instance_valid(_target):
		body_poly.rotation = global_position.angle_to_point(_target.global_position)
	elif velocity.length() > 10:
		body_poly.rotation = velocity.angle()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") and not _target:
		_target = body

func _on_body_exited(body: Node) -> void:
	if body == _target:
		_target = null
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
	bullet.global_position = global_position + dir * 28.0
	bullet.rotation = dir.angle()
	bullet.damage   = 22 if not shielded else 16
	bullet.speed    = 820.0
	bullet.hit_color = Color(0.3, 0.9, 0.5) if not shielded else Color(0.45, 0.55, 1.0)
	get_tree().current_scene.add_child(bullet)

func _on_expired() -> void:
	expired.emit()
	queue_free()

func take_damage(amount: int) -> void:
	# Shielded units absorb 50% damage
	var actual := amount / 2 if shielded else amount
	queue_free()  # simplified: any lethal hit kills the squad member
