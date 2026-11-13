class_name Fortifications
extends RefCounted
## Walls, gates and towers. Plain rules, no Nodes; SimWorld steps it after the economy.
##
## A wall order is a line of nav cells from one point to another, drawn 4-connected (every
## cell touches the next by a side, never only by a corner) so nothing on foot slips through.
## Each end snaps onto rock, water, woods, a building or another wall within `snap_cells`, so
## a wall across a bridge or a pass seals it. The line is cut into pieces of `piece_cells`;
## each piece is a Building (kind "wall") that workers build, and carries its hit points in
## a structure SimUnit (kept out of `world.units`, so it never thinks, moves, counts as an
## army or takes a settlement; units attack it like any foe, see SimWorld). When a piece
## falls its cells open again.
##
## A finished piece can turn into a gate (opens while one of its owner's units is close, so
## an enemy at hand can slip through then) or a tower (more hit points; up to `garrison`
## ranged units stand on it, shoot farther, and only ranged and flying foes can hurt them;
## they come down when ordered away or when the tower falls). Flyers ignore walls entirely.
## Numbers: economy.json "forts".

var world: SimWorld
var _next_chain: int = 1
var _entering: Dictionary = {}  ## unit id -> [tower id, the order point it was sent to]
var _progress: Dictionary = {}  ## building id -> build progress last tick


func _init(w: SimWorld) -> void:
	world = w


func conf() -> Dictionary:
	return world.economy.e.get("forts", {}) if world.economy != null else {}


func pieces() -> Array[Building]:
	var out: Array[Building] = []
	if world.economy != null:
		for b in world.economy.buildings:
			if b.is_fort():
				out.append(b)
	return out


# --- Planning a wall -----------------------------------------------------------------

## Cells from a to b where each cell shares a side with the next (a and b included).
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := signi(b.x - a.x)
	var sy := signi(b.y - a.y)
	var c := a
	var ix := 0
	var iy := 0
	while ix < dx or iy < dy:
		var tx := (0.5 + ix) / dx if dx > 0 else INF
		var ty := (0.5 + iy) / dy if dy > 0 else INF
		if tx < ty:
			c.x += sx
			ix += 1
		else:
			c.y += sy
			iy += 1
		out.append(c)
	return out


## What a wall order from a to b would build: {cells (the whole line, in order, ends
## snapped), free (the cells to build on), runs (free cells cut into pieces), problem}.
func plan(owner: int, a: Vector2, b: Vector2) -> Dictionary:
	var nav := world.nav
	var cf := conf()
	var line := line_cells(nav.cell_of(a), nav.cell_of(b))
	line = _snap(line, true)
	line = _snap(line, false)
	var out := {"cells": line, "free": [], "runs": [], "problem": ""}
	if cf.is_empty():
		out["problem"] = "No walls here"
		return out
	var free: Array[Vector2i] = []
	for c in line:
		if not nav.is_blocked_cell(c):
			free.append(c)
	out["free"] = free
	if free.is_empty():
		out["problem"] = "Nothing to wall off there"
		return out
	if free.size() > int(cf["max_cells"]):
		out["problem"] = "Too long: at most %d m at a time" % int(cf["max_cells"])
		return out
	for c in free:
		var why := _cell_problem(owner, c)
		if why != "":
			out["problem"] = why
			return out
	# Runs of free cells next to each other along the line, cut into pieces.
	var per := int(cf["piece_cells"])
	var runs: Array = []
	var cur: Array[Vector2i] = []
	for c in line:
		if nav.is_blocked_cell(c):
			if not cur.is_empty():
				runs.append(cur)
			cur = []
			continue
		cur.append(c)
		if cur.size() >= per:
			runs.append(cur)
			cur = []
	if not cur.is_empty():
		runs.append(cur)
	# A last stub of one cell joins the piece before it when they touch.
	if runs.size() > 1 and (runs[-1] as Array).size() == 1 and (runs[-2] as Array).size() < per + 2:
		var last: Vector2i = runs[-1][0]
		var prev: Array = runs[-2]
		var tail: Vector2i = prev[prev.size() - 1]
		if absi(last.x - tail.x) + absi(last.y - tail.y) == 1:
			prev.append(last)
			runs.pop_back()
	out["runs"] = runs
	return out


func _cell_problem(owner: int, c: Vector2i) -> String:
	var nav := world.nav
	var cf := conf()
	if not nav.in_bounds(c):
		return "Cannot build there"
	var p := nav.center_of(c)
	var eco := world.economy
	for s in eco.sectors:
		var d := s.center.distance_to(p)
		if d < float(cf["settlement_clearance"]):
			return "Too close to a settlement"
		if s.owner >= 0 and s.owner != owner and s.owner != Economy.NEUTRAL and d < float(cf["enemy_clearance"]):
			return "Too close to the enemy"
	for n in eco.nodes:
		if not n.depleted() and n.pos.distance_to(p) < 30.0:
			return "Cannot wall over a resource pile"
	return ""


## Carries one end of the line on to the nearest blocked cell within snap_cells, unless it
## already touches one by a side.
func _snap(line: Array[Vector2i], at_start: bool) -> Array[Vector2i]:
	var nav := world.nav
	var snap := int(conf().get("snap_cells", 0))
	var e: Vector2i = line[0] if at_start else line[line.size() - 1]
	var inner: Vector2i = line[1] if line.size() > 1 and at_start else (line[line.size() - 2] if line.size() > 1 else e)
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := e + d
		if n != inner and not (n in line) and nav.is_blocked_cell(n) and nav.in_bounds(n):
			return line
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-snap, snap + 1):
		for dx in range(-snap, snap + 1):
			var q := e + Vector2i(dx, dy)
			if not nav.in_bounds(q) or not nav.is_blocked_cell(q) or q in line:
				continue
			# Only ahead of the end, or to the side: never back along the wall.
			var away := Vector2(e - inner)
			if away != Vector2.ZERO and Vector2(dx, dy).dot(away) < 0.0:
				continue
			var dd := float(absi(dx) + absi(dy)) + float(q.y * nav.width + q.x) * 1e-7
			if dd < best_d:
				best_d = dd
				best = q
	if best_d == INF:
		return line
	var link := line_cells(e, best)
	link.pop_front()
	var add: Array[Vector2i] = []
	for c in link:
		if nav.is_blocked_cell(c):
			break
		add.append(c)
	if at_start:
		add.reverse()
		return add + line
	return line + add


# --- Commands ------------------------------------------------------------------------

## Lays a wall from a to b and sends the workers to build it. Returns the pieces ([] if not).
func command_build_wall(ids: Array, owner: int, a: Vector2, b: Vector2) -> Array[Building]:
	var eco := world.economy
	var made: Array[Building] = []
	var pl := eco.player(owner)
	var pl_plan := plan(owner, a, b)
	if pl_plan["problem"] != "":
		eco.notices.append({"owner": owner, "text": pl_plan["problem"]})
		return made
	var runs: Array = pl_plan["runs"]
	var cost := wall_cost(runs.size())
	if not pl.can_pay(cost):
		eco.notices.append({"owner": owner, "text": "Not enough resources"})
		return made
	pl.pay(cost)
	var chain := _next_chain
	_next_chain += 1
	var axis := (b - a).normalized() if a.distance_to(b) > 1.0 else Vector2.RIGHT
	for run: Array in runs:
		made.append(_make_piece(owner, run, axis, chain))
	world.push_out_of_blocked()
	var workers: Array = []
	for u in world.owned_units(ids):
		if u.is_worker() and u.owner == owner:
			workers.append(u.id)
	if not workers.is_empty():
		eco.command_help_build(workers, made[0].id)
	return made


func wall_cost(pieces_n: int) -> Dictionary:
	var out := {}
	var c: Dictionary = conf()["wall"]["cost"]
	for r in c:
		out[r] = int(c[r]) * pieces_n
	return out


func upgrade_cost(kind: String) -> Dictionary:
	return (conf()[kind]["cost"] as Dictionary).duplicate()


## Turns a finished wall piece into a gate or a tower (it takes the kind's seconds).
func command_upgrade(owner: int, building_id: int, kind: String) -> bool:
	var eco := world.economy
	var b := eco.building(building_id)
	if b == null or b.owner != owner or b.kind != "wall" or not b.done() or b.upgrade_left > 0.0:
		return false
	if kind != "gate" and kind != "tower":
		return false
	var cost := upgrade_cost(kind)
	var pl := eco.player(owner)
	if not pl.can_pay(cost):
		eco.notices.append({"owner": owner, "text": "Not enough resources"})
		return false
	pl.pay(cost)
	b.upgrade_to = kind
	b.upgrade_left = float(conf()[kind]["seconds"])
	return true


## Sends ranged units up into a tower (as many as it has room for).
func command_garrison(ids: Array, building_id: int) -> int:
	var b := world.economy.building(building_id)
	if b == null or b.kind != "tower" or not b.done():
		return 0
	var room := int(conf()["tower"]["garrison"]) - b.garrison.size()
	for id in _entering:
		if int(_entering[id][0]) == b.id:
			room -= 1
	var sent := 0
	for u in world.owned_units(ids):
		if room <= 0:
			break
		if u.owner != b.owner or not u.is_ranged() or u.is_flying() or u.is_hero() or u.garrison_of >= 0:
			continue
		world.command_move([u.id], b.pos)
		_entering[u.id] = [b.id, u.order_point]
		room -= 1
		sent += 1
	return sent


## Sends everyone in the tower back down.
func command_release(owner: int, building_id: int) -> void:
	var b := world.economy.building(building_id)
	if b == null or b.owner != owner:
		return
	for id in b.garrison.duplicate():
		var u := world.get_unit(id)
		if u != null:
			_eject(u, b)
			world.go_idle(u)
	b.garrison.clear()


# --- Tick ----------------------------------------------------------------------------

func step() -> void:
	if world.economy == null:
		return
	var cf := conf()
	for b in pieces():
		var st := world.get_unit(b.structure)
		if st == null:
			_break(b)
			continue
		if not b.done() or _progress.has(b.id):
			var last := float(_progress.get(b.id, 0.0))
			st.hp = minf(st.max_hp, st.hp + (b.progress - last) * st.max_hp * 0.9)
			if b.done():
				_progress.erase(b.id)
			else:
				_progress[b.id] = b.progress
		if b.upgrade_left > 0.0:
			b.upgrade_left -= world.dt
			if b.upgrade_left <= 0.0:
				_finish_upgrade(b, st)
		match b.kind:
			"gate":
				_step_gate(b, cf)
			"tower":
				_step_tower(b)
	_step_entering()


func _make_piece(owner: int, cells: Array, axis: Vector2, chain: int) -> Building:
	var nav := world.nav
	var cf := conf()
	var b := Building.new()
	b.owner = owner
	b.kind = "wall"
	b.key = "fort_wall"
	b.chain = chain
	b.progress = 0.0
	b.build_seconds = float(cf["wall"]["seconds"])
	var centre := Vector2.ZERO
	for c: Vector2i in cells:
		centre += nav.center_of(c)
		b.cells.append(c)
		nav.set_fort(c, true)
	centre /= cells.size()
	b.pos = centre
	var first := nav.center_of(cells[0])
	var last := nav.center_of(cells[cells.size() - 1])
	b.axis = (last - first).normalized() if first.distance_to(last) > 1.0 else axis
	if b.axis.dot(axis) < 0.0:
		b.axis = -b.axis
	var lo := INF
	var hi := -INF
	for c: Vector2i in cells:
		var t := (nav.center_of(c) - centre).dot(b.axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	b.length = hi - lo + NavGrid.CELL
	b.radius = maxf(NavGrid.CELL, b.length * 0.5)
	b.rally = b.pos
	world.economy.add_building(b)
	var st := world.add_structure("fort_wall", owner, b.pos, _def("wall", b.radius))
	st.hp = st.max_hp * 0.1
	b.structure = st.id
	_progress[b.id] = 0.0
	return b


func _def(kind: String, radius: float) -> Dictionary:
	var k: Dictionary = conf()[kind]
	return {"id": "fort_" + kind, "name": kind.capitalize(), "role": "structure", "faction": "",
		"hp": float(k["hp"]), "armor_pct": float(k["armor_pct"]), "speed": 0.0, "damage": 0.0,
		"attack_interval": 1.0, "range": 0.0, "radius": radius, "sight": 96.0, "abilities": [],
		"tier": 0, "cost": {}}


func _finish_upgrade(b: Building, st: SimUnit) -> void:
	var kind := b.upgrade_to
	b.upgrade_left = 0.0
	b.upgrade_to = ""
	b.kind = kind
	b.key = "fort_" + kind
	var ratio := st.hp_ratio()
	st.def = _def(kind, b.radius)
	st.type_id = b.key
	st.max_hp = float(st.def["hp"])
	st.hp = st.max_hp * ratio
	if kind == "gate":
		for c: Vector2i in b.cells:
			world.nav.set_fort(c, true, true)
	world.events.append({"type": "fort_upgraded", "building": b.id, "owner": b.owner, "kind": kind})


## A gate stands open while one of its owner's units is close (or anyone is in it).
func _step_gate(b: Building, cf: Dictionary) -> void:
	var reach := float(cf["gate"]["open_reach"])
	var open := false
	for u: SimUnit in world.nearby(b.pos, reach + b.radius):
		if u.is_flying():
			continue
		if u.owner == b.owner and u.garrison_of < 0:
			open = true
			break
		if b.gate_open and b.cells.has(world.nav.cell_of(u.pos)):
			open = true  # never shut on someone standing in it
			break
	if open != b.gate_open:
		b.gate_open = open
		for c: Vector2i in b.cells:
			world.nav.set_gate_open(c, open)
		world.events.append({"type": "gate", "building": b.id, "open": open})


func _step_tower(b: Building) -> void:
	var keep: Array[int] = []
	for id in b.garrison:
		var u := world.get_unit(id)
		if u == null:
			continue
		if u.order != SimUnit.Order.HOLD:
			_eject(u, b)  # ordered somewhere else: down it comes
			if u.order == SimUnit.Order.MOVE or u.order == SimUnit.Order.ATTACK_MOVE:
				world.set_path(u, u.order_point)
			continue
		keep.append(id)
	b.garrison = keep


func _step_entering() -> void:
	if _entering.is_empty():
		return
	var ids := _entering.keys()
	ids.sort()
	var cap := int(conf()["tower"]["garrison"])
	for id in ids:
		var u := world.get_unit(int(id))
		var e: Array = _entering[id]
		var b := world.economy.building(int(e[0]))
		if u == null or b == null or b.kind != "tower" or u.order_point != e[1] \
				or not (u.order == SimUnit.Order.MOVE or u.order == SimUnit.Order.IDLE):
			_entering.erase(id)
			continue
		if u.pos.distance_to(b.pos) <= b.radius + u.radius() + 24.0 and b.garrison.size() < cap:
			_entering.erase(id)
			_enter(u, b)
		elif u.order == SimUnit.Order.IDLE:
			_entering.erase(id)  # stopped short of it


func _enter(u: SimUnit, b: Building) -> void:
	world.command_hold([u.id])
	var i := b.garrison.size()
	u.garrison_of = b.id
	u.pos = b.pos + b.axis * (8.0 if i % 2 == 0 else -8.0) + Vector2(b.axis.y, -b.axis.x) * 4.0
	u.prev_pos = u.pos
	u.anchor = u.pos
	u.path = PackedVector2Array()
	b.garrison.append(u.id)
	world.events.append({"type": "garrison", "unit": u.id, "building": b.id})


func _eject(u: SimUnit, b: Building) -> void:
	u.garrison_of = -1
	# Down on the owner's side: the free cell nearest the archer's own hall, else any.
	var nav := world.nav
	var side := Vector2(-b.axis.y, b.axis.x) * NavGrid.CELL * 1.5
	var home := world.economy.hall_of(u.owner)
	var a := b.pos + side
	var c := b.pos - side
	var p := a
	if home != null and c.distance_to(home.center) < a.distance_to(home.center):
		p = c
	u.pos = nav.nearest_free(p)
	u.prev_pos = u.pos
	u.anchor = u.pos
	world.events.append({"type": "ungarrison", "unit": u.id, "building": b.id})


func _break(b: Building) -> void:
	for c: Vector2i in b.cells:
		world.nav.set_fort(c, false)
	for id in b.garrison:
		var u := world.get_unit(id)
		if u != null:
			_eject(u, b)
			world.go_idle(u)
	b.garrison.clear()
	_progress.erase(b.id)
	world.remove_structure(b.structure)
	world.economy.remove_building(b)
	world.events.append({"type": "fort_broken", "building": b.id, "owner": b.owner, "pos": b.pos, "kind": b.kind})


# --- Targets for SimWorld ------------------------------------------------------------

## The nearest enemy structure within radius of p that `u` may strike, or null.
func structure_near(u: SimUnit, p: Vector2, radius: float) -> SimUnit:
	var best: SimUnit = null
	var best_d := INF
	for s in world.structures:
		if not s.alive or s.owner == u.owner:
			continue
		var d := s.pos.distance_to(p) - s.radius()
		if d <= radius and d < best_d:
			best_d = d
			best = s
	return best
