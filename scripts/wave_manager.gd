extends Node

# Predefined story-driven wave configs.
# Waves beyond this array are auto-generated using the formula: 20 + wave * 5 enemies.
const WAVE_CONFIGS: Array = [
	{
		"wave": 1,
		"enemy_count": 25,
		"title": "WAVE 1",
		"subtitle": "Enemy forces advancing on Sector 7.\nHold the line, soldier.",
		"speed_bonus": 0.0,
		"health_bonus": 0,
	},
	{
		"wave": 2,
		"enemy_count": 30,
		"title": "WAVE 2",
		"subtitle": "Reinforcements confirmed inbound.\nThey are getting organized. Stay sharp.",
		"speed_bonus": 8.0,
		"health_bonus": 10,
	},
]

func get_wave_config(wave_number: int) -> Dictionary:
	if wave_number <= WAVE_CONFIGS.size():
		return WAVE_CONFIGS[wave_number - 1]
	# Auto-generate beyond predefined waves: +5 enemies each wave
	var count := 20 + wave_number * 5
	return {
		"wave": wave_number,
		"enemy_count": count,
		"title": "WAVE " + str(wave_number),
		"subtitle": "More hostiles inbound. Stay disciplined, stay alive.",
		"speed_bonus": float(wave_number - 1) * 8.0,
		"health_bonus": (wave_number - 1) * 10,
	}
