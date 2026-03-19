extends Node

## Central authority for all build-mode state.  Autoloaded as "BuildManager".

const TILE := 80

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

func unregister(cell: Vector2i) -> void:
	occupied_cells.erase(cell)

# ─── Mode control ─────────────────────────────────────────────────────────────

func start_build_mode() -> void:
	build_mode = true
	selected = "wall"
	build_mode_started.emit()

func end_build_mode() -> void:
	build_mode = false
	build_mode_ended.emit()
