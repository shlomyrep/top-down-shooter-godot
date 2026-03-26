extends Node

const SAVE_PATH := "user://save.json"

var record_wave: int = 0
var player_name: String = "SURVIVOR"
var _last_wave_reached: int = 0

# ── Multiplayer session state (reset each lobby entry) ────────────────────────
var is_multiplayer: bool = false
var is_host: bool        = false
var room_id: String      = ""
var partner_name: String = ""

func reset_multiplayer() -> void:
	is_multiplayer = false
	is_host        = false
	room_id        = ""
	partner_name   = ""

func _ready() -> void:
	_load()

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

func _save() -> void:
	var data := {"record_wave": record_wave, "player_name": player_name}
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
