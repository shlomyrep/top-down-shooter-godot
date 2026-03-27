extends Node2D

## Draws the arena background — "Ghost Op" dark tactical battlefield aesthetic.
## Dark concrete/dirt floor with battle damage marks, tread scars, rubble clusters,
## and a concrete-bunker border.  No bright checkerboard; entities pop forward naturally.

const ARENA_W        := 3200
const ARENA_H        := 2400
const TILE           := 80
const WALL_THICKNESS := 40.0

# Pre-computed scatter data (deterministic: no RNG in _draw to keep frame-stable)
# Format: [x, y, radius] for damage blotches
const _DAMAGE_MARKS: Array = [
	[180, 220, 28], [430, 90, 18], [760, 340, 32], [920, 680, 14], [1140, 210, 24],
	[1380, 510, 20], [1540, 820, 36], [1720, 140, 16], [1960, 440, 28], [2080, 760, 22],
	[2310, 180, 30], [2560, 520, 18], [2740, 280, 26], [2980, 640, 20], [3080, 180, 14],
	[320, 1100, 22], [600, 1340, 32], [850, 1060, 18], [1080, 1480, 28], [1300, 1200, 14],
	[1460, 1700, 24], [1680, 1340, 36], [1900, 1780, 20], [2140, 1100, 30], [2360, 1460, 16],
	[2600, 1200, 26], [2820, 1640, 22], [3020, 1360, 18], [140, 1880, 32], [400, 2120, 20],
	[720, 1960, 28], [980, 2280, 16], [1200, 2080, 24], [1460, 2200, 30], [1700, 2060, 18],
	[1940, 2280, 22], [2200, 2060, 28], [2460, 2160, 16], [2720, 2000, 32], [2960, 2220, 20],
	[540, 560, 16], [1240, 960, 20], [2000, 1560, 14], [2680, 880, 18], [1080, 2040, 24],
	[380, 1680, 18], [1820, 620, 22], [2460, 300, 14], [680, 2200, 20], [2940, 1000, 26],
	[120, 400, 12], [1600, 600, 16], [2200, 1700, 20], [800, 1500, 14], [2800, 300, 18],
	[1400, 100, 22], [100, 1600, 16], [3000, 800, 24], [1800, 2200, 18], [600, 700, 12],
]
# Tread-mark lines: [x, y, w, h, angle_deg]
const _TREAD_MARKS: Array = [
	[340, 480, 200, 5, 12], [820, 200, 180, 4, -8], [1200, 740, 220, 5, 15],
	[1600, 400, 190, 4, -11], [2000, 860, 210, 5, 9], [2400, 360, 200, 4, -14],
	[2800, 760, 180, 5, 12], [480, 1200, 200, 4, -9], [1000, 1560, 220, 5, 13],
	[1480, 1140, 190, 4, -10], [1900, 1420, 200, 5, 8], [2300, 1640, 210, 4, -15],
	[2700, 1260, 180, 5, 11], [300, 1800, 200, 4, -12], [900, 2140, 190, 5, 14],
]
# Micro-cracks in the concrete: [x1, y1, x2, y2]
const _CRACKS: Array = [
	[240, 380, 295, 408], [680, 178, 742, 225], [1100, 520, 1176, 492],
	[1500, 280, 1548, 338], [1900, 682, 1978, 652], [2350, 380, 2398, 440],
	[2720, 200, 2792, 238], [480, 1100, 558, 1138], [920, 1482, 998, 1444],
	[1448, 1162, 1528, 1198], [1880, 1458, 1958, 1488], [2582, 1362, 2648, 1400],
	[340, 1860, 418, 1898], [780, 2102, 858, 2062], [2160, 1958, 2238, 1998],
]
# Tiny pebbles/stones: [x, y, radius]
const _PEBBLES: Array = [
	[320, 458, 3], [540, 268, 2], [762, 622, 4], [982, 382, 2], [1198, 820, 3],
	[1442, 558, 4], [1682, 242, 2], [1922, 562, 3], [2162, 380, 2], [2378, 678, 4],
	[2638, 262, 3], [2860, 542, 2], [420, 1258, 4], [702, 1542, 2], [1062, 1318, 3],
	[1338, 1642, 2], [1742, 1362, 4], [2042, 1598, 3], [2338, 1278, 2], [2858, 1918, 3],
]

func _draw() -> void:
	# --- BASE GROUND: dark tactical concrete, just bright enough for shadows to show ---
	draw_rect(Rect2(0, 0, ARENA_W, ARENA_H), Color(0.155, 0.165, 0.142, 1.0))

	# --- ALT TILE LAYER: barely-visible warm-cool variation ---
	var alt_color := Color(0.182, 0.194, 0.168, 1.0)
	# Use 2×2-tile blocks to give a very subtle large-grid texture without "graph paper" buzz
	for bx in range(0, ARENA_W, TILE * 4):
		for by in range(0, ARENA_H, TILE * 4):
			if ((bx / (TILE * 4)) + (by / (TILE * 4))) % 2 == 0:
				draw_rect(Rect2(bx, by, TILE * 4, TILE * 4), alt_color)

	# --- BATTLE DAMAGE BLOTCHES ---
	var dmg_color := Color(0.095, 0.105, 0.082, 0.70)
	for mark in _DAMAGE_MARKS:
		draw_circle(Vector2(mark[0], mark[1]), float(mark[2]), dmg_color)
		# outer halo for softer edge
		draw_circle(Vector2(mark[0], mark[1]), float(mark[2]) * 1.4, Color(0.100, 0.110, 0.086, 0.22))

	# --- TREAD MARKS: directional scars across the ground ---
	var tread_color := Color(0.108, 0.118, 0.095, 0.60)
	for tm in _TREAD_MARKS:
		var cx: float = tm[0]
		var cy: float = tm[1]
		var w: float  = tm[2]
		var h: float  = tm[3]
		var ang: float = deg_to_rad(float(tm[4]))
		draw_set_transform(Vector2(cx, cy), ang, Vector2.ONE)
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), tread_color)
		# parallel tread line
		draw_rect(Rect2(-w * 0.5, -h * 0.5 + h * 3.0, w, h), tread_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset transform

	# --- BORDER WALLS: concrete bunker aesthetic ---
	var wall_outer := Color(0.122, 0.118, 0.102, 1.0)   # dark outer concrete
	var wall_mid   := Color(0.165, 0.157, 0.133, 1.0)   # inner face
	var wall_edge  := Color(0.290, 0.490, 0.349, 1.0)   # military-green bevel line

	# Outer walls
	draw_rect(Rect2(-WALL_THICKNESS, -WALL_THICKNESS, ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), wall_outer)
	draw_rect(Rect2(-WALL_THICKNESS, ARENA_H,          ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), wall_outer)
	draw_rect(Rect2(-WALL_THICKNESS, 0,               WALL_THICKNESS, ARENA_H), wall_outer)
	draw_rect(Rect2(ARENA_W,         0,               WALL_THICKNESS, ARENA_H), wall_outer)
	# Inner face bevel
	draw_rect(Rect2(0, 0, ARENA_W, WALL_THICKNESS * 0.4),       wall_mid)
	draw_rect(Rect2(0, ARENA_H - WALL_THICKNESS * 0.4, ARENA_W, WALL_THICKNESS * 0.4), wall_mid)
	draw_rect(Rect2(0, 0, WALL_THICKNESS * 0.4, ARENA_H),       wall_mid)
	draw_rect(Rect2(ARENA_W - WALL_THICKNESS * 0.4, 0, WALL_THICKNESS * 0.4, ARENA_H), wall_mid)
	# Military-green inner edge line
	draw_rect(Rect2(0, 0, ARENA_W, ARENA_H), wall_edge, false, 2.5)

	# --- RUBBLE / DEBRIS CLUSTERS (replace circle-bushes) ---
	_draw_rubble(Vector2(400, 300))
	_draw_rubble(Vector2(800, 800))
	_draw_rubble(Vector2(2200, 500))
	_draw_rubble(Vector2(1600, 1800))
	_draw_rubble(Vector2(2800, 1600))
	_draw_rubble(Vector2(600,  2000))
	_draw_rubble(Vector2(2400, 1200))

	# --- CONCRETE DEBRIS SLABS (replace rect rocks) ---
	_draw_slab(Vector2(780,  520), Vector2(160, 36),  12)
	_draw_slab(Vector2(1820, 980), Vector2(36,  160), -5)
	_draw_slab(Vector2(2460, 420), Vector2(120, 32),  8)
	_draw_slab(Vector2(1020, 1700), Vector2(32, 200), -10)

	# --- MICRO-DETAILS: hairline cracks + scattered pebbles ---
	_draw_microdetails()


func _draw_rubble(center: Vector2) -> void:
	var c_dark  := Color(0.220, 0.200, 0.165, 1.0)
	var c_mid   := Color(0.270, 0.248, 0.200, 1.0)
	var c_light := Color(0.310, 0.285, 0.230, 0.7)
	# Three offset sandbag-like rectangles
	var offsets: Array = [Vector2(-14, 8), Vector2(10, -10), Vector2(0, 18), Vector2(-18, -4)]
	var sizes:   Array = [Vector2(36, 22), Vector2(28, 18), Vector2(32, 20), Vector2(24, 16)]
	for i in offsets.size():
		var r := Rect2(center + offsets[i] - sizes[i] * 0.5, sizes[i])
		draw_rect(r, c_dark)
		draw_rect(r, c_mid, false, 1.5)
	# Top highlight chip
	draw_rect(Rect2(center + Vector2(-6, -8), Vector2(14, 8)), c_light)


func _draw_slab(center: Vector2, size: Vector2, angle_deg: int) -> void:
	var c_body    := Color(0.255, 0.235, 0.196, 1.0)
	var c_outline := Color(0.180, 0.165, 0.135, 1.0)
	var c_light   := Color(0.310, 0.285, 0.235, 0.6)
	var ang := deg_to_rad(float(angle_deg))
	draw_set_transform(center, ang, Vector2.ONE)
	draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y), c_body)
	draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y), c_outline, false, 2.0)
	# Top-left highlight sliver
	draw_rect(Rect2(-size.x * 0.5 + 2, -size.y * 0.5 + 2, size.x * 0.35, 3), c_light)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_microdetails() -> void:
	# Hairline cracks — slightly darker than floor
	var crack_col := Color(0.110, 0.118, 0.100, 0.80)
	for c in _CRACKS:
		draw_line(Vector2(c[0], c[1]), Vector2(c[2], c[3]), crack_col, 1.2)
		# Short branch off the main crack for realism
		var mid := Vector2((c[0] + c[2]) * 0.5, (c[1] + c[3]) * 0.5)
		var perp := (Vector2(c[2] - c[0], c[3] - c[1])).rotated(PI * 0.45).normalized()
		draw_line(mid, mid + perp * 14.0, crack_col, 0.8)

	# Tiny pebbles — slightly lighter than floor, gives stone texture feel
	var pebble_light := Color(0.228, 0.238, 0.205, 0.90)
	var pebble_dark  := Color(0.128, 0.138, 0.118, 0.80)
	for p in _PEBBLES:
		draw_circle(Vector2(p[0], p[1]), float(p[2]), pebble_dark)
		# highlight chip on each stone
		draw_circle(Vector2(p[0] - float(p[2]) * 0.3, p[1] - float(p[2]) * 0.3),
				float(p[2]) * 0.45, pebble_light)
