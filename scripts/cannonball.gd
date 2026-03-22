extends Node2D

## Cannonball fired by CannonSoldier.
## Damages walls on contact only — passes through players and other enemies.
## Self-destructs on wall hit or after a fixed lifetime.

var direction: Vector2 = Vector2.RIGHT
var speed := 380.0
var wall_damage := 35

var _lifetime := 1.8  # seconds before auto-expire

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Dark iron cannonball with a small highlight
	draw_circle(Vector2.ZERO, 9.0, Color(0.18, 0.18, 0.18, 1.0))
	draw_circle(Vector2(-3, -3), 3.0, Color(0.4, 0.4, 0.4, 0.6))

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

func _on_hit_area_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(wall_damage)
	queue_free()
