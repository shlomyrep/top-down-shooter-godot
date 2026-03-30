## SoundManager — Autoloaded global audio controller for Resistance.
##
## Architecture:
##   • 5 audio buses: Music, SFX, Voice (radio-filtered), UI, Ambient
##   • 2  AudioStreamPlayer  for music crossfade (A/B)
##   • 1  AudioStreamPlayer  for priority voice queue
##   • 1  AudioStreamPlayer  for UI sounds
##   • 1  AudioStreamPlayer  for ambient loop
##   • 8  AudioStreamPlayer2D pool for weapon shots (handles LMG @ 16/s)
##   • 1  AudioStreamPlayer2D dedicated LMG looping player
##   • 14 AudioStreamPlayer2D pool for spatial SFX (enemies, structures, world)
##
## All methods are no-ops when the audio file doesn't exist yet —
## the game runs fine before any .ogg files are provided.
extends Node

# ─── Bus indices (resolved in _setup_buses) ─────────────────────────────────
var _bus_music   := -1
var _bus_sfx     := -1
var _bus_voice   := -1
var _bus_ui      := -1
var _bus_ambient := -1
var _buses_ready := false

# ─── Music crossfade ──────────────────────────────────────────────────────────
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active := "a"   # "a" or "b" — which player owns the current track
var _current_music := ""
var _music_duck_tween: Tween = null

const MUSIC_VOL_DB   := -10.0
const SFX_VOL_DB     := 0.0
const VOICE_VOL_DB   := 2.0
const UI_VOL_DB      := -5.0
const AMBIENT_VOL_DB := -22.0

# ─── Voice queue ─────────────────────────────────────────────────────────────
var _voice_player: AudioStreamPlayer
var _voice_queue: Array = []          # Array of {stream, priority}
var _voice_current_priority := -1

enum VoicePriority { NORMAL = 0, HIGH = 1, CRITICAL = 2 }

# ─── UI / Ambient ─────────────────────────────────────────────────────────────
var _ui_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer

# ─── Weapon pool (round-robin, 8 slots) ──────────────────────────────────────
const WEAPON_POOL_SIZE := 8
var _weapon_pool: Array[AudioStreamPlayer2D] = []
var _weapon_pool_idx := 0

# ─── LMG dedicated looping player ────────────────────────────────────────────
var _lmg_player: AudioStreamPlayer2D
var _lmg_active := false

# ─── Spatial SFX pool (round-robin, 14 slots) ────────────────────────────────
const SFX_POOL_SIZE := 14
var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _sfx_pool_idx := 0

# ─── Build timer warning guard ────────────────────────────────────────────────
var _build_warning_played := false

# ─── Stream cache (lazy-load, keyed by full res:// path) ─────────────────────
var _cache: Dictionary = {}

const _SFX_PATH   := "res://assets/audio/sfx/"
const _MUSIC_PATH := "res://assets/audio/music/"
const _VOICE_PATH := "res://assets/audio/voice/"

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_buses()
	_build_players()

# ─── Bus Setup ───────────────────────────────────────────────────────────────
func _setup_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true

	for bus_name: String in ["Music", "SFX", "Voice", "UI", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

	_bus_music   = AudioServer.get_bus_index("Music")
	_bus_sfx     = AudioServer.get_bus_index("SFX")
	_bus_voice   = AudioServer.get_bus_index("Voice")
	_bus_ui      = AudioServer.get_bus_index("UI")
	_bus_ambient = AudioServer.get_bus_index("Ambient")

	# Music bus — soft compressor so BGM doesn't swamp combat SFX
	_add_effect_once(_bus_music, AudioEffectCompressor, func(e: AudioEffectCompressor):
		e.ratio     = 4.0
		e.threshold = -18.0
		e.attack_us = 20000.0
		e.release_ms = 250.0)

	# SFX bus — small room reverb for arena depth
	_add_effect_once(_bus_sfx, AudioEffectReverb, func(e: AudioEffectReverb):
		e.room_size = 0.15
		e.wet       = 0.08)

	# Voice bus — radio chain: HPF 300 Hz → LPF 3500 Hz → light overdrive
	var vi := _bus_voice
	while AudioServer.get_bus_effect_count(vi) > 0:
		AudioServer.remove_bus_effect(vi, 0)
	var hpf := AudioEffectHighPassFilter.new()
	hpf.cutoff_hz = 300.0
	AudioServer.add_bus_effect(vi, hpf)
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = 3500.0
	AudioServer.add_bus_effect(vi, lpf)
	var dist := AudioEffectDistortion.new()
	dist.mode      = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive     = 0.12
	dist.post_gain = -4.0
	AudioServer.add_bus_effect(vi, dist)

func _add_effect_once(bus_idx: int, effect_class, configure: Callable) -> void:
	if AudioServer.get_bus_effect_count(bus_idx) > 0:
		return  # already added (autoload persists across scenes)
	var effect = effect_class.new()
	configure.call(effect)
	AudioServer.add_bus_effect(bus_idx, effect)

# ─── Player Construction ──────────────────────────────────────────────────────
func _build_players() -> void:
	# Music A (starts active)
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	_music_a.volume_db = MUSIC_VOL_DB
	add_child(_music_a)

	# Music B (starts silent, used as crossfade target)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	_music_b.volume_db = -80.0
	add_child(_music_b)

	# Voice
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voice"
	_voice_player.volume_db = VOICE_VOL_DB
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

	# UI
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "UI"
	_ui_player.volume_db = UI_VOL_DB
	add_child(_ui_player)

	# Ambient
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.volume_db = AMBIENT_VOL_DB
	add_child(_ambient_player)

	# Weapon pool
	for _i in WEAPON_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 1600.0
		p.attenuation  = 1.0
		add_child(p)
		_weapon_pool.append(p)

	# LMG dedicated looping player
	_lmg_player = AudioStreamPlayer2D.new()
	_lmg_player.bus = "SFX"
	_lmg_player.max_distance = 1600.0
	add_child(_lmg_player)

	# Spatial SFX pool
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 1600.0
		p.attenuation  = 1.2
		add_child(p)
		_sfx_pool.append(p)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Play background music by name (no extension). Pass "" to fade out.
## Crossfades over fade_sec seconds.
func play_music(track_name: String, fade_sec: float = 1.5) -> void:
	if track_name == _current_music:
		return
	_current_music = track_name

	var outgoing: AudioStreamPlayer = _music_a if _music_active == "a" else _music_b
	var incoming: AudioStreamPlayer = _music_b if _music_active == "a" else _music_a
	_music_active = "b" if _music_active == "a" else "a"

	# Fade out the current track
	_tween_vol_player(outgoing, outgoing.volume_db, -80.0, fade_sec)

	if track_name.is_empty():
		incoming.stop()
		return

	var stream := _load_music(track_name)
	if not stream:
		return

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_tween_vol_player(incoming, -80.0, MUSIC_VOL_DB, fade_sec)

## Play a non-spatial SFX (build actions, UI feedback, etc.)
func play_sfx(sound_name: String) -> void:
	var stream := _load_sfx(sound_name)
	if not stream:
		return
	var p := _next_sfx()
	p.global_position = Vector2.ZERO
	p.max_distance = 999999.0   # effectively global — no attenuation
	p.stream = stream
	p.play()

## Play a spatially-positioned in-world SFX.
func play_sfx_2d(sound_name: String, world_pos: Vector2) -> void:
	var stream := _load_sfx(sound_name)
	if not stream:
		return
	var p := _next_sfx()
	p.global_position = world_pos
	p.max_distance = 1600.0
	p.stream = stream
	p.play()

## Play a weapon shot sound from the weapon pool at a world position.
func play_weapon(sound_name: String, world_pos: Vector2) -> void:
	var stream := _load_sfx(sound_name)
	if not stream:
		return
	var p := _next_weapon()
	p.global_position = world_pos
	p.stream = stream
	p.play()

## Start the LMG loop (call each frame while firing, it guards internally).
func start_lmg(world_pos: Vector2) -> void:
	_lmg_player.global_position = world_pos
	if _lmg_active:
		return
	var stream := _load_sfx("lmg_shoot_loop")
	if not stream:
		return
	_lmg_active = true
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_lmg_player.stream = stream
	_lmg_player.play()
	play_weapon("lmg_spinup", world_pos)

## Stop the LMG loop.
func stop_lmg() -> void:
	if not _lmg_active:
		return
	_lmg_active = false
	_lmg_player.stop()

## Play a UI sound (goes through the UI bus, no spatial attenuation).
func play_ui(sound_name: String) -> void:
	var stream := _load_sfx(sound_name)
	if not stream:
		return
	_ui_player.stream = stream
	_ui_player.play()

## Play the ambient loop (guard: won't restart the same track).
func play_ambient(sound_name: String) -> void:
	var stream := _load_sfx(sound_name)
	if not stream:
		return
	if _ambient_player.playing and _ambient_player.stream == stream:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambient_player.stream = stream
	_ambient_player.play()

## Queue a voice line. CRITICAL interrupts any current line.
## HIGH interrupts NORMAL. Duplicate NORMAL lines while one is playing are dropped.
func play_voice(voice_name: String, priority: int = VoicePriority.NORMAL) -> void:
	var stream := _load_voice(voice_name)
	if not stream:
		return
	if _voice_player.playing:
		if priority > _voice_current_priority:
			# Interrupt lower-priority line
			_voice_player.stop()
			_voice_queue.clear()
		elif priority == VoicePriority.NORMAL:
			return  # Drop NORMAL when something is already playing
	_voice_queue.append({"stream": stream, "priority": priority})
	if not _voice_player.playing:
		_play_next_voice()

## Called by main.gd every frame during build phase to trigger 5s countdown beep.
func notify_build_timer(time_left: float) -> void:
	if not _build_warning_played and time_left > 0.0 and time_left <= 5.0:
		_build_warning_played = true
		play_sfx("build_timer_warning")

## Call when build phase begins (resets warning, swaps music, starts ambient).
func on_build_start() -> void:
	_build_warning_played = false
	play_music("build_bg")
	play_ambient("ambient_wind")

## Full reset — call on scene change / game restart.
func reset() -> void:
	stop_lmg()
	_voice_queue.clear()
	_voice_player.stop()
	_voice_current_priority = -1
	_build_warning_played = false
	_current_music = ""
	_music_a.stop()
	_music_b.stop()
	_music_a.volume_db = MUSIC_VOL_DB
	_music_b.volume_db = -80.0
	_music_active = "a"
	_ambient_player.stop()
	if _bus_music >= 0:
		AudioServer.set_bus_volume_db(_bus_music, 0.0)

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _on_voice_finished() -> void:
	_duck_music(false)
	_play_next_voice()

func _play_next_voice() -> void:
	if _voice_queue.is_empty():
		_voice_current_priority = -1
		return
	# Sort highest priority first
	_voice_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.priority > b.priority)
	var entry: Dictionary = _voice_queue.pop_front()
	_voice_current_priority = entry.priority
	_voice_player.stream = entry.stream
	_voice_player.play()
	_duck_music(true)

func _duck_music(duck: bool) -> void:
	if _bus_music < 0:
		return
	if _music_duck_tween:
		_music_duck_tween.kill()
	_music_duck_tween = create_tween()
	var current_db := AudioServer.get_bus_volume_db(_bus_music)
	var target_db  := MUSIC_VOL_DB - 7.0 if duck else 0.0
	_music_duck_tween.tween_method(
		func(v: float): AudioServer.set_bus_volume_db(_bus_music, v),
		current_db, target_db, 0.25)

func _tween_vol_player(player: AudioStreamPlayer, from_db: float, to_db: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float): player.volume_db = v, from_db, to_db, dur)

func _next_weapon() -> AudioStreamPlayer2D:
	_weapon_pool_idx = (_weapon_pool_idx + 1) % WEAPON_POOL_SIZE
	return _weapon_pool[_weapon_pool_idx]

func _next_sfx() -> AudioStreamPlayer2D:
	_sfx_pool_idx = (_sfx_pool_idx + 1) % SFX_POOL_SIZE
	var p := _sfx_pool[_sfx_pool_idx]
	if p.playing:
		p.stop()
	return p

func _load_sfx(name: String) -> AudioStream:
	return _load(_SFX_PATH + name + ".ogg")

func _load_music(name: String) -> AudioStream:
	return _load(_MUSIC_PATH + name + ".ogg")

func _load_voice(name: String) -> AudioStream:
	return _load(_VOICE_PATH + name + ".ogg")

func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null   # cache the miss so we don't stat every frame
		return null
	var stream := load(path) as AudioStream
	_cache[path] = stream
	return stream
