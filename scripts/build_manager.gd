extends Node

## Central authority for all build-mode state.  Autoloaded as "BuildManager".

const TILE := 80
const ARENA_COLS := 40   # 3200 / 80
const ARENA_ROWS := 30   # 2400 / 80

# Build costs (coins)
const COSTS: Dictionary = {
	"wall":  20,
	"door":  20,
	"tower": 60,
}

# Partial refund when erasing a structure
const ERASE_REFUND := 10

var build_mode := false
var selected  := "wall"   # "wall" | "door" | "tower" | "erase"

# Vector2i → Node — which structure occupies each grid cell
var occupied_cells: Dictionary = {}
# Cells enclosed by structures — enemies must not spawn here
var interior_cells: Dictionary = {}

signal build_mode_started
signal build_mode_ended

# ─── Coordinate helpers ───────────────────────────────────────────────────────

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x) / TILE, int(world_pos.y) / TILE)

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)

# ─── Cell registry ────────────────────────────────────────────────────────────

func is_occupied(cell: Vector2i) -> bool:
	return occupied_cells.has(cell)

func register(cell: Vector2i, node: Node) -> void:
	occupied_cells[cell] = node
	_recompute_interior()

func unregister(cell: Vector2i) -> void:
	occupied_cells.erase(cell)
	_recompute_interior()

# ─── Interior detection (flood-fill from arena boundary) ─────────────────────
# Any cell unreachable from the border (and not occupied) is inside a fortress.

func _recompute_interior() -> void:
	interior_cells.clear()
	var visited: Dictionary = {}
	var queue: Array = []
	# Seed BFS from all border cells
	for x in ARENA_COLS:
		_bfs_add(Vector2i(x, 0), visited, queue)
		_bfs_add(Vector2i(x, ARENA_ROWS - 1), visited, queue)
	for y in range(1, ARENA_ROWS - 1):
		_bfs_add(Vector2i(0, y), visited, queue)
		_bfs_add(Vector2i(ARENA_COLS - 1, y), visited, queue)
	# BFS expand
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for nb in [Vector2i(cell.x+1,cell.y), Vector2i(cell.x-1,cell.y),
				   Vector2i(cell.x,cell.y+1), Vector2i(cell.x,cell.y-1)]:
			if nb.x >= 0 and nb.x < ARENA_COLS and nb.y >= 0 and nb.y < ARENA_ROWS:
				_bfs_add(nb, visited, queue)
	# Mark unreachable non-occupied cells as interior
	for x in ARENA_COLS:
		for y in ARENA_ROWS:
			var c := Vector2i(x, y)
			if not visited.has(c) and not occupied_cells.has(c):
				interior_cells[c] = true

func _bfs_add(cell: Vector2i, visited: Dictionary, queue: Array) -> void:
	if visited.has(cell) or occupied_cells.has(cell):
		return
	visited[cell] = true
	queue.append(cell)

# ─── Mode control ─────────────────────────────────────────────────────────────

func start_build_mode() -> void:
	build_mode = true
	selected = "wall"
	build_mode_started.emit()

func end_build_mode() -> void:
	build_mode = false
	build_mode_ended.emit()
