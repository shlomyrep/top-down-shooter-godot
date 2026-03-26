extends CharacterBody2D

## Tank — one per wave from wave 7 onward.
## Priority: destroy towers first (one shot each), then walls, then player.
## Body turns gradually like a real tracked vehicle (can't strafe).
## Barrel independently sweeps smoothly to aim at the current target.

@export var speed := 40.0
@export var max_health := 1200
@export var attack_range := 300.0
@export var attack_cooldown_time := 4.0
@export var contact_damage := 20
@export var contact_cooldown_time := 1.5

var health: int
var player: Node2D = null
var _is_dead := false

enum State {
	APPROACH_TOWER,    ## moving toward nearest tower
	ATTACK_ANY_TOWER,  ## standing still, shoots every tower in range without moving
	APPROACH_WALL,     ## moving toward nearest wall
	ATTACK_WALL,       ## standing still, shooting current wall
	SEEK_PLAYER        ## no structures — hunt the player
}
var _state        := State.SEEK_PLAYER
var _target       : Node2D = null   # primary move-to target
var _shoot_target : Node2D = null   # node barrel is currently aimed at

var _attack_timer  := 0.0
var _contact_timer := 0.0
# Navigation / stuck avoidance
var _stuck_timer      := 0.0
var _avoid_angle      := 0.0   # radians added to move direction when stuck
var _checkpoint_pos   := Vector2.ZERO
var _checkpoint_timer := 0.0
const CHECKPOINT_INTERVAL := 0.5   # sample net displacement every 0.5 s
# Log throttle
var _log_timer   := 0.0
const LOG_INTERVAL := 1.0

signal died_at(pos: Vector2)

# tankb.png faces UP → rotation_offset = -PI/2 to align with Godot's right-is-0°
const BODY_ROTATION_OFFSET := -PI / 2.0
const BODY_TURN_SPEED   := 3.0
const BARREL_TURN_SPEED := 5.0

@onready var body_sprite  : Sprite2D    = $BodySprite
@onready var barrel_sprite: Sprite2D    = $BarrelSprite
@onready var health_bar   : ProgressBar = $HealthBarPivot/HealthBar
@onready var health_bar_pivot: Node2D   = $HealthBarPivot

var _cannonball_scene: PackedScene = preload("res://scenes/cannonball.tscn")

func _ready() -> void:
	_checkpoint_pos = global_position
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.visible = false
	print("[TANK] Spawned  pos=", global_position, "  hp=", health)
	call_deferred("_pick_next_target")

func _find_nearest_structure(type: String) -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for cell in BuildManager.occupied_cells:
		var occ = BuildManager.occupied_cells[cell]
		if not is_instance_valid(occ): continue
		if not occ.has_meta("structure_type") or occ.get_meta("structure_type") != type: continue
		if not occ.has_method("take_damage"): continue
		var d := global_position.distance_to(occ.global_position)
		if d < best:
			best = d
			nearest = occ
	return nearest

## Returns nearest structure of 'type' that is within range_px of the tank.
func _find_nearest_in_range(type: String, range_px: float) -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for cell in BuildManager.occupied_cells:
		var occ = BuildManager.occupied_cells[cell]
		if not is_instance_valid(occ): continue
		if not occ.has_meta("structure_type") or occ.get_meta("structure_type") != type: continue
		if not occ.has_method("take_damage"): continue
		var d := global_position.distance_to(occ.global_position)
		if d <= range_px and d < best:
			best = d
			nearest = occ
	return nearest

func _pick_next_target() -> void:
	# Priority 1: towers
	var tower := _find_nearest_structure("tower")
	if tower:
		_target = tower
		var d := global_position.distance_to(tower.global_position)
		if d <= attack_range:
			_shoot_target = tower
			_state = State.ATTACK_ANY_TOWER
			print("[TANK] _pick \u2192 ATTACK_ANY_TOWER  tower=(", snappedf(tower.global_position.x,1.0), ",", snappedf(tower.global_position.y,1.0), ")  d=", snappedf(d,1.0))
		else:
			_state = State.APPROACH_TOWER
			print("[TANK] _pick \u2192 APPROACH_TOWER  tower=(", snappedf(tower.global_position.x,1.0), ",", snappedf(tower.global_position.y,1.0), ")  d=", snappedf(d,1.0))
		return
	# Priority 2: walls
	var wall := _find_nearest_structure("wall")
	if wall:
		_target = wall
		var d := global_position.distance_to(wall.global_position)
		if d <= attack_range:
			_state = State.ATTACK_WALL
			print("[TANK] _pick \u2192 ATTACK_WALL  wall=(", snappedf(wall.global_position.x,1.0), ",", snappedf(wall.global_position.y,1.0), ")  d=", snappedf(d,1.0))
		else:
			_state = State.APPROACH_WALL
			print("[TANK] _pick \u2192 APPROACH_WALL  wall=(", snappedf(wall.global_position.x,1.0), ",", snappedf(wall.global_position.y,1.0), ")  d=", snappedf(d,1.0))
		return
	# Priority 3: player
	_target       = null
	_shoot_target = null
	_state        = State.SEEK_PLAYER
	print("[TANK] _pick \u2192 SEEK_PLAYER (no structures found)")

func _physics_process(delta: float) -> void:
	if _is_dead or not player or not is_instance_valid(player):
		return

	_attack_timer  = maxf(0.0, _attack_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_log_timer    += delta

	# Periodic debug snapshot
	if _log_timer >= LOG_INTERVAL:
		_log_timer = 0.0
		var tpos := "none"
		if _target and is_instance_valid(_target):
			tpos = str(snappedf(_target.global_position.x, 1.0)) + "," + str(snappedf(_target.global_position.y, 1.0))
		print("[TANK] tick  state=", _state_name(),
			"  pos=(", snappedf(global_position.x,1.0), ",", snappedf(global_position.y,1.0), ")",
			"  target=", tpos, "  hp=", health,
			"  atk_cd=", snappedf(_attack_timer,0.1), "  stuck=", snappedf(_stuck_timer,0.1))

	match _state:

		# ── Move toward nearest tower ──────────────────────────────────────────
		State.APPROACH_TOWER:
			if not is_instance_valid(_target):
				print("[TANK] APPROACH_TOWER: target gone \u2192 re-pick")
				_pick_next_target(); return
			var d := global_position.distance_to(_target.global_position)
			if d <= attack_range:
				_shoot_target = _find_nearest_in_range("tower", attack_range)
				_state = State.ATTACK_ANY_TOWER
				print("[TANK] APPROACH_TOWER \u2192 ATTACK_ANY_TOWER  d=", snappedf(d,1.0))
				return
			_move_toward(_target.global_position, delta)
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				(_target.global_position - global_position).angle(), BARREL_TURN_SPEED * delta)
			health_bar_pivot.rotation = -rotation

		# ── Stand ground, sweep barrel, shoot ANY tower in range ──────────────
		State.ATTACK_ANY_TOWER:
			velocity = Vector2.ZERO
			move_and_slide()
			health_bar_pivot.rotation = -rotation
			var t := _find_nearest_in_range("tower", attack_range)
			if t:
				if _shoot_target != t:
					print("[TANK] ATTACK_ANY_TOWER: barrel re-targeting \u2192 ", t.global_position)
				_shoot_target = t
				var aim := (_shoot_target.global_position - global_position).normalized()
				body_sprite.rotation = lerp_angle(body_sprite.rotation,
					aim.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * delta)
				barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
					aim.angle(), BARREL_TURN_SPEED * delta)
				if _attack_timer <= 0.0:
					print("[TANK] FIRE tower at ", _shoot_target.global_position)
					_fire_cannonball(_shoot_target.global_position)
					_attack_timer = attack_cooldown_time
			else:
				var any_tower := _find_nearest_structure("tower")
				if any_tower:
					_target = any_tower
					_state  = State.APPROACH_TOWER
					print("[TANK] ATTACK_ANY_TOWER: no tower in range \u2192 APPROACH_TOWER at ", any_tower.global_position)
				else:
					print("[TANK] ATTACK_ANY_TOWER: all towers gone \u2192 re-pick")
					_pick_next_target()

		# ── Move toward nearest wall ───────────────────────────────────────────
		State.APPROACH_WALL:
			if not is_instance_valid(_target):
				print("[TANK] APPROACH_WALL: target gone \u2192 re-pick")
				_pick_next_target(); return
			var d := global_position.distance_to(_target.global_position)
			if d <= attack_range:
				_state = State.ATTACK_WALL
				print("[TANK] APPROACH_WALL \u2192 ATTACK_WALL  d=", snappedf(d,1.0))
				return
			_move_toward(_target.global_position, delta)
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				(_target.global_position - global_position).angle(), BARREL_TURN_SPEED * delta)
			health_bar_pivot.rotation = -rotation

		# ── Stand ground, shoot current wall ──────────────────────────────────
		State.ATTACK_WALL:
			if not is_instance_valid(_target):
				print("[TANK] ATTACK_WALL: wall gone \u2192 re-pick")
				_pick_next_target(); return
			velocity = Vector2.ZERO
			move_and_slide()
			var dir := (_target.global_position - global_position).normalized()
			body_sprite.rotation = lerp_angle(body_sprite.rotation,
				dir.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * delta)
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				dir.angle(), BARREL_TURN_SPEED * delta)
			health_bar_pivot.rotation = -rotation
			if _attack_timer <= 0.0:
				print("[TANK] FIRE wall at ", _target.global_position)
				_fire_cannonball(_target.global_position)
				_attack_timer = attack_cooldown_time

		# ── Chase + shoot player ───────────────────────────────────────────────
		State.SEEK_PLAYER:
			if _find_nearest_structure("tower") or _find_nearest_structure("wall"):
				print("[TANK] SEEK_PLAYER: structure appeared \u2192 re-pick")
				_pick_next_target(); return
			var dist := global_position.distance_to(player.global_position)
			var dir  := (player.global_position - global_position).normalized()
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				dir.angle(), BARREL_TURN_SPEED * delta)
			health_bar_pivot.rotation = -rotation
			if dist > attack_range:
				_move_toward(player.global_position, delta)
			else:
				velocity = Vector2.ZERO
				move_and_slide()
				body_sprite.rotation = lerp_angle(body_sprite.rotation,
					dir.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * delta)
				if _attack_timer <= 0.0:
					print("[TANK] FIRE player")
					_fire_cannonball(player.global_position)
					_attack_timer = attack_cooldown_time

## Anti-stuck navigation: measures net displacement over 0.5s checkpoints
## (immune to frame-level oscillation), grows avoidance angle, gentle wall deflection.
func _move_toward(target_pos: Vector2, delta: float) -> void:
	var to_target     := target_pos - global_position
	var dir_to_target := to_target.normalized()

	# ── Stuck detection via 0.5 s position checkpoints ───────────────────
	# Measuring frame-to-frame displacement is fooled by oscillation (tank
	# bounces ±3 px/frame → always looks like it moved).  Checkpoint sampling
	# measures net drift over a longer window.
	_checkpoint_timer += delta
	if _checkpoint_timer >= CHECKPOINT_INTERVAL:
		var net_move := global_position.distance_to(_checkpoint_pos)
		var min_move := speed * CHECKPOINT_INTERVAL * 0.2   # expect ≥20% of max speed
		if net_move < min_move:
			_stuck_timer += CHECKPOINT_INTERVAL
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - CHECKPOINT_INTERVAL * 2.0)
		_checkpoint_pos   = global_position
		_checkpoint_timer = 0.0

	# ── Grow avoidance angle: 0→90° over 2 s, flip side every 1.5 s ─────
	if _stuck_timer > 0.4:
		var magnitude := minf(_stuck_timer / 2.0, 1.0) * (PI * 0.5)
		var flip      := 1.0 if int(_stuck_timer / 1.5) % 2 == 0 else -1.0
		_avoid_angle  = magnitude * flip
		if fmod(_stuck_timer, 1.5) < delta + 0.05:
			print("[TANK] STUCK  timer=", snappedf(_stuck_timer, 0.1),
				"  avoid=", snappedf(rad_to_deg(_avoid_angle), 1.0), "°")
	else:
		_avoid_angle = lerpf(_avoid_angle, 0.0, delta * 3.0)

	# ── Gentle wall pushout (LOW weight — deflects, does not reverse) ─────
	# Weight 1.5 caused the bug: repulsion(0,1) overpowered desire(0,-1)
	# and sent the tank backward, preventing stuck_timer from ever firing.
	var repulsion := Vector2.ZERO
	for i in get_slide_collision_count():
		repulsion += get_slide_collision(i).get_normal()

	var move_dir := dir_to_target.rotated(_avoid_angle)
	if repulsion.length_squared() > 0.01:
		move_dir = (move_dir + repulsion.normalized() * 0.3).normalized()

	velocity = move_dir * speed
	move_and_slide()
	var travel_dir := velocity.normalized() if velocity.length_squared() > 25.0 else dir_to_target
	body_sprite.rotation = lerp_angle(body_sprite.rotation,
		travel_dir.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * delta)

func _state_name() -> String:
	return State.keys()[_state]

func _fire_cannonball(target_pos: Vector2) -> void:
	var cb: Node2D = _cannonball_scene.instantiate()
	cb.direction = (target_pos - global_position).normalized()
	# Spawn BEHIND the tank so the ball always starts outside any structure's collision shape
	cb.global_position = global_position - cb.direction * 30.0
	cb.wall_damage = 999  # one-shots any structure
	get_tree().current_scene.add_child(cb)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	print("[TANK] take_damage  amount=", amount, "  hp_left=", health)
	health_bar.value = health
	health_bar.visible = true
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tw: Tween = create_tween()
	tw.tween_property(body_sprite, "modulate", Color.WHITE, 0.15)
	barrel_sprite.modulate = Color(10, 10, 10, 1)
	var tw2: Tween = create_tween()
	tw2.tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)
	if health <= 0:
		_is_dead = true
		print("[TANK] DEAD at ", global_position)
		died_at.emit(global_position)
		_spawn_death_effect()
		queue_free()

func _on_hit_area_body_entered(body: Node2D) -> void:
	var is_player_body := player != null and body == player
	if is_player_body and _contact_timer <= 0.0:
		print("[TANK] Contact damage to player  amount=", contact_damage)
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown_time

func _spawn_death_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 30
	particles.lifetime = 0.8
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 260.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 5.0
	mat.scale_max = 14.0
	mat.color = Color(0.9, 0.5, 0.05, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)
