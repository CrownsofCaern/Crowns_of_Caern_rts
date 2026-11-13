class_name SimWorld
extends RefCounted
## Headless real-time simulation: fixed ticks, orders, movement, combat.
## No Nodes. The view reads `units`, `projectiles` and `events`, and calls the
## command_* methods. All randomness goes through `rng`; units are always
## processed in id order, so a seed plus the same commands gives the same game.

const GRID := 64  ## spatial hash cell size in pixels

var catalog: UnitCatalog
var rng: GameRng
var nav := NavGrid.new()
var tick_rate: int = 20
var dt: float = 0.05
var tick: int = 0

var units: Array[SimUnit] = []  ## alive units, ascending id
var _by_id: Dictionary = {}
var _next_id: int = 1
var projectiles: Array[Dictionary] = []  ## {id, from, pos, prev, target, damage, owner, attacker}
var _next_shot: int = 1
## Things that happened this tick, for the view and tests:
## {type: "attack"|"hit"|"death"|"heal", ...}
var events: Array[Dictionary] = []

var _grid: Dictionary = {}
var _r: Dictionary = {}  ## rules shortcut
## Sectors, workers and buildings. Empty (and free) in a plain battle.
var economy: Economy
## What the map generator made for the view: template, roads, bridges, set pieces, biome
## regions, sites (MapGen). Empty on hand-built test maps.
var map_info: Dictionary = {}
## Heroes: levels, skills, statuses, auras, summons. Idle until a hero is spawned.
var heroes: HeroSystem
## Lairs, shrines and merchants for heroes (see MapSites). Empty unless the map places some.
var sites: MapSites
## Halls shoot arrows at enemies close by (see BaseDefense).
var defense: BaseDefense
## Walls, gates and towers (see Fortifications); their hit points live in `structures`.
var forts: Fortifications
## The faction buildings' effects (see FactionBuildings).
var specials: FactionBuildings
## Wall pieces as targets: SimUnits of role "structure", outside `units` (they never think,
## move or count as soldiers), but found by get_unit, hit and killed like any unit.
var structures: Array[SimUnit] = []
## Fog of war per player (see Vision); the view reads it.
var vision := Vision.new()
## Melee blocks (see SimFormation), in creation order; _forms finds one by id.
var formations: Array[SimFormation] = []
var _forms: Dictionary = {}
var _next_form_id: int = 1
## Shift-queued orders, by plan id: {id, members: Array of unit ids, cur: the step being
## carried out, steps: the ones still to come}. See queue_command.
var plans: Dictionary = {}
var _next_plan_id: int = 1


func _init(seed_value: int = 1, cat: UnitCatalog = null) -> void:
	catalog = cat if cat != null else UnitCatalog.get_default()
	rng = GameRng.new(seed_value)
	_r = catalog.rules
	tick_rate = int(_r["tick_rate"])
	dt = 1.0 / float(tick_rate)
	SimUnit.speed_scale = float(_r.get("speed_scale", 1.0))
	var vet: Dictionary = _r["veterans"]
	SimUnit.vet_damage = (vet["damage"] as Array).duplicate()
	SimUnit.vet_ward = (vet["ward"] as Array).duplicate()
	SimUnit.vet_names = (vet["names"] as Array).duplicate()
	economy = Economy.new(self)
	heroes = HeroSystem.new(self)
	sites = MapSites.new(self)
	defense = BaseDefense.new(self)
	forts = Fortifications.new(self)
	specials = FactionBuildings.new(self)


## blocked: rock cells; water: water cells; forest: thick woods. All block ground units.
func setup_map(w_cells: int, h_cells: int, blocked: Array = [], water: Array = [], forest: Array = []) -> void:
	nav.setup(w_cells, h_cells)
	vision.setup(nav.world_size())
	for c in blocked:
		nav.set_blocked(c, true, NavGrid.Kind.ROCK)
	for c in water:
		nav.set_blocked(c, true, NavGrid.Kind.WATER)
	for c in forest:
		nav.set_blocked(c, true, NavGrid.Kind.FOREST)


## def_override: a unit not in units.json (heroes build their own stats).
func spawn(type_id: String, owner: int, p: Vector2, def_override: Dictionary = {}) -> SimUnit:
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.owner = owner
	u.type_id = type_id
	u.def = def_override if not def_override.is_empty() else catalog.get_unit(type_id)
	assert(not u.def.is_empty(), "unknown unit " + type_id)
	u.max_hp = float(u.def["hp"])
	u.hp = u.max_hp
	u.pos = p if u.is_flying() else nav.nearest_free(p)
	u.prev_pos = u.pos
	u.anchor = u.pos
	u.facing = 1.0 if owner == 0 else -1.0
	u.acquire_timer = float(u.id % 5) * 0.05  # stagger target searches
	if u.def.has("upgrade_of") and can_rank_up(u):
		# Trained already upgraded: starts at the rank a base unit is promoted at (as in the main game).
		u.vet_xp = float(_r["veterans"]["thresholds"][int(_r["veterans"]["promote_level"]) - 1])
		u.veteran = int(_r["veterans"]["promote_level"])
	units.append(u)
	_by_id[u.id] = u
	return u


## A structure (a wall piece's hit points): registered for targeting, kept out of `units`.
func add_structure(type_id: String, owner: int, p: Vector2, def: Dictionary) -> SimUnit:
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.owner = owner
	u.type_id = type_id
	u.def = def
	u.max_hp = float(def["hp"])
	u.hp = u.max_hp
	u.pos = p
	u.prev_pos = p
	u.anchor = p
	u.order = SimUnit.Order.HOLD
	structures.append(u)
	_by_id[u.id] = u
	return u


func remove_structure(id: int) -> void:
	var u: SimUnit = _by_id.get(id)
	if u != null:
		u.alive = false
		structures.erase(u)
		_by_id.erase(id)


func get_unit(id: int) -> SimUnit:
	var u: SimUnit = _by_id.get(id)
	return u if u != null and u.alive else null


func count_alive(owner: int) -> int:
	var n := 0
	for u in units:
		if u.owner == owner:
			n += 1
	return n


# --- Commands (the only way players and AI change the game) -----------------

func command_move(ids: Array, point: Vector2) -> void:
	_group_order(ids, point, SimUnit.Order.MOVE)


func command_attack_move(ids: Array, point: Vector2) -> void:
	_group_order(ids, point, SimUnit.Order.ATTACK_MOVE)


## A plain right-click on open ground. Troops march ready to fight (attack-move), but a
## group that is already in a fight gets a plain move instead: it breaks off, walks to the
## point and picks no new fight on the way. That lets a player pull a hero out of a melee.
func command_smart_move(ids: Array, point: Vector2) -> void:
	if in_fight(ids):
		command_move(ids, point)
	else:
		command_attack_move(ids, point)


## True when any of these units has a live foe, struck or was struck a moment ago, or
## stands in a block that is fighting.
func in_fight(ids: Array) -> bool:
	var memory := float(_r["fight_memory_seconds"])
	for u in _owned_units(ids):
		if u.since_hit < memory or u.since_attack < memory:
			return true
		var t := get_unit(u.target_id)
		if t != null and t.owner != u.owner and u.order != SimUnit.Order.MOVE:
			return true
		var f: SimFormation = _forms.get(u.form_id)
		if f != null and f.engaged:
			return true
	return false


func command_attack(ids: Array, target_id: int) -> void:
	var t := get_unit(target_id)
	if t == null:
		return
	for u in _owned_units(ids):
		if u.owner == t.owner or not _can_hit(u, t):
			continue
		_leave_formation(u)  # a picked target sends the unit out of its block
		u.order = SimUnit.Order.ATTACK
		u.target_id = target_id
		u.path = PackedVector2Array()
		u.repath_timer = 0.0


## Sends troops to take a settlement: they march to it ready to fight, beat whoever holds
## it and stand in it until it is theirs, then wait there. Workers don't capture and are
## left out. False when nobody in the group can take it.
func command_capture(ids: Array, sector_id: int) -> bool:
	var s := economy.sector_by_id(sector_id) if economy != null else null
	if s == null:
		return false
	var group: Array[SimUnit] = []
	for u in _owned_units(ids):
		if not u.is_worker() and not u.is_structure() and u.garrison_of < 0 and economy.can_capture(u.owner, s):
			group.append(u)
	if group.is_empty():
		return false
	for u in group:
		_leave_formation(u)  # capturers fight loose so they spread over the settlement
	_march(group, s.center, SimUnit.Order.ATTACK_MOVE)
	for u in group:
		u.order = SimUnit.Order.CAPTURE
		u.capture_sector = s.id
	return true


## Retreat: every unit runs home to its capital (else the nearest settlement its side holds)
## at rules.retreat speed_factor x its pace, ignoring every foe until it gets there. Returns
## how many units fall back (garrisoned archers and units with nowhere to go stay).
func command_retreat(ids: Array) -> int:
	var n := 0
	for u in _owned_units(ids):
		if u.is_structure() or u.garrison_of >= 0 or u.passive:
			continue
		var home := retreat_point(u)
		if home.x < 0.0:
			continue
		_leave_formation(u)
		_leave_plan(u)
		_go_idle(u)
		u.order = SimUnit.Order.RETREAT
		u.order_point = home
		_set_path(u, home)
		n += 1
	return n


## Where a unit of this side falls back to: a spot in its capital, else in the nearest
## settlement its side holds, else (-1, -1). Spread round the centre by unit id so a
## crowd doesn't pile on one point.
func retreat_point(u: SimUnit) -> Vector2:
	if economy == null:
		return Vector2(-1, -1)
	var best: Sector = null
	var best_d := INF
	for s in economy.sectors:
		if s.owner != u.owner:
			continue
		if s.home_of == u.owner:
			best = s
			break
		var d := s.center.distance_squared_to(u.pos)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return Vector2(-1, -1)
	var a := float(u.id) * 2.39996  # golden angle
	var r := 70.0 + float(u.id % 4) * 18.0
	return best.center + Vector2(cos(a), sin(a)) * r


func command_stop(ids: Array) -> void:
	drop_plans(ids)
	var group := _owned_units(ids)
	_keep_whole_blocks(group, SimUnit.Order.IDLE)
	for u in group:
		_go_idle(u)


func command_hold(ids: Array) -> void:
	drop_plans(ids)
	var group := _owned_units(ids)
	_keep_whole_blocks(group, SimUnit.Order.HOLD)
	for u in group:
		u.order = SimUnit.Order.HOLD
		u.target_id = -1
		u.path = PackedVector2Array()
		u.anchor = u.pos


func _owned_units(ids: Array) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var sorted := ids.duplicate()
	sorted.sort()
	for id in sorted:
		var u := get_unit(int(id))
		if u != null:
			out.append(u)
	return out


## Formation: a block centred on the point, facing the way the group travels.
## Melee and heavy units take the front rows, ranged and support the back.
func _group_order(ids: Array, point: Vector2, order: int) -> void:
	var group := _owned_units(ids)
	if group.is_empty():
		return
	var same := _whole_block(group)
	if same != null:
		# The same block again: it keeps its ranks (and its fight, if it is in one).
		same.mode = order
		same.dest = point
		for u in group:
			u.order = order
			u.order_point = point
		if same.engaged and not same.loose and order == SimUnit.Order.ATTACK_MOVE:
			return
		same.engaged = false
		same.foe_id = -1
	else:
		for u in group:
			_leave_formation(u)
		_form_block(group, point, order)
	var fwd := _march(group, point, order)
	for u in group:
		if u.form_id >= 0:
			(_forms[u.form_id] as SimFormation).fwd = fwd
			break


## Marching order: a block centred on the point, facing the way the group travels,
## one shared A* path. Does not change who stands in which melee block.
func _march(group: Array[SimUnit], point: Vector2, order: int) -> Vector2:
	var centroid := Vector2.ZERO
	for u in group:
		centroid += u.pos
	centroid /= group.size()
	var fwd := (point - centroid).normalized()
	if fwd == Vector2.ZERO:
		fwd = Vector2.RIGHT
	var side := Vector2(-fwd.y, fwd.x)
	var rank := {"worker": 6, "heavy": 0, "infantry": 1, "cavalry": 2, "flyer": 3, "support": 4, "ranged": 5}
	group.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var ra: int = rank[a.role()]
		var rb: int = rank[b.role()]
		return ra < rb if ra != rb else a.id < b.id)
	var spacing := float(_r["formation_spacing"])
	var max_r := 0.0
	for u in group:
		max_r = maxf(max_r, u.radius())
	var step := max_r * 2.0 + spacing
	# The group marches together at the pace of its slowest member.
	var slowest := INF
	for u in group:
		if not u.is_flying():
			slowest = minf(slowest, u.speed())
	if slowest == INF or group.size() == 1:
		slowest = 0.0
	var cols := maxi(1, int(ceil(sqrt(group.size() * 2.0))))
	var rows := int(ceil(float(group.size()) / cols))
	# One A* for the whole group; each unit walks straight when it can.
	var shared := PackedVector2Array()
	var shared_done := false
	for i in group.size():
		var u := group[i]
		var row := i / cols
		var col := i % cols
		var in_row := mini(cols, group.size() - row * cols)
		var x := (float(col) - float(in_row - 1) * 0.5) * step
		var y := (float(rows - 1) * 0.5 - float(row)) * step
		var slot := point + side * x + fwd * y
		if not u.is_flying():
			slot = nav.nearest_free(slot)
		u.order = order
		u.order_point = slot
		u.target_id = -1
		u.provoked_by = -1
		u.group_speed = slowest
		if u.is_flying() or nav.line_clear(u.pos, slot):
			u.path = PackedVector2Array([slot])
			u.path_i = 0
			u.stuck_timer = 0.0
			u.stuck_ref = u.pos
		else:
			if not shared_done:
				shared_done = true
				shared = nav.find_path(nav.nearest_free(centroid), point)
			_set_shared_path(u, shared, slot)
	return fwd


# Public helpers for Economy.
func owned_units(ids: Array) -> Array[SimUnit]:
	return _owned_units(ids)


func nearby(p: Vector2, radius: float) -> Array:
	return _nearby(p, radius)


func go_idle(u: SimUnit) -> void:
	_go_idle(u)


func set_path(u: SimUnit, goal: Vector2) -> void:
	_set_path(u, goal)


func follow_path(u: SimUnit) -> bool:
	return _follow_path(u)


## Takes a unit off the map without a death (a worker entering a dwelling).
func retire(u: SimUnit) -> void:
	u.alive = false
	events.append({"type": "retire", "unit": u.id, "owner": u.owner})


## After a building blocks cells, ground units standing there step out.
func push_out_of_blocked() -> void:
	for u in units:
		if not u.is_flying() and u.garrison_of < 0 and nav.is_blocked(u.pos):
			u.pos = nav.nearest_free(u.pos)
			u.prev_pos = u.pos
			u.path = PackedVector2Array()


func _set_path(u: SimUnit, goal: Vector2) -> void:
	if u.is_flying():
		u.path = PackedVector2Array([goal])
	else:
		u.path = nav.find_path(u.pos, goal)
	u.path_i = 0
	u.stuck_timer = 0.0
	u.stuck_ref = u.pos


## Joins the group path at the farthest waypoint the unit can see, ends at its slot.
## Falls back to its own A* when it cannot see any waypoint.
func _set_shared_path(u: SimUnit, shared: PackedVector2Array, slot: Vector2) -> void:
	var join := -1
	for i in range(shared.size() - 1, -1, -1):
		if nav.line_clear(u.pos, shared[i]):
			join = i
			break
	if join < 0:
		_set_path(u, slot)
		return
	var p := PackedVector2Array()
	for i in range(join, shared.size() - 1):
		p.append(shared[i])
	p.append(slot)
	u.path = p
	u.path_i = 0
	u.stuck_timer = 0.0
	u.stuck_ref = u.pos


## Puts a unit down somewhere else at once (a faction gate), out of its block and idle there.
func teleport(u: SimUnit, p: Vector2) -> void:
	_leave_formation(u)
	u.pos = p if u.is_flying() else nav.nearest_free(p)
	u.prev_pos = u.pos
	_go_idle(u)


func _go_idle(u: SimUnit) -> void:
	u.group_speed = 0.0
	u.order = SimUnit.Order.IDLE
	u.target_id = -1
	u.provoked_by = -1
	u.path = PackedVector2Array()
	u.anchor = u.pos


# --- The tick --------------------------------------------------------------

func step() -> void:
	tick += 1
	events.clear()
	_rebuild_grid()
	for u in units:
		u.prev_pos = u.pos
		u.moving = false
		u.cooldown = maxf(0.0, u.cooldown - dt)
		u.since_attack += dt
		u.since_hit += dt
		u.cursed = maxf(0.0, u.cursed - dt)
		u.provoked_left = maxf(0.0, u.provoked_left - dt)
		if u.poison_left > 0.0 and u.alive:
			_poison_tick(u)
		if not u.dots.is_empty() and u.alive:
			_dot_tick(u)
		u.tick_status(dt)
		if u.has_ability("regenerate"):
			u.hp = minf(u.max_hp, u.hp + u.max_hp * float(_r["regenerate_per_second"]) * dt)
	for st in structures:
		if not st.dots.is_empty() and st.alive:
			_dot_tick(st)  # a burning building
	if economy != null and tick % NEAR_TICKS == 0:
		_terrain_regen()
		_rest_heal()
	if tick % NEAR_TICKS == 0:
		_auras()
	_step_formations()
	for u in units:
		if u.alive and not u.stunned():
			if u.passive:
				_think_passive(u)
			else:
				_think(u)
	_separate()
	if not plans.is_empty():
		_step_plans()
	_update_projectiles()
	economy.step()
	defense.step()
	forts.step()
	specials.step()
	heroes.step()
	sites.step()
	_remove_dead()
	if tick % Vision.UPDATE_TICKS == 1:
		vision.update(self)


func checksum() -> int:
	var h := 17
	for u in units:
		h = (h * 31 + u.id) & 0x7FFFFFFF
		h = (h * 31 + int(u.pos.x * 16.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u.pos.y * 16.0)) & 0x7FFFFFFF
		h = (h * 31 + int(u.hp * 16.0)) & 0x7FFFFFFF
	return h


func _think(u: SimUnit) -> void:
	if u.form_id >= 0:
		var f: SimFormation = _forms.get(u.form_id)
		if f != null and not f.loose and f.mode != SimUnit.Order.MOVE and u.order in BLOCK_ORDERS:
			_think_block(u, f)
			return
	match u.order:
		SimUnit.Order.MOVE:
			if _follow_path(u):
				_go_idle(u)
		SimUnit.Order.ATTACK:
			var t := get_unit(u.target_id)
			if t == null:
				_go_idle(u)
			else:
				_fight(u, t, true)
		SimUnit.Order.ATTACK_MOVE:
			var t := _current_or_new_target(u, _sight(u))
			if t != null:
				_fight(u, t, true)
			elif _follow_path(u):
				_go_idle(u)
		SimUnit.Order.HOLD:
			var t := _current_or_new_target(u, _reach(u) + 60.0)
			if t != null:
				_fight(u, t, false)
		SimUnit.Order.GATHER, SimUnit.Order.BUILD, SimUnit.Order.DRAFT:
			economy.think_worker(u)
		SimUnit.Order.CAST:
			heroes.think_cast(u)
		SimUnit.Order.CAPTURE:
			_think_capture(u)
		SimUnit.Order.RETREAT:
			u.target_id = -1  # no fights on the way home
			if _follow_path(u):
				_go_idle(u)
		_ when u.is_worker():
			# Idle workers only fight back; after a while they find work on their own.
			var t := get_unit(u.target_id)
			if t != null and t.pos.distance_to(u.pos) < 120.0:
				_fight(u, t, true)
				u.idle_time = 0.0
				return
			u.target_id = -1
			if u.path_i < u.path.size() and not _follow_path(u):
				return
			u.idle_time += dt
			if u.idle_time >= 1.5:
				u.idle_time = 0.0
				economy.auto_job(u)
		_:  # IDLE: defend yourself, chase a little, then return
			if _try_heal(u):
				return
			var guard := u.guard_radius > 0.0
			var leash := u.guard_radius * 1.5 if guard else float(_r["idle_leash"])
			var t := _current_or_new_target(u, u.guard_radius if guard else _sight(u))
			if t != null and t.pos.distance_to(u.anchor) > leash:
				u.target_id = -1
				t = null
			if t == null:
				t = _provoker(u, leash)
			if t != null:
				_fight(u, t, true)
			elif u.pos.distance_to(u.anchor) > 8.0:
				if u.path.is_empty():
					_set_path(u, u.anchor)
				if _follow_path(u):
					u.path = PackedVector2Array()


## On a capture order: fight what comes in sight like an attack-move, then stand on its spot
## in the settlement until the settlement is ours (or nobody can take it any more).
func _think_capture(u: SimUnit) -> void:
	var s := economy.sector_by_id(u.capture_sector) if economy != null else null
	if s == null or not economy.can_capture(u.owner, s):
		_go_idle(u)
		return
	var t := _current_or_new_target(u, _sight(u))
	if t != null:
		_fight(u, t, true)
		return
	if u.path_i < u.path.size():
		if _follow_path(u):
			u.path = PackedVector2Array()
	elif u.pos.distance_to(u.order_point) > 24.0:
		_set_path(u, u.order_point)


## The enemy that hurt this idle unit a moment ago, while it stands within the unit's leash
## plus that enemy's own reach of home: a guard shot from beyond its radius goes after
## the archer instead of standing there. Null once it runs off or the anger fades.
func _provoker(u: SimUnit, leash: float) -> SimUnit:
	if u.provoked_by < 0:
		return null
	var t := get_unit(u.provoked_by)
	if u.provoked_left <= 0.0 or t == null or t.owner == u.owner or not _can_hit(u, t) \
			or t.pos.distance_to(u.anchor) > leash + _reach(t) + t.radius() + 60.0:
		u.provoked_by = -1
		return null
	u.target_id = t.id
	return t


## A hurt idle unit fights back; a hurt lair guard also rouses the idle guards around it.
func _provoke(t: SimUnit, src: SimUnit) -> void:
	if t.passive or not _can_hit(t, src):
		return
	t.provoked_by = src.id
	t.provoked_left = float(_r["provoke_seconds"])
	if t.target_id == -1:
		t.target_id = src.id
	if t.guard_radius <= 0.0:
		return
	for o: SimUnit in _nearby(t.pos, t.guard_radius):
		if o.owner == t.owner and o.guard_radius > 0.0 and o.order == SimUnit.Order.IDLE \
				and o.provoked_by < 0 and not o.passive and _can_hit(o, src):
			o.provoked_by = src.id
			o.provoked_left = float(_r["provoke_seconds"])


## A passive unit (campaign NPC) only walks its path, then stands.
func _think_passive(u: SimUnit) -> void:
	u.target_id = -1
	if u.order == SimUnit.Order.MOVE and _follow_path(u):
		_go_idle(u)


## Keeps a valid current target, or looks for a new one every acquire_interval.
func _current_or_new_target(u: SimUnit, radius: float) -> SimUnit:
	var t := get_unit(u.target_id)
	if t != null and u.pos.distance_to(t.pos) <= radius + 40.0:
		return t
	u.target_id = -1
	u.acquire_timer -= dt
	if u.acquire_timer > 0.0:
		return null
	u.acquire_timer = float(_r["acquire_interval"])
	var best: SimUnit = null
	var best_d := INF
	for o: SimUnit in _nearby(u.pos, radius):
		if o.owner == u.owner or not _can_hit(u, o):
			continue
		var d := u.pos.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null and u.order == SimUnit.Order.ATTACK_MOVE and not structures.is_empty():
		best = forts.structure_near(u, u.pos, radius)  # nobody to fight: break the wall in the way
	if best != null:
		u.target_id = best.id
		u.path = PackedVector2Array() if u.order != SimUnit.Order.ATTACK_MOVE else u.path
	return best


## Ground melee without reach cannot hit flyers (rule from the main game).
func _can_hit(a: SimUnit, t: SimUnit) -> bool:
	if t.garrison_of >= 0:
		return a.is_ranged() or a.is_flying()  # up on a tower: out of a sword's reach
	if t.is_flying():
		return a.is_ranged() or a.is_flying() or a.has_ability("reach")
	return true


func _reach(u: SimUnit) -> float:
	if u.garrison_of >= 0:
		return float(u.def["range"]) * float(forts.conf()["tower"]["range_factor"])
	return float(u.def["range"])


func _in_range(a: SimUnit, t: SimUnit) -> bool:
	return a.pos.distance_to(t.pos) <= a.radius() + t.radius() + _reach(a) + 3.0


## Attack when in range, otherwise close in (unless holding position).
func _fight(u: SimUnit, t: SimUnit, may_move: bool) -> void:
	if _in_range(u, t):
		u.facing = 1.0 if t.pos.x >= u.pos.x else -1.0
		if u.cooldown <= 0.0:
			if not _try_heal(u):
				_attack(u, t)
		return
	if not may_move:
		u.target_id = -1
		return
	u.repath_timer -= dt
	if u.path.is_empty() or u.path_i >= u.path.size() or u.repath_timer <= 0.0:
		u.repath_timer = float(_r["repath_interval"])
		if u.is_flying() or nav.line_clear(u.pos, t.pos):
			u.path = PackedVector2Array([t.pos])
			u.path_i = 0
		else:
			_set_path(u, t.pos)
	elif u.path.size() - u.path_i == 1:
		u.path[u.path_i] = t.pos  # direct chase: track the moving target
	_advance(u, u.path[mini(u.path_i, u.path.size() - 1)], true)


## Moves along the path. Returns true when the path is finished (or stuck near its end).
func _follow_path(u: SimUnit) -> bool:
	if u.path_i >= u.path.size():
		return true
	var wp := u.path[u.path_i]
	var last := u.path_i == u.path.size() - 1
	if _advance(u, wp, not last, true):
		u.path_i += 1
		if u.path_i >= u.path.size():
			return true
	# Crowded destinations: stop once progress stalls close to the goal.
	u.stuck_timer += dt
	if u.stuck_timer >= 1.0:
		var goal := u.path[u.path.size() - 1]
		var near := u.pos.distance_to(goal) < u.radius() * 6.0 + 30.0
		if u.pos.distance_to(u.stuck_ref) < 6.0 and near:
			return true
		u.stuck_timer = 0.0
		u.stuck_ref = u.pos
	return false


## Steps toward p. Returns true on arrival.
func _advance(u: SimUnit, p: Vector2, loose: bool, marching: bool = false) -> bool:
	var to := p - u.pos
	var d := to.length()
	var arrive := 8.0 if loose else 2.0
	if d <= arrive:
		return true
	var sp := u.speed()
	if marching and u.group_speed > 0.0:
		sp = minf(sp, u.group_speed)
	sp *= _road_factor(u) * u.speed_factor()
	if u.order == SimUnit.Order.RETREAT:
		sp *= float(_r["retreat"]["speed_factor"])
	var s := minf(sp * dt, d)
	var step_v := to / d * s
	var np := u.pos + step_v
	if not u.is_flying() and nav.is_blocked(np):
		# Slide along walls instead of walking into them.
		if not nav.is_blocked(Vector2(np.x, u.pos.y)):
			np = Vector2(np.x, u.pos.y)
		elif not nav.is_blocked(Vector2(u.pos.x, np.y)):
			np = Vector2(u.pos.x, np.y)
		else:
			return false
	step_v = np - u.pos
	u.pos = np
	u.moving = true
	u.charge_dist += s
	if absf(step_v.x) > 0.1:
		u.facing = signf(step_v.x)
	return d - s <= arrive


func _attack(u: SimUnit, t: SimUnit) -> void:
	u.cooldown = float(u.def["attack_interval"]) / u.attack_speed_factor() / SimUnit.speed_scale
	u.since_attack = 0.0
	# A building, wall, gate or tower takes the unit's building damage (siege engines and giants
	# tear them down, archers barely scratch them); a unit takes its damage x the role matchup.
	var base := UnitCatalog.building_damage_of(u.def) if t.is_structure() \
		else float(u.def["damage"]) * catalog.matchup(u.role(), t.role())
	var dmg := base * u.damage_factor()
	var ch: Dictionary = _r["charge"]
	if u.has_ability("charge") and u.charge_dist >= float(ch["distance"]):
		var bonus := float(ch["multiplier"]) - 1.0
		if t.has_ability("brace"):
			bonus *= float(_r["brace"]["charge_bonus_factor"])  # set spears blunt the charge
		dmg *= 1.0 + bonus
	if t.hp >= t.max_hp and economy != null:
		dmg *= float(economy.twist(u.owner, "first_strike_factor", 1.0))  # Whisper Web ambush
	u.charge_dist = 0.0
	if u.has_ability("first_strike") and t.hp >= t.max_hp:
		dmg *= float(_up("first_strike")["factor"])  # the first blow on a fresh foe lands hard
	if u.cursed > 0.0:
		dmg *= float(_r["curse"]["damage_factor"])
	if u.hero != null and not u.hero.talents.is_empty():
		dmg *= heroes.blow_factor(u, t)
	var v := float(_r["damage_variance"])
	dmg *= 1.0 + rng.next_float_range(-v, v)
	events.append({"type": "attack", "unit": u.id, "target": t.id})
	var dtype := u.damage_type()
	if u.is_ranged():
		fire_projectile(u.pos, t, dmg, u.owner, u.id, 0.0, dtype)
	else:
		_damage(t, dmg, false, u.id, false, dtype)
	if u.has_ability("double_strike") and t.alive:
		# A second, lighter blow (or shot) right behind the first.
		var second := dmg * float(_up("double_strike")["factor"])
		if u.is_ranged():
			fire_projectile(u.pos, t, second, u.owner, u.id, 0.0, dtype)
		else:
			_damage(t, second, false, u.id, false, dtype)


## A missile from `from` that homes on `t` and deals `dmg` (as a ranged hit) when it lands.
## attacker -1: no unit fired it (a hall or tower). lift: metres above the ground it leaves
## from, for the view (0 = the attacker's own height). dtype: "ranged" (arrows, bolts, shells)
## or "magic" (a caster's bolt), met by the target's defense against it.
func fire_projectile(from: Vector2, t: SimUnit, dmg: float, owner: int, attacker: int, lift: float = 0.0,
		dtype: String = "ranged") -> void:
	var pr := {"id": _next_shot, "from": from, "pos": from, "prev": from, "target": t.id,
		"damage": dmg, "owner": owner, "attacker": attacker, "dtype": dtype}
	if lift > 0.0:
		pr["lift"] = lift
	projectiles.append(pr)
	_next_shot += 1


## Damage from a skill or effect (the target's defense against dtype and wards apply; may kill).
## Spells are magic; a talent's extra swing (cleave, thorns) passes "melee".
func deal_damage(t: SimUnit, raw: float, attacker: int, dtype: String = "magic") -> void:
	if t.alive:
		_damage(t, raw, false, attacker, true, dtype)


## skill: damage from a skill or effect rather than a blow or a missile (hero talents tell them apart).
## ranged: it came as a missile. dtype: melee, ranged or magic, picks the target's defense ("" =
## magic for a skill, ranged for a missile, else melee).
func _damage(t: SimUnit, raw: float, ranged: bool, attacker: int, skill: bool = false, dtype: String = "") -> void:
	var src := get_unit(attacker)
	var talents := heroes.has_talents
	if talents and skill and src != null and src.hero != null:
		raw *= heroes.damage_factor(src, t)
	if dtype == "":
		dtype = "magic" if skill else ("ranged" if ranged else "melee")
	var armor := t.defense(dtype)
	if src != null and not skill and src.has_ability("armor_pierce"):
		armor *= 1.0 - float(_up("armor_pierce")["ignore"])
	var dmg := raw * (1.0 - armor) * t.taken_factor()
	if economy != null and not t.is_structure():
		var tp := economy.player(t.owner)
		if tp != null:
			dmg *= tp.taken_factor  # faction research (Armoury)
	if ranged and dtype == "ranged" and t.has_ability("shield_wall"):  # a shield stops arrows, not spells
		dmg *= float(_r["shield_wall_ranged_factor"])
	if talents and t.hero != null:
		dmg = heroes.hero_taken(t, src, dmg, ranged, skill)
		if dmg <= 0.0:
			events.append({"type": "evade", "unit": t.id, "attacker": attacker})
			return
	dmg = maxf(1.0, dmg)
	t.hp -= dmg
	t.since_hit = 0.0
	if talents and t.hp <= 0.0 and t.alive:
		heroes.spare_from_death(t)
	if talents:
		heroes.after_hit(t, src, dmg, ranged, skill)
	if src != null and src.has_ability("curse"):
		t.cursed = float(_r["curse"]["seconds"])
	if src != null and src.has_ability("poison") and not t.is_structure():
		# Venom: a share of the blow again over a few seconds, through armour.
		var pr: Dictionary = _r["poison"]
		var dps := dmg * float(pr["fraction"]) / float(pr["seconds"])
		t.poison_dps = maxf(t.poison_dps, dps) if t.poison_left > 0.0 else dps
		t.poison_left = float(pr["seconds"])
		t.poison_by = attacker
	if src != null and not skill and t.alive:
		_apply_dots(src, t, raw, dmg)
	events.append({"type": "hit", "unit": t.id, "damage": dmg, "attacker": attacker})
	if src != null and src.owner != t.owner and not t.is_structure():
		gain_xp(src, dmg)
	if src != null and not skill:
		_upgrade_specials(src, t, raw, dmg, ranged)
	if t.hp <= 0.0 and t.alive:
		_die(t, src)
	elif t.order == SimUnit.Order.IDLE and src != null and src.owner != t.owner:
		_provoke(t, src)  # fight back, even against a shooter out of reach
	if src != null and src.has_ability("relentless") and t.alive:
		# Relentless: the blow staggers, so the target's own swing comes later.
		t.cooldown = maxf(t.cooldown, float(_r["relentless"]["stagger_seconds"]))


## Rules of the specials upgraded units carry (rules.json "upgrade_specials"), after a blow or
## missile from src dealt dmg to t (raw: before armour). Spill-over hits count as skills, so
## they never chain.
func _upgrade_specials(src: SimUnit, t: SimUnit, raw: float, dmg: float, ranged: bool) -> void:
	if src.has_ability("life_drain") and src.alive:
		src.hp = minf(src.max_hp, src.hp + dmg * float(_up("life_drain")["fraction"]))
	if not t.alive or t.is_structure():
		return
	if src.has_ability("sunder"):
		var su := _up("sunder")
		t.add_status("exposed", float(su["seconds"]), float(su["exposed"]))
	if src.has_ability("fear"):
		var fe := _up("fear")
		t.add_status("weak", float(fe["seconds"]), float(fe["weak"]))
	if src.has_ability("stun") and t.hero == null and rng.next_float() < float(_up("stun")["chance"]):
		t.add_status("stun", float(_up("stun")["seconds"]), 1.0)
	for kind in ["cleave", "splash"]:
		if not src.has_ability(kind) or (kind == "cleave" and ranged):
			continue
		var sp := _up(kind)
		var n := 0
		for o: SimUnit in _nearby(t.pos, float(sp["radius"])):
			if o == t or o.owner == src.owner or o.passive or not _can_hit(src, o):
				continue
			_damage(o, raw * float(sp["factor"]), ranged, src.id, true)
			n += 1
			if n >= int(sp["max_targets"]):
				break


# --- Veterans (rules.json "veterans") -----------------------------------------

## True for a unit that earns veteran ranks: a trained or recruited fighter of the catalog,
## not a worker, hero, summon, structure or campaign NPC.
func can_rank_up(u: SimUnit) -> bool:
	return not u.is_worker() and not u.is_structure() and u.hero == null and u.expires <= 0.0 \
		and not u.passive and catalog.units.has(u.type_id) and not u.def.get("hero", false)


## Credits a unit with `amount` hit points of damage dealt or healed (or a kill's bonus);
## raises its rank when it crosses a threshold.
func gain_xp(u: SimUnit, amount: float) -> void:
	if amount <= 0.0 or not u.alive or u.veteran >= 5 or not can_rank_up(u):
		return
	u.vet_xp += amount / float(u.def["hp"])
	var th: Array = _r["veterans"]["thresholds"]
	var level := u.veteran
	while level < th.size() and u.vet_xp >= float(th[level]):
		level += 1
	if level > u.veteran:
		set_veteran(u, level)


## Puts a unit at this rank (and the xp it needs, if it has less): promotes a base unit to
## its upgraded form at promote_level, and raises its hit points for the Ascendant form.
func set_veteran(u: SimUnit, level: int) -> void:
	var vet: Dictionary = _r["veterans"]
	level = clampi(level, 1, 5)
	u.vet_xp = maxf(u.vet_xp, float(vet["thresholds"][level - 1]))
	var old := u.veteran
	if level <= old:
		return
	u.veteran = level
	var ratio := u.hp_ratio()
	var promoted := ""
	if level >= int(vet["promote_level"]) and not u.def.has("upgrade_of"):
		var up := catalog.upgrade_of_unit(u.type_id)
		if up != "" and catalog.units.has(up):
			promoted = up
			u.type_id = up
			u.def = catalog.get_unit(up)
	u.max_hp = roundf(float(u.def["hp"]) * (1.0 + float(vet["hp"][level - 1])))
	u.hp = maxf(1.0, u.max_hp * ratio)
	events.append({"type": "veteran", "unit": u.id, "owner": u.owner, "level": level, "from": old,
		"promoted": promoted, "pos": u.pos})


## Aura: allies near a unit with it strike harder for a moment (refreshed every NEAR_TICKS).
func _auras() -> void:
	var au := _up("aura")
	var secs := float(NEAR_TICKS) * dt * 1.5
	for u in units:
		if not u.alive or not u.has_ability("aura"):
			continue
		for o: SimUnit in _nearby(u.pos, float(au["radius"])):
			if o.owner == u.owner and o != u and not o.is_worker():
				o.add_status("might", secs, float(au["might"]))


func _up(kind: String) -> Dictionary:
	return _r["upgrade_specials"][kind]


func _die(t: SimUnit, killer: SimUnit) -> void:
	t.alive = false
	var ev := {"type": "fort_death" if t.is_structure() else "death", "unit": t.id, "owner": t.owner, "type_id": t.type_id, "pos": t.pos,
		"facing": t.facing, "killer": killer.id if killer != null else -1, "summoned": t.expires > 0.0}
	if not t.status.is_empty():
		ev["status"] = t.status.duplicate(true)  # hexes that may spread (Contagion)
	events.append(ev)
	if killer != null and killer.alive and killer.owner != t.owner and not t.is_structure():
		gain_xp(killer, t.max_hp * float(_r["veterans"]["kill_bonus"]))
	if killer != null and killer.alive and economy != null:
		# Feast of Victory: the one who lands the killing blow catches its breath.
		var f := float(economy.twist(killer.owner, "kill_heal", 0.0))
		if f > 0.0 and killer.role() != "worker":
			killer.hp = minf(killer.max_hp, killer.hp + killer.max_hp * f)


## Burn, bleed and frost (rules.json "dots") from a blow or missile of src that dealt dmg to t
## (raw: before defences). Burn: fire, a share of the raw blow over a few seconds, met by the
## target's magic defense; it also sets buildings alight. Bleed: a share of the dealt damage,
## through armour, not on the bloodless. Frost: slows the target for a moment.
func _apply_dots(src: SimUnit, t: SimUnit, raw: float, dmg: float) -> void:
	var dots: Dictionary = _r["dots"]
	if src.has_ability("burn"):
		var b: Dictionary = dots["burn"]
		var hot := raw * float(b["fraction"]) * (1.0 - t.defense("magic")) / float(b["seconds"])
		add_dot(t, "burn", hot, float(b["seconds"]), src.id)
	if src.has_ability("bleed") and not t.bloodless():
		var bl: Dictionary = dots["bleed"]
		add_dot(t, "bleed", dmg * float(bl["fraction"]) / float(bl["seconds"]), float(bl["seconds"]), src.id)
	if src.has_ability("frost") and not t.is_structure():
		var fr: Dictionary = dots["frost"]
		t.add_status("slow", float(fr["seconds"]), float(fr["slow"]))


## Starts (or tops up) a damage over time: the stronger rate wins, the clock restarts.
func add_dot(t: SimUnit, kind: String, dps: float, seconds: float, by: int) -> void:
	if dps <= 0.0 or not t.alive:
		return
	var cur: Array = t.dots.get(kind, [])
	var rate := maxf(float(cur[1]), dps) if not cur.is_empty() else dps
	t.dots[kind] = [seconds, rate, by]
	if cur.is_empty():
		events.append({"type": "dot", "unit": t.id, "kind": kind})  # it catches fire, starts to bleed


func _dot_tick(u: SimUnit) -> void:
	var killer := -1
	for kind in u.dots.keys():
		var d: Array = u.dots[kind]
		var step_t := minf(float(d[0]), dt)
		u.hp -= float(d[1]) * step_t
		killer = int(d[2])
		d[0] = float(d[0]) - dt
		if float(d[0]) <= 0.0:
			u.dots.erase(kind)
	if u.hp <= 0.0 and u.alive:
		_die(u, get_unit(killer))


func _poison_tick(u: SimUnit) -> void:
	var d := minf(u.poison_left, dt)
	u.poison_left = maxf(0.0, u.poison_left - dt)
	u.hp -= u.poison_dps * d
	if u.poison_left <= 0.0:
		u.poison_dps = 0.0
	if u.hp <= 0.0:
		_die(u, get_unit(u.poison_by))


## Healers mend the most hurt ally in range instead of attacking.
func _try_heal(u: SimUnit) -> bool:
	if not u.has_ability("heal") or u.cooldown > 0.0:
		return false
	var h: Dictionary = _r["heal"]
	var best: SimUnit = null
	for o: SimUnit in _nearby(u.pos, float(h["range"])):
		if o.owner != u.owner or o == u or o.hp_ratio() >= float(h["below_hp_ratio"]):
			continue
		if best == null or o.hp_ratio() < best.hp_ratio():
			best = o
	if best == null:
		return false
	var amount := float(u.def["damage"]) * float(h["fraction_of_damage"])
	gain_xp(u, minf(amount, best.max_hp - best.hp))
	best.hp = minf(best.max_hp, best.hp + amount)
	u.cooldown = float(u.def["attack_interval"]) / SimUnit.speed_scale
	u.since_attack = 0.0
	events.append({"type": "heal", "unit": u.id, "target": best.id, "amount": amount})
	return true


## Whisper Web (a faction twist): this faction's units spot enemies from farther away.
func _sight(u: SimUnit) -> float:
	var s := float(u.def["sight"])
	return s if economy == null else s * float(economy.twist(u.owner, "sight_factor", 1.0))


## Deep roads (a faction twist): units of this faction march faster on the roads
## between settlements.
const ROAD_HALF_WIDTH := 40.0
var _roads: Array = []  ## [a, b] in px, cached from the economy's settlements
var _roads_for := -1


func _road_factor(u: SimUnit) -> float:
	if economy == null or u.is_flying():
		return 1.0
	var f := float(economy.twist(u.owner, "road_speed_factor", 1.0))
	if f == 1.0:
		return 1.0
	if _roads_for != economy.sectors.size():
		_roads = SkirmishScenario.roads(economy)
		_roads_for = economy.sectors.size()
	for sg in _roads:
		if u.pos.distance_to(Geometry2D.get_closest_point_to_segment(u.pos, sg[0], sg[1])) <= ROAD_HALF_WIDTH:
			return f
	return 1.0


## Wildwalk / Tidebound (faction twists): hurt units close to woods or water heal over
## time. Checked every NEAR_TICKS ticks to keep the cell scan cheap.
const NEAR_TICKS := 10
const REGEN_KINDS := {"forest": NavGrid.Kind.FOREST, "water": NavGrid.Kind.WATER}


func _terrain_regen() -> void:
	var rates := {}
	for pl in economy.players:
		var r := float(economy.twist(pl.owner, "regen_per_second", 0.0))
		if r > 0.0:
			rates[pl.owner] = [r, float(economy.twist(pl.owner, "regen_reach", 64.0)),
				int(REGEN_KINDS.get(economy.twist(pl.owner, "regen_near", "forest"), NavGrid.Kind.FOREST))]
	if rates.is_empty():
		return
	for u in units:
		if not u.alive or not rates.has(u.owner) or u.hp >= u.max_hp or u.role() == "worker":
			continue
		var rt: Array = rates[u.owner]
		if _near_kind(u.pos, float(rt[1]), int(rt[2])):
			u.hp = minf(u.max_hp, u.hp + u.max_hp * float(rt[0]) * dt * NEAR_TICKS)


## Soldiers resting at their own capital mend slowly (rules.json rest_heal).
func _rest_heal() -> void:
	var rh: Dictionary = _r.get("rest_heal", {})
	var rate := float(rh.get("per_second", 0.0))
	if rate <= 0.0:
		return
	var radius := float(rh["radius"])
	var calm := float(rh["calm_seconds"])
	for s in economy.sectors:
		if s.home_of < 0 or s.owner != s.home_of:
			continue
		for u: SimUnit in _nearby(s.center, radius):
			if u.owner != s.owner or not u.alive or u.hp >= u.max_hp or u.is_worker() or u.is_structure() \
					or u.since_hit < calm or not u.order in [SimUnit.Order.IDLE, SimUnit.Order.HOLD]:
				continue
			u.hp = minf(u.max_hp, u.hp + u.max_hp * rate * dt * NEAR_TICKS)


func _near_kind(p: Vector2, reach: float, kind: int) -> bool:
	var c := nav.cell_of(p)
	var n := int(ceil(reach / NavGrid.CELL))
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var q := c + Vector2i(dx, dy)
			if nav.in_bounds(q) and nav.kind_at(q) == kind \
					and p.distance_to(nav.center_of(q)) <= reach + NavGrid.CELL * 0.5:
				return true
	return false


func _update_projectiles() -> void:
	var speed := float(_r["projectile_speed"]) * SimUnit.speed_scale * dt
	var keep: Array[Dictionary] = []
	for p in projectiles:
		var t := get_unit(int(p["target"]))
		if t == null:
			continue  # target died: the shot is wasted
		var to: Vector2 = t.pos - p["pos"]
		p["prev"] = p["pos"]  # the view draws the shot between prev and pos
		if to.length() <= speed + t.radius():
			_damage(t, float(p["damage"]), true, int(p["attacker"]), false, String(p.get("dtype", "ranged")))
		else:
			p["pos"] = p["pos"] + to.normalized() * speed
			keep.append(p)
	projectiles = keep


func _remove_dead() -> void:
	var alive: Array[SimUnit] = []
	for u in units:
		if u.alive:
			alive.append(u)
		else:
			_by_id.erase(u.id)
	units = alive


# --- Queued orders (shift) ----------------------------------------------------------

## Adds an order to the end of these units' queue. cmd = {type, ...}:
##   move {point} (a right-click move), attack_move {point}, attack {target},
##   capture {sector}, gather {node}, build {building}, garrison {fort}.
## The group carries out its steps one after another, together: the next step starts once
## every member is done with the current one (so a group re-forms at each waypoint).
## Units that were not queued as this exact group start a new queue that waits for what
## they are doing now; an idle group starts the order at once.
func queue_command(ids: Array, cmd: Dictionary) -> void:
	var group := _owned_units(ids)
	if group.is_empty():
		return
	var p: Dictionary = plans.get(group[0].plan_id, {})
	if p.is_empty() or _plan_size(p) != group.size() or group.any(func(u: SimUnit) -> bool: return u.plan_id != p["id"]):
		for u in group:
			_leave_plan(u)
		p = {"id": _next_plan_id, "members": [], "cur": {"type": "current"}, "steps": []}
		_next_plan_id += 1
		for u in group:
			u.plan_id = p["id"]
			p["members"].append(u.id)
		plans[p["id"]] = p
	p["steps"].append(cmd)
	_advance_plan(p)


## Forgets the queued orders of these units (any order given without shift does this).
func drop_plans(ids: Array) -> void:
	for u in _owned_units(ids):
		_leave_plan(u)


## The points a unit's queue still leads to, in order (for the view): the step under way
## first, unless that is what the units were doing before the queue began.
func plan_points(u: SimUnit) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var p: Dictionary = plans.get(u.plan_id, {})
	if p.is_empty():
		return out
	var cur: Dictionary = p["cur"]
	if cur["type"] != "current":
		var q: Variant = _step_point(cur)
		if q != null:
			out.append(q)
	for c in p["steps"]:
		var q: Variant = _step_point(c)
		if q != null:
			out.append(q)
	return out


func _step_point(c: Dictionary) -> Variant:
	match String(c["type"]):
		"move", "attack_move":
			return c["point"]
		"attack":
			var t := get_unit(int(c["target"]))
			return t.pos if t != null else null
		"capture":
			var s := economy.sector_by_id(int(c["sector"])) if economy != null else null
			return s.center if s != null else null
		"gather":
			var n := economy.node(int(c["node"])) if economy != null else null
			return n.pos if n != null else null
		"build", "garrison":
			var b := economy.building(int(c.get("building", c.get("fort", -1)))) if economy != null else null
			return b.pos if b != null else null
	return null


func _plan_size(p: Dictionary) -> int:
	var n := 0
	for id in p["members"]:
		var u := get_unit(id)
		if u != null and u.plan_id == p["id"]:
			n += 1
	return n


func _leave_plan(u: SimUnit) -> void:
	if u.plan_id < 0:
		return
	var p: Dictionary = plans.get(u.plan_id, {})
	u.plan_id = -1
	if not p.is_empty():
		p["members"].erase(u.id)
		if p["members"].is_empty():
			plans.erase(p["id"])


func _step_plans() -> void:
	for pid in plans.keys():
		var p: Dictionary = plans.get(pid, {})
		if p.is_empty():
			continue
		var live: Array = []
		for id in p["members"]:
			var u := get_unit(id)
			if u != null and u.plan_id == pid:
				live.append(id)
		p["members"] = live
		if live.is_empty():
			plans.erase(pid)
			continue
		_advance_plan(p)


func _advance_plan(p: Dictionary) -> void:
	while _plan_step_done(p):
		if p["steps"].is_empty():
			for id in p["members"]:
				var u := get_unit(id)
				if u != null and u.plan_id == p["id"]:
					u.plan_id = -1
			plans.erase(p["id"])
			return
		p["cur"] = p["steps"].pop_front()
		run_command(p["members"], p["cur"])


func _plan_step_done(p: Dictionary) -> bool:
	var c: Dictionary = p["cur"]
	var group := _owned_units(p["members"])
	if group.is_empty():
		return true
	var idle := func(done_orders: Array) -> bool:
		return group.all(func(u: SimUnit) -> bool: return u.order in done_orders)
	match String(c["type"]):
		"current":
			# Whatever they did before the queue: endless jobs (gathering, holding) count as done.
			return idle.call([SimUnit.Order.IDLE, SimUnit.Order.HOLD, SimUnit.Order.GATHER])
		"move", "attack_move":
			return idle.call([SimUnit.Order.IDLE, SimUnit.Order.HOLD, SimUnit.Order.GATHER])
		"attack":
			return get_unit(int(c["target"])) == null or idle.call([SimUnit.Order.IDLE, SimUnit.Order.HOLD])
		"capture":
			return group.all(func(u: SimUnit) -> bool: return u.order != SimUnit.Order.CAPTURE)
		"build":
			var b := economy.building(int(c["building"])) if economy != null else null
			return b == null or b.done()
		"garrison":
			return true
		"gather":
			return true  # gathering never ends; whatever comes next takes over
	return true


## Carries out one order of the kinds queue_command takes, at once.
func run_command(ids: Array, c: Dictionary) -> void:
	match String(c["type"]):
		"move":
			var workers: Array = []
			var others: Array = []
			for u in _owned_units(ids):
				(workers if u.is_worker() else others).append(u.id)
			if not workers.is_empty():
				command_move(workers, c["point"])
			if not others.is_empty():
				command_smart_move(others, c["point"])
		"attack_move":
			command_attack_move(ids, c["point"])
		"attack":
			command_attack(ids, int(c["target"]))
		"capture":
			command_capture(ids, int(c["sector"]))
		"gather":
			economy.command_gather(ids, int(c["node"]))
		"build":
			economy.command_help_build(ids, int(c["building"]))
		"garrison":
			forts.command_garrison(ids, int(c["fort"]))


# --- Melee blocks ------------------------------------------------------------

## Orders a block member carries out as part of its block; any other order (a picked
## target, gathering, casting) takes it out of the block.
const BLOCK_ORDERS := [SimUnit.Order.ATTACK_MOVE, SimUnit.Order.IDLE, SimUnit.Order.HOLD]
## Seconds without a foe before a block stops fighting and moves on.
const BLOCK_CALM := 1.0
## How far (in places) a melee member may step out of its place to reach a foe.
const BLOCK_LEASH := 0.6


## Makes a melee block of the group's foot soldiers when it has enough melee infantry
## (a handful of escorts fight loose); ranged and support stand in its back rows.
func _form_block(group: Array[SimUnit], point: Vector2, order: int) -> void:
	var members: Array[SimUnit] = []
	var melee := 0
	for u in group:
		if SimFormation.can_join(u):
			members.append(u)
			if SimFormation.is_melee_foot(u):
				melee += 1
	if melee < SimFormation.MIN_MELEE:
		return
	members.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var ra := SimFormation.rank_of(a)
		var rb := SimFormation.rank_of(b)
		return ra < rb if ra != rb else a.id < b.id)
	var f := SimFormation.new()
	f.id = _next_form_id
	_next_form_id += 1
	f.owner = members[0].owner
	f.mode = order
	f.dest = point
	f.anchor = point
	var max_r := 0.0
	f.pace = INF
	for u in members:
		f.members.append(u.id)
		u.form_id = f.id
		max_r = maxf(max_r, u.radius())
		f.pace = minf(f.pace, u.speed())
	f.step = max_r * 2.0 + float(_r["formation_spacing"])
	f.cols = maxi(1, int(ceil(sqrt(members.size() * 2.0))))
	formations.append(f)
	_forms[f.id] = f


func _leave_formation(u: SimUnit) -> void:
	if u.form_id < 0:
		return
	var f: SimFormation = _forms.get(u.form_id)
	u.form_id = -1
	if f != null:
		f.members.erase(u.id)


## The block whose standing members are exactly this group, or null.
func _whole_block(group: Array[SimUnit]) -> SimFormation:
	if group.is_empty() or group[0].form_id < 0:
		return null
	var f: SimFormation = _forms.get(group[0].form_id)
	if f == null:
		return null
	var n := 0
	for id in f.members:
		if get_unit(id) != null:
			n += 1
	if n != group.size():
		return null
	for u in group:
		if u.form_id != f.id:
			return null
	return f


## Stop and hold keep a block together when it gets the order as a whole: it forms up
## where it stands. Members ordered on their own leave their block.
func _keep_whole_blocks(group: Array[SimUnit], order: int) -> void:
	var whole := _whole_block(group)
	if whole == null:
		for u in group:
			_leave_formation(u)
		return
	whole.mode = order
	whole.engaged = false
	whole.foe_id = -1
	whole.center = _block_centroid(whole)
	whole.anchor = whole.center
	whole.dest = whole.center
	_reslot(whole)


func _block_centroid(f: SimFormation) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for id in f.members:
		var u := get_unit(id)
		if u != null:
			c += u.pos
			n += 1
	return c / n if n > 0 else f.center


## Gives every standing member its place: rows from the front, melee first, as wide as
## the block started (so rows step up as the front falls); within a row members keep
## their left-to-right order so nobody walks across the block.
func _reslot(f: SimFormation) -> void:
	var alive: Array[SimUnit] = []
	for id in f.members:
		var u := get_unit(id)
		if u != null:
			alive.append(u)
	f.slots.clear()
	f.slotted_count = alive.size()
	if alive.is_empty():
		return
	var cols := mini(f.cols, alive.size())
	var rows := int(ceil(float(alive.size()) / float(cols)))
	var side := Vector2(-f.fwd.y, f.fwd.x)
	for r in rows:
		var row := alive.slice(r * cols, mini(alive.size(), (r + 1) * cols))
		row.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
			var pa := (a.pos - f.center).dot(side)
			var pb := (b.pos - f.center).dot(side)
			return pa < pb if absf(pa - pb) > 0.01 else a.id < b.id)
		var y := (float(rows - 1) * 0.5 - float(r)) * f.step
		for c in row.size():
			var x := (float(c) - float(row.size() - 1) * 0.5) * f.step
			f.slots[row[c].id] = side * x + f.fwd * y


## Once per tick, before units think: drops the fallen, finds the block's foe, turns
## and moves the block, and ends fights that are over.
func _step_formations() -> void:
	if formations.is_empty():
		return
	var keep: Array[SimFormation] = []
	for f in formations:
		var alive: Array[int] = []
		for id in f.members:
			var u := get_unit(id)
			if u != null and u.form_id == f.id:
				if u.order in BLOCK_ORDERS or u.order == SimUnit.Order.MOVE:
					alive.append(id)
				else:
					u.form_id = -1  # given some other job: out of the block
		f.members = alive
		if alive.size() < 2:
			for id in alive:
				get_unit(id).form_id = -1
			_forms.erase(f.id)
			continue
		keep.append(f)
		_step_block(f)
	formations = keep


func _step_block(f: SimFormation) -> void:
	f.contact_prev = f.contact
	f.contact = false
	var marching := f.mode == SimUnit.Order.MOVE or (f.mode == SimUnit.Order.ATTACK_MOVE and not f.engaged)
	if marching:
		var all_idle := true
		for id in f.members:
			if get_unit(id).order != SimUnit.Order.IDLE:
				all_idle = false
				break
		if all_idle:
			# Arrived: dress the ranks where the men stand.
			f.mode = SimUnit.Order.IDLE
			f.center = _block_centroid(f)
			f.anchor = f.center
			_reslot(f)
		elif f.mode == SimUnit.Order.MOVE:
			return
	var foe := _block_foe(f)
	if foe != null:
		f.calm = 0.0
		if foe.id != f.last_foe:
			# A foe behind rocks or water: members find their own way, one by one.
			f.last_foe = foe.id
			f.loose = not nav.line_clear(f.center if f.engaged else _block_centroid(f), foe.pos)
		if not f.engaged:
			f.engaged = true
			if f.mode != SimUnit.Order.HOLD:
				f.center = _block_centroid(f)
			f.fwd = _toward(f.center, foe.pos, f.fwd)
			_reslot(f)
			return
		if f.mode == SimUnit.Order.HOLD:
			if f.slotted_count != f.members.size():
				_reslot(f)
			return
		var dir := _toward(f.center, foe.pos, f.fwd)
		if not f.contact_prev and dir.dot(f.fwd) < 0.5:
			f.fwd = dir  # turn to face a foe off to the side (only when not locked in)
			_reslot(f)
		if not f.contact_prev:
			var gap := f.front_depth() + foe.radius() + f.step * 0.5 + 8.0
			_slide_center(f, foe.pos - f.fwd * gap)
	else:
		if f.engaged:
			f.calm += dt
			if f.calm < BLOCK_CALM:
				if f.slotted_count != f.members.size():
					_reslot(f)
				return
			f.engaged = false
			f.loose = false
			f.foe_id = -1
			f.last_foe = -1
			if f.mode == SimUnit.Order.ATTACK_MOVE:
				# The fight is won: march on to where the order pointed.
				var group: Array[SimUnit] = []
				for id in f.members:
					group.append(get_unit(id))
				f.fwd = _march(group, f.dest, SimUnit.Order.ATTACK_MOVE)
				return
		if f.mode == SimUnit.Order.IDLE:
			_slide_center(f, f.anchor)  # back to where it stood
	if f.slotted_count != f.members.size():
		_reslot(f)


## Moves the block's middle toward p at its marching pace.
func _slide_center(f: SimFormation, p: Vector2) -> void:
	var to := p - f.center
	var d := to.length()
	if d < 0.5:
		return
	f.center += to / d * minf(d, f.pace * 0.9 * dt)


func _toward(from: Vector2, to: Vector2, fallback: Vector2) -> Vector2:
	var d := to - from
	return d.normalized() if d.length() > 1.0 else fallback


## The enemy the block closes on: the ground enemy nearest its front. A block on the
## march looks as far as its members see, an idle one as far as its leash allows, one
## holding the line only at arm's length.
func _block_foe(f: SimFormation) -> SimUnit:
	var ref := f.center if (f.engaged or f.mode != SimUnit.Order.ATTACK_MOVE) else _block_centroid(f)
	var front := ref + f.fwd * f.front_depth()
	var sight := 0.0
	var reach := 0.0
	for id in f.members:
		var u := get_unit(id)
		sight = maxf(sight, _sight(u))
		reach = maxf(reach, _reach(u) + u.radius())
	var radius := sight + f.front_depth()
	if f.mode == SimUnit.Order.HOLD:
		radius = reach + 60.0 + f.front_depth()
	var cur := get_unit(f.foe_id)
	if cur != null and _block_may_chase(f, cur) and cur.pos.distance_to(ref) <= radius + 40.0:
		return cur
	f.foe_id = -1
	f.acquire_timer -= dt
	if f.acquire_timer > 0.0:
		return null
	f.acquire_timer = float(_r["acquire_interval"])
	var best: SimUnit = null
	var best_d := INF
	for o: SimUnit in _nearby(ref, radius):
		if o.owner == f.owner or o.is_flying() or not _block_may_chase(f, o):
			continue
		var d := front.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null and f.mode == SimUnit.Order.ATTACK_MOVE and not structures.is_empty():
		best = forts.structure_near(get_unit(f.members[0]), front, radius)  # a wall in the way
	if best != null:
		f.foe_id = best.id
	return best


func _block_may_chase(f: SimFormation, o: SimUnit) -> bool:
	if o.is_flying() or not o.alive:
		return false
	if f.mode == SimUnit.Order.IDLE:
		return o.pos.distance_to(f.anchor) <= float(_r["idle_leash"])
	return true


## One block member's tick: march with the block, or keep its place in the fight. The
## front row strikes whoever is within a step of its place; rows behind wait (archers
## shoot over them) and step up as the front falls.
func _think_block(u: SimUnit, f: SimFormation) -> void:
	var ranged := u.is_ranged()
	if f.mode == SimUnit.Order.ATTACK_MOVE and not f.engaged:
		var shot := _block_target(u, u.pos, 0.0) if ranged else null
		if shot != null:
			_strike(u, shot, f)
		elif _follow_path(u):
			_go_idle(u)
		return
	var slot := f.slot_of(u.id)
	if not nav.is_blocked(u.pos) and nav.is_blocked(slot):
		slot = nav.nearest_free(slot)
	var leash := 0.0
	if not ranged:
		leash = f.step * (0.3 if f.mode == SimUnit.Order.HOLD else BLOCK_LEASH)
	var t := _block_target(u, slot, leash)
	if t != null:
		if _in_range(u, t):
			_strike(u, t, f)
			return
		if not ranged:
			_advance(u, t.pos, true)
			return
	if _try_heal(u):
		return
	if u.pos.distance_to(slot) > 3.0:
		_advance(u, slot, false)
	elif absf(f.fwd.x) > 0.2:
		u.facing = signf(f.fwd.x)


func _strike(u: SimUnit, t: SimUnit, f: SimFormation) -> void:
	if not u.is_ranged():
		f.contact = true  # archers shooting over the ranks do not stop the advance
	u.facing = 1.0 if t.pos.x >= u.pos.x else -1.0
	if u.cooldown <= 0.0 and not _try_heal(u):
		_attack(u, t)


## The enemy a block member may hit: within its reach plus `leash` of its place.
func _block_target(u: SimUnit, slot: Vector2, leash: float) -> SimUnit:
	var t := get_unit(u.target_id)
	if t != null and t.owner != u.owner and _can_hit(u, t) and _block_reaches(u, t, slot, leash):
		return t
	u.target_id = -1
	u.acquire_timer -= dt
	if u.acquire_timer > 0.0:
		return null
	u.acquire_timer = float(_r["acquire_interval"])
	var best: SimUnit = null
	var best_d := INF
	for o: SimUnit in _nearby(slot, _reach(u) + u.radius() + leash + 40.0):
		if o.owner == u.owner or not _can_hit(u, o) or not _block_reaches(u, o, slot, leash):
			continue
		var d := u.pos.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null and not structures.is_empty() and u.form_id >= 0 \
			and (_forms[u.form_id] as SimFormation).mode == SimUnit.Order.ATTACK_MOVE:
		var w := forts.structure_near(u, slot, _reach(u) + u.radius() + leash + 3.0)
		if w != null and _block_reaches(u, w, slot, leash):
			best = w
	if best != null:
		u.target_id = best.id
	return best


func _block_reaches(u: SimUnit, t: SimUnit, slot: Vector2, leash: float) -> bool:
	return slot.distance_to(t.pos) <= u.radius() + t.radius() + _reach(u) + 3.0 + leash


# --- Spatial hash and crowd separation -------------------------------------

func _key(cx: int, cy: int) -> int:
	return (cx + 1024) * 4096 + (cy + 1024)


func _rebuild_grid() -> void:
	_grid.clear()
	for u in units:
		if u.passive:
			continue  # campaign NPCs: nobody finds, targets or pushes them
		var k := _key(int(floor(u.pos.x / GRID)), int(floor(u.pos.y / GRID)))
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(u)


## Alive units within radius of p, in id order per cell (deterministic).
func _nearby(p: Vector2, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	var x0 := int(floor((p.x - radius) / GRID))
	var x1 := int(floor((p.x + radius) / GRID))
	var y0 := int(floor((p.y - radius) / GRID))
	var y1 := int(floor((p.y + radius) / GRID))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell: Array = _grid.get(_key(cx, cy), [])
			for o: SimUnit in cell:
				if o.alive and o.pos.distance_squared_to(p) <= r2:
					out.append(o)
	return out


## Pushes overlapping units apart. Flyers only collide with flyers.
## Moving units yield less than standing ones, so armies flow around blockers.
func _separate() -> void:
	_rebuild_grid()
	for u in units:
		if not u.alive or u.garrison_of >= 0:
			continue
		var push := Vector2.ZERO
		for o: SimUnit in _nearby(u.pos, u.radius() + 20.0):
			if o == u or o.is_flying() != u.is_flying() or o.garrison_of >= 0:
				continue
			var min_d := u.radius() + o.radius()
			var delta: Vector2 = u.pos - o.pos
			var d := delta.length()
			if d >= min_d:
				continue
			if d < 0.01:
				delta = Vector2(1, 0).rotated(float((u.id * 37) % 360))
				d = 1.0
			var mass_u := u.radius() * u.radius()
			var mass_o := o.radius() * o.radius()
			var share := mass_o / (mass_u + mass_o)
			if u.order == SimUnit.Order.HOLD or (not u.moving and o.moving):
				share *= 0.35
			push += delta / d * (min_d - d) * share
		if push == Vector2.ZERO:
			continue
		var np := u.pos + push.limit_length(u.speed() * dt * 2.5 + 4.0)
		if u.is_flying():
			u.pos = _clamp_world(np)
		elif not nav.is_blocked(np):
			u.pos = np
		elif not nav.is_blocked(Vector2(np.x, u.pos.y)):
			u.pos = Vector2(np.x, u.pos.y)
		elif not nav.is_blocked(Vector2(u.pos.x, np.y)):
			u.pos = Vector2(u.pos.x, np.y)


func _clamp_world(p: Vector2) -> Vector2:
	var s := nav.world_size()
	return Vector2(clampf(p.x, 0.0, s.x), clampf(p.y, 0.0, s.y))
