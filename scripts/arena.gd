extends Node2D

## Draws the arena background with grass patterns, grid, and boundary walls

const ARENA_W := 3200
const ARENA_H := 2400
const TILE := 80
const WALL_THICKNESS := 40.0

func _draw() -> void:
	# Ground
	draw_rect(Rect2(0, 0, ARENA_W, ARENA_H), Color(0.18, 0.42, 0.18, 1.0))

	# Checkerboard grass pattern
	var light_grass := Color(0.22, 0.48, 0.22, 1.0)
	for x in range(0, ARENA_W, TILE):
		for y in range(0, ARENA_H, TILE):
			if (x / TILE + y / TILE) % 2 == 0:
				draw_rect(Rect2(x, y, TILE, TILE), light_grass)

	# Grid lines (subtle)
	var grid_color := Color(0.15, 0.38, 0.15, 0.3)
	for x in range(0, ARENA_W + 1, TILE):
		draw_line(Vector2(x, 0), Vector2(x, ARENA_H), grid_color, 1.0)
	for y in range(0, ARENA_H + 1, TILE):
		draw_line(Vector2(0, y), Vector2(ARENA_W, y), grid_color, 1.0)

	# Arena border walls (dark thick edges)
	var wall_color := Color(0.35, 0.25, 0.15, 1.0)
	var border_outline := Color(0.2, 0.15, 0.08, 1.0)
	# Top
	draw_rect(Rect2(-WALL_THICKNESS, -WALL_THICKNESS, ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), wall_color)
	# Bottom
	draw_rect(Rect2(-WALL_THICKNESS, ARENA_H, ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), wall_color)
	# Left
	draw_rect(Rect2(-WALL_THICKNESS, 0, WALL_THICKNESS, ARENA_H), wall_color)
	# Right
	draw_rect(Rect2(ARENA_W, 0, WALL_THICKNESS, ARENA_H), wall_color)

	# Border outline
	draw_rect(Rect2(-WALL_THICKNESS, -WALL_THICKNESS, ARENA_W + WALL_THICKNESS * 2, ARENA_H + WALL_THICKNESS * 2), border_outline, false, 3.0)

	# Some decorative bushes/obstacles
	var bush_color := Color(0.12, 0.55, 0.12, 0.7)
	_draw_bush(Vector2(400, 300), 60.0, bush_color)
	_draw_bush(Vector2(800, 800), 50.0, bush_color)
	_draw_bush(Vector2(2200, 500), 70.0, bush_color)
	_draw_bush(Vector2(1600, 1800), 55.0, bush_color)
	_draw_bush(Vector2(2800, 1600), 65.0, bush_color)
	_draw_bush(Vector2(600, 2000), 45.0, bush_color)
	_draw_bush(Vector2(2400, 1200), 50.0, bush_color)

	# Some rocks/walls for cover
	var rock_color := Color(0.45, 0.4, 0.35, 1.0)
	draw_rect(Rect2(700, 500, 160, 40), rock_color)
	draw_rect(Rect2(700, 500, 160, 40), Color(0.3, 0.25, 0.2, 1.0), false, 2.0)
	draw_rect(Rect2(1800, 900, 40, 160), rock_color)
	draw_rect(Rect2(1800, 900, 40, 160), Color(0.3, 0.25, 0.2, 1.0), false, 2.0)
	draw_rect(Rect2(2400, 400, 120, 40), rock_color)
	draw_rect(Rect2(2400, 400, 120, 40), Color(0.3, 0.25, 0.2, 1.0), false, 2.0)
	draw_rect(Rect2(1000, 1600, 40, 200), rock_color)
	draw_rect(Rect2(1000, 1600, 40, 200), Color(0.3, 0.25, 0.2, 1.0), false, 2.0)

func _draw_bush(pos: Vector2, radius: float, color: Color) -> void:
	draw_circle(pos, radius, color)
	draw_circle(pos + Vector2(radius * 0.5, -radius * 0.3), radius * 0.7, color)
	draw_circle(pos + Vector2(-radius * 0.4, -radius * 0.4), radius * 0.6, color)
