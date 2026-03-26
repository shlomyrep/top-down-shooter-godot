extends Node2D
## Visual-only representation of the remote co-op partner.
## All position/animation data is fed via apply_state() from main.gd.
## Uses the same survivor sprite frames as the local player but tinted cyan
## so the two players are visually distinct.

const LERP_SPEED := 18.0

var _body:       AnimatedSprite2D
var _name_lbl:   Label
var _hp_bar:     ProgressBar
var _lerp_target: Vector2

func _ready() -> void:
	_lerp_target = global_position
	z_index = 1
	_build_visuals()

func _build_visuals() -> void:
	# ── Animated sprite (same assets as player) ───────────────────────────────
	_body = AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var base   := "res://assets/player/Top_Down_Survivor/handgun/"

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

	_body.sprite_frames = frames
	# Cyan tint so partner is distinguishable from the local (white) player
	_body.modulate = Color(0.55, 0.95, 1.0, 1.0)
	_body.play("idle")
	add_child(_body)

	# ── Name label ────────────────────────────────────────────────────────────
	_name_lbl = Label.new()
	_name_lbl.text = GameData.partner_name
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.position = Vector2(-40.0, -58.0)
	_name_lbl.size    = Vector2(80.0, 20.0)
	var ls := LabelSettings.new()
	ls.font_size    = 13
	ls.font_color   = Color(0.5, 0.95, 1.0, 1.0)
	ls.outline_size  = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	_name_lbl.label_settings = ls
	add_child(_name_lbl)

	# ── Health bar ────────────────────────────────────────────────────────────
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value      = 100
	_hp_bar.value          = 100
	_hp_bar.size           = Vector2(48.0, 6.0)
	_hp_bar.position       = Vector2(-24.0, -44.0)
	_hp_bar.show_percentage = false
	add_child(_hp_bar)

func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(_lerp_target, LERP_SPEED * delta)

## Called by main.gd whenever a remote_player_state packet arrives.
func apply_state(data: Dictionary) -> void:
	_lerp_target = Vector2(float(data.get("x", global_position.x)),
	                       float(data.get("y", global_position.y)))
	_body.rotation = float(data.get("rot", 0.0))

	var anim: String = str(data.get("anim", "idle"))
	if _body.animation != anim:
		_body.play(anim)

	var hp:     int = int(data.get("hp",     100))
	var max_hp: int = int(data.get("max_hp", 100))
	_hp_bar.max_value = max_hp
	_hp_bar.value     = hp

	# Refresh name label in case GameData was updated after _ready
	_name_lbl.text = GameData.partner_name
