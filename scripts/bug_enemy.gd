extends CharacterBody2D

## Bug enemy — phases through walls, explodes near the player.
## Introduced in wave 3. Kills squad members in explosion radius.

@export var speed := 100.0
@export var max_health := 90
@export var explode_radius := 110.0
@export var explode_damage := 45
@export var explode_distance := 52.0

var health: int
var player: Node2D = null
var _is_dead := false
var _exploded := false

## BFS path-following
var _path: Array = []           # Array[Vector2] world-space waypoints
var _path_timer := 0.0
const PATH_REFRESH   := 0.5      # seconds between path recalculations
const WAYPOINT_REACH := 30.0     # px — how close before advancing to next waypoint

signal died_at(pos: Vector2)

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var health_bar: ProgressBar = $HealthBarPivot/HealthBar
@onready var health_bar_pivot: Node2D = $HealthBarPivot

func _ready() -> void:
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.visible = false
	_setup_animations()

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("move")
	frames.set_animation_speed("move", 7.0)
	frames.add_frame("move", load("res://assets/enemies/bug1.png"))
	frames.add_frame("move", load("res://assets/enemies/bug2.png"))
	body_sprite.sprite_frames = frames
	body_sprite.play("move")

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

	# Periodically recalculate BFS path around structures
	_path_timer -= delta
	if _path_timer <= 0.0:
		_recalculate_path()
		_path_timer = PATH_REFRESH

	var chase_target := _nearest_target()

	# Follow path waypoints, fall back to direct movement when path is empty
	var direction: Vector2
	if _path.is_empty():
		direction = (chase_target.global_position - global_position).normalized()
	else:
		# Advance waypoint when close enough
		if global_position.distance_to(_path[0]) < WAYPOINT_REACH:
			_path.remove_at(0)
		direction = (_path[0] if not _path.is_empty() else chase_target.global_position) \
				- global_position
		direction = direction.normalized()

	velocity = direction * speed
	DepenetrationHelper.resolve(self, delta)
	move_and_slide()
	body_sprite.rotation = direction.angle()
	health_bar_pivot.rotation = -rotation

	if global_position.distance_to(chase_target.global_position) <= explode_distance:
		_explode()

## Compute BFS path from current cell to nearest target's cell, navigating around structures.
func _recalculate_path() -> void:
	var from := BuildManager.world_to_cell(global_position)
	var target := _nearest_target()
	var to   := BuildManager.world_to_cell(target.global_position if target else global_position)
	_path = _bfs(from, to)

func _bfs(from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return []
	var visited: Dictionary = {}
	var parent:  Dictionary = {}
	var queue: Array = [from]
	visited[from] = true

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			# Reconstruct path back to start, then reverse
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
			# Passable: empty cell, OR open door (bugs look for door gaps)
			var passable := true
			if BuildManager.is_occupied(nb):
				var structure: Node = BuildManager.occupied_cells[nb]
				# Only open doors are passable; walls, towers, and closed doors block
				if not (structure.has_method("toggle") and structure.is_open):
					passable = false
			if passable:
				visited[nb] = true
				parent[nb] = cell
				queue.append(nb)

	return []  # No path — caller falls back to direct movement

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	health -= amount
	health_bar.value = health
	health_bar.visible = true
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.12)
	if health <= 0:
		_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_is_dead = true
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	# Damage all players in explosion radius
	for t in tree.get_nodes_in_group("target_players"):
		if is_instance_valid(t) and global_position.distance_to(t.global_position) <= explode_radius:
			t.take_damage(explode_damage)
	# Instantly remove all squad members in radius
	for member in tree.get_nodes_in_group("squad_members"):
		if is_instance_valid(member) and global_position.distance_to(member.global_position) <= explode_radius:
			member.queue_free()
	_spawn_explosion_effect()
	SoundManager.play_sfx_2d("bug_death", global_position)
	died_at.emit(global_position)
	queue_free()

func _spawn_explosion_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 28
	particles.lifetime = 0.55
	particles.global_position = global_position
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 240.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 5.0
	mat.scale_max = 12.0
	mat.color = Color(1.0, 0.55, 0.0, 1.0)
	particles.process_material = mat
	particles.finished.connect(particles.queue_free)
	var scene_root := get_tree().current_scene if get_tree() else null
	if scene_root == null:
		return
	scene_root.add_child(particles)
