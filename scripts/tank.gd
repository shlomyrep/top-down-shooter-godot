extends CharacterBody2D

## Tank — one per wave from wave 7 onward.
##
## Hull (body) behaves like a real tracked vehicle:
##   - In HOLD_AND_FIRE: hull slowly turns toward the current threat; barrel
##     aims precisely and independently, can fire in any direction.
##   - In ADVANCE: hull faces the travel direction (tanks can't strafe).
##     Barrel stays locked on the best target and fires while moving.
##   - In RAM: hull aligns with the charge direction at high turn-rate.
##     Barrel also faces the target (combined fire + ram).
##
## States re-evaluated every PATH_REFRESH seconds via BFS (same as bug enemy).

@export var max_health           := 3600
@export var attack_range         := 400.0
@export var attack_cooldown_time := 3.0
@export var contact_damage       := 60
@export var contact_cooldown_time := 1.5
@export var move_speed           := 55.0
@export var ram_speed            := 130.0

var health: int
var player: Node2D = null
var _is_dead := false

var _attack_timer  := 0.0
var _contact_timer := 0.0

## BFS navigation
var _path: Array    = []
var _path_blocked   := false
var _path_timer     := 0.0
const PATH_REFRESH   := 3.0
const WAYPOINT_REACH := 30.0

enum State { HOLD_AND_FIRE, ADVANCE, RAM }
var _state := State.HOLD_AND_FIRE

signal died_at(pos: Vector2)

## tankb.png front faces the BOTTOM of the image.
## Rotating by -PI/2 aligns that downward-front with Godot's right-is-0° convention.
const BODY_ROTATION_OFFSET := -PI / 2.0
## Hull turns slower than the barrel — the lag feels like a heavy vehicle pivoting.
const BODY_TURN_SPEED      := 3.0
## Barrel swivels fast — the gunner tracks targets precisely.
const BARREL_TURN_SPEED    := 7.0

@onready var body_sprite     : Sprite2D    = $BodySprite
@onready var barrel_sprite   : Sprite2D    = $BarrelSprite
@onready var health_bar      : ProgressBar = $HealthBarPivot/HealthBar
@onready var health_bar_pivot: Node2D      = $HealthBarPivot

var _cannonball_scene: PackedScene = preload("res://scenes/cannonball.tscn")

func _ready() -> void:
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.visible = false
	call_deferred("_refresh_path_and_state")

# ─────────────────────────────────────────────────────────────────────────────
# Structure / target helpers
# ─────────────────────────────────────────────────────────────────────────────

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

func _any_structures_exist() -> bool:
	for cell in BuildManager.occupied_cells:
		var occ = BuildManager.occupied_cells[cell]
		if not is_instance_valid(occ): continue
		if not occ.has_meta("structure_type"): continue
		var t: String = occ.get_meta("structure_type")
		if (t == "tower" or t == "wall") and occ.has_method("take_damage"):
			return true
	return false

func _nearest_target() -> Node2D:
	var best: Node2D = player
	var best_dist: float = INF if not player else global_position.distance_to(player.global_position)
	for t in get_tree().get_nodes_in_group("target_players"):
		if not is_instance_valid(t): continue
		var d := global_position.distance_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t
	return best

## Highest-priority target inside attack_range: tower > wall > player.
func _get_best_target() -> Node2D:
	var tower := _find_nearest_in_range("tower", attack_range)
	if tower: return tower
	var wall := _find_nearest_in_range("wall", attack_range)
	if wall: return wall
	var p := _nearest_target()
	if p and is_instance_valid(p) and global_position.distance_to(p.global_position) <= attack_range:
		return p
	return null

## Returns the next BFS waypoint (advances the path as waypoints are reached).
func _next_waypoint() -> Vector2:
	if _path.is_empty():
		return player.global_position
	if global_position.distance_to(_path[0]) < WAYPOINT_REACH:
		_path.remove_at(0)
	return _path[0] if not _path.is_empty() else player.global_position

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _is_dead or not player or not is_instance_valid(player):
		return

	_attack_timer  = maxf(0.0, _attack_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	# health bar pivot is a sibling sprite — counter-rotate to keep it upright
	health_bar_pivot.rotation = 0.0

	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_REFRESH
		_refresh_path_and_state()

	match _state:

		# ── Blocked: stand ground, hull lazily faces the threat ───────────────
		State.HOLD_AND_FIRE:
			velocity = Vector2.ZERO
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()
			var threat := _get_best_target()
			if threat and is_instance_valid(threat):
				# Hull slowly swings toward the threat — gives the feel of a
				# heavy turret ring adjusting its base plate.
				var td := (threat.global_position - global_position).normalized()
				body_sprite.rotation = lerp_angle(body_sprite.rotation,
					td.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * 0.35 * delta)
			_aim_barrel_and_fire(delta)

		# ── Path open but structures remain: advance while shooting ──────────
		State.ADVANCE:
			var dest       := _next_waypoint()
			var travel_dir := (dest - global_position).normalized()
			velocity = travel_dir * move_speed
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()
			# Hull faces travel direction: tanks are tracked, they CANNOT strafe.
			body_sprite.rotation = lerp_angle(body_sprite.rotation,
				travel_dir.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * delta)
			# Barrel is fully independent — it keeps aiming at the best target
			# even if that means pointing sideways or backwards relative to the hull.
			_aim_barrel_and_fire(delta)

		# ── Clear field: charge the player at full speed ──────────────────────
		State.RAM:
			var ram_target := _nearest_target()
			if not ram_target or not is_instance_valid(ram_target):
				return
			var dir := (ram_target.global_position - global_position).normalized()
			velocity = dir * ram_speed
			DepenetrationHelper.resolve(self, delta)
			move_and_slide()
			# Hull snaps quickly toward charge direction (urgent pivot).
			body_sprite.rotation = lerp_angle(body_sprite.rotation,
				dir.angle() + BODY_ROTATION_OFFSET, BODY_TURN_SPEED * 2.5 * delta)
			# Barrel also aims at the target — fire during the charge.
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				dir.angle(), BARREL_TURN_SPEED * delta)
			if _attack_timer <= 0.0:
				_fire_cannonball(ram_target.global_position)
				_attack_timer = attack_cooldown_time

## Rotate the barrel toward the best target and fire.
## The barrel's rotation is in world-space (parent CharacterBody2D never rotates)
## so it aims independently of the hull orientation — including straight backwards.
func _aim_barrel_and_fire(delta: float) -> void:
	var target := _get_best_target()
	if target and is_instance_valid(target):
		var dir := (target.global_position - global_position).normalized()
		barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
			dir.angle(), BARREL_TURN_SPEED * delta)
		if _attack_timer <= 0.0:
			_fire_cannonball(target.global_position)
			_attack_timer = attack_cooldown_time
	else:
		# No target — barrel idles with a slow continuous sweep
		barrel_sprite.rotation += delta * 0.5

# ─────────────────────────────────────────────────────────────────────────────
# BFS navigation
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_path_and_state() -> void:
	if not player or not is_instance_valid(player): return
	var nav_target := _nearest_target()
	if not nav_target: return
	var from := BuildManager.world_to_cell(global_position)
	var to   := BuildManager.world_to_cell(nav_target.global_position)
	if from == to:
		_path = []; _path_blocked = false; _state = State.RAM; return
	var result := _bfs(from, to)
	if result.is_empty():
		_path = []; _path_blocked = true; _state = State.HOLD_AND_FIRE
	else:
		_path = result; _path_blocked = false
		_state = State.ADVANCE if _any_structures_exist() else State.RAM

func _bfs(from: Vector2i, to: Vector2i) -> Array:
	var visited: Dictionary = {}
	var parent:  Dictionary = {}
	var queue: Array = [from]
	visited[from] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			var path: Array = []
			var c := cell
			while c != from:
				path.append(BuildManager.cell_to_world(c))
				c = parent[c]
			path.reverse()
			return path
		for nb in [Vector2i(cell.x+1,cell.y), Vector2i(cell.x-1,cell.y),
				   Vector2i(cell.x,cell.y+1), Vector2i(cell.x,cell.y-1)]:
			if nb.x < 0 or nb.x >= BuildManager.ARENA_COLS \
					or nb.y < 0 or nb.y >= BuildManager.ARENA_ROWS: continue
			if visited.has(nb): continue
			var passable := true
			if BuildManager.is_occupied(nb):
				var s: Node = BuildManager.occupied_cells[nb]
				if not (s.has_method("toggle") and s.is_open): passable = false
			if passable:
				visited[nb] = true; parent[nb] = cell; queue.append(nb)
	return []

# ─────────────────────────────────────────────────────────────────────────────
# Combat
# ─────────────────────────────────────────────────────────────────────────────

func _fire_cannonball(target_pos: Vector2) -> void:
	var cb: Node2D = _cannonball_scene.instantiate()
	cb.direction     = (target_pos - global_position).normalized()
	cb.global_position = global_position + cb.direction * 44.0
	cb.wall_damage   = 999   # direct hit = instant destruction
	cb.player_damage = 25
	cb.aoe_radius    = 200.0 # ~2.5 tiles blast radius
	cb.aoe_damage    = 45    # heavy but not instant for splash structures
	get_tree().current_scene.add_child(cb)

func take_damage(amount: int) -> void:
	if _is_dead: return
	health -= amount
	health_bar.value   = health
	health_bar.visible = true
	body_sprite.modulate   = Color(10, 10, 10, 1)
	barrel_sprite.modulate = Color(10, 10, 10, 1)
	create_tween().tween_property(body_sprite,   "modulate", Color.WHITE, 0.15)
	create_tween().tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)
	if health <= 0:
		_is_dead = true
		died_at.emit(global_position)
		_spawn_death_effect()
		queue_free()

func _on_hit_area_body_entered(body: Node2D) -> void:
	if player != null and body == player and _contact_timer <= 0.0:
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown_time

func _spawn_death_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true; particles.one_shot = true
	particles.amount = 30; particles.lifetime = 0.8
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0,0,0); mat.spread = 180.0
	mat.initial_velocity_min = 100.0; mat.initial_velocity_max = 260.0
	mat.gravity = Vector3.ZERO; mat.scale_min = 5.0; mat.scale_max = 14.0
	mat.color = Color(0.9, 0.5, 0.05, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)


