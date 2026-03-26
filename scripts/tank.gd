extends CharacterBody2D

## Tank — one per wave from wave 7 onward.
## Body hull NEVER rotates. Only the barrel sweeps to aim at targets.
##
## Three states (re-evaluated every PATH_REFRESH seconds via BFS):
##   HOLD_AND_FIRE — path to player is completely blocked by structures.
##                   Stands still, barrel tracks nearest target, fires every 3 s.
##   ADVANCE       — a navigable path exists but structures still present.
##                   Follows BFS path toward player while barrel keeps firing.
##   RAM           — no structures block the route; tank charges at full speed.

@export var max_health           := 3600
@export var attack_range         := 400.0
@export var attack_cooldown_time := 3.0
@export var contact_damage       := 60
@export var contact_cooldown_time := 1.5
@export var move_speed           := 55.0    # speed while navigating
@export var ram_speed            := 130.0   # speed while charging the player

var health: int
var player: Node2D = null
var _is_dead := false

var _attack_timer  := 0.0
var _contact_timer := 0.0

## BFS navigation
var _path: Array        = []
var _path_blocked       := false   # true when BFS found NO route at all
var _path_timer         := 0.0
const PATH_REFRESH      := 3.0     # seconds between BFS recalculations
const WAYPOINT_REACH    := 30.0    # px — when to advance to next waypoint

enum State { HOLD_AND_FIRE, ADVANCE, RAM }
var _state := State.HOLD_AND_FIRE

signal died_at(pos: Vector2)

const BARREL_TURN_SPEED := 6.0

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
	# Run first BFS immediately so the tank picks its starting state.
	call_deferred("_refresh_path_and_state")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

## Nearest structure of 'type' within range_px (pass INF to ignore range).
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

## Returns true if any attackable structure (tower or wall) exists anywhere.
func _any_structures_exist() -> bool:
	for cell in BuildManager.occupied_cells:
		var occ = BuildManager.occupied_cells[cell]
		if not is_instance_valid(occ): continue
		if not occ.has_meta("structure_type"): continue
		var t: String = occ.get_meta("structure_type")
		if (t == "tower" or t == "wall") and occ.has_method("take_damage"):
			return true
	return false

## Highest-priority target inside attack_range: tower > wall > player.
func _get_best_target() -> Node2D:
	var tower := _find_nearest_in_range("tower", attack_range)
	if tower: return tower
	var wall := _find_nearest_in_range("wall", attack_range)
	if wall: return wall
	if player and is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= attack_range:
			return player
	return null

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _is_dead or not player or not is_instance_valid(player):
		return

	_attack_timer  = maxf(0.0, _attack_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	health_bar_pivot.rotation = -rotation  # health bar always faces up

	# Periodic BFS recalculation & state decision
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_REFRESH
		_refresh_path_and_state()

	match _state:
		State.HOLD_AND_FIRE:
			velocity = Vector2.ZERO
			move_and_slide()
			_aim_and_fire(delta)

		State.ADVANCE:
			# Move along BFS path while barrel keeps firing
			var dest: Vector2
			if _path.is_empty():
				dest = player.global_position
			else:
				if global_position.distance_to(_path[0]) < WAYPOINT_REACH:
					_path.remove_at(0)
				dest = _path[0] if not _path.is_empty() else player.global_position
			velocity = (dest - global_position).normalized() * move_speed
			move_and_slide()
			_aim_and_fire(delta)

		State.RAM:
			# Charge straight at the player — barrel faces the charge direction
			var dir := (player.global_position - global_position).normalized()
			velocity = dir * ram_speed
			move_and_slide()
			barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
				dir.angle(), BARREL_TURN_SPEED * delta)

## Rotate barrel toward best target and fire; called every frame in HOLD and ADVANCE.
## Body sprite is intentionally never rotated.
func _aim_and_fire(delta: float) -> void:
	var target := _get_best_target()
	if target and is_instance_valid(target):
		var dir := (target.global_position - global_position).normalized()
		barrel_sprite.rotation = lerp_angle(barrel_sprite.rotation,
			dir.angle(), BARREL_TURN_SPEED * delta)
		if _attack_timer <= 0.0:
			_fire_cannonball(target.global_position)
			_attack_timer = attack_cooldown_time
	else:
		# Idle slow sweep so barrel movement stays visible
		barrel_sprite.rotation += delta * 0.6

# ─────────────────────────────────────────────────────────────────────────────
# BFS navigation (same algorithm as bug_enemy.gd)
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_path_and_state() -> void:
	if not player or not is_instance_valid(player):
		return
	var from := BuildManager.world_to_cell(global_position)
	var to   := BuildManager.world_to_cell(player.global_position)

	if from == to:
		# Already on the player's cell — ram
		_path         = []
		_path_blocked = false
		_state        = State.RAM
		return

	var result := _bfs(from, to)

	if result.is_empty():
		# No navigable path — all routes blocked by structures
		_path         = []
		_path_blocked = true
		_state        = State.HOLD_AND_FIRE
	else:
		_path         = result
		_path_blocked = false
		if _any_structures_exist():
			# Path exists but defences still present — advance while shooting
			_state = State.ADVANCE
		else:
			# Open field, nothing in the way — charge
			_state = State.RAM

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

		for nb in [Vector2i(cell.x + 1, cell.y), Vector2i(cell.x - 1, cell.y),
				   Vector2i(cell.x, cell.y + 1), Vector2i(cell.x, cell.y - 1)]:
			if nb.x < 0 or nb.x >= BuildManager.ARENA_COLS \
					or nb.y < 0 or nb.y >= BuildManager.ARENA_ROWS:
				continue
			if visited.has(nb):
				continue
			var passable := true
			if BuildManager.is_occupied(nb):
				var structure: Node = BuildManager.occupied_cells[nb]
				# Open doors are passable; walls, towers, closed doors block
				if not (structure.has_method("toggle") and structure.is_open):
					passable = false
			if passable:
				visited[nb] = true
				parent[nb] = cell
				queue.append(nb)

	return []  # no path found

# ─────────────────────────────────────────────────────────────────────────────
# Combat
# ─────────────────────────────────────────────────────────────────────────────

func _fire_cannonball(target_pos: Vector2) -> void:
	var cb: Node2D = _cannonball_scene.instantiate()
	cb.direction = (target_pos - global_position).normalized()
	cb.global_position = global_position + cb.direction * 44.0
	cb.wall_damage    = 999   # one-shots any structure
	cb.player_damage  = 25    # quarter of player HP per hit
	get_tree().current_scene.add_child(cb)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	health_bar.value   = health
	health_bar.visible = true
	body_sprite.modulate   = Color(10, 10, 10, 1)
	barrel_sprite.modulate = Color(10, 10, 10, 1)
	var tw  := create_tween()
	tw.tween_property(body_sprite,   "modulate", Color.WHITE, 0.15)
	var tw2 := create_tween()
	tw2.tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)
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
	particles.emitting  = true
	particles.one_shot  = true
	particles.amount    = 30
	particles.lifetime  = 0.8
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction            = Vector3(0, 0, 0)
	mat.spread               = 180.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 260.0
	mat.gravity              = Vector3.ZERO
	mat.scale_min            = 5.0
	mat.scale_max            = 14.0
	mat.color                = Color(0.9, 0.5, 0.05, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	get_tree().current_scene.add_child(particles)

