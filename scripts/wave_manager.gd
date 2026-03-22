extends Node

# Predefined story-driven wave configs.
# Waves beyond this array are auto-generated using the formula: 20 + wave * 5 enemies.
const WAVE_CONFIGS: Array = [
	{
		"wave": 1,
		"enemy_count": 5,
		"title": "WAVE 1",
		"subtitle": "Enemy forces advancing on Sector 7.\nHold the line, soldier.",
		"speed_bonus": 0.0,
		"health_bonus": 0,
	},
	{
		"wave": 2,
		"enemy_count": 12,
		"title": "WAVE 2",
		"subtitle": "Reinforcements confirmed inbound.\nThey are getting organized. Stay sharp.",
		"speed_bonus": 8.0,
		"health_bonus": 10,
	},
	{
		"wave": 3,
		"enemy_count": 19,
		"title": "WAVE 3",
		"subtitle": "New threat detected. Unknown hostiles inbound.\nThey explode on contact. Keep your distance.",
		"speed_bonus": 16.0,
		"health_bonus": 20,
	},
	{
		"wave": 4,
		"enemy_count": 25,
		"title": "WAVE 4",
		"subtitle": "They are pushing harder. No signs of slowing down.\nDefend your perimeter.",
		"speed_bonus": 24.0,
		"health_bonus": 30,
	},
	{
		"wave": 5,
		"enemy_count": 31,
		"title": "WAVE 5",
		"subtitle": "Heavy units inbound. Cannon soldiers target your walls.\nReinforce your defenses before they breach.",
		"speed_bonus": 32.0,
		"health_bonus": 40,
	},
	{
		"wave": 6,
		"enemy_count": 36,
		"title": "WAVE 6",
		"subtitle": "They are adapting. More cannons, more firepower.\nFortify and hold.",
		"speed_bonus": 40.0,
		"health_bonus": 50,
	},
	{
		"wave": 7,
		"enemy_count": 40,
		"title": "WAVE 7",
		"subtitle": "ARMORED UNIT DETECTED. A tank is leading the assault.\nTarget it before it tears down your walls.",
		"speed_bonus": 48.0,
		"health_bonus": 60,
	},
]

func get_wave_config(wave_number: int) -> Dictionary:
	if wave_number <= WAVE_CONFIGS.size():
		return WAVE_CONFIGS[wave_number - 1]
	# Auto-generate: 20 + wave*5 enemies, +8 speed and +10 health per wave beyond defined
	var count := int((20 + wave_number * 5) * 0.9)
	return {
		"wave": wave_number,
		"enemy_count": count,
		"title": "WAVE " + str(wave_number),
		"subtitle": "More hostiles inbound. Stay disciplined, stay alive.",
		"speed_bonus": float(wave_number - 1) * 8.0,
		"health_bonus": (wave_number - 1) * 10,
	}
