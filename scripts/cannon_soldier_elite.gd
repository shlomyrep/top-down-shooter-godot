extends "res://scripts/cannon_soldier.gd"

## Elite Cannon Soldier — 2-crew heavy unit introduced in wave 6.
## Higher health, slower movement, shorter fire cooldown, more damage.
## Uses dedicated 2-crew sprites for all animation states.

func _ready() -> void:
	max_health      = 260
	speed           = 22.0
	attack_range    = 260.0
	attack_cooldown_time = 2.2
	contact_damage  = 18
	super._ready()

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	var base   := "res://assets/enemies/cannon_soldier/"

	# idle — 2-crew flanking the cannon at rest
	frames.add_animation("idle")
	frames.set_animation_loop("idle", false)
	frames.set_animation_speed("idle", 1.0)
	frames.add_frame("idle", load(base + "cs_elite_idle.png"))

	# All walk directions share the same 2-frame cycle
	# (elite is heavy and always faces the same orientation in these sprites)
	for anim in ["walk_right", "walk_left", "walk_up"]:
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		frames.set_animation_speed(anim, 4.0)
		frames.add_frame(anim, load(base + "cs_elite_wu1.png"))
		frames.add_frame(anim, load(base + "cs_elite_idle.png"))

	# fire — idle pose + muzzle-flash frame
	frames.add_animation("fire")
	frames.set_animation_loop("fire", true)
	frames.set_animation_speed("fire", 3.0)
	frames.add_frame("fire", load(base + "cs_elite_idle.png"))
	frames.add_frame("fire", load(base + "cs_elite_fire.png"))

	# fire_up — same as fire (elite only has up-facing fire sprite)
	frames.add_animation("fire_up")
	frames.set_animation_loop("fire_up", true)
	frames.set_animation_speed("fire_up", 3.0)
	frames.add_frame("fire_up", load(base + "cs_elite_idle.png"))
	frames.add_frame("fire_up", load(base + "cs_elite_fire.png"))

	body_sprite.sprite_frames = frames
	body_sprite.play("idle")
