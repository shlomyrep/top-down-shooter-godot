extends Area2D

## Recovery station — lets the player buy health packs and shields.
## Emits player_entered / player_exited signals (same pattern as buy_station).

const DWELL_TIME := 1.5

signal player_entered(station: Node)
signal player_exited

@onready var _dwell_bar: ProgressBar = $DwellBar
@onready var _icon_label: Node2D = $NameLabel

var _player_inside := false
var _dwell_timer: Timer
var _dwell_tween: Tween
var _float_tween: Tween

func _ready() -> void:
	_dwell_timer = Timer.new()
	_dwell_timer.one_shot = true
	_dwell_timer.wait_time = DWELL_TIME
	_dwell_timer.timeout.connect(_on_dwell_complete)
	add_child(_dwell_timer)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_start_float()

func _start_float() -> void:
	var base_y := _icon_label.position.y
	_float_tween = create_tween()
	_float_tween.set_loops()
	_float_tween.tween_property(_icon_label, "position:y", base_y - 8.0, 1.1) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_float_tween.tween_property(_icon_label, "position:y", base_y, 1.1) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_dwell_bar.value = 0.0
	_dwell_bar.visible = true
	_dwell_timer.start(DWELL_TIME)
	if _dwell_tween:
		_dwell_tween.kill()
	_dwell_tween = create_tween()
	_dwell_tween.tween_property(_dwell_bar, "value", 100.0, DWELL_TIME)

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	_dwell_timer.stop()
	if _dwell_tween:
		_dwell_tween.kill()
	_dwell_bar.value = 0.0
	_dwell_bar.visible = false
	player_exited.emit()

func _on_dwell_complete() -> void:
	if _dwell_tween:
		_dwell_tween.kill()
	_dwell_bar.visible = false
	player_entered.emit(self)
