extends Node2D

const ARENA_WIDTH := 3200
const ARENA_HEIGHT := 2400
const STORY_DURATION  := 3.0
const BUILD_DURATION  := 60.0

@export var enemy_scene: PackedScene
@export var spawn_interval := 2.0
@export var spawn_distance := 600.0
@export var max_enemies := 30

@onready var player := $Player
@onready var spawn_timer := $SpawnTimer
@onready var hud := $UILayer/HUD

var coin_scene:        PackedScene = preload("res://scenes/coin.tscn")
var buy_station_scene: PackedScene = preload("res://scenes/buy_station.tscn")
var wall_scene:        PackedScene = preload("res://scenes/wall.tscn")
var door_scene:        PackedScene = preload("res://scenes/door.tscn")
var tower_scene:       PackedScene = preload("res://scenes/defense_tower.tscn")
var airstrike_scene:   PackedScene = preload("res://scenes/airstrike.tscn")
var squad_scene:       PackedScene = preload("res://scenes/squad_member.tscn")

var score := 0
var coins := 0
var wave := 1
var enemies_spawned_this_wave := 0
var _enemies_killed_this_wave := 0
var _wave_active := false
var _between_wave_timer: Timer
var _build_timer: Timer
var _build_cursor: Polygon2D

func _ready() -> void:
	_between_wave_timer = Timer.new()
	_between_wave_timer.one_shot = true
	_between_wave_timer.timeout.connect(_on_between_wave_timeout)
	add_child(_between_wave_timer)

	_build_timer = Timer.new()
	_build_timer.one_shot = true
	_build_timer.timeout.connect(_on_build_timer_timeout)
	add_child(_build_timer)

	_build_cursor = Polygon2D.new()
	_build_cursor.polygon = PackedVector2Array([
		Vector2(-39, -39), Vector2(39, -39), Vector2(39, 39), Vector2(-39, 39)])
	_build_cursor.color = Color(0.3, 1.0, 0.3, 0.45)
	_build_cursor.visible = false
	_build_cursor.z_index = 10
	add_child(_build_cursor)

	spawn_timer.wait_time = spawn_interval
	player.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(player.health, player.max_health)

	var move_joy: Control = hud.get_node("MoveJoystick")
	var aim_joy: Control = hud.get_node("AimJoystick")
	move_joy.joystick_input.connect(player.set_move_joystick)
	move_joy.joystick_released.connect(_on_move_released)
	aim_joy.joystick_input.connect(player.set_aim_joystick)
	aim_joy.joystick_released.connect(_on_aim_released)

	hud.update_coins(coins)
	_place_buy_stations()
	player.weapon_changed.connect(hud.update_weapon)
	hud.update_weapon(WeaponManager.get_current()["name"])
	hud.build_ready_pressed.connect(_on_build_ready_pressed)
	hud.build_item_selected.connect(_on_build_item_selected)
	hud.door_toggle_pressed.connect(_on_door_toggle_pressed)
	hud.airstrike_pressed.connect(_on_airstrike_pressed)
	hud.squad_pressed.connect(_on_squad_pressed)
	hud.shield_squad_pressed.connect(_on_shield_squad_pressed)
	SupportManager.cooldowns_updated.connect(_on_support_cooldowns_updated)
	_begin_wave(wave)

func _place_buy_stations() -> void:
	var station_data := [
		{"weapon_id": "shotgun", "pos": Vector2(400,  300)},
		{"weapon_id": "rifle",   "pos": Vector2(2800, 300)},
		{"weapon_id": "lmg",    "pos": Vector2(1600, 2100)},
	]
	for entry in station_data:
		var station := buy_station_scene.instantiate()
		station.weapon_id = entry["weapon_id"]
		station.global_position = entry["pos"]
		var w: Dictionary = WeaponManager.WEAPONS[entry["weapon_id"]]
		# Update the visual labels to match the exported weapon_id
		station.get_node("NameLabel").text = w["name"].to_upper()
		station.get_node("CostLabel").text = str(w["cost"]) + " coins"
		station.player_entered.connect(_on_buy_station_entered)
		station.player_exited.connect(_on_buy_station_exited)
		station.buy_requested.connect(_on_buy_requested)
		add_child(station)

func _on_buy_station_entered(station: Node) -> void:
	var w: Dictionary = WeaponManager.WEAPONS[station.weapon_id]
	hud.show_buy_prompt(w["name"], w["cost"])

func _on_buy_station_exited() -> void:
	hud.hide_buy_prompt()

func _on_buy_requested(weapon_id: String, cost: int) -> void:
	if WeaponManager.current_weapon == weapon_id:
		return  # already equipped
	if coins < cost:
		hud.flash_buy_denied()
		return
	coins -= cost
	hud.update_coins(coins)
	player.equip_weapon(weapon_id)
	hud.hide_buy_prompt()

func _begin_wave(wave_number: int) -> void:
	enemies_spawned_this_wave = 0
	_enemies_killed_this_wave = 0
	_wave_active = true
	spawn_timer.start()
	hud.update_wave(wave_number)

func _on_move_released() -> void:
	player.move_input = Vector2.ZERO

func _on_aim_released() -> void:
	player.aim_input = Vector2.ZERO

func _process(_delta: float) -> void:
	if player:
		hud.update_health(player.health, player.max_health)
		hud.update_score(score)
	if not _wave_active and not _between_wave_timer.is_stopped():
		hud.update_countdown(int(ceil(_between_wave_timer.time_left)))
	if BuildManager.build_mode:
		if not _build_timer.is_stopped():
			hud.update_build_timer(int(ceil(_build_timer.time_left)))
		_update_build_cursor()

func _update_build_cursor() -> void:
	var world_pos := get_global_mouse_position()
	var cell := BuildManager.world_to_cell(world_pos)
	_build_cursor.global_position = BuildManager.cell_to_world(cell)
	if BuildManager.selected == "erase":
		_build_cursor.color = Color(1.0, 0.2, 0.2, 0.5) if BuildManager.is_occupied(cell) \
							  else Color(0.5, 0.5, 0.5, 0.2)
	else:
		_build_cursor.color = Color(0.3, 1.0, 0.3, 0.45) if not BuildManager.is_occupied(cell) \
							  else Color(1.0, 0.2, 0.2, 0.45)

func _unhandled_input(event: InputEvent) -> void:
	if not BuildManager.build_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		var world_pos := get_global_mouse_position()
		var cell := BuildManager.world_to_cell(world_pos)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_at(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_erase_at(cell)

func _try_place_at(cell: Vector2i) -> void:
	if BuildManager.selected == "erase":
		_try_erase_at(cell)
		return
	# Allow replacing a wall with a door
	if BuildManager.is_occupied(cell):
		if BuildManager.selected == "door":
			var existing: Node = BuildManager.occupied_cells[cell]
			if existing.get_meta("structure_type", "") == "wall":
				# Swap wall → door (costs the door cost, no refund for wall)
				var cost: int = BuildManager.COSTS["door"]
				if coins < cost:
					hud.flash_build_denied()
					return
				coins -= cost
				hud.update_coins(coins)
				existing.queue_free()
				BuildManager.unregister(cell)
				var door := _create_structure("door", cell)
				add_child(door)
				BuildManager.register(cell, door)
		return
	var cost: int = BuildManager.COSTS[BuildManager.selected]
	if coins < cost:
		hud.flash_build_denied()
		return
	coins -= cost
	hud.update_coins(coins)
	var structure := _create_structure(BuildManager.selected, cell)
	add_child(structure)
	BuildManager.register(cell, structure)

func _try_erase_at(cell: Vector2i) -> void:
	if not BuildManager.is_occupied(cell):
		return
	var node: Node = BuildManager.occupied_cells[cell]
	if node and is_instance_valid(node):
		node.queue_free()
	coins += BuildManager.ERASE_REFUND
	hud.update_coins(coins)
	BuildManager.unregister(cell)

func _create_structure(type: String, cell: Vector2i) -> Node:
	var pos := BuildManager.cell_to_world(cell)
	var node: Node
	match type:
		"wall":  node = wall_scene.instantiate()
		"door":  node = door_scene.instantiate()
		"tower": node = tower_scene.instantiate()
	node.cell = cell
	node.global_position = pos
	node.set_meta("structure_type", type)
	node.destroyed.connect(func(c: Vector2i): BuildManager.unregister(c))
	return node

func _on_spawn_timer_timeout() -> void:
	if not _wave_active or not player:
		return
	var config := WaveManager.get_wave_config(wave)
	if enemies_spawned_this_wave >= config["enemy_count"]:
		return
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	if enemy_count >= max_enemies:
		return

	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	# Find a spawn position that is not inside or on top of structures
	var spawn_pos := Vector2.ZERO
	var valid := false
	for _attempt in 8:
		var angle: float = randf() * TAU
		var candidate: Vector2 = player.global_position + Vector2.RIGHT.rotated(angle) * spawn_distance
		candidate.x = clampf(candidate.x, 60.0, float(ARENA_WIDTH - 60))
		candidate.y = clampf(candidate.y, 60.0, float(ARENA_HEIGHT - 60))
		var cell := BuildManager.world_to_cell(candidate)
		if not BuildManager.is_occupied(cell) and not BuildManager.interior_cells.has(cell):
			spawn_pos = candidate
			valid = true
			break
	if not valid:
		return

	enemy.global_position = spawn_pos
	enemy.player = player
	enemy.add_to_group("enemies")
	enemy.died_at.connect(_on_enemy_died_at)
	enemy.max_health = 60 + int(config["health_bonus"])
	enemy.speed = 120.0 + float(config["speed_bonus"])

	add_child(enemy)
	enemies_spawned_this_wave += 1

func _on_enemy_died_at(pos: Vector2) -> void:
	score += 10
	_enemies_killed_this_wave += 1
	_spawn_coin(pos)
	_check_wave_complete()

func _spawn_coin(pos: Vector2) -> void:
	var coin := coin_scene.instantiate()
	coin.global_position = pos
	coin.collected.connect(_on_coin_collected)
	add_child(coin)

func _on_coin_collected(amount: int) -> void:
	coins += amount
	hud.update_coins(coins)

func _check_wave_complete() -> void:
	if not _wave_active:
		return
	var config := WaveManager.get_wave_config(wave)
	if _enemies_killed_this_wave >= config["enemy_count"]:
		_start_between_wave()

func _start_between_wave() -> void:
	_wave_active = false
	spawn_timer.stop()
	var config := WaveManager.get_wave_config(wave)
	hud.show_wave_transition(config)
	_between_wave_timer.start(STORY_DURATION)

func _on_between_wave_timeout() -> void:
	hud.hide_wave_transition()
	hud.show_build_mode()
	BuildManager.start_build_mode()
	_build_cursor.visible = true
	_build_timer.start(BUILD_DURATION)

func _on_build_timer_timeout() -> void:
	_end_build_phase()

func _end_build_phase() -> void:
	if not BuildManager.build_mode:
		return
	BuildManager.end_build_mode()
	_build_cursor.visible = false
	hud.hide_build_mode()
	_build_timer.stop()
	wave += 1
	spawn_interval = maxf(0.5, spawn_interval - 0.15)
	spawn_timer.wait_time = spawn_interval
	_begin_wave(wave)

func _on_build_ready_pressed() -> void:
	_end_build_phase()

func _on_build_item_selected(item: String) -> void:
	BuildManager.selected = item

func _on_door_toggle_pressed() -> void:
	for door in get_tree().get_nodes_in_group("doors"):
		door.toggle()

func _on_player_health_changed(current: int, maximum: int) -> void:
	hud.update_health(current, maximum)

# ─── Support callables ────────────────────────────────────────────────────────

func _on_airstrike_pressed() -> void:
	if not SupportManager.can_airstrike(coins):
		return
	coins -= SupportManager.AIRSTRIKE_COST
	hud.update_coins(coins)
	SupportManager.use_airstrike()
	var strike := airstrike_scene.instantiate()
	strike.global_position = player.global_position
	add_child(strike)

# Spawns 3 regular soldiers around the player
func _on_squad_pressed() -> void:
	if not SupportManager.can_squad(coins):
		return
	coins -= SupportManager.SQUAD_COST
	hud.update_coins(coins)
	SupportManager.use_squad()
	_spawn_squad(3, false)

# Spawns 2 shielded soldiers around the player
func _on_shield_squad_pressed() -> void:
	if not SupportManager.can_shield_squad(coins):
		return
	coins -= SupportManager.SHIELD_SQUAD_COST
	hud.update_coins(coins)
	SupportManager.use_shield_squad()
	_spawn_squad(2, true)

func _spawn_squad(count: int, shielded: bool) -> void:
	for i in count:
		var angle := TAU * i / count
		var offset := Vector2.RIGHT.rotated(angle) * 70.0
		var member := squad_scene.instantiate()
		member.global_position = player.global_position + offset
		member.player = player
		member.shielded = shielded
		add_child(member)

func _on_support_cooldowns_updated() -> void:
	hud.update_support_cooldowns(
		SupportManager.airstrike_cd,
		SupportManager.AIRSTRIKE_COOLDOWN,
		SupportManager.squad_cd,
		SupportManager.SQUAD_COOLDOWN,
		SupportManager.shield_squad_cd,
		SupportManager.SHIELD_SQUAD_COOLDOWN
	)
