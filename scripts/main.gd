extends Node2D

const ARENA_WIDTH := 3200
const ARENA_HEIGHT := 2400
const STORY_DURATION  := 3.0
const BUILD_DURATION  := 30.0

@export var enemy_scene: PackedScene
@export var spawn_interval := 2.0
@export var spawn_distance := 600.0
@export var max_enemies := 30

@onready var player := $Player
@onready var spawn_timer := $SpawnTimer
@onready var hud := $UILayer/HUD

var coin_scene:           PackedScene = preload("res://scenes/coin.tscn")
var buy_station_scene:    PackedScene = preload("res://scenes/buy_station.tscn")
var wall_scene:           PackedScene = preload("res://scenes/wall.tscn")
var door_scene:           PackedScene = preload("res://scenes/door.tscn")
var tower_scene:          PackedScene = preload("res://scenes/defense_tower.tscn")
var airstrike_scene:      PackedScene = preload("res://scenes/airstrike.tscn")
var squad_scene:          PackedScene = preload("res://scenes/squad_member.tscn")
var bug_scene:            PackedScene = preload("res://scenes/bug_enemy.tscn")
var cannon_soldier_scene: PackedScene = preload("res://scenes/cannon_soldier.tscn")
var tank_scene:           PackedScene = preload("res://scenes/tank.tscn")

var score := 0
var coins := 0
var wave := 1
var enemies_spawned_this_wave := 0
var _enemies_killed_this_wave := 0
var _wave_active := false
var _tank_spawned_this_wave := false
var _global_doors_open := false  # tracks the current door toggle state
var _between_wave_timer: Timer
var _build_timer: Timer
var _build_cursor: Polygon2D
var _build_cursor_cell: Vector2i
var _current_template_size: String = "small"
var _template_preview: Node2D
var _template_preview_cells: Array = []
var _current_buy_station: Node = null
var _picker_cell: Vector2i
var _touch_joy := {}        # finger_index → {"side": "move"|"aim", "origin": Vector2}
var _mouse_joy_side := ""
var _mouse_joy_origin := Vector2.ZERO
var _move_joy: Control
var _aim_joy: Control

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

	# Build template preview pool (32 cells = max for large 9x9 template)
	_template_preview = Node2D.new()
	_template_preview.z_index = 10
	_template_preview.visible = false
	add_child(_template_preview)
	for _i in 32:
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-39, -39), Vector2(39, -39), Vector2(39, 39), Vector2(-39, 39)])
		p.color = Color(0.3, 1.0, 0.3, 0.45)
		p.visible = false
		_template_preview.add_child(p)
		_template_preview_cells.append(p)

	spawn_timer.wait_time = spawn_interval
	player.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(player.health, player.max_health)

	_move_joy = hud.get_node("MoveJoystick")
	_aim_joy = hud.get_node("AimJoystick")
	_move_joy.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_aim_joy.layout_direction = Control.LAYOUT_DIRECTION_LTR

	hud.update_coins(coins)
	_place_buy_stations()
	hud.buy_pressed.connect(_on_hud_buy_pressed)
	hud.weapon_shop_buy.connect(_on_weapon_shop_buy)
	player.weapon_changed.connect(hud.update_weapon)
	hud.update_weapon(WeaponManager.get_current()["name"])
	hud.build_ready_pressed.connect(_on_build_ready_pressed)
	hud.build_place_pressed.connect(_on_build_place_pressed)
	hud.build_item_selected.connect(_on_build_item_selected)
	hud.build_picker_selected.connect(_on_build_picker_selected)
	hud.door_toggle_pressed.connect(_on_door_toggle_pressed)
	hud.template_size_selected.connect(_on_template_size_selected)
	hud.repair_all_pressed.connect(_on_repair_all_pressed)
	hud.airstrike_pressed.connect(_on_airstrike_pressed)
	hud.squad_pressed.connect(_on_squad_pressed)
	hud.shield_squad_pressed.connect(_on_shield_squad_pressed)
	SupportManager.cooldowns_updated.connect(_on_support_cooldowns_updated)
	_begin_wave(wave)

func _place_buy_stations() -> void:
	var station := buy_station_scene.instantiate()
	station.weapon_id = "shop"
	# Snap to exact cell center so the shop occupies exactly one tile
	var shop_cell := Vector2i(20, 13)
	station.global_position = BuildManager.cell_to_world(shop_cell)
	station.get_node("NameLabel").text = "WEAPON SHOP"
	station.get_node("CostLabel").text = "WALK IN"
	station.player_entered.connect(_on_buy_station_entered)
	station.player_exited.connect(_on_buy_station_exited)
	add_child(station)
	# Reserve the shop cell so nothing can be built on it
	BuildManager.reserve_cell(shop_cell)

func _on_buy_station_entered(station: Node) -> void:
	_current_buy_station = station
	hud.show_weapon_shop(coins, WeaponManager.current_weapon)

func _on_buy_station_exited() -> void:
	_current_buy_station = null
	hud.hide_weapon_shop()

func _on_hud_buy_pressed() -> void:
	pass  # legacy — kept for signal compat

func _on_weapon_shop_buy(weapon_id: String) -> void:
	var w: Dictionary = WeaponManager.WEAPONS[weapon_id]
	if WeaponManager.current_weapon == weapon_id:
		return
	if w["cost"] > 0 and coins < w["cost"]:
		return
	coins -= w["cost"]
	hud.update_coins(coins)
	player.equip_weapon(weapon_id)
	hud.show_weapon_shop(coins, WeaponManager.current_weapon)

func _on_buy_requested(weapon_id: String, cost: int) -> void:
	_on_weapon_shop_buy(weapon_id)

func _begin_wave(wave_number: int) -> void:
	enemies_spawned_this_wave = 0
	_enemies_killed_this_wave = 0
	_wave_active = true
	_tank_spawned_this_wave = false
	spawn_timer.start()
	hud.update_wave(wave_number)

# ─── Touch joystick ──────────────────────────────────────────────────────────

const JOY_DEADZONE := 10.0

func _get_joy_side(pos: Vector2) -> String:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if pos.y < vp.y * 0.55:
		return ""
	if pos.x < vp.x * 0.45:
		return "move"
	elif pos.x > vp.x * 0.55:
		return "aim"
	return ""

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only manually forward button presses for secondary fingers (index > 0).
			# Primary touch (index 0) already fires Buttons via Godot's mouse emulation;
			# doing it again for index 0 would toggle a door twice per tap.
			if event.index > 0:
				if _try_press_button_at(event.position):
					get_viewport().set_input_as_handled()
					return
			var side := _get_joy_side(event.position)
			if side != "":
				_touch_joy[event.index] = {"side": side, "origin": event.position}
				get_viewport().set_input_as_handled()
		else:
			_release_finger(event.index)
	elif event is InputEventScreenDrag:
		if _touch_joy.has(event.index):
			var info: Dictionary = _touch_joy[event.index]
			_apply_joy(info["side"], event.position, info["origin"])
			get_viewport().set_input_as_handled()

# Returns true and fires the button if a visible enabled Button contains screen_pos.
func _try_press_button_at(screen_pos: Vector2) -> bool:
	return _find_and_press_button(hud, screen_pos)

func _find_and_press_button(node: Node, pos: Vector2) -> bool:
	if node is Button:
		var btn := node as Button
		if btn.visible and not btn.disabled and btn.get_global_rect().has_point(pos):
			btn.pressed.emit()
			return true
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if _find_and_press_button(child, pos):
			return true
	return false

func _release_finger(finger: int) -> void:
	if not _touch_joy.has(finger):
		return
	var side: String = _touch_joy[finger]["side"]
	_touch_joy.erase(finger)
	if side == "move":
		player.move_input = Vector2.ZERO
		_move_joy.reset_knob()
	else:
		player.aim_input = Vector2.ZERO
		_aim_joy.reset_knob()

func _apply_joy(side: String, pos: Vector2, origin: Vector2) -> void:
	var joy: Control = _move_joy if side == "move" else _aim_joy
	var direction := pos - origin
	var dist := direction.length()
	var normalized := Vector2.ZERO
	if dist > JOY_DEADZONE:
		normalized = direction / joy.joystick_radius
		if normalized.length() > 1.0:
			normalized = normalized.normalized()
	joy.update_knob(normalized)
	if side == "move":
		player.move_input = normalized
	else:
		player.aim_input = normalized

func _process(_delta: float) -> void:
	# ── Mouse-based fallback (single touch via emulate_mouse_from_touch) ──
	if _touch_joy.is_empty():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mp := get_viewport().get_mouse_position()
			if _mouse_joy_side == "":
				_mouse_joy_side = _get_joy_side(mp)
				_mouse_joy_origin = mp
			if _mouse_joy_side != "":
				_apply_joy(_mouse_joy_side, mp, _mouse_joy_origin)
		elif _mouse_joy_side != "":
			if _mouse_joy_side == "move":
				player.move_input = Vector2.ZERO
				_move_joy.reset_knob()
			else:
				player.aim_input = Vector2.ZERO
				_aim_joy.reset_knob()
			_mouse_joy_side = ""

	# ── Game HUD updates ──
	if player:
		hud.update_health(player.health, player.max_health)
		hud.update_score(score)
	if not _wave_active and not _between_wave_timer.is_stopped():
		hud.update_countdown(_between_wave_timer.time_left)
	if BuildManager.build_mode:
		if not _build_timer.is_stopped():
			hud.update_build_timer(_build_timer.time_left)
		if BuildManager.selected == "template":
			_update_template_preview()
			_build_cursor.visible = false
		else:
			_build_cursor.visible = true
			_update_build_cursor()

func _update_build_cursor() -> void:
	var world_pos: Vector2 = player.global_position + player.aim_direction * float(BuildManager.TILE) * 1.5
	var cell := BuildManager.world_to_cell(world_pos)
	_build_cursor_cell = cell
	_build_cursor.global_position = BuildManager.cell_to_world(cell)
	var blocked := BuildManager.is_occupied(cell) or BuildManager.is_reserved(cell)
	if BuildManager.selected == "erase":
		_build_cursor.color = Color(1.0, 0.2, 0.2, 0.5) if BuildManager.is_occupied(cell) \
							  else Color(0.5, 0.5, 0.5, 0.2)
	else:
		_build_cursor.color = Color(0.3, 1.0, 0.3, 0.45) if not blocked \
							  else Color(1.0, 0.2, 0.2, 0.45)

func _update_template_preview() -> void:
	var size_map := {"small": 5, "medium": 7, "large": 9}
	var sz: int = size_map[_current_template_size]
	var center := BuildManager.world_to_cell(player.global_position)
	var cells := BuildManager.get_template_cells(center, sz)
	_template_preview.visible = true
	for i in _template_preview_cells.size():
		var poly: Polygon2D = _template_preview_cells[i]
		if i < cells.size():
			var entry: Dictionary = cells[i]
			poly.global_position = BuildManager.cell_to_world(entry.cell)
			var cell_blocked := BuildManager.is_occupied(entry.cell) or BuildManager.is_reserved(entry.cell)
			poly.color = Color(1.0, 0.2, 0.2, 0.45) if cell_blocked \
													else Color(0.3, 1.0, 0.3, 0.45)
			poly.visible = true
		else:
			poly.visible = false
	hud.update_template_cost(BuildManager.calculate_template_cost(cells))

func _hide_template_preview() -> void:
	_template_preview.visible = false
	for p in _template_preview_cells:
		p.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not BuildManager.build_mode:
		return
	if event is InputEventScreenTouch and event.pressed:
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		_picker_cell = BuildManager.world_to_cell(world_pos)
		hud.show_build_picker(event.position)

func _try_place_at(cell: Vector2i) -> void:
	# Block placement on reserved cells (e.g. the weapon shop)
	if BuildManager.is_reserved(cell):
		hud.flash_build_denied()
		return
	# Block placement on the player's current cell
	var player_cell := BuildManager.world_to_cell(player.global_position)
	if cell == player_cell:
		hud.flash_build_denied()
		return
	# Block placement on any squad member's cell
	for member in get_tree().get_nodes_in_group("squad_members"):
		if is_instance_valid(member) and BuildManager.world_to_cell(member.global_position) == cell:
			hud.flash_build_denied()
			return

	if BuildManager.selected == "erase":
		_try_erase_at(cell)
		return

	if BuildManager.is_occupied(cell):
		var existing: Node = BuildManager.occupied_cells[cell]
		var existing_type: String = existing.get_meta("structure_type", "")
		if existing_type == BuildManager.selected:
			# Same type — offer repair if it's a wall
			if existing_type == "wall" and existing.hp < existing.MAX_HP:
				var repair_cost: int = maxi(1, int(BuildManager.COSTS["wall"] * 0.20))
				if coins < repair_cost:
					hud.flash_build_denied()
					return
				coins -= repair_cost
				hud.update_coins(coins)
				existing.repair()
			return
		# Different type — replace at minimum cost (new cost minus erase refund)
		var replace_cost: int = maxi(0, BuildManager.COSTS[BuildManager.selected] - BuildManager.ERASE_REFUND)
		if coins < replace_cost:
			hud.flash_build_denied()
			return
		coins -= replace_cost
		hud.update_coins(coins)
		existing.queue_free()
		BuildManager.unregister(cell)
		var replacement := _create_structure(BuildManager.selected, cell)
		add_child(replacement)
		BuildManager.register(cell, replacement)
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
		"door":
			node = door_scene.instantiate()
		"tower": node = tower_scene.instantiate()
	node.cell = cell
	node.global_position = pos
	node.set_meta("structure_type", type)
	node.destroyed.connect(func(c: Vector2i): BuildManager.unregister(c))
	# Sync new door to the current global door state so all doors stay aligned
	if type == "door" and _global_doors_open:
		node.toggle()
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

	var is_tank := wave >= 7 and not _tank_spawned_this_wave
	var is_cannon := not is_tank and wave >= 5 and randf() < 0.15
	var is_bug := not is_tank and not is_cannon and wave >= 3 and randf() < 0.40
	var enemy: CharacterBody2D
	if is_tank:
		enemy = tank_scene.instantiate() as CharacterBody2D
		_tank_spawned_this_wave = true
	elif is_cannon:
		enemy = cannon_soldier_scene.instantiate() as CharacterBody2D
	elif is_bug:
		enemy = bug_scene.instantiate() as CharacterBody2D
	else:
		enemy = enemy_scene.instantiate() as CharacterBody2D

	# Find a spawn position that is not on/inside structures
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
	if is_tank:
		enemy.max_health = (120 + int(config["health_bonus"])) * 10  # 10x cannon soldier
		enemy.speed = 40.0  # tank stays slow regardless of wave bonus
	elif is_cannon:
		enemy.max_health = 120 + int(config["health_bonus"])
		enemy.speed = 75.0 + float(config["speed_bonus"])
	elif is_bug:
		enemy.max_health = 90 + int(config["health_bonus"])
		enemy.speed = 100.0 + float(config["speed_bonus"])
	else:
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
	hud.show_wave_transition(config, STORY_DURATION)
	_between_wave_timer.start(STORY_DURATION)

func _on_between_wave_timeout() -> void:
	hud.hide_wave_transition()
	hud.show_build_mode(BUILD_DURATION + float(wave) * 5.0)
	BuildManager.start_build_mode()
	_build_cursor.visible = true
	# More time per wave: base 30 s + 5 s for each completed wave
	var scaled_build := BUILD_DURATION + float(wave) * 5.0
	_build_timer.start(scaled_build)
	_refresh_repair_button()

func _on_build_timer_timeout() -> void:
	_end_build_phase()

func _end_build_phase() -> void:
	if not BuildManager.build_mode:
		return
	BuildManager.end_build_mode()
	_build_cursor.visible = false
	_hide_template_preview()
	hud.hide_build_mode()
	_build_timer.stop()
	wave += 1
	spawn_interval = maxf(0.5, spawn_interval - 0.15)
	spawn_timer.wait_time = spawn_interval
	_begin_wave(wave)

func _on_build_ready_pressed() -> void:
	_end_build_phase()

func _on_build_place_pressed() -> void:
	if BuildManager.selected == "template":
		_try_place_template()
	else:
		_try_place_at(_build_cursor_cell)
	_refresh_repair_button()

func _on_build_picker_selected(type: String) -> void:
	var prev := BuildManager.selected
	BuildManager.selected = type
	_try_place_at(_picker_cell)
	BuildManager.selected = prev

func _on_build_item_selected(item: String) -> void:
	BuildManager.selected = item
	if item != "template":
		_hide_template_preview()

func _on_door_toggle_pressed() -> void:
	_global_doors_open = !_global_doors_open
	for door in get_tree().get_nodes_in_group("doors"):
		door.toggle()

func _on_template_size_selected(size: String) -> void:
	_current_template_size = size

func _refresh_repair_button() -> void:
	var cost := BuildManager.calculate_repair_all_cost()
	hud.update_repair_all_button(cost, cost > 0, coins >= cost)

func _on_repair_all_pressed() -> void:
	var cost := BuildManager.calculate_repair_all_cost()
	if coins < cost:
		hud.flash_build_denied()
		return
	coins -= cost
	hud.update_coins(coins)
	for wall in BuildManager.get_damaged_walls():
		if is_instance_valid(wall):
			wall.repair()
	_refresh_repair_button()

func _try_place_template() -> void:
	var size_map := {"small": 5, "medium": 7, "large": 9}
	var sz: int = size_map[_current_template_size]
	var center := BuildManager.world_to_cell(player.global_position)
	var cells := BuildManager.get_template_cells(center, sz)
	var cost := BuildManager.calculate_template_cost(cells)
	if coins < cost:
		hud.flash_build_denied()
		return
	coins -= cost
	hud.update_coins(coins)
	var player_cell := BuildManager.world_to_cell(player.global_position)
	for entry in cells:
		if BuildManager.is_occupied(entry.cell):
			continue
		if BuildManager.is_reserved(entry.cell):
			continue
		if entry.cell == player_cell:
			continue
		var skip := false
		for member in get_tree().get_nodes_in_group("squad_members"):
			if is_instance_valid(member) and BuildManager.world_to_cell(member.global_position) == entry.cell:
				skip = true
				break
		if skip:
			continue
		var structure := _create_structure(entry.type, entry.cell)
		add_child(structure)
		BuildManager.register(entry.cell, structure)

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
		member.add_to_group("squad_members")
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
