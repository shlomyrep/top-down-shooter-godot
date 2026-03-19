extends Area2D

## Weapon buy station. Place in the arena at a position reachable after opening
## the base doors.  weapon_id must match a key in WeaponManager.WEAPONS.

@export var weapon_id := "shotgun"

signal player_entered(station: Node)
signal player_exited
signal buy_requested(weapon_id: String, cost: int)

var _player_inside := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if _player_inside and event.is_action_pressed("interact"):
		var w: Dictionary = WeaponManager.WEAPONS[weapon_id]
		buy_requested.emit(weapon_id, w["cost"])

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		player_entered.emit(self)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		player_exited.emit()
