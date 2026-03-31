extends Node2D
## Visual-only representation of the remote co-op partner.
## All position/animation data is fed via apply_state() from main.gd.
## Uses the same survivor sprite frames as the local player but tinted cyan
## so the two players are visually distinct.

## Entity interpolation constants ─────────────────────────────────────────────
## Render this many ms behind the most-recently received snapshot.
## Covers 1 full packet interval (50 ms @ 20 Hz) + typical WiFi jitter.
const INTERP_DELAY_MS   := 120.0
## Hard cap on dead-reckoning extrapolation (ms). Beyond this, freeze.
const EXTRAP_CAP_MS     := 250.0
## If the interpolated position is farther than this, teleport instead of
## gliding there (handles reconnects / scene reloads).
const SNAP_THRESHOLD_PX := 400.0
## Maximum number of snapshots to keep in the ring-buffer.
const MAX_BUFFER_SIZE   := 30

var _body:     AnimatedSprite2D
var _name_lbl: Label
var _hp_bar:   ProgressBar

## Sorted ring-buffer of received state snapshots.
## Each entry: { recv_ts: float, x: float, y: float, rot: float, anim: String }
var _snapshot_buffer: Array = []

## True after the first real snapshot has set an initial position.
var _initialized: bool = false

func _ready() -> void:
	z_index = 1
	add_to_group("target_players")
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
	_body.scale = Vector2(0.27, 0.27)  # match player.tscn BodySprite scale
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

func _physics_process(_delta: float) -> void:
	if not _initialized or _snapshot_buffer.is_empty():
		return

	var render_time: float = float(Time.get_ticks_msec()) - INTERP_DELAY_MS

	# Find snap_a (last snapshot ≤ render_time) and snap_b (first > render_time).
	# Buffer is kept in ascending recv_ts order so we can break early.
	var snap_a_idx: int = -1
	for i in _snapshot_buffer.size():
		if _snapshot_buffer[i].recv_ts <= render_time:
			snap_a_idx = i
		else:
			break

	var interp_pos:  Vector2
	var interp_rot:  float
	var interp_anim: String

	if snap_a_idx == -1:
		# render_time is before all buffered snapshots — hold at oldest position.
		var oldest: Dictionary = _snapshot_buffer[0]
		interp_pos  = Vector2(oldest.x, oldest.y)
		interp_rot  = oldest.rot
		interp_anim = oldest.anim

	elif snap_a_idx == _snapshot_buffer.size() - 1:
		# render_time is past all snapshots — dead-reckoning extrapolation.
		var newest: Dictionary = _snapshot_buffer[snap_a_idx]
		var age_ms: float = minf(float(Time.get_ticks_msec()) - newest.recv_ts - INTERP_DELAY_MS, EXTRAP_CAP_MS)
		age_ms = maxf(age_ms, 0.0)
		var vel := Vector2.ZERO
		if _snapshot_buffer.size() >= 2:
			var prev: Dictionary = _snapshot_buffer[snap_a_idx - 1]
			var dt: float = newest.recv_ts - prev.recv_ts
			if dt > 0.0:
				vel = (Vector2(newest.x, newest.y) - Vector2(prev.x, prev.y)) / dt
		interp_pos  = Vector2(newest.x, newest.y) + vel * age_ms
		interp_rot  = newest.rot
		interp_anim = newest.anim

	else:
		# Normal interpolation between the two bracketing snapshots.
		var snap_a: Dictionary = _snapshot_buffer[snap_a_idx]
		var snap_b: Dictionary = _snapshot_buffer[snap_a_idx + 1]
		var dt: float = snap_b.recv_ts - snap_a.recv_ts
		var t: float  = clampf((render_time - snap_a.recv_ts) / dt, 0.0, 1.0)
		interp_pos  = Vector2(snap_a.x, snap_a.y).lerp(Vector2(snap_b.x, snap_b.y), t)
		interp_rot  = lerp_angle(snap_a.rot, snap_b.rot, t)
		interp_anim = snap_b.anim

	# Apply position — snap if extremely far (reconnect / scene-reload artifact).
	if global_position.distance_to(interp_pos) > SNAP_THRESHOLD_PX:
		global_position = interp_pos
	else:
		global_position = interp_pos

	_body.rotation = interp_rot
	if _body.animation != interp_anim:
		_body.play(interp_anim)

	# Prune snapshots older than the render window (keep at least 2).
	while _snapshot_buffer.size() > 2 and _snapshot_buffer[0].recv_ts < render_time - 50.0:
		_snapshot_buffer.remove_at(0)

## Called by main.gd whenever a remote_player_state packet arrives.
func apply_state(data: Dictionary) -> void:
	var snap := {
		"recv_ts": float(Time.get_ticks_msec()),
		"x":       float(data.get("x", global_position.x)),
		"y":       float(data.get("y", global_position.y)),
		"rot":     float(data.get("rot", 0.0)),
		"anim":    str(data.get("anim", "idle")),
	}
	_snapshot_buffer.append(snap)
	if _snapshot_buffer.size() > MAX_BUFFER_SIZE:
		_snapshot_buffer.remove_at(0)

	# On first packet: teleport to the real position immediately so there
	# is no cold-start glide from the default arena-center spawn point.
	if not _initialized:
		_initialized = true
		global_position = Vector2(snap.x, snap.y)

	# Health and name are shown immediately — no interpolation delay needed.
	var hp:     int = int(data.get("hp",     100))
	var max_hp: int = int(data.get("max_hp", 100))
	_hp_bar.max_value = max_hp
	_hp_bar.value     = hp
	_name_lbl.text = GameData.partner_name

## Teleport immediately to a position and clear the snapshot buffer.
## Useful for explicit repositioning (e.g. scene reset or reconnect).
func teleport_to(pos: Vector2) -> void:
	global_position = pos
	_snapshot_buffer.clear()
	_initialized = false

## Called by main.gd when the partner's downed state changes.
func set_downed(downed_state: bool) -> void:
	if downed_state:
		_body.modulate = Color(1.0, 0.25, 0.25, 0.85)  # Red tint — partner is down
		_body.play("idle")
		_name_lbl.text = tr("PARTNER_DOWN_LABEL") % [GameData.partner_name]
	else:
		_body.modulate = Color(0.55, 0.95, 1.0, 1.0)   # Restore cyan
		_name_lbl.text = GameData.partner_name
