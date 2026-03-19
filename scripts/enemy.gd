extends CharacterBody2D

@export var speed := 120.0
@export var max_health := 60
@export var damage := 10
@export var attack_cooldown_time := 1.0

var health: int
var player: Node2D = null
var _is_dead := false

signal died_at(pos: Vector2)

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var health_bar := $HealthBarPivot/HealthBar
@onready var health_bar_pivot := $HealthBarPivot
@onready var attack_cooldown := $AttackCooldown

func _ready() -> void:
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.visible = false
	attack_cooldown.wait_time = attack_cooldown_time
	_setup_animations()
	body_sprite.animation_finished.connect(func(): body_sprite.play("idle"))

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	var base := "res://assets/enemies/export/skeleton-"

	frames.add_animation("idle")
	frames.set_animation_speed("idle", 10.0)
	for i in 17:
		frames.add_frame("idle", load(base + "idle_%d.png" % i))

	frames.add_animation("move")
	frames.set_animation_speed("move", 15.0)
	for i in 17:
		frames.add_frame("move", load(base + "move_%d.png" % i))

	frames.add_animation("attack")
	frames.set_animation_speed("attack", 12.0)
	frames.set_animation_loop("attack", false)
	for i in 9:
		frames.add_frame("attack", load(base + "attack_%d.png" % i))

	body_sprite.sprite_frames = frames
	body_sprite.play("idle")

func _physics_process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	var direction: Vector2 = (player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	# Face movement direction but keep health bar upright
	body_sprite.rotation = direction.angle()
	health_bar_pivot.rotation = -rotation

	# Drive animation
	if body_sprite.animation != "attack":
		body_sprite.play("move")

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	health_bar.value = health
	health_bar.visible = true
	_flash()
	if health <= 0:
		_is_dead = true
		died_at.emit(global_position)
		_spawn_death_effect()
		queue_free()

func _flash() -> void:
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.12)

func _spawn_death_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.4
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 120.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 3.0
	mat.scale_max = 6.0
	mat.color = Color(1.0, 0.3, 0.2, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)

func _on_hit_area_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage") and attack_cooldown.is_stopped():
		body.take_damage(damage)
		attack_cooldown.start()
		body_sprite.play("attack")
