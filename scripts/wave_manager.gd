extends Node

# Predefined story-driven wave configs.
# Waves beyond this array are auto-generated using the formula: 20 + wave * 5 enemies.
const WAVE_CONFIGS: Array = [
	{
		"wave": 1,
		"enemy_count": 5,
		"title": "WAVE_1_TITLE",
		"subtitle": "WAVE_1_SUBTITLE",
		"speed_bonus": 0.0,
		"health_bonus": 0,
	},
	{
		"wave": 2,
		"enemy_count": 12,
		"title": "WAVE_2_TITLE",
		"subtitle": "WAVE_2_SUBTITLE",
		"speed_bonus": 8.0,
		"health_bonus": 10,
	},
	{
		"wave": 3,
		"enemy_count": 19,
		"title": "WAVE_3_TITLE",
		"subtitle": "WAVE_3_SUBTITLE",
		"speed_bonus": 16.0,
		"health_bonus": 20,
	},
	{
		"wave": 4,
		"enemy_count": 25,
		"title": "WAVE_4_TITLE",
		"subtitle": "WAVE_4_SUBTITLE",
		"speed_bonus": 24.0,
		"health_bonus": 30,
	},
	{
		"wave": 5,
		"enemy_count": 31,
		"title": "WAVE_5_TITLE",
		"subtitle": "WAVE_5_SUBTITLE",
		"speed_bonus": 32.0,
		"health_bonus": 40,
	},
	{
		"wave": 6,
		"enemy_count": 36,
		"title": "WAVE_6_TITLE",
		"subtitle": "WAVE_6_SUBTITLE",
		"speed_bonus": 40.0,
		"health_bonus": 50,
	},
	{
		"wave": 7,
		"enemy_count": 1,
		"title": "WAVE_7_TITLE",
		"subtitle": "WAVE_7_SUBTITLE",
		"speed_bonus": 0.0,
		"health_bonus": 60,
	},
]

func get_wave_config(wave_number: int) -> Dictionary:
	var cfg: Dictionary
	if wave_number <= WAVE_CONFIGS.size():
		cfg = WAVE_CONFIGS[wave_number - 1].duplicate()
	else:
		# Auto-generate: 20 + wave*5 enemies, +8 speed and +10 health per wave beyond defined
		var count := int((20 + wave_number * 5) * 0.9)
		cfg = {
			"wave": wave_number,
			"enemy_count": count,
			"title": "WAVE_AUTO_TITLE",
			"subtitle": "WAVE_AUTO_SUBTITLE",
			"speed_bonus": float(wave_number - 1) * 8.0,
			"health_bonus": (wave_number - 1) * 10,
		}
	# ── Weekly operation modifier ─────────────────────────────────────────────
	var op_modifier: String = ProgressionManager.weekly_op.get("modifier", "normal")
	match op_modifier:
		"double_bugs":
			cfg["op_double_bugs"] = true
		"no_towers":
			cfg["op_no_towers"] = true
		"elite_enemies":
			cfg["health_bonus"] = cfg.get("health_bonus", 0) + 20
			cfg["speed_bonus"]  = cfg.get("speed_bonus", 0.0) + 15.0
		"fast_waves":
			cfg["op_fast_waves"] = true  # main.gd reads this flag to shorten build timer
		"coin_frenzy":
			cfg["op_coin_frenzy"] = true  # coin.gd reads this flag for double drop
		"pistol_only":
			cfg["op_pistol_only"] = true  # main.gd enforces weapon lock
	return cfg
