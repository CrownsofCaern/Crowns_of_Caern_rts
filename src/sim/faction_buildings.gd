class_name FactionBuildings
extends RefCounted
## What the faction buildings do (economy.json "faction_buildings"; two per house, in the art the
## shared dwellings freed). Plain rules, no Nodes: SimWorld steps it after the halls' arrows.
##
## Passive kinds work on their own once the building stands: aura, tower, raise, income, spawn.
## Button kinds go through `use(owner, building_id, arg)`: trade, market, gate, research, feast.
## `can_use` says whether a button works now and why not, for the view and the computer players.

const BUTTONS := ["trade", "market", "gate", "research", "feast"]
const KINDS := ["aura", "tower", "raise", "income", "spawn", "trade", "market", "gate", "research", "feast"]
## Statuses an aura or feast may hand out (SimUnit.status kinds).
const STATUSES := ["might", "ward", "haste", "weak", "exposed", "slow"]
const COMMON := ["gold", "wood", "ore"]

var world: SimWorld


func _init(w: SimWorld) -> void:
	world = w


func step() -> void:
	var eco := world.economy
	if eco == null or eco.buildings.is_empty():
		return
	var dt := world.dt
	var near := world.tick % SimWorld.NEAR_TICKS == 0
	for b in eco.buildings:
		if b.kind != "special" or not b.done():
			continue
		var d := eco.def_of(b)
		if d.is_empty():
			continue
		var fx: Dictionary = d["effect"]
		b.cooldown = maxf(0.0, b.cooldown - dt)
		match String(fx["kind"]):
			"aura":
				if near:
					_aura(b, fx)
			"income":
				_income(b, fx, dt)
				if near:
					_aura(b, fx)
			"tower":
				_tower(b, fx)
			"raise":
				_raise(b, fx)
			"spawn":
				_spawn(b, fx, dt)
			"research":
				_research(b, fx, dt)


# --- Passive kinds --------------------------------------------------------------

## Own units near it heal (a share of their health a second) and get the "own" statuses; enemies
## near it get the "foe" ones. Refreshed every NEAR_TICKS, so they last as long as one stands there.
func _aura(b: Building, fx: Dictionary) -> void:
	var secs := float(SimWorld.NEAR_TICKS) * world.dt * 1.5
	var own: Dictionary = fx.get("own", {})
	var foe: Dictionary = fx.get("foe", {})
	for o: SimUnit in world.nearby(b.pos, float(fx.get("radius", 0.0))):
		if not o.alive or o.passive or o.is_structure():
			continue
		if o.owner == b.owner:
			if o.is_worker():
				continue
			if own.has("heal") and o.hp < o.max_hp:
				o.hp = minf(o.max_hp, o.hp + o.max_hp * float(own["heal"]) * world.dt * SimWorld.NEAR_TICKS)
			for k in own:
				if k != "heal":
					o.add_status(k, secs, float(own[k]))
		else:
			for k in foe:
				o.add_status(k, secs, float(foe[k]))


## Arrows at the nearest enemy soldiers in range (workers only when no soldier is near), like a hall.
func _tower(b: Building, fx: Dictionary) -> void:
	if b.cooldown > 0.0:
		return
	var soldiers: Array = []
	var workers: Array = []
	for o: SimUnit in world.nearby(b.pos, float(fx["range"])):
		if not o.alive or o.owner == b.owner or o.passive or o.is_structure():
			continue
		if o.owner == Economy.NEUTRAL:
			var t := world.get_unit(o.target_id)
			if t == null or t.owner != b.owner:
				continue  # militia and lair guards only when they come for you
		var entry := [o.pos.distance_squared_to(b.pos), o.id, o]
		if o.is_worker():
			workers.append(entry)
		else:
			soldiers.append(entry)
	var pool: Array = soldiers if not soldiers.is_empty() else workers
	if pool.is_empty():
		return
	pool.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var n := int(fx["count"])
	b.cooldown = float(fx["interval"]) / SimUnit.speed_scale
	world.events.append({"type": "tower_shot", "building": b.id, "pos": b.pos, "owner": b.owner, "count": n})
	for i in n:
		var a := float(i) / float(n) * TAU + float(b.id)
		world.fire_projectile(b.pos + Vector2(cos(a), sin(a)) * 14.0, pool[i % pool.size()][2], float(fx["damage"]),
			b.owner, -1, float(fx.get("height", 5.0)))


## Enemies (not workers, heroes or summons) dying near it rise on its owner's side for a while.
func _raise(b: Building, fx: Dictionary) -> void:
	var r2 := float(fx["radius"]) * float(fx["radius"])
	for ev: Dictionary in world.events.duplicate():
		if ev["type"] != "death" or int(ev["owner"]) == b.owner or bool(ev.get("summoned", false)):
			continue
		var p: Vector2 = ev["pos"]
		if p.distance_squared_to(b.pos) > r2:
			continue
		var ud := world.catalog.get_unit(String(ev["type_id"]))
		if ud.is_empty() or String(ud.get("role", "")) == "worker":
			continue
		_prune(b)
		if b.spawned.size() >= int(fx["max"]):
			return
		var u := world.spawn(String(fx["unit"]), b.owner, p)
		u.expires = float(fx["seconds"])
		b.spawned.append(u.id)
		world.events.append({"type": "summon", "unit": u.id, "owner": b.owner, "building": b.id})


## A free unit every `seconds`, at most `max` of them alive.
func _spawn(b: Building, fx: Dictionary, dt: float) -> void:
	_prune(b)
	if b.spawned.size() >= int(fx["max"]):
		b.timer = 0.0
		return
	b.timer += dt
	if b.timer < float(fx["seconds"]):
		return
	b.timer = 0.0
	var eco := world.economy
	var u := world.spawn(String(fx["unit"]), b.owner, b.pos + Vector2(0, b.radius + 14.0))
	u.pos = eco.free_spot(b.owner, u.pos, u.radius(), 3, u.id)
	u.prev_pos = u.pos
	b.spawned.append(u.id)
	world.command_move([u.id], eco.free_spot(b.owner, b.rally, u.radius(), 8, u.id))
	world.events.append({"type": "trained", "unit": u.id, "owner": b.owner, "building": b.id})


func _income(b: Building, fx: Dictionary, dt: float) -> void:
	b.timer += float(fx["per_minute"]) / 60.0 * dt
	if b.timer >= 1.0:
		var whole := int(b.timer)
		b.timer -= whole
		world.economy.player(b.owner).earn(String(fx["resource"]), whole)


func _research(b: Building, fx: Dictionary, dt: float) -> void:
	if b.timer <= 0.0:
		return
	b.timer -= dt
	if b.timer <= 0.0:
		b.timer = 0.0
		var pl := world.economy.player(b.owner)
		pl.researched[b.special] = true
		pl.taken_factor *= float(fx["taken_factor"])
		world.events.append({"type": "researched", "building": b.id, "owner": b.owner, "special": b.special})


func _prune(b: Building) -> void:
	var keep: Array[int] = []
	for id in b.spawned:
		var u := world.get_unit(id)
		if u != null and u.alive:
			keep.append(id)
	b.spawned = keep


# --- Buttons ------------------------------------------------------------------

## Whether the building's button (arg: market "give>take") works now: "" if so, else why not.
func can_use(owner: int, building_id: int, arg: String = "") -> String:
	var eco := world.economy
	var b := eco.building(building_id)
	if b == null or b.owner != owner or b.kind != "special":
		return "Not yours"
	if not b.done():
		return "Still being built"
	var fx: Dictionary = eco.def_of(b)["effect"]
	var pl := eco.player(owner)
	match String(fx["kind"]):
		"trade":
			if not pl.can_pay(fx["give"]):
				return "Not enough resources"
			if bool(fx.get("worker", false)) and _worker_near(b) == null:
				return "No worker to give"
		"market":
			var o := market_offer(owner, building_id, arg)
			if o.is_empty():
				return "No such trade"
			if not pl.can_pay({o["give"]: o["give_n"]}):
				return "Not enough %s" % eco.e["resources"][o["give"]]
		"gate":
			if b.cooldown > 0.0:
				return "Ready in %d s" % ceili(b.cooldown)
			if _gate_sources(b, fx).is_empty():
				return "Nobody to call: the gate pulls from %s" % ("your hall" if fx["from"] == "hall" else "your other gates")
		"research":
			if pl.researched.has(b.special) or b.timer > 0.0:
				return "Done" if pl.researched.has(b.special) else "Under way"
			if not pl.can_pay(fx["cost"]):
				return "Not enough resources"
		"feast":
			if b.cooldown > 0.0:
				return "Ready in %d s" % ceili(b.cooldown)
			if not pl.can_pay(fx["cost"]):
				return "Not enough resources"
		_:
			return "Works on its own"
	return ""


func use(owner: int, building_id: int, arg: String = "") -> bool:
	var why := can_use(owner, building_id, arg)
	var eco := world.economy
	if why != "":
		eco.notices.append({"owner": owner, "text": why})
		return false
	var b := eco.building(building_id)
	var fx: Dictionary = eco.def_of(b)["effect"]
	var pl := eco.player(owner)
	match String(fx["kind"]):
		"trade":
			if bool(fx.get("worker", false)):
				world.retire(_worker_near(b))
			pl.pay(fx["give"])
			for r in fx["take"]:
				pl.earn(r, int(fx["take"][r]))
		"market":
			var o := market_offer(owner, building_id, arg)
			pl.pay({o["give"]: o["give_n"]})
			pl.earn(o["take"], int(o["take_n"]))
		"gate":
			var moved := 0
			for u in _gate_sources(b, fx):
				var p := eco.free_spot(owner, b.rally, u.radius(), 8, u.id)
				world.teleport(u, p)
				moved += 1
			b.cooldown = float(fx["cooldown"])
			world.events.append({"type": "gate", "building": b.id, "owner": owner, "count": moved})
		"research":
			pl.pay(fx["cost"])
			b.timer = float(fx["seconds"])
		"feast":
			pl.pay(fx["cost"])
			b.cooldown = float(fx["cooldown"])
			for u in world.units:
				if u.alive and u.owner == owner and not u.is_worker() and not u.passive and not u.is_structure():
					u.add_status(String(fx["status"]), float(fx["seconds"]), float(fx["value"]))
			world.events.append({"type": "feast", "building": b.id, "owner": owner})
	world.events.append({"type": "special_used", "building": b.id, "owner": owner, "arg": arg})
	return true


## The market's pairs: every resource the owner uses, as "give>take".
func market_pairs(owner: int) -> Array:
	var eco := world.economy
	var res: Array = ["gold"]
	for r in eco.e["resources"]:
		if r != "gold" and eco.uses(owner, r):
			res.append(r)
	var out: Array = []
	for g in res:
		for t in res:
			if g != t:
				out.append("%s>%s" % [g, t])
	return out


## A market deal: {give, give_n, take, take_n}, or {} for no such pair. Common goods go `amount`
## at a time; a rare one counts rare_multiplier times as much (economy.json train).
func market_offer(owner: int, building_id: int, arg: String) -> Dictionary:
	var eco := world.economy
	var b := eco.building(building_id)
	if b == null or not arg in market_pairs(owner):
		return {}
	var fx: Dictionary = eco.def_of(b)["effect"]
	var parts := arg.split(">")
	var mult := float(eco.e["train"]["rare_multiplier"])
	var amount := float(fx["amount"])
	var give_n := amount if parts[0] in COMMON else amount / mult
	var take_n := amount * float(fx["rate"]) if parts[1] in COMMON else amount * float(fx["rare_rate"])
	if not parts[0] in COMMON and not parts[1] in COMMON:
		take_n = give_n * float(fx["rate"])
	return {"give": parts[0], "give_n": maxi(1, int(round(give_n))), "take": parts[1], "take_n": maxi(1, int(round(take_n)))}


## The worker given to a Brand Pit: the nearest one not building.
func _worker_near(b: Building) -> SimUnit:
	var best: SimUnit = null
	var best_d := INF
	for u in world.economy.workers_of(b.owner):
		if u.order == SimUnit.Order.BUILD:
			continue
		var dd := u.pos.distance_squared_to(b.pos)
		if dd < best_d:
			best_d = dd
			best = u
	return best


## A gate's travellers: own soldiers (heroes too) standing near its partner (the home hall, or the
## owner's other finished gates of the same kind), in id order.
func _gate_sources(b: Building, fx: Dictionary) -> Array[SimUnit]:
	var eco := world.economy
	var spots: Array[Vector2] = []
	if fx["from"] == "hall":
		var h := eco.hall_of(b.owner)
		if h != null:
			spots.append(h.center)
	else:
		for o in eco.buildings:
			if o != b and o.owner == b.owner and o.kind == "special" and o.special == b.special and o.done():
				spots.append(o.pos)
	var r := float(fx["radius"])
	var out: Array[SimUnit] = []
	for u in world.units:
		if not u.alive or u.owner != b.owner or u.is_worker() or u.passive or u.is_structure() or u.garrison_of >= 0:
			continue
		if u.pos.distance_to(b.pos) <= r:
			continue
		for s in spots:
			if u.pos.distance_to(s) <= r:
				out.append(u)
				break
	return out


## The extra sight a faction building gives beyond its footprint (0: the usual).
func sight_of(b: Building) -> float:
	var d := world.economy.def_of(b)
	return float(d["effect"].get("sight", 0.0)) if not d.is_empty() and b.done() else 0.0
