extends Node

const SAVE_PATH := "user://save.json"

var record_wave: int = 0
var player_name: String = "SURVIVOR"
var _last_wave_reached: int = 0
var tutorial_plays: int = 0

## Voice language code. Supported: "en", "he". Defaults to "en".
var voice_language: String = "en"

## On-device friends list (array of player name strings, saved to disk).
var saved_friends: Array = []

func add_friend(name: String) -> void:
	var trimmed := name.strip_edges().to_upper()
	if trimmed.is_empty() or trimmed in saved_friends:
		return
	saved_friends.append(trimmed)
	_save()

func remove_friend(name: String) -> void:
	var idx := saved_friends.find(name.strip_edges().to_upper())
	if idx >= 0:
		saved_friends.remove_at(idx)
		_save()

func has_friend(name: String) -> bool:
	return name.strip_edges().to_upper() in saved_friends

# ── Multiplayer session state (reset each lobby entry) ────────────────────────
var is_multiplayer: bool = false
var is_host: bool        = false
var room_id: String      = ""
var partner_name: String = ""
# Per-session kill tallies shown on the game-over screen
var my_kills: int      = 0
var partner_kills: int = 0

func reset_multiplayer() -> void:
	is_multiplayer = false
	is_host        = false
	room_id        = ""
	partner_name   = ""
	my_kills       = 0
	partner_kills  = 0

func _ready() -> void:
	_load()
	_apply_locale()

func _apply_locale() -> void:
	# Android reports Hebrew as "iw" (old Java code); normalize to "he".
	const ALIASES := {"iw": "he", "in": "id", "ji": "yi"}
	var lang := OS.get_locale_language()
	if lang in ALIASES:
		lang = ALIASES[lang]
	var supported := TranslationServer.get_loaded_locales()
	if lang in supported:
		TranslationServer.set_locale(lang)
	else:
		TranslationServer.set_locale("en")

## Call when a game session ends.
## Saves the wave if it is a new record. Returns true if it is.
func save_if_record(wave_number: int) -> bool:
	_last_wave_reached = wave_number
	var is_record := wave_number > record_wave
	if is_record:
		record_wave = wave_number
	_save()
	return is_record

func get_last_wave() -> int:
	return _last_wave_reached

func set_player_name(new_name: String) -> void:
	var trimmed := new_name.strip_edges().to_upper()
	player_name = trimmed if trimmed.length() > 0 else "SURVIVOR"
	_save()

## Spawn a debris + dust explosion at world-space [pos] when a structure is destroyed.
## Particles are added directly to the current scene root so they outlive the structure.
func spawn_structure_explosion(pos: Vector2) -> void:
	var root: Node = get_tree().current_scene

	# — Debris burst (brown/grey chunks) —
	var debris := GPUParticles2D.new()
	debris.emitting  = true
	debris.one_shot  = true
	debris.amount    = 22
	debris.lifetime  = 0.55
	debris.global_position = pos
	var dmat := ParticleProcessMaterial.new()
	dmat.direction             = Vector3(0, 0, 0)
	dmat.spread                = 180.0
	dmat.initial_velocity_min  = 90.0
	dmat.initial_velocity_max  = 200.0
	dmat.gravity               = Vector3.ZERO
	dmat.scale_min             = 4.0
	dmat.scale_max             = 9.0
	dmat.color                 = Color(0.58, 0.44, 0.24, 1.0)  # sandy brown
	debris.process_material    = dmat
	debris.finished.connect(debris.queue_free)
	root.add_child(debris)

	# — Dust ring (light grey expanding cloud) —
	var dust := GPUParticles2D.new()
	dust.emitting  = true
	dust.one_shot  = true
	dust.amount    = 12
	dust.lifetime  = 0.45
	dust.global_position = pos
	var dustmat := ParticleProcessMaterial.new()
	dustmat.direction             = Vector3(0, 0, 0)
	dustmat.spread                = 180.0
	dustmat.initial_velocity_min  = 20.0
	dustmat.initial_velocity_max  = 50.0
	dustmat.gravity               = Vector3.ZERO
	dustmat.scale_min             = 10.0
	dustmat.scale_max             = 20.0
	dustmat.color                 = Color(0.80, 0.78, 0.72, 0.65)  # dusty grey
	dust.process_material         = dustmat
	dust.finished.connect(dust.queue_free)
	root.add_child(dust)

	# — Flash (brief orange-yellow spark) —
	var flash := GPUParticles2D.new()
	flash.emitting  = true
	flash.one_shot  = true
	flash.amount    = 8
	flash.lifetime  = 0.20
	flash.global_position = pos
	var fmat := ParticleProcessMaterial.new()
	fmat.direction             = Vector3(0, 0, 0)
	fmat.spread                = 180.0
	fmat.initial_velocity_min  = 30.0
	fmat.initial_velocity_max  = 70.0
	fmat.gravity               = Vector3.ZERO
	fmat.scale_min             = 5.0
	fmat.scale_max             = 10.0
	fmat.color                 = Color(1.0, 0.72, 0.10, 0.90)
	flash.process_material     = fmat
	flash.finished.connect(flash.queue_free)
	root.add_child(flash)

## Save immediately without requiring a new record. Used by the tutorial system.
func force_save() -> void:
	_save()

func _save() -> void:
	var data := {"record_wave": record_wave, "player_name": player_name, "tutorial_plays": tutorial_plays, "voice_language": voice_language, "saved_friends": saved_friends}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		record_wave = int(parsed.get("record_wave", 0))
		player_name = str(parsed.get("player_name", "SURVIVOR"))
		tutorial_plays = int(parsed.get("tutorial_plays", 0))
		voice_language = str(parsed.get("voice_language", "en"))
		var raw_friends = parsed.get("saved_friends", [])
		if raw_friends is Array:
			saved_friends = raw_friends
