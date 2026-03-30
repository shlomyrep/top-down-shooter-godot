class_name DepenetrationHelper

## Layer 6 bitmask (walls + doors).  Nothing else should be 32.
const WALL_MASK  := 32
## Speed (px/s) added to push a character clear of an overlapping wall/door.
const PUSH_SPEED := 200.0

## Call AFTER setting body.velocity and BEFORE move_and_slide().
## Detects overlap with any wall or door and blends a push component into
## body.velocity so the character visibly slides out instead of staying stuck.
static func resolve(body: CharacterBody2D, _delta: float) -> void:
	var space := body.get_world_2d().direct_space_state
	if not space:
		return

	var owners := body.get_shape_owners()
	if owners.is_empty():
		return
	var owner_id: int = owners[0]
	if body.shape_owner_get_shape_count(owner_id) == 0:
		return
	var shape: Shape2D = body.shape_owner_get_shape(owner_id, 0)
	if not shape:
		return

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape     = shape
	params.transform = body.global_transform * body.shape_owner_get_transform(owner_id)
	params.collision_mask     = WALL_MASK
	params.exclude            = [body.get_rid()]
	params.collide_with_bodies = true
	params.collide_with_areas  = false

	var results := space.intersect_shape(params, 8)
	if results.is_empty():
		return

	var push := Vector2.ZERO
	for hit: Dictionary in results:
		var collider: Object = hit.get("collider")
		if not collider or not collider is Node2D:
			continue
		var diff: Vector2 = body.global_position - (collider as Node2D).global_position
		if diff.is_zero_approx():
			diff = Vector2.RIGHT  # fallback when centres exactly coincide
		push += diff.normalized()

	if not push.is_zero_approx():
		body.velocity += push.normalized() * PUSH_SPEED
