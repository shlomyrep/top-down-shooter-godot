extends Node2D

## Cannonball fired by CannonSoldier or Tank.
## Damages walls on contact only — passes through players and other enemies.
## Self-destructs on wall hit or after a fixed lifetime.
## When aoe_radius > 0 (tank shells), structures near the impact are also damaged.

var direction: Vector2 = Vector2.RIGHT
var speed := 380.0
var wall_damage := 35
var player_damage := 25  # separate damage value when the cannonball hits the player

## AoE splash — set to 0 to disable (cannon soldier keeps default 0).
var aoe_radius  := 0.0   # world-space pixel radius of the blast
var aoe_damage  := 0     # damage dealt to structures inside the blast radius

var _lifetime := 1.8  # seconds before auto-expire

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Dark iron cannonball with a small highlight
	draw_circle(Vector2.ZERO, 9.0, Color(0.18, 0.18, 0.18, 1.0))
	draw_circle(Vector2(-3, -3), 3.0, Color(0.4, 0.4, 0.4, 0.6))

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

func _on_hit_area_body_entered(body: Node) -> void:
	var impact := global_position

	if body.has_method("take_damage"):
		# Use player_damage for layer-1 bodies (the player), wall_damage for structures
		var dmg := player_damage if (body is CharacterBody2D and (body.collision_layer & 1) != 0) else wall_damage
		body.take_damage(dmg)

	# AoE blast — damages all structures within aoe_radius of the impact point
	if aoe_radius > 0.0:
		_apply_splash(impact, body)
		_spawn_blast_effect(impact)

	queue_free()

## Deals aoe_damage to every structure within aoe_radius, excluding the direct-hit body.
func _apply_splash(impact: Vector2, direct_hit: Node) -> void:
	for cell in BuildManager.occupied_cells:
		var s: Node = BuildManager.occupied_cells[cell]
		if not is_instance_valid(s): continue
		if s == direct_hit: continue
		if not s.has_method("take_damage"): continue
		if impact.distance_to(s.global_position) <= aoe_radius:
			s.take_damage(aoe_damage)

## Shockwave ring + ember particles so the blast feels weighty.
func _spawn_blast_effect(pos: Vector2) -> void:
	var root := get_tree().current_scene

	# Ember/fire burst
	var embers := GPUParticles2D.new()
	embers.emitting  = true
	embers.one_shot  = true
	embers.amount    = 28
	embers.lifetime  = 0.6
	embers.global_position = pos
	var emat := ParticleProcessMaterial.new()
	emat.direction            = Vector3(0, 0, 0)
	emat.spread               = 180.0
	emat.initial_velocity_min = 120.0
	emat.initial_velocity_max = 300.0
	emat.gravity              = Vector3.ZERO
	emat.scale_min            = 5.0
	emat.scale_max            = 14.0
	emat.color                = Color(1.0, 0.45, 0.05, 1.0)
	embers.process_material   = emat
	embers.finished.connect(embers.queue_free)
	root.add_child(embers)

	# Smoke cloud
	var smoke := GPUParticles2D.new()
	smoke.emitting  = true
	smoke.one_shot  = true
	smoke.amount    = 16
	smoke.lifetime  = 0.8
	smoke.global_position = pos
	var smat := ParticleProcessMaterial.new()
	smat.direction            = Vector3(0, 0, 0)
	smat.spread               = 180.0
	smat.initial_velocity_min = 40.0
	smat.initial_velocity_max = 110.0
	smat.gravity              = Vector3.ZERO
	smat.scale_min            = 10.0
	smat.scale_max            = 22.0
	smat.color                = Color(0.3, 0.3, 0.3, 0.7)
	smoke.process_material    = smat
	smoke.finished.connect(smoke.queue_free)
	root.add_child(smoke)
