extends Node2D

const ARENA_WIDTH := 3200
const ARENA_HEIGHT := 2400
const STORY_DURATION  := 3.0
const BUILD_DURATION  := 30.0
const RECOVERY_ITEMS := {
	"health": {"amount": 50, "cost": 40},
	"shield": {"amount": 100, "cost": 75},
}

@export var enemy_scene: PackedScene
@export var spawn_interval := 2.0
@export var spawn_distance := 600.0
@export var max_enemies := 30

@onready var player := $Player
@onready var spawn_timer := $SpawnTimer
@onready var hud := $UILayer/HUD

var coin_scene:           PackedScene = preload("res://scenes/coin.tscn")
var buy_station_scene:    PackedScene = preload("res://scenes/buy_station.tscn")
var recovery_station_scene: PackedScene = preload("res://scenes/recovery_station.tscn")
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
var _current_recovery_station: Node = null
var _picker_cell: Vector2i
var _touch_joy := {}        # finger_index → {"side": "move"|"aim", "origin": Vector2}
var _mouse_joy_side := ""
var _mouse_joy_origin := Vector2.ZERO
var _move_joy: Control
var _aim_joy: Control

# ── Co-op multiplayer state ───────────────────────────────────────────────────
var _confirmed_kills: Dictionary = {}      # net_id → true (double-kill guard)
var _enemy_sync_timer: float = 0.0
const _ENEMY_SYNC_INTERVAL := 0.10

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

	# Reset autoload state so restarts begin fresh
	BuildManager.occupied_cells.clear()
	BuildManager.interior_cells.clear()
	BuildManager.reserved_cells.clear()
	BuildManager.build_mode = false
	BuildManager.selected = "wall"
	WeaponManager.current_weapon = "pistol"

	spawn_timer.wait_time = spawn_interval
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	_on_player_health_changed(player.health, player.max_health)
	player.shield_changed.connect(_on_player_shield_changed)

	_move_joy = hud.get_node("MoveJoystick")
	_aim_joy = hud.get_node("AimJoystick")
	_move_joy.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_aim_joy.layout_direction = Control.LAYOUT_DIRECTION_LTR

	hud.update_coins(coins)
	_place_buy_stations()
	hud.buy_pressed.connect(_on_hud_buy_pressed)
	hud.weapon_shop_buy.connect(_on_weapon_shop_buy)
	hud.recovery_shop_buy.connect(_on_recovery_shop_buy)
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
	if GameData.is_multiplayer:
		_init_multiplayer()

func _place_buy_stations() -> void:
	var station := buy_station_scene.instantiate()
	station.weapon_id = "shop"
	# Snap to exact cell center so the shop occupies exactly one tile
	var shop_cell := Vector2i(20, 13)
	station.global_position = BuildManager.cell_to_world(shop_cell)
	station.player_entered.connect(_on_buy_station_entered)
	station.player_exited.connect(_on_buy_station_exited)
	add_child(station)
	# Reserve the shop cell so nothing can be built on it
	BuildManager.reserve_cell(shop_cell)

	# Place recovery station on the opposite side of the map
	var rec_station := recovery_station_scene.instantiate()
	var rec_cell := Vector2i(10, 20)
	rec_station.global_position = BuildManager.cell_to_world(rec_cell)
	rec_station.player_entered.connect(_on_recovery_station_entered)
	rec_station.player_exited.connect(_on_recovery_station_exited)
	add_child(rec_station)
	BuildManager.reserve_cell(rec_cell)

func _on_buy_station_entered(station: Node) -> void:
	_current_buy_station = station
	hud.show_weapon_shop(coins, WeaponManager.current_weapon)

func _on_buy_station_exited() -> void:
	_current_buy_station = null
	hud.hide_weapon_shop()

func _on_recovery_station_entered(_station: Node) -> void:
	_current_recovery_station = _station
	hud.show_recovery_shop(coins, player.health, player.max_health, player.shield)

func _on_recovery_station_exited() -> void:
	_current_recovery_station = null
	hud.hide_recovery_shop()

func _on_recovery_shop_buy(item_id: String) -> void:
	var item: Dictionary = RECOVERY_ITEMS[item_id]
	if coins < item["cost"]:
		return
	match item_id:
		"health":
			if player.health >= player.max_health:
				return
			coins -= item["cost"]
			hud.update_coins(coins)
			player.heal(item["amount"])
		"shield":
			if player.shield >= player.max_shield:
				return
			coins -= item["cost"]
			hud.update_coins(coins)
			player.add_shield(item["amount"])
	hud.show_recovery_shop(coins, player.health, player.max_health, player.shield)

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
	_confirmed_kills.clear()
	spawn_timer.start()
	hud.update_wave(wave_number)
	if GameData.is_multiplayer and GameData.is_host:
		NetworkManager.send_wave_event({"type": "wave_start", "wave": wave_number})

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

	# ── Enemy position broadcast (HOST → CLIENT, 10 Hz) ──────────────────────
	if GameData.is_multiplayer and GameData.is_host and _wave_active:
		_enemy_sync_timer += _delta
		if _enemy_sync_timer >= _ENEMY_SYNC_INTERVAL:
			_enemy_sync_timer = 0.0
			var batch: Array = []
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e):
					batch.append({"id": e.get_meta("net_id", ""), "x": e.global_position.x, "y": e.global_position.y})
			if not batch.is_empty():
				NetworkManager.send_enemies_sync(batch)

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
	if GameData.is_multiplayer:
		NetworkManager.send_structure_placed(BuildManager.selected, cell.x, cell.y)

func _try_erase_at(cell: Vector2i) -> void:
	if not BuildManager.is_occupied(cell):
		return
	var node: Node = BuildManager.occupied_cells[cell]
	if node and is_instance_valid(node):
		node.queue_free()
	coins += BuildManager.ERASE_REFUND
	hud.update_coins(coins)
	BuildManager.unregister(cell)
	if GameData.is_multiplayer:
		NetworkManager.send_structure_erased(cell.x, cell.y)

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
	if GameData.is_multiplayer and not GameData.is_host:
		return  # only HOST spawns enemies in co-op
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

	# Assign a network ID so both clients can reference this enemy by ID
	var type_str := "tank" if is_tank else ("cannon" if is_cannon else ("bug" if is_bug else "skeleton"))
	var net_id := str(randi_range(100000, 999999))
	enemy.set_meta("net_id", net_id)

	if GameData.is_multiplayer:
		# Capture net_id for the closure
		var _nid := net_id
		enemy.died_at.connect(func(pos: Vector2): _on_enemy_died_host(_nid, pos))
		NetworkManager.send_enemy_spawned({
			"id": net_id, "type": type_str,
			"x": spawn_pos.x, "y": spawn_pos.y,
			"max_hp": enemy.max_health, "speed": enemy.speed
		})
	else:
		enemy.died_at.connect(_on_enemy_died_at)

	enemies_spawned_this_wave += 1

func _on_enemy_died_at(pos: Vector2) -> void:
	score += 10
	_enemies_killed_this_wave += 1
	_spawn_coin(pos)
	_check_wave_complete()

# ── Co-op: HOST records kill, notifies CLIENT ──────────────────────────────
func _on_enemy_died_host(net_id: String, pos: Vector2) -> void:
	if _confirmed_kills.has(net_id):
		return
	_confirmed_kills[net_id] = true
	score += 10
	_enemies_killed_this_wave += 1
	_spawn_coin(pos)
	_check_wave_complete()
	NetworkManager.send_enemy_killed({"id": net_id, "tx": pos.x, "ty": pos.y})
	NetworkManager.send_score_sync({"score": score})

# ── Co-op: CLIENT kills an enemy locally → notify HOST ────────────────────
func _on_client_enemy_died(net_id: String, pos: Vector2) -> void:
	_spawn_coin(pos)
	NetworkManager.send_enemy_killed({"id": net_id, "tx": pos.x, "ty": pos.y})

# ── Co-op: HOST receives kill report from CLIENT ───────────────────────────
func _on_remote_enemy_killed_from_client(data: Dictionary) -> void:
	var net_id := str(data.get("id", ""))
	if net_id.is_empty() or _confirmed_kills.has(net_id):
		return
	_confirmed_kills[net_id] = true
	var e := _find_enemy_by_net_id(net_id)
	if e and is_instance_valid(e):
		e.queue_free()
	score += 10
	_enemies_killed_this_wave += 1
	var pos := Vector2(float(data.get("tx", 0.0)), float(data.get("ty", 0.0)))
	_spawn_coin(pos)
	_check_wave_complete()
	NetworkManager.send_score_sync({"score": score})

# ── Co-op: CLIENT receives kill report from HOST (remove mirrored enemy) ──
func _on_remote_enemy_killed(data: Dictionary) -> void:
	var net_id := str(data.get("id", ""))
	var e := _find_enemy_by_net_id(net_id)
	if e and is_instance_valid(e):
		e.queue_free()

# ── Find an enemy node by net_id metadata ────────────────────────────────
func _find_enemy_by_net_id(id: String) -> Node:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.get_meta("net_id", "") == id:
			return e
	return null

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
	if GameData.is_multiplayer and GameData.is_host:
		NetworkManager.send_wave_event({"type": "between_wave", "wave": wave})

func _on_between_wave_timeout() -> void:
	hud.hide_wave_transition()
	var scaled_build := BUILD_DURATION + float(wave) * 5.0
	hud.show_build_mode(scaled_build)
	BuildManager.start_build_mode()
	_build_cursor.visible = true
	_build_timer.start(scaled_build)
	_refresh_repair_button()
	if GameData.is_multiplayer and GameData.is_host:
		NetworkManager.send_wave_event({"type": "build_start", "wave": wave, "duration": scaled_build})

func _on_build_timer_timeout() -> void:
	# CLIENT waits for host's build_end wave_event — only HOST ends the build phase on timer expiry
	if GameData.is_multiplayer and not GameData.is_host:
		hud.show_partner_waiting_label()
		return
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
	if GameData.is_multiplayer and GameData.is_host:
		NetworkManager.send_wave_event({"type": "build_end", "next_wave": wave})

func _on_build_ready_pressed() -> void:
	if GameData.is_multiplayer:
		NetworkManager.send_build_ready_vote()
		hud.show_partner_waiting_label()
	else:
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
	if GameData.is_multiplayer:
		NetworkManager.send_door_toggled(_global_doors_open)

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

func _on_player_shield_changed(current: int, maximum: int) -> void:
	hud.update_shield(current, maximum)

func _on_player_died() -> void:
	spawn_timer.stop()
	_between_wave_timer.stop()
	_build_timer.stop()
	GameData.save_if_record(wave)
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

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
	if GameData.is_multiplayer:
		NetworkManager.send_airstrike_used({"x": player.global_position.x, "y": player.global_position.y})

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
	if GameData.is_multiplayer:
		NetworkManager.send_squad_spawned({
			"x": player.global_position.x, "y": player.global_position.y,
			"count": count, "shielded": shielded
		})

func _on_support_cooldowns_updated() -> void:
	hud.update_support_cooldowns(
		SupportManager.airstrike_cd,
		SupportManager.AIRSTRIKE_COOLDOWN,
		SupportManager.squad_cd,
		SupportManager.SQUAD_COOLDOWN,
		SupportManager.shield_squad_cd,
		SupportManager.SHIELD_SQUAD_COOLDOWN
	)

# ══════════════════════════════════════════════════════════════════════════════
# ── Co-op multiplayer ─────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

var _remote_player_node: Node2D = null
var _partner_down_label: Label  = null

const _remote_player_scene := preload("res://scenes/remote_player.tscn")

func _init_multiplayer() -> void:
	# Spawn remote player visual
	_remote_player_node = _remote_player_scene.instantiate()
	_remote_player_node.global_position = Vector2(ARENA_WIDTH * 0.5, ARENA_HEIGHT * 0.5)
	add_child(_remote_player_node)

	# HUD label for partner events (hidden initially)
	_partner_down_label = Label.new()
	_partner_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_partner_down_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_partner_down_label.size = Vector2(600.0, 80.0)
	_partner_down_label.position = Vector2(340.0, 300.0)
	_partner_down_label.visible = false
	var ls := LabelSettings.new()
	ls.font_size    = 32
	ls.font_color   = Color(1.0, 0.3, 0.3, 1.0)
	ls.outline_size  = 3
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	_partner_down_label.label_settings = ls
	$UILayer.add_child(_partner_down_label)

	# Wire NetworkManager signals to handlers in this scene
	NetworkManager.remote_player_state.connect(_on_remote_player_state)
	NetworkManager.remote_bullet_fired.connect(_on_remote_bullet_fired)
	NetworkManager.partner_died.connect(_on_partner_died)
	NetworkManager.partner_disconnected.connect(_on_partner_disconnected)

	# Enemy sync
	if GameData.is_host:
		# Host receives kill reports from the client
		NetworkManager.remote_enemy_killed.connect(_on_remote_enemy_killed_from_client)
	else:
		# Client receives spawns and kill confirmations from the host
		NetworkManager.remote_enemy_spawned.connect(_on_remote_enemy_spawned)
		NetworkManager.remote_enemies_sync.connect(_on_remote_enemies_sync)
		NetworkManager.remote_enemy_killed.connect(_on_remote_enemy_killed)
		NetworkManager.remote_score_sync.connect(_on_remote_score_sync)

	# Wave events — client mirrors host's wave state
	if not GameData.is_host:
		NetworkManager.remote_wave_event.connect(_on_remote_wave_event)

	# Build ready vote — both players handle this
	NetworkManager.remote_build_ready_vote.connect(_on_remote_build_ready_vote)
	NetworkManager.remote_build_end_vote.connect(_on_remote_build_end_vote)

	# Structure sync
	NetworkManager.remote_structure_placed.connect(_on_remote_structure_placed)
	NetworkManager.remote_structure_erased.connect(_on_remote_structure_erased)
	NetworkManager.remote_door_toggled.connect(_on_remote_door_toggled)

	# Support abilities
	NetworkManager.remote_squad_spawned.connect(_on_remote_squad_spawned)
	NetworkManager.remote_airstrike_used.connect(_on_remote_airstrike_used)

func _on_remote_player_state(data: Dictionary) -> void:
	if _remote_player_node and is_instance_valid(_remote_player_node):
		_remote_player_node.apply_state(data)

func _on_remote_bullet_fired(data: Dictionary) -> void:
	var bullet: Area2D = (preload("res://scenes/bullet.tscn")).instantiate() as Area2D
	bullet.global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	bullet.rotation        = float(data.get("rot", 0.0))
	bullet.damage          = int(data.get("dmg", 20))
	bullet.speed           = float(data.get("spd", 900.0))
	bullet.hit_color       = Color.from_string(str(data.get("color", "ffffff")), Color.WHITE)
	bullet.bullet_scale    = float(data.get("scale", 1.0))
	add_child(bullet)

func _on_partner_died() -> void:
	_show_partner_event("⚠  PARTNER DOWN  –  GAME OVER")
	await get_tree().create_timer(2.5).timeout
	_on_player_died()

func _on_partner_disconnected() -> void:
	_show_partner_event("⚡  PARTNER DISCONNECTED")
	await get_tree().create_timer(2.5).timeout
	_on_player_died()

func _show_partner_event(msg: String) -> void:
	if _partner_down_label:
		_partner_down_label.text    = msg
		_partner_down_label.visible = true

# ══════════════════════════════════════════════════════════════════════════════
# ── Co-op: Remote enemy spawn / sync / death handlers ─────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## CLIENT receives a new enemy spawned by HOST — mirror it locally
func _on_remote_enemy_spawned(data: Dictionary) -> void:
	var type_str := str(data.get("type", "skeleton"))
	var enemy: CharacterBody2D
	match type_str:
		"tank":
			enemy = tank_scene.instantiate() as CharacterBody2D
		"cannon":
			enemy = cannon_soldier_scene.instantiate() as CharacterBody2D
		"bug":
			enemy = bug_scene.instantiate() as CharacterBody2D
		_:
			enemy = enemy_scene.instantiate() as CharacterBody2D

	enemy.global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	enemy.player = player
	enemy.max_health = int(data.get("max_hp", 60))
	enemy.speed      = float(data.get("speed", 120.0))
	enemy.add_to_group("enemies")

	var net_id := str(data.get("id", ""))
	enemy.set_meta("net_id", net_id)

	# Connect LOCAL die signal → notify host
	var _nid := net_id
	enemy.died_at.connect(func(pos: Vector2): _on_client_enemy_died(_nid, pos))

	add_child(enemy)
	enemies_spawned_this_wave += 1

## CLIENT receives batched position updates from HOST
func _on_remote_enemies_sync(batch: Array) -> void:
	for entry in batch:
		var e := _find_enemy_by_net_id(str(entry.get("id", "")))
		if e and is_instance_valid(e):
			var target := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
			if e.global_position.distance_to(target) > 300.0:
				e.global_position = target   # teleport if very far off
			else:
				e.global_position = e.global_position.lerp(target, 0.25)

## CLIENT receives score from HOST
func _on_remote_score_sync(data: Dictionary) -> void:
	score = int(data.get("score", score))

# ══════════════════════════════════════════════════════════════════════════════
# ── Co-op: Wave state mirror (CLIENT) ─────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

func _on_remote_wave_event(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"wave_start":
			wave = int(data.get("wave", wave))
			_wave_active = true
			_enemies_killed_this_wave = 0
			enemies_spawned_this_wave = 0
			_confirmed_kills.clear()
			hud.update_wave(wave)
			spawn_timer.stop()  # client never spawns
		"between_wave":
			_wave_active = false
			spawn_timer.stop()
			var config := WaveManager.get_wave_config(int(data.get("wave", wave)))
			hud.show_wave_transition(config, STORY_DURATION)
			_between_wave_timer.start(STORY_DURATION)
		"build_start":
			hud.hide_wave_transition()
			var dur := float(data.get("duration", BUILD_DURATION))
			hud.show_build_mode(dur)
			BuildManager.start_build_mode()
			_build_cursor.visible = true
			_build_timer.start(dur)
			_refresh_repair_button()
		"build_end":
			wave = int(data.get("next_wave", wave))
			spawn_interval = maxf(0.5, spawn_interval - 0.15)
			spawn_timer.wait_time = spawn_interval
			if BuildManager.build_mode:
				BuildManager.end_build_mode()
				_build_cursor.visible = false
				_hide_template_preview()
				hud.hide_build_mode()
				_build_timer.stop()
			hud.hide_partner_waiting_label()
			_wave_active = true
			_enemies_killed_this_wave = 0
			enemies_spawned_this_wave = 0
			hud.update_wave(wave)

# ══════════════════════════════════════════════════════════════════════════════
# ── Co-op: Build-phase ready-vote handlers ────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## One player voted ready — show a note to the other player
func _on_remote_build_ready_vote(_data: Dictionary) -> void:
	hud.show_partner_ready_label()

## Both voted (or server timed both) → end build phase on this device
func _on_remote_build_end_vote() -> void:
	hud.hide_partner_waiting_label()
	hud.hide_partner_ready_label()
	_end_build_phase()

# ══════════════════════════════════════════════════════════════════════════════
# ── Co-op: Structure sync ─────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

func _on_remote_structure_placed(data: Dictionary) -> void:
	var cell := Vector2i(int(data.get("cx", 0)), int(data.get("cy", 0)))
	if BuildManager.is_occupied(cell) or BuildManager.is_reserved(cell):
		return
	var s := _create_structure(str(data.get("type", "wall")), cell)
	add_child(s)
	BuildManager.register(cell, s)

func _on_remote_structure_erased(data: Dictionary) -> void:
	var cell := Vector2i(int(data.get("cx", 0)), int(data.get("cy", 0)))
	if not BuildManager.is_occupied(cell):
		return
	var node: Node = BuildManager.occupied_cells[cell]
	if node and is_instance_valid(node):
		node.queue_free()
	BuildManager.unregister(cell)

func _on_remote_door_toggled(data: Dictionary) -> void:
	_global_doors_open = bool(data.get("is_open", false))
	for door in get_tree().get_nodes_in_group("doors"):
		if door.is_open != _global_doors_open:
			door.toggle()

# ── Co-op: Support abilities from partner ─────────────────────────────────────

## Partner spawned squad — mirror them following `_remote_player_node`
func _on_remote_squad_spawned(data: Dictionary) -> void:
	if not _remote_player_node or not is_instance_valid(_remote_player_node):
		return
	var count: int  = int(data.get("count", 3))
	var shielded: bool = bool(data.get("shielded", false))
	var origin := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	for i in count:
		var angle := TAU * i / count
		var offset := Vector2.RIGHT.rotated(angle) * 70.0
		var member := squad_scene.instantiate()
		member.global_position = origin + offset
		member.player = _remote_player_node   # follow the partner's visual
		member.shielded = shielded
		member.add_to_group("squad_members")
		add_child(member)

## Partner used airstrike — spawn the visual + damage at their position
func _on_remote_airstrike_used(data: Dictionary) -> void:
	var strike := airstrike_scene.instantiate()
	strike.global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	add_child(strike)
