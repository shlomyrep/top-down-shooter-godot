extends CharacterBody2D

## Cannon Soldier — introduced in wave 5.
## On spawn: finds nearest wall. Approaches if not in range, then stands
## ground and shoots until the wall is destroyed, then finds the next one.

@export var speed := 35.0
@export var max_health := 120
@export var attack_range := 220.0
@export var attack_cooldown_time := 3.5
@export var contact_damage := 10
@export var contact_cooldown_time := 1.0

var health: int
var player: Node2D = null
var _is_dead := false

enum State { APPROACH_WALL, ATTACK_WALL, IDLE }
var _state := State.IDLE
var _wall_target: Node2D = null

var _attack_timer  := 0.0
var _contact_timer := 0.0
# Log throttle
var _log_timer   := 0.0
const LOG_INTERVAL := 1.0

signal died_at(pos: Vector2)

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var health_bar: ProgressBar = $HealthBarPivot/HealthBar
@onready var health_bar_pivot: Node2D = $HealthBarPivot

var _cannonball_scene: PackedScene = preload("res://scenes/cannonball.tscn")

func _ready() -> void:
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.visible = false
	_setup_animations()
	print("[CANNON] Spawned  pos=", global_position)
	# Pick initial target after one frame so BuildManager is ready
	call_deferred("_pick_next_wall")

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", false)
	frames.add_frame("idle", load("res://assets/enemies/sgc1.png"))
	body_sprite.sprite_frames = frames
	body_sprite.play("idle")  # single non-looping frame — shows sprite, then stays on frame 0

func _find_nearest_wall() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	var wall_count := 0
	for cell in BuildManager.occupied_cells:
		var occupier = BuildManager.occupied_cells[cell]
		if not is_instance_valid(occupier):
			continue
		if not occupier.has_meta("structure_type") or occupier.get_meta("structure_type") != "wall":
			continue
		if not occupier.has_method("take_damage"):
			continue
		wall_count += 1
		var d: float = global_position.distance_to(occupier.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = occupier
	if nearest:
		print("[CANNON] _find_nearest_wall: total=", wall_count, "  nearest=", nearest.global_position, "  dist=", snappedf(nearest_dist,1.0))
	else:
		print("[CANNON] _find_nearest_wall: NO walls found (checked ", BuildManager.occupied_cells.size(), " cells)")
	return nearest

func _pick_next_wall() -> void:
	_wall_target = _find_nearest_wall()
	if _wall_target:
		var dist := global_position.distance_to(_wall_target.global_position)
		var new_state := State.ATTACK_WALL if dist <= attack_range else State.APPROACH_WALL
		print("[CANNON] _pick_next_wall → ", State.keys()[new_state], "  dist=", snappedf(dist,1.0))
		_state = new_state
	else:
		print("[CANNON] _pick_next_wall → IDLE (no walls)")
		_state = State.IDLE

## Returns the nearest node in the "target_players" group (local + remote player).
func _nearest_target() -> Node2D:
	var best: Node2D = player
	var best_dist: float = INF if not player else global_position.distance_to(player.global_position)
	for t in get_tree().get_nodes_in_group("target_players"):
		if not is_instance_valid(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t
	return best

func _physics_process(delta: float) -> void:
	if _is_dead or not player or not is_instance_valid(player):
		return

	_attack_timer  = maxf(0.0, _attack_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_log_timer    += delta

	# Periodic state log
	if _log_timer >= LOG_INTERVAL:
		_log_timer = 0.0
		var wt := "none"
		if _wall_target and is_instance_valid(_wall_target):
			wt = str(_wall_target.global_position)
		print("[CANNON] tick  state=", State.keys()[_state],
			"  pos=", global_position,
			"  target=", wt,
			"  atk_cd=", snappedf(_attack_timer,0.1))

	# Validate current target every frame — re-pick if wall was destroyed
	if _state != State.IDLE:
		if not is_instance_valid(_wall_target) or _wall_target.hp <= 0:
			print("[CANNON] Target invalid/dead  valid=", is_instance_valid(_wall_target) if _wall_target else false, " → re-picking")
			_pick_next_wall()

	match _state:
		State.APPROACH_WALL:
			var dir := (_wall_target.global_position - global_position).normalized()
			velocity = dir * speed
			move_and_slide()
			body_sprite.rotation = dir.angle()
			health_bar_pivot.rotation = -rotation
			var d := global_position.distance_to(_wall_target.global_position)
			if d <= attack_range:
				print("[CANNON] APPROACH_WALL → ATTACK_WALL  dist=", snappedf(d,1.0))
				_state = State.ATTACK_WALL

		State.ATTACK_WALL:
			velocity = Vector2.ZERO
			move_and_slide()
			var dir := (_wall_target.global_position - global_position).normalized()
			body_sprite.rotation = dir.angle()
			health_bar_pivot.rotation = -rotation
			if _attack_timer <= 0.0:
				print("[CANNON] FIRE  target=", _wall_target.global_position)
				_fire_cannonball(_wall_target.global_position)
				_attack_timer = attack_cooldown_time

		State.IDLE:
			# No walls — keep checking every frame so we immediately start moving when one appears
			velocity = Vector2.ZERO
			move_and_slide()
			body_sprite.play("idle")
			_pick_next_wall()

func _fire_cannonball(target_pos: Vector2) -> void:
	var cb: Node2D = _cannonball_scene.instantiate()
	cb.direction = (target_pos - global_position).normalized()
	# Spawn BEHIND the soldier so the ball always starts outside any wall's collision shape
	cb.global_position = global_position - cb.direction * 25.0
	get_tree().current_scene.add_child(cb)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	print("[CANNON] take_damage  amount=", amount, "  hp_left=", health)
	health_bar.value = health
	health_bar.visible = true
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.12)
	if health <= 0:
		_is_dead = true
		print("[CANNON] DEAD at ", global_position)
		died_at.emit(global_position)
		_spawn_death_effect()
		queue_free()

func _on_hit_area_body_entered(body: Node2D) -> void:
	# Contact damage — applies in all states so the soldier is dangerous up close
	var is_player_body := body.is_in_group("target_players")
	if is_player_body and _contact_timer <= 0.0:
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown_time

func _spawn_death_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 16
	particles.lifetime = 0.5
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 180.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 4.0
	mat.scale_max = 8.0
	mat.color = Color(0.6, 0.4, 0.1, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)
