class_name BaseDefense
extends RefCounted
## A house's hall shoots arrows at enemies near it, harder with every hall level, so a
## base can hold out against an early push. Plain rules, no Nodes: SimWorld steps it after
## the economy. The numbers live in economy.json ("hall_defense" and "arrows" on every
## entry of "hall_levels").
##
## Shots are ordinary SimWorld projectiles with attacker -1 (no unit fired them) and a
## "lift" in metres, so the view launches the arrow from the top of the hall.
##
## The hall cannot be captured, only torn down. Its hit points (hall_defense "hp", one value
## per hall level) live in a structure SimUnit (Sector.hall_structure), which units strike like
## a wall piece. It mends slowly while no enemy is near it. When it falls the house is out of
## the game (Economy.eliminate).
##
## Unit buildings (dwellings and faction buildings) carry hit points the same way
## (Building.structure, economy.json "building_defense"). They are torn down, never taken; a
## fallen one loses its queue and frees its ground.

var world: SimWorld
var _cooldown: Dictionary = {}  ## sector id -> seconds until the next volley
var _progress: Dictionary = {}  ## building id -> build progress last tick (sites only)


func _init(w: SimWorld) -> void:
	world = w


## The hall's arrows at its owner's current hall level: {count, damage, interval}, or {}
## when this sector does not shoot (not a home, or held by someone else).
func arrows_of(s: Sector) -> Dictionary:
	var eco := world.economy
	if eco == null or s.home_of < 0 or s.owner != s.home_of:
		return {}
	var pl := eco.player(s.owner)
	if pl == null:
		return {}
	var levels: Array = eco.e["hall_levels"]
	var lv := clampi(pl.hall_level, 1, levels.size())
	return levels[lv - 1].get("arrows", {})


func reach() -> float:
	return float(_conf().get("range", 0.0))


func step() -> void:
	var eco := world.economy
	if eco == null or not eco.settlements_active:
		return
	if _conf().is_empty():
		_step_buildings()
		return
	_step_halls()
	_step_buildings()
	for s in eco.sectors:
		var a := arrows_of(s)
		if a.is_empty() or int(a.get("count", 0)) <= 0:
			continue
		var cd := float(_cooldown.get(s.id, 0.0)) - world.dt
		if cd > 0.0:
			_cooldown[s.id] = cd
			continue
		var targets := _targets(s, int(a["count"]))
		if targets.is_empty():
			_cooldown[s.id] = 0.0  # ready the moment someone walks in
			continue
		_cooldown[s.id] = float(a["interval"]) / SimUnit.speed_scale
		_volley(s, targets, float(a["damage"]))


func _conf() -> Dictionary:
	return world.economy.e.get("hall_defense", {}) if world.economy != null else {}


## `count` arrows' targets: the soldiers in reach, nearest first; workers only when no
## soldier is near. With fewer foes than arrows, the spare arrows go round again.
func _targets(s: Sector, count: int) -> Array[SimUnit]:
	var soldiers: Array = []
	var workers: Array = []
	for o: SimUnit in world.nearby(s.center, reach()):
		if o.owner == s.owner or (o.owner == Economy.NEUTRAL and not _neutral_hostile(o, s)):
			continue
		var entry := [o.pos.distance_squared_to(s.center), o.id, o]
		if o.is_worker():
			workers.append(entry)
		else:
			soldiers.append(entry)
	var by_dist := func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]
	soldiers.sort_custom(by_dist)
	workers.sort_custom(by_dist)
	var pool: Array = soldiers if not soldiers.is_empty() else workers
	var out: Array[SimUnit] = []
	if pool.is_empty():
		return out
	for i in count:
		out.append(pool[i % pool.size()][2])
	return out


## Neutral units (militia, lair guards) are only shot when they come for the hall.
func _neutral_hostile(o: SimUnit, s: Sector) -> bool:
	var t := world.get_unit(o.target_id)
	return t != null and t.owner == s.owner


func _volley(s: Sector, targets: Array[SimUnit], damage: float) -> void:
	var lift := float(_conf().get("height", 6.0))
	world.events.append({"type": "tower_shot", "sector": s.id, "pos": s.center, "owner": s.owner,
		"count": targets.size()})
	for i in targets.size():
		# Spread the arrows over the roof so a volley does not leave as one line.
		var a := float(i) / float(targets.size()) * TAU + float(s.id)
		var from := s.center + Vector2(cos(a), sin(a)) * 18.0
		world.fire_projectile(from, targets[i], damage, s.owner, -1, lift)


# --- The hall's hit points ------------------------------------------------------------

## Hit points of a hall at this level (0: halls have none on this setup, so they are captured).
func hall_hp(level: int) -> float:
	var hp: Array = _conf().get("hp", [])
	if hp.is_empty():
		return 0.0
	return float(hp[clampi(level, 1, hp.size()) - 1])


## The structure that carries a standing capital's hit points, or null.
func hall_structure(s: Sector) -> SimUnit:
	return world.get_unit(s.hall_structure) if s.hall_structure >= 0 else null


## Gives every standing capital its hit points (once), follows hall upgrades, mends a hall
## nobody is attacking, and razes a hall that has fallen.
func _step_halls() -> void:
	var eco := world.economy
	for s in eco.sectors:
		if s.home_of < 0 or s.owner != s.home_of:
			continue
		var pl := eco.player(s.owner)
		if pl == null or pl.defeated:
			continue
		var max_hp := hall_hp(pl.hall_level)
		if max_hp <= 0.0:
			continue
		if s.hall_structure < 0:
			var st := world.add_structure("hall", s.owner, s.center, _hall_def(max_hp))
			s.hall_structure = st.id
			continue
		var st := hall_structure(s)
		if st == null:
			_raze(s)
			continue
		if st.max_hp != max_hp:  # a new hall level: stronger walls, same share of damage
			st.hp = st.hp / st.max_hp * max_hp
			st.max_hp = max_hp
			st.def["hp"] = max_hp
		st.since_hit += world.dt
		if st.hp < st.max_hp and st.since_hit >= float(_conf().get("mend_after", 10.0)):
			st.hp = minf(st.max_hp, st.hp + float(_conf().get("mend_per_second", 0.0)) * world.dt)


func _hall_def(hp: float) -> Dictionary:
	var c := _conf()
	return {"id": "hall", "name": "Hall", "role": "structure", "faction": "",
		"hp": hp, "armor_pct": float(c.get("armor_pct", 0.0)), "speed": 0.0, "damage": 0.0,
		"attack_interval": 1.0, "range": 0.0, "radius": float(c.get("radius", 48.0)), "sight": 96.0,
		"abilities": [], "tier": 0, "cost": {}}


func _raze(s: Sector) -> void:
	var owner := s.owner
	var by := -1
	for e in world.events:
		if e["type"] == "fort_death" and int(e["unit"]) == s.hall_structure:
			var k := world.get_unit(int(e.get("killer", -1)))
			by = k.owner if k != null else -1
	world.remove_structure(s.hall_structure)
	s.hall_structure = -1
	_cooldown.erase(s.id)
	world.events.append({"type": "hall_destroyed", "sector": s.id, "owner": owner, "by": by, "pos": s.center})
	world.economy.eliminate(owner, by)


# --- Unit buildings' hit points --------------------------------------------------------

func _bconf() -> Dictionary:
	return world.economy.e.get("building_defense", {}) if world.economy != null else {}


## True for the buildings that can be torn down here: dwellings and faction buildings.
static func destroyable(b: Building) -> bool:
	return b.kind == "dwelling" or b.kind == "special"


## Full hit points of a unit building (0: it cannot be hurt on this setup).
func building_hp(b: Building) -> float:
	var c := _bconf()
	if c.is_empty() or not destroyable(b):
		return 0.0
	if b.kind == "special":
		return float(c.get("special_hp", 0.0))
	var hp := float(c.get("hp_base", 0.0)) + float(c.get("hp_per_tier", 0.0)) * float(maxi(b.tier, 1) - 1)
	if b.upgraded:
		hp *= float(c.get("upgraded_factor", 1.0))
	return hp


## The structure that carries a unit building's hit points, or null.
func building_structure(b: Building) -> SimUnit:
	return world.get_unit(b.structure) if b != null and b.structure >= 0 and not b.is_fort() else null


## Gives every unit building its hit points, grows them with the work on a site, follows
## upgrades, mends a building left alone, and tears down one that has fallen.
func _step_buildings() -> void:
	var eco := world.economy
	if _bconf().is_empty():
		return
	for b in eco.buildings.duplicate():
		if not destroyable(b):
			continue
		var max_hp := building_hp(b)
		if max_hp <= 0.0:
			continue
		if b.structure < 0:
			var st := world.add_structure("building", b.owner, b.pos, _building_def(b, max_hp))
			var share := float(_bconf().get("start_share", 0.1))
			st.hp = max_hp if b.done() else max_hp * (share + (1.0 - share) * b.progress)
			b.structure = st.id
			if not b.done():
				_progress[b.id] = b.progress
			continue
		var st := world.get_unit(b.structure)
		if st == null:
			_raze_building(b)
			continue
		if _progress.has(b.id):  # a site: the walls go up with the work
			var last := float(_progress[b.id])
			var share := float(_bconf().get("start_share", 0.1))
			st.hp = minf(st.max_hp, st.hp + (b.progress - last) * st.max_hp * (1.0 - share))
			if b.done():
				_progress.erase(b.id)
			else:
				_progress[b.id] = b.progress
		if st.max_hp != max_hp:  # an upgrade: stronger walls, same share of damage
			st.hp = st.hp / st.max_hp * max_hp
			st.max_hp = max_hp
			st.def["hp"] = max_hp
		st.since_hit += world.dt
		if b.done() and st.hp < st.max_hp and st.since_hit >= float(_bconf().get("mend_after", 15.0)):
			st.hp = minf(st.max_hp, st.hp + float(_bconf().get("mend_per_second", 0.0)) * world.dt)


func _building_def(b: Building, hp: float) -> Dictionary:
	return {"id": "building", "name": world.economy.building_name(b), "role": "structure", "faction": "",
		"hp": hp, "armor_pct": float(_bconf().get("armor_pct", 0.0)), "speed": 0.0, "damage": 0.0,
		"attack_interval": 1.0, "range": 0.0, "radius": b.radius * 0.7, "sight": 96.0,
		"abilities": [], "tier": 0, "cost": {}}


## A unit building has fallen: its queue is lost, its ground opens again, and it is gone.
func _raze_building(b: Building) -> void:
	var by := -1
	for e in world.events:
		if e["type"] == "fort_death" and int(e["unit"]) == b.structure:
			var k := world.get_unit(int(e.get("killer", -1)))
			by = k.owner if k != null else -1
	world.remove_structure(b.structure)
	b.structure = -1
	_progress.erase(b.id)
	for c: Vector2i in b.cells:
		world.nav.set_blocked(c, false)
	b.cells.clear()
	b.queue.clear()
	world.economy.remove_building(b)
	world.events.append({"type": "building_destroyed", "building": b.id, "owner": b.owner, "by": by,
		"kind": b.kind, "key": b.key, "pos": b.pos, "radius": b.radius})
