extends CharacterBody2D

@export var speed := 350.0
@export var max_health := 100
@export var max_shield := 100
var health: int
var shield: int = 0

@onready var gun_pivot := $GunPivot
@onready var muzzle := $GunPivot/Muzzle
@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var shoot_cooldown := $ShootCooldown
@onready var shield_aura := $ShieldAura
@onready var _muzzle_flash_light := $GunPivot/Muzzle/MuzzleFlashLight

var _screen_flash_rect: ColorRect = null

var _is_shooting := false

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var aim_direction := Vector2.RIGHT
var move_input    := Vector2.ZERO
var aim_input     := Vector2.ZERO

# Multiplayer: broadcast state at 20 Hz — tighter intervals reduce max positional
# jump per packet and give the entity-interpolation buffer more waypoints.
const _NET_INTERVAL := 0.050
var _net_timer: float = 0.0

signal health_changed(current: int, maximum: int)
signal shield_changed(current: int, maximum: int)
signal died
signal downed  ## Multiplayer: HP hit 0 but partner may still revive
signal weapon_changed(weapon_name: String)

## True while waiting for the partner to revive (multiplayer only).
var is_downed := false

func _ready() -> void:
	health = max_health
	shield = 0
	add_to_group("player")
	add_to_group("target_players")
	shoot_cooldown.wait_time = WeaponManager.get_current()["cooldown"]
	_setup_animations()
	body_sprite.animation_finished.connect(_on_animation_finished)
	shield_aura.visible = false
	# Build the screen-damage flash overlay (full-screen red ColorRect in UI canvas)
	_screen_flash_rect = ColorRect.new()
	_screen_flash_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	_screen_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_flash_rect.z_index = 5
	get_tree().current_scene.get_node("UILayer").add_child(_screen_flash_rect)

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	var base := "res://assets/player/Top_Down_Survivor/handgun/"

	frames.add_animation("idle")
	frames.set_animation_speed("idle", 10.0)
	for i in 20:
		frames.add_frame("idle", load(base + "idle/survivor-idle_handgun_%d.png" % i))

	frames.add_animation("move")
	frames.set_animation_speed("move", 20.0)
	for i in 20:
		frames.add_frame("move", load(base + "move/survivor-move_handgun_%d.png" % i))

	frames.add_animation("shoot")
	frames.set_animation_speed("shoot", 20.0)
	frames.set_animation_loop("shoot", false)
	for i in 3:
		frames.add_frame("shoot", load(base + "shoot/survivor-shoot_handgun_%d.png" % i))

	body_sprite.sprite_frames = frames
	body_sprite.play("idle")

func _on_animation_finished() -> void:
	_is_shooting = false

func _physics_process(delta: float) -> void:
	if is_downed:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	velocity = move_input.normalized() * speed
	move_and_slide()
	# Broadcast position/state to partner
	if GameData.is_multiplayer:
		_net_timer += delta
		if _net_timer >= _NET_INTERVAL:
			_net_timer = 0.0
			_broadcast_state()

	if BuildManager.build_mode:
		# Determine which direction the player should face:
		# right joystick takes priority, then movement direction.
		var face_dir := Vector2.ZERO
		if aim_input.length() > 0.1:
			face_dir = aim_input.normalized()
		elif move_input.length() > 0.1:
			face_dir = move_input.normalized()
		if face_dir.length() > 0.0:
			aim_direction = face_dir
			gun_pivot.rotation = face_dir.angle()
			body_sprite.rotation = gun_pivot.rotation
		if velocity.length() > 10.0:
			body_sprite.play("move")
		else:
			body_sprite.play("idle")
		return

	if aim_input.length() > 0.1:
		aim_direction = aim_input.normalized()
		gun_pivot.rotation = aim_direction.angle()
		if shoot_cooldown.is_stopped():
			shoot()
			shoot_cooldown.start()
	elif move_input.length() > 0.1:
		# No aim input — face the movement direction naturally
		aim_direction = move_input.normalized()
		gun_pivot.rotation = aim_direction.angle()

	body_sprite.rotation = gun_pivot.rotation

	if not _is_shooting:
		if velocity.length() > 10.0:
			body_sprite.play("move")
		else:
			body_sprite.play("idle")

func shoot() -> void:
	var w := WeaponManager.get_current()
	for i in w["pellets"]:
		var bullet: Area2D = bullet_scene.instantiate() as Area2D
		bullet.global_position = muzzle.global_position
		var spread: float = (randf() - 0.5) * float(w["spread"])
		bullet.rotation = gun_pivot.rotation + spread
		bullet.damage = w["damage"]
		bullet.speed = w["bullet_speed"]
		bullet.hit_color = w["bullet_color"]
		bullet.bullet_scale = w.get("bullet_scale", 1.0)
		get_tree().current_scene.add_child(bullet)
		if GameData.is_multiplayer:
			NetworkManager.send_bullet_fired({
				"x":     muzzle.global_position.x,
				"y":     muzzle.global_position.y,
				"rot":   bullet.rotation,
				"dmg":   w["damage"],
				"spd":   w["bullet_speed"],
				"color": w["bullet_color"].to_html(false),
				"scale": w.get("bullet_scale", 1.0),
			})
	_is_shooting = true
	body_sprite.play("shoot")
	# Muzzle flash: burst the point-light energy then tween to zero
	_muzzle_flash_light.energy = 3.0
	var _mf_tween := create_tween()
	_mf_tween.tween_property(_muzzle_flash_light, "energy", 0.0, 0.08)

func equip_weapon(weapon_id: String) -> void:
	WeaponManager.equip(weapon_id)
	var w := WeaponManager.get_current()
	shoot_cooldown.wait_time = w["cooldown"]
	weapon_changed.emit(w["name"])

func take_damage(amount: int) -> void:
	if is_downed:
		return  # Already downed; ignore further hits
	if shield > 0:
		var absorbed := mini(shield, amount)
		shield -= absorbed
		amount -= absorbed
		shield_changed.emit(shield, max_shield)
		_update_aura_visibility()
	if amount > 0:
		health -= amount
		health_changed.emit(health, max_health)
		_flash()
		if health <= 0:
			health = 0
			if GameData.is_multiplayer:
				downed.emit()  ## Let main.gd decide between downed vs. game-over
			else:
				died.emit()
				get_tree().reload_current_scene()

## Called by main.gd when the partner successfully revives this player.
func revive(hp_pct: float = 0.5) -> void:
	is_downed = false
	health = maxi(1, int(max_health * hp_pct))
	health_changed.emit(health, max_health)
	body_sprite.play("idle")

func heal(amount: int) -> void:
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)

func add_shield(amount: int) -> void:
	shield = mini(shield + amount, max_shield)
	shield_changed.emit(shield, max_shield)
	_update_aura_visibility()

func _update_aura_visibility() -> void:
	shield_aura.visible = shield > 0

func _flash() -> void:
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.15)
	# Full-screen red flash
	if _screen_flash_rect:
		_screen_flash_rect.color.a = 0.35
		var ft := create_tween()
		ft.tween_property(_screen_flash_rect, "color:a", 0.0, 0.28)

func _broadcast_state() -> void:
	var anim := "idle"
	if _is_shooting:
		anim = "shoot"
	elif velocity.length() > 10.0:
		anim = "move"
	NetworkManager.send_player_state({
		"x":      global_position.x,
		"y":      global_position.y,
		"rot":    body_sprite.rotation,
		"anim":   anim,
		"hp":     health,
		"max_hp": max_health,
	})
