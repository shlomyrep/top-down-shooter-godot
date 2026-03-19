extends CharacterBody2D

@export var speed := 350.0
@export var max_health := 100
var health: int

@onready var gun_pivot := $GunPivot
@onready var muzzle := $GunPivot/Muzzle
@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var shoot_cooldown := $ShootCooldown

var _is_shooting := false

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var aim_direction := Vector2.RIGHT
var is_using_touch := false
var move_input := Vector2.ZERO
var aim_input := Vector2.ZERO

signal health_changed(current: int, maximum: int)
signal died
signal weapon_changed(weapon_name: String)

func _ready() -> void:
	health = max_health
	add_to_group("player")
	shoot_cooldown.wait_time = WeaponManager.get_current()["cooldown"]
	_setup_animations()
	body_sprite.animation_finished.connect(_on_animation_finished)

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

func _physics_process(_delta: float) -> void:
	# Movement from keyboard or virtual joystick
	if not is_using_touch:
		move_input = Vector2.ZERO
		move_input.x = Input.get_axis("move_left", "move_right")
		move_input.y = Input.get_axis("move_up", "move_down")

	velocity = move_input.normalized() * speed
	move_and_slide()

	# Aim
	if BuildManager.build_mode:
		body_sprite.play("idle")
		return
	if is_using_touch:
		if aim_input.length() > 0.1:
			aim_direction = aim_input.normalized()
			gun_pivot.rotation = aim_direction.angle()
			# Auto-shoot when aiming with joystick
			if shoot_cooldown.is_stopped():
				shoot()
				shoot_cooldown.start()
	else:
		gun_pivot.look_at(get_global_mouse_position())
		aim_direction = (get_global_mouse_position() - global_position).normalized()
		if Input.is_action_just_pressed("shoot"):
			if shoot_cooldown.is_stopped():
				shoot()
				shoot_cooldown.start()

	# Rotate sprite to face aim direction
	body_sprite.rotation = gun_pivot.rotation

	# Drive animation
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
		get_tree().current_scene.add_child(bullet)
	_is_shooting = true
	body_sprite.play("shoot")

func equip_weapon(weapon_id: String) -> void:
	WeaponManager.equip(weapon_id)
	var w := WeaponManager.get_current()
	shoot_cooldown.wait_time = w["cooldown"]
	weapon_changed.emit(w["name"])

func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health, max_health)
	_flash()
	if health <= 0:
		died.emit()
		get_tree().reload_current_scene()

func _flash() -> void:
	body_sprite.modulate = Color(10, 10, 10, 1)
	var tween: Tween = create_tween()
	tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.15)

func set_move_joystick(direction: Vector2) -> void:
	is_using_touch = true
	move_input = direction

func set_aim_joystick(direction: Vector2) -> void:
	is_using_touch = true
	aim_input = direction
