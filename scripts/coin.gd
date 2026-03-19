extends Area2D

@export var value := 10

signal collected(amount: int)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Gentle coin bob animation
	var start_y := position.y
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position:y", start_y - 5.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", start_y, 0.4).set_ease(Tween.EASE_IN_OUT)

func _on_body_entered(_body: Node) -> void:
	collected.emit(value)
	queue_free()
