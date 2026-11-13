class_name NavGrid
extends RefCounted
## Walkability grid and pathfinding. Cells are CELL pixels square.
## Flyers ignore it; ground units path around blocked cells.

const CELL := 32
## What fills a blocked cell (for the view; the rules only care that it is blocked).
enum Kind { GROUND, ROCK, WATER, BUILDING, FOREST, FORT }

var width: int = 0
var height: int = 0
var _blocked := PackedByteArray()
var _kind := PackedByteArray()
var _astar := AStarGrid2D.new()
## Built only once a wall stands: the same grid with every wall and gate open. When the real
## grid finds no way through, paths are planned on this one, so units walk up to the wall
## that is in their way (and break it) instead of waiting on some far shore.
var _breach: AStarGrid2D = null
var _forts: Dictionary = {}  ## cell -> true for wall, gate and tower cells


func setup(w: int, h: int) -> void:
	width = w
	height = h
	_blocked.resize(w * h)
	_blocked.fill(0)
	_kind.resize(w * h)
	_kind.fill(Kind.GROUND)
	_astar.region = Rect2i(0, 0, w, h)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = Vector2(CELL, CELL) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.jumping_enabled = true
	_astar.update()
	_breach = null
	_forts.clear()


func set_blocked(cell: Vector2i, blocked: bool, kind: int = Kind.ROCK) -> void:
	if not in_bounds(cell):
		return
	_blocked[cell.y * width + cell.x] = 1 if blocked else 0
	_kind[cell.y * width + cell.x] = kind if blocked else Kind.GROUND
	_astar.set_point_solid(cell, blocked)
	if _breach != null:
		_breach.set_point_solid(cell, blocked)
	_forts.erase(cell)


## A wall, gate or tower cell. Walls block everyone on foot. A gate (`gate`) blocks too while
## closed, but paths are planned through it as if open: its owner's units walk up and it
## opens; enemies walk up and find a gate to break. `on` false clears the cell.
func set_fort(cell: Vector2i, on: bool, gate: bool = false) -> void:
	if not in_bounds(cell):
		return
	if not on:
		set_blocked(cell, false)
		return
	if _breach == null:
		_breach = AStarGrid2D.new()
		_breach.region = _astar.region
		_breach.cell_size = _astar.cell_size
		_breach.offset = _astar.offset
		_breach.diagonal_mode = _astar.diagonal_mode
		_breach.jumping_enabled = false  # every cell on the path, to cut it at the first wall
		_breach.update()
		for y in height:
			for x in width:
				if _blocked[y * width + x] == 1 and not _forts.has(Vector2i(x, y)):
					_breach.set_point_solid(Vector2i(x, y), true)
	_blocked[cell.y * width + cell.x] = 1
	_kind[cell.y * width + cell.x] = Kind.FORT
	_astar.set_point_solid(cell, not gate)
	_breach.set_point_solid(cell, false)
	_forts[cell] = true


## Opens or shuts a gate cell for walking (its path planning stays open either way).
func set_gate_open(cell: Vector2i, open: bool) -> void:
	if in_bounds(cell) and _forts.has(cell):
		_blocked[cell.y * width + cell.x] = 0 if open else 1


func is_fort(cell: Vector2i) -> bool:
	return _forts.has(cell)


func kind_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Kind.ROCK
	return _kind[cell.y * width + cell.x]


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func center_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5


func is_blocked_cell(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	return _blocked[cell.y * width + cell.x] == 1


func is_blocked(p: Vector2) -> bool:
	return is_blocked_cell(cell_of(p))


func world_size() -> Vector2:
	return Vector2(width * CELL, height * CELL)


## True if a straight walk from a to b crosses no blocked cell.
## Walks the cells the segment crosses (grid traversal), so the cost grows with
## the number of cells, not the length in pixels.
func line_clear(a: Vector2, b: Vector2) -> bool:
	var c := cell_of(a)
	var end := cell_of(b)
	if is_blocked_cell(c) or is_blocked_cell(end):
		return false
	var d := b - a
	var step_x := 1 if d.x > 0.0 else -1
	var step_y := 1 if d.y > 0.0 else -1
	var t_dx := absf(CELL / d.x) if d.x != 0.0 else INF
	var t_dy := absf(CELL / d.y) if d.y != 0.0 else INF
	var next_x := float(c.x + (1 if step_x > 0 else 0)) * CELL
	var next_y := float(c.y + (1 if step_y > 0 else 0)) * CELL
	var t_x := absf((next_x - a.x) / d.x) if d.x != 0.0 else INF
	var t_y := absf((next_y - a.y) / d.y) if d.y != 0.0 else INF
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 2
	while c != end and guard > 0:
		guard -= 1
		if t_x < t_y:
			c.x += step_x
			t_x += t_dx
		else:
			c.y += step_y
			t_y += t_dy
		if is_blocked_cell(c):
			return false
	return true


## Nearest walkable cell centre to p (spiral search), or p itself if walkable.
func nearest_free(p: Vector2) -> Vector2:
	var c := cell_of(p)
	if not is_blocked_cell(c):
		return p
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if not is_blocked_cell(n):
					return center_of(n)
	return p


## Waypoints from a to b (b excluded if unreachable: ends at the nearest free cell).
## Straight line when clear; otherwise A* with line-of-sight smoothing.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var goal := nearest_free(b)
	if line_clear(a, goal):
		return PackedVector2Array([goal])
	var start := cell_of(nearest_free(a))
	var raw := _astar.get_point_path(start, cell_of(goal), true)
	if _breach != null and (raw.is_empty() or cell_of(raw[raw.size() - 1]) != cell_of(goal)):
		# No way round: plan through the walls; the unit will stop at the one in its way.
		var through := _breach.get_point_path(start, cell_of(goal), true)
		if not through.is_empty() and cell_of(through[through.size() - 1]) == cell_of(goal):
			raw = PackedVector2Array()
			for p in through:
				if is_blocked(p):
					break
				raw.append(p)
			if raw.is_empty():
				return PackedVector2Array([nearest_free(a)])
			goal = raw[raw.size() - 1]
	if raw.is_empty():
		return PackedVector2Array([goal])
	raw[raw.size() - 1] = goal
	# Smooth: from each kept point, jump to the farthest point still in sight.
	var out := PackedVector2Array()
	var from := a
	var i := 0
	while i < raw.size():
		var j := raw.size() - 1
		while j > i and not line_clear(from, raw[j]):
			j -= 1
		out.append(raw[j])
		from = raw[j]
		i = j + 1
	return out
