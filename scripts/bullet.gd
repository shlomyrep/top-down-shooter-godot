extends Area2D

@export var speed := 900.0
@export var damage := 20
@export var lifetime := 1.5
var hit_color := Color(1.0, 0.9, 0.3, 1.0)
var bullet_scale := 1.0
## Who fired this bullet (used to trigger aggro on hit enemies)
var source: Node2D = null

const _TRAIL_MAX := 6
var _trail_positions: Array[Vector2] = []
@onready var _trail: Line2D = $Trail

func _ready() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)
	modulate = hit_color
	scale = Vector2(bullet_scale, bullet_scale)
	# Set trail color to match the bullet's weapon color
	_trail.default_color = Color(hit_color.r, hit_color.g, hit_color.b, 0.65)

func _physics_process(delta: float) -> void:
	position += transform.x * speed * delta
	# Update trail: store world positions, then convert to local for Line2D
	_trail_positions.push_front(global_position)
	if _trail_positions.size() > _TRAIL_MAX:
		_trail_positions.resize(_TRAIL_MAX)
	var pts: PackedVector2Array
	for i in _trail_positions.size():
		pts.append(to_local(_trail_positions[i]))
	_trail.points = pts
	# Fade the trail width toward the tail
	var widths := PackedFloat32Array()
	for i in _trail_positions.size():
		widths.append(lerp(3.0, 0.3, float(i) / float(_TRAIL_MAX)))
	_trail.width_curve = null  # clear curve; rely on per-point widths not available in Line2D, use alpha
	_trail.modulate.a = 0.7

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
