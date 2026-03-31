extends Node

# ─── Weapon definitions ───────────────────────────────────────────────────────
const WEAPONS: Dictionary = {
	"pistol": {
		"name":         "WEAPON_PISTOL",
		"cost":         0,
		"damage":       20,
		"cooldown":     0.25,
		"pellets":      1,
		"spread":       0.0,
		"bullet_speed": 900.0,
		"bullet_color": Color(1.0, 0.9, 0.3, 1.0),
		"bullet_scale": 1.0,
	},
	"shotgun": {
		"name":         "WEAPON_SHOTGUN",
		"cost":         75,
		"damage":       15,
		"cooldown":     0.7,
		"pellets":      5,
		"spread":       0.30,
		"bullet_speed": 700.0,
		"bullet_color": Color(1.0, 0.5, 0.1, 1.0),
		"bullet_scale": 0.7,
	},
	"rifle": {
		"name":         "WEAPON_RIFLE",
		"cost":         150,
		"damage":       35,
		"cooldown":     0.10,
		"pellets":      1,
		"spread":       0.0,
		"bullet_speed": 1200.0,
		"bullet_color": Color(0.3, 0.8, 1.0, 1.0),
		"bullet_scale": 1.3,
	},
	"lmg": {
		"name":         "WEAPON_LMG",
		"cost":         250,
		"damage":       18,
		"cooldown":     0.06,
		"pellets":      1,
		"spread":       0.12,
		"bullet_speed": 900.0,
		"bullet_color": Color(1.0, 0.3, 0.3, 1.0),
		"bullet_scale": 0.85,
	},
}

# ─── State ────────────────────────────────────────────────────────────────────
var current_weapon := "pistol"

func get_current() -> Dictionary:
	return WEAPONS[current_weapon]

func equip(weapon_id: String) -> void:
	if WEAPONS.has(weapon_id):
		current_weapon = weapon_id
