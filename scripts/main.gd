extends Node2D

const ARENA_WIDTH := 3200
const ARENA_HEIGHT := 2400

@export var enemy_scene: PackedScene
@export var spawn_interval := 2.0
@export var spawn_distance := 600.0
@export var max_enemies := 30

@onready var player := $Player
@onready var spawn_timer := $SpawnTimer
@onready var hud := $UILayer/HUD
@onready var camera := $Player/Camera2D

var score := 0
var wave := 1
var enemies_per_wave := 5
var enemies_spawned_this_wave := 0

func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.start()
	player.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(player.health, player.max_health)
	hud.update_wave(wave)

	# Connect joysticks
	var move_joy: Control = hud.get_node("MoveJoystick")
	var aim_joy: Control = hud.get_node("AimJoystick")
	move_joy.joystick_input.connect(player.set_move_joystick)
	move_joy.joystick_released.connect(_on_move_released)
	aim_joy.joystick_input.connect(player.set_aim_joystick)
	aim_joy.joystick_released.connect(_on_aim_released)

func _on_move_released() -> void:
	player.move_input = Vector2.ZERO

func _on_aim_released() -> void:
	player.aim_input = Vector2.ZERO

func _process(_delta: float) -> void:
	if player:
		hud.update_health(player.health, player.max_health)
		hud.update_score(score)

func _on_spawn_timer_timeout() -> void:
	if not player:
		return
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	if enemy_count >= max_enemies:
		return
	if enemies_spawned_this_wave >= enemies_per_wave:
		# Check if all dead
		if enemy_count == 0:
			wave += 1
			enemies_per_wave += 3
			spawn_interval = maxf(0.5, spawn_interval - 0.15)
			spawn_timer.wait_time = spawn_interval
			enemies_spawned_this_wave = 0
			hud.update_wave(wave)
		return

	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D

	# Spawn at random position around the player off-screen
	var angle: float = randf() * TAU
	var spawn_pos: Vector2 = player.global_position + Vector2.RIGHT.rotated(angle) * spawn_distance

	# Clamp to arena bounds
	spawn_pos.x = clampf(spawn_pos.x, 60.0, float(ARENA_WIDTH - 60))
	spawn_pos.y = clampf(spawn_pos.y, 60.0, float(ARENA_HEIGHT - 60))

	enemy.global_position = spawn_pos
	enemy.player = player
	enemy.add_to_group("enemies")
	enemy.tree_exiting.connect(_on_enemy_killed)

	# Scale difficulty with waves
	enemy.max_health = 60 + wave * 10
	enemy.health = enemy.max_health
	enemy.speed = 120.0 + wave * 8.0

	add_child(enemy)
	enemies_spawned_this_wave += 1

func _on_enemy_killed() -> void:
	score += 10

func _on_player_health_changed(current: int, maximum: int) -> void:
	hud.update_health(current, maximum)
