extends Area2D

@export var speed := 900.0
@export var damage := 20
@export var lifetime := 1.5
var hit_color := Color(1.0, 0.9, 0.3, 1.0)
var bullet_scale := 1.0
## Who fired this bullet (used to trigger aggro on hit enemies)
var source: Node2D = null

func _ready() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)
	# Apply color tint and scale from weapon
	modulate = hit_color
	scale = Vector2(bullet_scale, bullet_scale)

func _physics_process(delta: float) -> void:
	position += transform.x * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		# Notify enemy that it was attacked by this bullet's source
		if source and is_instance_valid(source) and body.has_method("set_aggro"):
			body.set_aggro(source)
	_spawn_hit_effect()
	queue_free()

func _spawn_hit_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 6
	particles.lifetime = 0.3
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 150.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = hit_color
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)
