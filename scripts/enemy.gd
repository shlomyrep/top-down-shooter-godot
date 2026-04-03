extends CharacterBody2D

@export var speed := 120.0
@export var max_health := 60
@export var damage := 10
@export var attack_cooldown_time := 1.0

var health: int
var player: Node2D = null
var _is_dead := false
var _knockback_velocity := Vector2.ZERO
var _bodies_in_hit_area: Array[Node2D] = []

## AI state machine
enum State { CHASE, ATTACK_PLAYER, ATTACK_STRUCTURE }
var _state := State.CHASE
var _wall_target: Node2D = null
## Set when a squad soldier shoots this enemy
var _aggro_target: Node2D = null

const KNOCKBACK_FORCE   := 340.0
const KNOCKBACK_DECAY   := 12.0

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
	$HitArea.body_exited.connect(_on_hit_area_body_exited)
	attack_cooldown.timeout.connect(_on_attack_cooldown_timeout)

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

## Called by bullet.gd when a squad soldier's bullet hits this enemy.
func set_aggro(attacker: Node2D) -> void:
	if attacker and is_instance_valid(attacker) and attacker.is_in_group("squad"):
		_aggro_target = attacker

## Returns the nearest non-downed node in the "target_players" group.
## Downed players are skipped so enemies chase the living partner instead.
func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for t in get_tree().get_nodes_in_group("target_players"):
		if not is_instance_valid(t):
			continue
		# Skip downed players
		if t.get("is_downed") == true:
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t
	# Fall back to any target if all are downed (shouldn't happen — game ends)
	if best == null:
		best = player
	return best

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	# Clear stale references
	if _aggro_target and not is_instance_valid(_aggro_target):
		_aggro_target = null
	if _wall_target and not is_instance_valid(_wall_target):
		_wall_target = null
		_state = State.CHASE

	# Prefer chasing the squad member that last shot us; fall back to nearest player
	var focus: Node2D = _aggro_target \
			if (_aggro_target and is_instance_valid(_aggro_target)) \
			else _nearest_target()

	match _state:
		State.CHASE:
			var direction: Vector2 = (focus.global_position - global_position).normalized()
			_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, KNOCKBACK_DECAY * delta)
			velocity = direction * speed + _knockback_velocity
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()

			body_sprite.rotation = direction.angle()
			health_bar_pivot.rotation = -rotation

			if body_sprite.animation != "attack":
				body_sprite.play("move")

			# Detect collision with a damageable structure → switch to wall-attack mode
			for i in get_slide_collision_count():
				var col := get_slide_collision(i)
				var collider := col.get_collider()
				if collider and collider.has_method("take_damage") \
						and not collider.is_in_group("player") \
						and not collider.is_in_group("squad"):
					_wall_target = collider
					_state = State.ATTACK_STRUCTURE
					break

		State.ATTACK_PLAYER:
			# Stop pressing into the player — stand still and swing
			velocity = Vector2.ZERO
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()

			# If all players left the hit area, resume chasing
			if _bodies_in_hit_area.is_empty():
				_state = State.CHASE
				return

			var hit_target := _bodies_in_hit_area[0]
			if is_instance_valid(hit_target):
				body_sprite.rotation = (hit_target.global_position - global_position).angle()
				health_bar_pivot.rotation = -rotation

			if attack_cooldown.is_stopped():
				_do_melee_attack(hit_target)

		State.ATTACK_STRUCTURE:
			velocity = Vector2.ZERO
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()

			if not _wall_target or not is_instance_valid(_wall_target):
				_wall_target = null
				_state = State.CHASE
				return

			var dir_to_wall: Vector2 = (_wall_target.global_position - global_position).normalized()
			body_sprite.rotation = dir_to_wall.angle()
			health_bar_pivot.rotation = -rotation

			if attack_cooldown.is_stopped():
				_wall_target.take_damage(damage)
				attack_cooldown.start()
				body_sprite.play("attack")
				SoundManager.play_sfx_2d("enemy_hit_structure", global_position)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	health_bar.value = health
	health_bar.visible = true
	SoundManager.play_sfx_2d("enemy_hit", global_position)
	_flash()
	if health <= 0:
		_is_dead = true
		died_at.emit(global_position)
		SoundManager.play_sfx_2d("skeleton_death", global_position)
		_spawn_death_effect()
		queue_free()

func _flash() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color(1.4, 0.2, 0.2, 1.0), 0.04)
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.08)

func _spawn_death_effect() -> void:
	# Main blood/debris burst
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 18
	particles.lifetime = 0.5
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 160.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 3.0
	mat.scale_max = 7.0
	mat.color = Color(0.78, 0.12, 0.12, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)
	# Secondary flash ring
	var flash := GPUParticles2D.new()
	flash.emitting = true
	flash.one_shot = true
	flash.amount = 6
	flash.lifetime = 0.25
	flash.global_position = global_position
	var fmat := ParticleProcessMaterial.new()
	fmat.direction = Vector3(0, 0, 0)
	fmat.spread = 180.0
	fmat.initial_velocity_min = 30.0
	fmat.initial_velocity_max = 55.0
	fmat.gravity = Vector3.ZERO
	fmat.scale_min = 6.0
	fmat.scale_max = 12.0
	fmat.color = Color(1.0, 0.55, 0.1, 0.85)
	flash.process_material = fmat
	flash.finished.connect(flash.queue_free)
	get_tree().current_scene.add_child(flash)
	_leave_bloodstain()


func _leave_bloodstain() -> void:
	var arena := get_tree().current_scene.get_node_or_null("Arena")
	if not arena:
		return
	var stain := Polygon2D.new()
	stain.color = Color(0.18, 0.028, 0.028, 0.80)
	var pts := PackedVector2Array()
	var r := 11.0 + randf() * 10.0
	var num_pts := 9
	for i in num_pts:
		var angle := TAU * i / num_pts + randf_range(-0.38, 0.38)
		var dist := r * (0.52 + randf() * 0.58)
		pts.append(Vector2(cos(angle) * dist, sin(angle) * dist))
	stain.polygon = pts
	stain.position = arena.to_local(global_position)
	stain.z_index = -1
	arena.add_child(stain)

func _on_hit_area_body_entered(body: Node2D) -> void:
	# Only melee-attack player(s) and squad members; walls are handled by the state machine
	var is_player_body := body.is_in_group("target_players")
	var is_squad_member := body.is_in_group("squad")
	if not (is_player_body or is_squad_member):
		return
	if not _bodies_in_hit_area.has(body):
		_bodies_in_hit_area.append(body)
	# Switch to stopped attack state so the skeleton doesn't keep pressing into the player
	if _state == State.CHASE:
		_state = State.ATTACK_PLAYER
	if attack_cooldown.is_stopped():
		_do_melee_attack(body)

func _on_hit_area_body_exited(body: Node2D) -> void:
	_bodies_in_hit_area.erase(body)
	if _bodies_in_hit_area.is_empty() and _state == State.ATTACK_PLAYER:
		_state = State.CHASE

func _on_attack_cooldown_timeout() -> void:
	# Structure-attack state drives its own attack cycle inline
	if _state == State.ATTACK_STRUCTURE:
		return
	# Remove any freed nodes
	_bodies_in_hit_area = _bodies_in_hit_area.filter(func(b): return is_instance_valid(b))
	if _bodies_in_hit_area.is_empty():
		if _state == State.ATTACK_PLAYER:
			_state = State.CHASE
		return
	_do_melee_attack(_bodies_in_hit_area[0])

func _do_melee_attack(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	body.take_damage(damage)
	attack_cooldown.start()
	body_sprite.play("attack")
	SoundManager.play_sfx_2d("enemy_melee_swing", global_position)
	# Knockback only applies when hitting a player — pushes enemy back so it
	# doesn't stay glued against the player
	if body.is_in_group("target_players"):
		var push_dir: Vector2 = (global_position - body.global_position).normalized()
		_knockback_velocity = push_dir * KNOCKBACK_FORCE
