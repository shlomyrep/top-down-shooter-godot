extends Node2D

## Dropped at a world position. Spawns a sequence of bomb-impact effects that
## each deal AOE damage to enemies within blast_radius.

@export var bomb_count   := 5
@export var blast_radius := 120.0
@export var damage       := 60
@export var delay        := 0.18

func _ready() -> void:
	for i in bomb_count:
		var t := get_tree().create_timer(i * delay)
		t.timeout.connect(_drop_bomb.bind(i))
	# Self-clean after all bombs
	var cleanup := get_tree().create_timer(bomb_count * delay + 0.8)
	cleanup.timeout.connect(queue_free)

func _drop_bomb(index: int) -> void:
	var offset := Vector2(randf_range(-80, 80), randf_range(-80, 80))
	var bomb_pos := global_position + offset

	# Visual flash
	var flash := Polygon2D.new()
	flash.polygon = _circle_poly(blast_radius * 0.6)
	flash.color = Color(1.0, 0.55, 0.05, 0.75)
	flash.global_position = bomb_pos
	flash.z_index = 20
	get_tree().current_scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector2(2.5, 2.5), 0.25)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.tween_callback(flash.queue_free)

	# Shockwave ring
	var ring := Polygon2D.new()
	ring.polygon = _circle_poly(blast_radius)
	ring.color   = Color(1.0, 0.8, 0.3, 0.35)
	ring.global_position = bomb_pos
	ring.z_index = 19
	get_tree().current_scene.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_property(ring, "scale", Vector2(1.8, 1.8), 0.3)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	ring_tween.tween_callback(ring.queue_free)

	# Particles
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot  = true
	particles.amount    = 16
	particles.lifetime  = 0.45
	particles.global_position = bomb_pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 120.0
	mat.initial_velocity_max = 240.0
	mat.gravity  = Vector3.ZERO
	mat.scale_min = 4.0
	mat.scale_max = 8.0
	mat.color = Color(1.0, 0.4, 0.1, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)

	# AOE damage
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			var d: float = enemy.global_position.distance_to(bomb_pos)
			if d <= blast_radius:
				enemy.take_damage(damage)

func _circle_poly(r: float) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	var steps := 16
	for i in steps:
		var a := TAU * i / steps
		pts.append(Vector2(cos(a), sin(a)) * r)
	return PackedVector2Array(pts)
