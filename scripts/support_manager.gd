extends Node

## Tracks cooldowns and costs for player support callables.
## Autoloaded as "SupportManager".

const AIRSTRIKE_COST     := 80
const SQUAD_COST         := 50
const SHIELD_SQUAD_COST  := 90

const AIRSTRIKE_COOLDOWN    := 45.0
const SQUAD_COOLDOWN        := 30.0
const SHIELD_SQUAD_COOLDOWN := 40.0

# Remaining cooldown seconds (0 = ready)
var airstrike_cd    := 0.0
var squad_cd        := 0.0
var shield_squad_cd := 0.0

signal cooldowns_updated

func _process(delta: float) -> void:
	var changed := false
	if airstrike_cd > 0.0:
		airstrike_cd = maxf(0.0, airstrike_cd - delta)
		changed = true
	if squad_cd > 0.0:
		squad_cd = maxf(0.0, squad_cd - delta)
		changed = true
	if shield_squad_cd > 0.0:
		shield_squad_cd = maxf(0.0, shield_squad_cd - delta)
		changed = true
	if changed:
		cooldowns_updated.emit()

func can_airstrike(coins: int) -> bool:
	return airstrike_cd <= 0.0 and coins >= AIRSTRIKE_COST

func can_squad(coins: int) -> bool:
	return squad_cd <= 0.0 and coins >= SQUAD_COST

func can_shield_squad(coins: int) -> bool:
	return shield_squad_cd <= 0.0 and coins >= SHIELD_SQUAD_COST

func use_airstrike() -> void:
	airstrike_cd = AIRSTRIKE_COOLDOWN

func use_squad() -> void:
	squad_cd = SQUAD_COOLDOWN

func use_shield_squad() -> void:
	shield_squad_cd = SHIELD_SQUAD_COOLDOWN
