class_name Economy
extends RefCounted
## Sectors, settlements, workers, resources and buildings (plan: Sectors and
## settlements, Resources, Buildings, Key skirmish mechanics 1, 3, 4, 5).
## Headless; owned by SimWorld and stepped once per tick after combat.

const STAFF_EVERY := 15  ## ticks between looks for unmanned building sites and one rebalancing move
const NEUTRAL := 8  ## owner id of neutral militia (players are 0 .. SkirmishScenario.MAX_PLAYERS - 1)

var world: SimWorld
var e: Dictionary  ## economy.json
var sectors: Array[Sector] = []
var nodes: Array[ResNode] = []
var buildings: Array[Building] = []
var players: Array[PlayerState] = []
var _next_building: int = 1
## False on a campaign hero map: settlements are scenery there (no capture, gold or workers).
var settlements_active: bool = true
## A campaign chapter's cap on the tiers anyone may raise (0: none).
var tier_cap: int = 0
## Messages for the view ("needs a worker", "not enough gold"...), cleared every tick.
var notices: Array[Dictionary] = []


func _init(w: SimWorld) -> void:
	world = w
	e = w.catalog.economy


# --- Setup ---------------------------------------------------------------------

func add_player(owner: int, faction: String) -> PlayerState:
	var p := PlayerState.new()
	p.owner = owner
	p.faction = faction
	p.res = {"gold": 0}
	for r in e["start"]["resources"]:
		p.res[r] = int(e["start"]["resources"][r])
	for r in world.catalog.faction_resources(faction):
		if not p.res.has(r):
			p.res[r] = 0
	players.append(p)
	return p


func player(owner: int) -> PlayerState:
	for p in players:
		if p.owner == owner:
			return p
	return null


func add_sector(center: Vector2, size: String, owner: int = -1) -> Sector:
	var s := Sector.new()
	s.id = sectors.size()
	s.center = center
	s.size = size
	s.owner = owner
	sectors.append(s)
	return s


## A pile of `resource` at pos. amount -2 takes the size from economy.json pile_amounts;
## -1 makes it endless.
func add_node(pos: Vector2, resource: String, amount: int = -2) -> ResNode:
	var n := ResNode.new()
	n.id = nodes.size()
	n.pos = pos
	n.resource = resource
	n.sector = sector_at(pos).id
	n.amount = pile_amount(resource) if amount == -2 else amount
	n.full = n.amount
	nodes.append(n)
	return n


## How much a new pile of r holds (-1: endless).
func pile_amount(r: String) -> int:
	var pa: Dictionary = e.get("pile_amounts", {})
	return int(pa.get(r, pa.get("rare", -1)))


## Gives a player their home: owns the sector, starting workers, prebuilt dwellings.
func setup_home(owner: int, sector: Sector) -> void:
	sector.owner = owner
	sector.home_of = owner
	var p := player(owner)
	for i in int(e["start"]["workers"]):
		var a := float(i) / float(e["start"]["workers"]) * TAU
		_spawn_worker(owner, sector, sector.center + Vector2(cos(a), sin(a)) * 90.0)
	var side := 1.0 if sector.center.x < world.nav.world_size().x * 0.5 else -1.0
	for t in e["start"]["dwellings"]:
		var b := _make_building(owner, "dwelling", int(t), sector.center + Vector2(side * (float(e["settlement_clearance"]) + float(e["dwelling"]["radius"]) + 20.0), -40.0))
		b.progress = 1.0
	if p != null:
		p.hall_level = 1
	# Home piles hold more, so nobody has to rush out before the first army stands.
	var hf := float(e.get("pile_amounts", {}).get("home_factor", 1.0))
	for n in nodes:
		if n.sector == sector.id and not n.endless():
			n.amount = int(round(n.amount * hf))
			n.full = n.amount


## Neutral defenders stand at every settlement except homes and waystones. They guard it like a
## lair: anyone who comes close or hurts one is fought (and the others join in), then they
## walk back to their posts.
func spawn_militia() -> void:
	var radius := float(e["militia_guard_radius"])
	for s in sectors:
		if s.owner != -1:
			continue
		var n := int(e["settlements"][s.size]["militia"])
		for i in n:
			var a := float(i) / float(maxi(n, 1)) * TAU
			var u := world.spawn("militia", NEUTRAL, s.center + Vector2(cos(a), sin(a)) * 70.0)
			u.guard_radius = radius


## A neutral garrison (MapGen's groups) at a settlement: ranged and support units in an
## inner ring, the rest around them. They guard it as the militia do.
func spawn_garrison(s: Sector, types: Array) -> void:
	var radius := float(e["militia_guard_radius"])
	var inner: Array = []
	var outer: Array = []
	for t: String in types:
		var role := String(world.catalog.get_unit(t).get("role", ""))
		(inner if role == "ranged" or role == "support" else outer).append(t)
	for ring: Array in [[inner, 40.0], [outer, 80.0]]:
		var list: Array = ring[0]
		for i in list.size():
			var a := float(i) / float(list.size()) * TAU + (0.4 if ring[1] < 50.0 else 0.0)
			var u := world.spawn(String(list[i]), NEUTRAL, s.center + Vector2(cos(a), sin(a)) * float(ring[1]))
			u.guard_radius = radius


# --- Queries -------------------------------------------------------------------

func sector_at(p: Vector2) -> Sector:
	var best: Sector = null
	var best_d := INF
	for s in sectors:
		var d := s.center.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = s
	return best


func sector_by_id(id: int) -> Sector:
	if id >= 0 and id < sectors.size() and sectors[id].id == id:
		return sectors[id]
	for s in sectors:
		if s.id == id:
			return s
	return null


## True when this player's troops may be sent to take the settlement (the capture order).
## A standing capital is never captured, only torn down (attack its hall instead).
func can_capture(owner: int, s: Sector) -> bool:
	return settlements_active and s != null and s.owner != owner and not _standing_capital(s)


## A settlement's numbers. A home held by its own player is its hall: its workers, worker pace
## and gold follow the hall level (hall_levels "home") and it never grows on its own, so the hall
## is the one main building with 4 levels.
func settlement(s: Sector) -> Dictionary:
	var st: Dictionary = e["settlements"][s.size]
	if s.home_of >= 0 and s.home_of == s.owner:
		var p := player(s.owner)
		if p != null:
			var lv: Dictionary = e["hall_levels"][clampi(p.hall_level, 1, e["hall_levels"].size()) - 1]
			if lv.has("home"):
				st = st.duplicate()
				st.merge(lv["home"], true)
				st["next"] = ""
	return st


func people(owner: int) -> int:
	var n := 0
	for u in world.units:
		# A drafted worker walking off to a centre already counts as the recruit in training.
		if u.owner == owner and u.order != SimUnit.Order.DRAFT:
			n += 1
	for b in buildings:
		if b.owner == owner and b.has_recruit:
			n += 1  # the unit in training is already a person
	return n


func workers_of(owner: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for u in world.units:
		if u.owner == owner and u.role() == "worker":
			out.append(u)
	return out


func uses(owner: int, resource: String) -> bool:
	var p := player(owner)
	return p != null and resource in world.catalog.faction_resources(p.faction)


## The player who won (the only one still holding a settlement), or -1.
func winner() -> int:
	if players.size() < 2:
		return -1
	var alive: Array = []
	for pl in players:
		for s in sectors:
			if s.owner == pl.owner:
				alive.append(pl.owner)
				break
	return alive[0] if alive.size() == 1 else -1


## A faction twist value from economy.json for this player's faction.
func twist(owner: int, key: String, fallback: Variant) -> Variant:
	var p := player(owner)
	if p == null or not e.has("twists") or not e["twists"].has(p.faction):
		return fallback
	return e["twists"][p.faction].get(key, fallback)


## True while this tier may train without a worker (a faction twist with a cap on how many live).
func raises_without_worker(owner: int, tier: int) -> bool:
	var listed := false
	for t in twist(owner, "no_worker_tiers", []):
		if int(t) == tier:
			listed = true
	if not listed:
		return false
	var cap := int(twist(owner, "raised_base", 0)) + int(twist(owner, "raised_per_sector", 0)) * sectors_of(owner)
	var alive := 0
	for u in world.units:
		if u.owner == owner and int(u.def["tier"]) == tier:
			alive += 1
	return alive < cap


func sectors_of(owner: int) -> int:
	var n := 0
	for s in sectors:
		if s.owner == owner:
			n += 1
	return n


## Adds a building made elsewhere (wall pieces, see Fortifications) and gives it an id.
func add_building(b: Building) -> void:
	b.id = _next_building
	_next_building += 1
	buildings.append(b)


func remove_building(b: Building) -> void:
	buildings.erase(b)


func building(id: int) -> Building:
	for b in buildings:
		if b.id == id:
			return b
	return null


func node(id: int) -> ResNode:
	return nodes[id] if id >= 0 and id < nodes.size() else null


## A pile that can still be worked (exists and is not empty).
func live_node(id: int) -> ResNode:
	var n := node(id)
	return n if n != null and not n.depleted() else null


## What is left in a sector's piles, by resource: {resource: amount}. An endless pile counts
## as -1 for its resource (and the resource stays -1). Empty piles are left out; a resource
## whose piles are all empty is missing.
func sector_remaining(sector_id: int) -> Dictionary:
	var out := {}
	for n in nodes:
		if n.sector != sector_id or n.depleted():
			continue
		if n.endless() or int(out.get(n.resource, 0)) < 0:
			out[n.resource] = -1
		else:
			out[n.resource] = int(out.get(n.resource, 0)) + n.amount
	return out


## What is left in the piles of every sector this player holds, of the resources they use
## (endless piles as above).
func remaining(owner: int) -> Dictionary:
	var out := {}
	for r in gather_resources(owner):
		out[r] = 0
	for s in sectors:
		if s.owner != owner:
			continue
		var left := sector_remaining(s.id)
		for r in left:
			if not out.has(r):
				continue
			out[r] = -1 if int(left[r]) < 0 or int(out[r]) < 0 else int(out[r]) + int(left[r])
	return out


func hall_of(owner: int) -> Sector:
	for s in sectors:
		if s.home_of == owner and s.owner == owner:
			return s
	return null


func max_tier(owner: int) -> int:
	var p := player(owner)
	var t := int(e["hall_levels"][p.hall_level - 1]["max_tier"])
	return mini(t, tier_cap) if tier_cap > 0 else t


## True when this tier is closed by the campaign chapter (tier_cap), whatever the hall.
func capped(tier: int) -> bool:
	return tier_cap > 0 and tier > tier_cap


## The tiers that share one dwelling with this tier (economy.json dwelling_slots).
func slot_tiers(tier: int) -> Array:
	for sl in e["dwelling_slots"]:
		var ts: Array = (sl as Array).map(func(x: Variant) -> int: return int(x))
		if tier in ts:
			return ts
	return [tier]


## The lowest tiers of every dwelling slot (1, 3, 5, 6, 7, 8): what the build menu offers.
func slot_heads() -> Array:
	var out: Array = []
	for sl in e["dwelling_slots"]:
		out.append(int(sl[0]))
	return out


## The owner's dwelling that trains this tier, or null.
func dwelling_of(owner: int, tier: int) -> Building:
	for b in buildings:
		if b.owner == owner and b.kind == "dwelling" and b.trains(tier):
			return b
	return null


## Why a tier cannot be built or trained yet.
func tier_lock_text(tier: int) -> String:
	return "Tier %d is locked in this chapter" % tier if capped(tier) else "Upgrade the hall first"


func dwelling_cost(tier: int) -> Dictionary:
	var c: Dictionary = e["dwelling"]["cost"]
	var out := {}
	for r in c:
		var v := int(c[r][0]) + int(c[r][1]) * tier
		if v > 0:
			out[r] = v
	return out


## Training cost of one unit: gold from units.json, rare resources x rare_multiplier.
func unit_cost(type_id: String) -> Dictionary:
	var out := {}
	var def := world.catalog.get_unit(type_id)
	var c: Dictionary = def["cost"]
	# A faction twist can make its troops dearer (or cheaper) in gold.
	var gold_factor := float(e.get("twists", {}).get(def["faction"], {}).get("unit_gold_factor", 1.0))
	for r in c:
		var v := int(c[r])
		out[r] = int(ceil(v * gold_factor)) if r == "gold" else v * int(e["train"]["rare_multiplier"])
	# Timber and ore for gear: base + per tier.
	var tier := int(world.catalog.get_unit(type_id)["tier"])
	for r in ["wood", "ore"]:
		var wo: Array = e["train"][r]
		out[r] = int(out.get(r, 0)) + int(wo[0]) + int(wo[1]) * tier
	return out


func hall_upgrade_cost(owner: int) -> Dictionary:
	var p := player(owner)
	if p.hall_level >= e["hall_levels"].size():
		return {}
	var c: Dictionary = e["hall_levels"][p.hall_level]["cost"].duplicate()
	if c.has("rare"):
		var n := int(c["rare"])
		c.erase("rare")
		# The rare part is paid in the faction's own rare (the first one that is not gems).
		var rares := world.catalog.faction_resources(p.faction).filter(
			func(r: String) -> bool: return r != "wood" and r != "ore" and r != "gems")
		c[rares[0] if not rares.is_empty() else "gems"] = n
	return c


## The permanent upgrade of a dwelling (economy.json dwelling_upgrade); {} when it has none.
func dwelling_upgrade_cost(owner: int, tier: int) -> Dictionary:
	var u: Dictionary = e["dwelling_upgrade"]
	var out := {}
	for r in u["cost"]:
		out[r] = int(u["cost"][r][0]) + int(u["cost"][r][1]) * tier
	var from := int(u["rare_from_tier"])
	if tier >= from:
		var p := player(owner)
		var rares := world.catalog.faction_resources(p.faction).filter(
			func(r: String) -> bool: return r != "wood" and r != "ore" and r != "gems")
		var rare: String = rares[0] if not rares.is_empty() else "gems"
		out[rare] = int(out.get(rare, 0)) + int(u["rare_per_tier"]) * (tier - from + 1)
	return out


## Seconds one unit of this type trains once its recruit is in.
func train_seconds(type_id: String) -> float:
	return float(e["train"]["base_seconds"]) + float(e["train"]["seconds_per_tier"]) * int(world.catalog.get_unit(type_id)["tier"])


func dwelling_upgrade_seconds(tier: int) -> float:
	var u: Dictionary = e["dwelling_upgrade"]
	return float(u["base_seconds"]) + float(u["seconds_per_tier"]) * tier


## Whether this tier of the dwelling may still be upgraded (finished, that tier not yet upgraded,
## nothing else being upgraded, an upgraded unit exists). tier 0: its lowest tier.
func can_upgrade_dwelling(b: Building, tier: int = 0) -> bool:
	if b == null or b.kind != "dwelling":
		return false
	var t := tier if tier > 0 else b.tier
	return b.trains(t) and b.done() and not b.upgraded_tiers.has(t) and b.refit_left <= 0.0 \
		and world.catalog.upgrade_of_unit(b.unit_of(t)) != ""


func settlement_upgrade_cost(s: Sector) -> Dictionary:
	var nxt: String = settlement(s)["next"]
	if nxt == "":
		return {}
	var u: Dictionary = e["settlement_upgrade"]
	return {"gold": int(e["settlements"][nxt]["gold_per_min"]) * int(u["gold_per_min_factor"]),
		"wood": int(u["wood"]), "ore": int(u["ore"])}


## Where a building of this radius may go: inside own sectors, on free ground,
## clear of other buildings, settlement centres and resource nodes.
func can_place(owner: int, p: Vector2, radius: float) -> bool:
	var s := sector_at(p)
	if s == null or s.owner != owner:
		return false
	if p.distance_to(s.center) < radius + float(e.get("settlement_clearance", 110.0)):
		return false
	var nav := world.nav
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var q := p + Vector2(dx, dy) * radius * 0.45
			if nav.is_blocked(q):
				return false
	for b in buildings:
		if b.pos.distance_to(p) < b.radius + radius + 10.0:
			return false
	for n in nodes:
		if not n.depleted() and n.pos.distance_to(p) < radius + 34.0:
			return false
	return true


# --- Commands ------------------------------------------------------------------

func _notice(owner: int, text: String) -> void:
	notices.append({"owner": owner, "text": text})


func command_gather(ids: Array, node_id: int) -> void:
	var n := node(node_id)
	if n == null:
		return
	if n.depleted():
		if not world.owned_units(ids).is_empty():
			_notice(world.owned_units(ids)[0].owner, "This %s pile has run dry" % String(e["resources"][n.resource]).to_lower())
		return
	for u in world.owned_units(ids):
		if u.role() != "worker":
			continue
		if not uses(u.owner, n.resource):
			_notice(u.owner, "Your people have no use for %s" % e["resources"][n.resource])
			return
		_set_job(u, SimUnit.Order.GATHER, n.id)


## Places a dwelling (any tier of its slot, 1-8), storehouse (tier 0) or faction building (kind
## "special", special = its id in economy.json faction_buildings) and sends the workers to build it.
func command_build(ids: Array, owner: int, kind: String, tier: int, p: Vector2, special: String = "") -> Building:
	var pl := player(owner)
	if kind == "special":
		var why := special_lock_text(owner, special)
		if why != "":
			_notice(owner, why)
			return null
	if kind == "dwelling":
		tier = int(slot_tiers(tier)[0])
	if kind == "dwelling" and tier > max_tier(owner):
		_notice(owner, tier_lock_text(tier))
		return null
	var cost := build_cost(owner, kind, tier, special)
	var radius := float(e["storehouse"]["radius"]) if kind == "storehouse" else float(e["dwelling"]["radius"])
	if not can_place(owner, p, radius):
		_notice(owner, "Cannot build there")
		return null
	if not pl.can_pay(cost):
		_notice(owner, "Not enough resources")
		return null
	for b in buildings:
		if b.owner == owner and b.kind == "dwelling" and kind == "dwelling" and b.trains(tier):
			_notice(owner, "You already have that dwelling")
			return null
	pl.pay(cost)
	var b := _make_building(owner, kind, tier, p, special)
	b.progress = 0.0
	for u in world.owned_units(ids):
		if u.role() == "worker" and u.owner == owner:
			_set_job(u, SimUnit.Order.BUILD, b.id)
	return b


## What a building costs to place.
func build_cost(owner: int, kind: String, tier: int, special: String = "") -> Dictionary:
	if kind == "special":
		return (special_def(player(owner).faction, special).get("cost", {}) as Dictionary)
	return dwelling_cost(tier) if kind == "dwelling" else (e["storehouse"]["cost"] as Dictionary)


# --- Faction buildings (economy.json faction_buildings; effects in FactionBuildings) --------

func special_defs(faction: String) -> Array:
	return e.get("faction_buildings", {}).get(faction, [])


func special_def(faction: String, id: String) -> Dictionary:
	for d: Dictionary in special_defs(faction):
		if d["id"] == id:
			return d
	return {}


## The faction building a placed one is ({} for any other building).
func def_of(b: Building) -> Dictionary:
	if b.kind != "special":
		return {}
	var pl := player(b.owner)
	return special_def(pl.faction, b.special) if pl != null else {}


## How many of this faction building the owner has (being built included).
func special_count(owner: int, id: String) -> int:
	var n := 0
	for b in buildings:
		if b.owner == owner and b.kind == "special" and b.special == id:
			n += 1
	return n


## Why this faction building can't be placed now ("" = it can, cost aside).
func special_lock_text(owner: int, id: String) -> String:
	var pl := player(owner)
	var d := special_def(pl.faction, id)
	if d.is_empty():
		return "Your house cannot build that"
	if pl.hall_level < int(d["hall"]):
		return "Needs hall %d" % int(d["hall"])
	if special_count(owner, id) >= int(d["limit"]):
		return "You have as many as you may (%d)" % int(d["limit"])
	return ""


## A building's name for the view: a faction building's own, else the art key's.
func building_name(b: Building) -> String:
	var d := def_of(b)
	if not d.is_empty():
		return String(d["name"])
	return String(world.catalog.building_names.get(b.key, b.key))


func command_help_build(ids: Array, building_id: int) -> void:
	var b := building(building_id)
	if b == null or b.done():
		return
	for u in world.owned_units(ids):
		if u.role() == "worker" and u.owner == b.owner:
			_set_job(u, SimUnit.Order.BUILD, b.id)


## Queues one unit of this tier (0: the dwelling's lowest tier) at a dwelling.
func command_train(owner: int, building_id: int, tier: int = 0) -> bool:
	var b := building(building_id)
	if b == null or b.owner != owner or b.kind != "dwelling" or not b.done():
		return false
	var t := tier if tier > 0 else b.tier
	if not b.trains(t):
		return false
	if t > max_tier(owner):
		_notice(owner, tier_lock_text(t))
		return false
	if b.refit_left > 0.0:
		_notice(owner, "Being upgraded")
		return false
	if b.queue.size() >= 5:
		_notice(owner, "Queue is full")
		return false
	var type_id := b.unit_of(t)
	var cost := unit_cost(type_id)
	if raises_without_worker(owner, t) and cost.has("gold"):
		cost["gold"] = int(ceil(float(cost["gold"]) * float(twist(owner, "raised_gold_factor", 1.0))))
	var pl := player(owner)
	if not pl.can_pay(cost):
		_notice(owner, "Not enough resources")
		return false
	pl.pay(cost)
	b.queue.append(type_id)
	return true


## Buys the permanent upgrade of one tier of a dwelling (0: its lowest tier). It needs an empty
## queue and trains nothing meanwhile; once done it trains that tier's upgraded unit for good.
func command_upgrade_dwelling(owner: int, building_id: int, tier: int = 0) -> bool:
	var b := building(building_id)
	var t := tier if tier > 0 else (b.tier if b != null else 0)
	if b == null or b.owner != owner or not can_upgrade_dwelling(b, t):
		return false
	if not b.queue.is_empty() or b.has_recruit:
		_notice(owner, "Finish training first")
		return false
	var cost := dwelling_upgrade_cost(owner, t)
	var pl := player(owner)
	if not pl.can_pay(cost):
		_notice(owner, "Not enough resources")
		return false
	pl.pay(cost)
	b.refit_left = dwelling_upgrade_seconds(t)
	b.refit_tier = t
	return true


func command_upgrade_hall(owner: int) -> bool:
	var pl := player(owner)
	if pl.hall_upgrading > 0.0 or pl.hall_level >= e["hall_levels"].size():
		return false
	var cost := hall_upgrade_cost(owner)
	if not pl.can_pay(cost):
		_notice(owner, "Not enough resources")
		return false
	pl.pay(cost)
	pl.hall_upgrading = float(e["hall_levels"][pl.hall_level]["seconds"])
	return true


func command_upgrade_settlement(owner: int, sector_id: int) -> bool:
	var s := sectors[sector_id]
	if s.owner != owner or s.growing > 0.0 or settlement(s)["next"] == "" or s.size == "waystone":
		if s.home_of == owner and s.owner == owner:
			_notice(owner, "Raise the hall instead")
		return false
	var cost := settlement_upgrade_cost(s)
	var pl := player(owner)
	if not pl.can_pay(cost):
		_notice(owner, "Not enough resources")
		return false
	pl.pay(cost)
	s.growing = float(e["settlement_upgrade"]["seconds"])
	return true


func command_rally(owner: int, building_id: int, p: Vector2) -> void:
	var b := building(building_id)
	if b != null and b.owner == owner:
		b.rally = p


func _set_job(u: SimUnit, order: int, target: int) -> void:
	u.order = order
	u.job = target
	u.target_id = -1
	u.path = PackedVector2Array()
	u.gather_timer = 0.0
	u.group_speed = 0.0


# --- Tick ------------------------------------------------------------------------

func step() -> void:
	notices.clear()
	var dt := world.dt
	for pl in players:
		if pl.hall_upgrading > 0.0:
			pl.hall_upgrading -= dt
			if pl.hall_upgrading <= 0.0:
				pl.hall_upgrading = 0.0
				pl.hall_level += 1
				pl.hall_times.append(float(world.tick) * world.dt)
	if not settlements_active:
		for b in buildings:
			_step_building(b, dt)
		return
	_step_capture(dt)
	for s in sectors:
		if s.owner < 0 or s.owner == NEUTRAL:
			continue
		if s.growing > 0.0:
			s.growing -= dt
			if s.growing <= 0.0:
				s.growing = 0.0
				s.size = settlement(s)["next"]
			continue
		if s.unsettled > 0.0:
			s.unsettled -= dt
			continue
		var st := settlement(s)
		var pl := player(s.owner)
		if pl != null:
			pl.gold_frac += float(st["gold_per_min"]) / 60.0 * dt * (1.0 + pl.income_bonus)
			if pl.gold_frac >= 1.0:
				var whole := int(pl.gold_frac)
				pl.gold_frac -= whole
				pl.earn("gold", whole)
		_step_spawn(s, st, dt)
	for b in buildings:
		_step_building(b, dt)
	if world.tick % STAFF_EVERY == 0:
		_staff_sites()
		for pl in players:
			_rebalance_once(pl.owner)


func _step_capture(dt: float) -> void:
	var radius := float(e["capture_radius"])
	for s in sectors:
		if _standing_capital(s):
			s.capture = 0.0  # a capital is never taken: it has to be torn down (BaseDefense)
			s.capturer = -1
			s.contested = false
			continue
		var present := {}
		for u: SimUnit in world.nearby(s.center, radius):
			if u.role() != "worker":
				present[u.owner] = true
		s.contested = present.size() > 1 or (present.size() == 1 and present.has(s.owner) == false and s.owner >= 0
			and _defenders_near(s))
		var takers: Array = []
		for o in present:
			if o != s.owner and o != NEUTRAL:
				takers.append(o)
		var held := present.has(s.owner) or present.has(NEUTRAL)
		if takers.size() != 1 or held:
			# Nobody taking it: the half-taken settlement recovers, faster with its own
			# troops (or militia) back in it. Two rival takers and no defenders: it waits.
			if s.capture > 0.0 and (takers.size() == 0 or held):
				var dk: Dictionary = e["capture_decay"]
				var rate := float(dk["defended" if held else "empty"])
				s.capture = maxf(0.0, s.capture - dt / capture_seconds(s) * rate)
				if s.capture <= 0.0:
					s.capturer = -1
			continue
		var o: int = takers[0]
		if s.capturer != o:
			s.capturer = o
			s.capture = 0.0
		s.capture += dt / capture_seconds(s)
		if s.capture >= 1.0:
			_take(s, o)


## Seconds to take this settlement from its current owner: its capture_time, sped up by
## capture_speed, then slowed by the owner's twist and for a home hall (only matters on a
## setup without hall hit points; normally a capital cannot be captured at all).
func capture_seconds(s: Sector) -> float:
	var ct := float(settlement(s)["capture_time"]) / float(e.get("capture_speed", 1.0))
	if s.owner >= 0 and s.owner != NEUTRAL:
		ct *= float(twist(s.owner, "capture_time_factor", 1.0))
		if s.home_of == s.owner:
			ct *= float(e.get("home_capture_factor", 1.0))  # a hall holds out longer
	return ct


## True for a home held by its founder while its hall has hit points to lose.
func _standing_capital(s: Sector) -> bool:
	return s.home_of >= 0 and s.owner == s.home_of and (e.get("hall_defense", {}) as Dictionary).has("hp")


## A house whose capital fell is out: its other settlements fall empty, its buildings come
## down, and its people are gone. `by` is the player who razed the hall (-1: unknown).
func eliminate(owner: int, by: int = -1) -> void:
	var pl := player(owner)
	if pl == null or pl.defeated:
		return
	pl.defeated = true
	pl.hall_upgrading = 0.0
	for s in sectors:
		if s.home_of == owner:
			s.home_of = -1
		if s.owner == owner:
			s.owner = -1
			s.capture = 0.0
			s.capturer = -1
			s.growing = 0.0
			s.unsettled = 0.0
	for b in buildings.duplicate():
		if b.owner != owner:
			continue
		if b.is_fort():
			world.remove_structure(b.structure)  # Fortifications takes the piece down next tick
		else:
			if b.structure >= 0:
				world.remove_structure(b.structure)  # a unit building's hit points (BaseDefense)
			buildings.erase(b)
	for u in world.units.duplicate():
		if u.owner == owner and u.alive:
			world._die(u, null)
	world.events.append({"type": "defeated", "owner": owner, "by": by})


func _defenders_near(_s: Sector) -> bool:
	return false


func _take(s: Sector, o: int) -> void:
	var old := s.owner
	s.owner = o
	s.capture = 0.0
	s.capturer = -1
	s.growing = 0.0
	s.unsettled = float(e["unsettled_seconds"])
	world.events.append({"type": "capture", "sector": s.id, "owner": o, "from": old})
	# Plunder (a faction twist): the taker carries off gold from the settlement.
	var plunder: Dictionary = twist(o, "plunder", {})
	var loot := int(plunder.get(s.size, 0))
	if loot > 0:
		player(o).earn("gold", loot)
		world.events.append({"type": "plunder", "sector": s.id, "owner": o, "gold": loot})
	# The old owner's workers from here flee to their nearest settlement.
	if old >= 0 and old != NEUTRAL:
		var refuge := _nearest_own_settlement(old, s.center, s.id)
		for u in workers_of(old):
			if u.home_sector == s.id:
				if refuge == null:
					u.home_sector = -1
				else:
					u.home_sector = refuge.id
					world.command_move([u.id], refuge.center)


func _nearest_own_settlement(owner: int, p: Vector2, except: int) -> Sector:
	var best: Sector = null
	for s in sectors:
		if s.owner == owner and s.id != except and s.size != "waystone":
			if best == null or s.center.distance_to(p) < best.center.distance_to(p):
				best = s
	return best


func _step_spawn(s: Sector, st: Dictionary, dt: float) -> void:
	var cap := int(st["workers"])
	if cap <= 0:
		return
	var n := 0
	for u in world.units:
		if u.owner == s.owner and u.role() == "worker" and u.home_sector == s.id:
			n += 1
	if n >= cap or people(s.owner) >= int(e["people_cap"]):
		s.spawn_timer = 0.0
		return
	s.spawn_timer += dt
	if s.spawn_timer >= float(st["spawn_every"]):
		s.spawn_timer = 0.0
		var a := float((world.tick * 7 + s.id * 13) % 360) * PI / 180.0
		var u := _spawn_worker(s.owner, s, s.center + Vector2(cos(a), sin(a)) * 60.0)
		world.events.append({"type": "worker", "unit": u.id, "owner": s.owner})


func _spawn_worker(owner: int, s: Sector, p: Vector2) -> SimUnit:
	var pl := player(owner)
	var u := world.spawn(world.catalog.worker_type(pl.faction), owner, p)
	u.home_sector = s.id
	auto_job(u)
	return u


# --- Worker distribution ---------------------------------------------------------------
# The player sets a weight from 0 to 10 per resource (the top bar); gatherers spread over
# the resources their sectors offer in those proportions. Building and drafting take the
# worker whose leaving brings the spread closest to that mix.

## The resources this player's workers gather, in the faction's order, without repeats.
func gather_resources(owner: int) -> Array[String]:
	var out: Array[String] = []
	var pl := player(owner)
	if pl == null:
		return out
	for r in world.catalog.faction_resources(pl.faction):
		if not (String(r) in out):
			out.append(String(r))
	return out


func gather_weight(owner: int, r: String) -> int:
	var pl := player(owner)
	if pl == null:
		return 0
	if pl.gather_weights.has(r):
		return int(pl.gather_weights[r])
	var conf: Dictionary = e["gather_weights"]
	return int(conf["default"].get(r, conf["other"]))


## Sets one resource's weight (0 .. max) and moves workers toward the new mix at once.
func set_gather_weight(owner: int, r: String, weight: int) -> void:
	var pl := player(owner)
	if pl == null or not uses(owner, r):
		return
	pl.gather_weights[r] = clampi(weight, 0, int(e["gather_weights"]["max"]))
	for i in workers_of(owner).size():
		if not _rebalance_once(owner):
			break


# --- Worker upgrades (storehouse) ----------------------------------------------------
# Each resource the faction gathers has its own track of levels (economy.json worker_upgrades).
# A finished storehouse researches one level at a time; once done, every load of that
# resource is worth more, for good.

## Levels of this resource's worker upgrade done so far.
func gather_level(owner: int, r: String) -> int:
	var pl := player(owner)
	return int(pl.gather_levels.get(r, 0)) if pl != null else 0


func gather_levels_max() -> int:
	return (e["worker_upgrades"]["bonus"] as Array).size()


## The share loads of this resource gain from the upgrades done (0.3 = +30%).
func gather_bonus(owner: int, r: String, level: int = -1) -> float:
	var n := gather_level(owner, r) if level < 0 else level
	var out := 0.0
	var bonus: Array = e["worker_upgrades"]["bonus"]
	for i in mini(n, bonus.size()):
		out += float(bonus[i])
	return out


## What the next level of this resource's upgrade costs ({} once all are done).
func gather_upgrade_cost(owner: int, r: String) -> Dictionary:
	var lv := gather_level(owner, r)
	var conf: Dictionary = e["worker_upgrades"]
	if lv >= gather_levels_max():
		return {}
	var cost: Dictionary = (conf["cost"][lv] as Dictionary).duplicate()
	var rare := int(conf["rare"][lv])
	if rare > 0 and not r in ["gold", "wood", "ore"]:
		cost[r] = rare
	return cost


func gather_upgrade_seconds(owner: int, r: String) -> float:
	var lv := mini(gather_level(owner, r), gather_levels_max() - 1)
	return float(e["worker_upgrades"]["seconds"][lv])


## The storehouse working on this resource's upgrade, or null.
func gather_upgrade_running(owner: int, r: String) -> Building:
	for b in buildings:
		if b.owner == owner and b.kind == "storehouse" and b.study == r:
			return b
	return null


## "" if the next level of this resource's upgrade may be bought at this storehouse now, else why not.
func gather_upgrade_lock(owner: int, building_id: int, r: String) -> String:
	var b := building(building_id)
	var pl := player(owner)
	if b == null or pl == null or b.owner != owner or b.kind != "storehouse":
		return "Not yours"
	if not b.done():
		return "Still being built"
	if not r in gather_resources(owner):
		return "Your workers do not gather that"
	var lv := gather_level(owner, r)
	if lv >= gather_levels_max():
		return "Fully upgraded"
	if gather_upgrade_running(owner, r) != null:
		return "Under way"
	if b.study != "":
		return "This storehouse is busy"
	var need := int(e["worker_upgrades"]["hall"][lv])
	if pl.hall_level < need:
		return "Needs hall level %d" % need
	if not pl.can_pay(gather_upgrade_cost(owner, r)):
		return "Not enough resources"
	return ""


## Buys the next level of a resource's worker upgrade at a storehouse.
func command_gather_upgrade(owner: int, building_id: int, r: String) -> bool:
	var why := gather_upgrade_lock(owner, building_id, r)
	if why != "":
		_notice(owner, why)
		return false
	var b := building(building_id)
	player(owner).pay(gather_upgrade_cost(owner, r))
	b.study = r
	b.study_left = gather_upgrade_seconds(owner, r)
	b.study_total = b.study_left
	return true


func _step_study(b: Building, dt: float) -> void:
	if b.study == "":
		return
	b.study_left -= dt
	if b.study_left > 0.0:
		return
	var pl := player(b.owner)
	var r := b.study
	b.study = ""
	b.study_left = 0.0
	if pl == null:
		return
	pl.gather_levels[r] = gather_level(b.owner, r) + 1
	world.events.append({"type": "gather_upgraded", "building": b.id, "owner": b.owner, "resource": r,
		"level": int(pl.gather_levels[r])})


## Gatherers per resource right now (workers walking to or working a pile, or carrying home).
func gather_counts(owner: int, except: int = -1) -> Dictionary:
	var out := {}
	for r in gather_resources(owner):
		out[r] = 0
	for u in workers_of(owner):
		if u.id == except or u.order != SimUnit.Order.GATHER:
			continue
		var n := node(u.job)
		if n != null and out.has(n.resource):
			out[n.resource] += 1
	return out


## How many of `count` gatherers each resource should have: the weights, over the resources
## with a pile in the player's sectors, shared out by largest remainder. All weights at 0
## counts as all equal, so workers never stand about.
func gather_targets(owner: int, count: int) -> Dictionary:
	var out := {}
	var avail := _available(owner)
	var rs: Array[String] = []
	var total := 0
	for r in gather_resources(owner):
		out[r] = 0
		if avail.has(r):
			rs.append(r)
			total += gather_weight(owner, r)
	if rs.is_empty() or count <= 0:
		return out
	var weights := {}
	for r in rs:
		weights[r] = gather_weight(owner, r) if total > 0 else 1
	var sum := 0
	for r in rs:
		sum += int(weights[r])
	var given := 0
	var rest: Array = []
	for i in rs.size():
		var exact := float(count) * float(weights[rs[i]]) / float(sum)
		out[rs[i]] = int(floor(exact))
		given += int(out[rs[i]])
		rest.append([exact - floor(exact), int(weights[rs[i]]), -i, rs[i]])
	rest.sort_custom(func(x: Array, y: Array) -> bool: return x.slice(0, 3) > y.slice(0, 3))
	for i in count - given:
		out[rest[i % rest.size()][3]] += 1
	return out


## Resources with at least one pile in this player's sectors.
func _available(owner: int) -> Dictionary:
	var out := {}
	for n in nodes:
		if sectors[n.sector].owner == owner and uses(owner, n.resource) and not n.depleted():
			out[n.resource] = true
	return out


## A worker without work joins the resource furthest below its share.
func auto_job(u: SimUnit) -> void:
	if player(u.owner) == null:
		return
	var counts := gather_counts(u.owner, u.id)
	var n_all := 1
	for r in counts:
		n_all += int(counts[r])
	var targets := gather_targets(u.owner, n_all)
	var best_r := ""
	var best_gap := -INF
	for r in gather_resources(u.owner):
		if int(targets.get(r, 0)) <= 0:
			continue
		var gap := float(int(targets[r]) - int(counts[r]))
		if gap > best_gap:
			best_gap = gap
			best_r = r
	if best_r != "":
		_send_to(u, best_r)


## Sends a worker to the best pile of resource r in its owner's sectors: near, and not crowded.
func _send_to(u: SimUnit, r: String) -> bool:
	var best: ResNode = null
	var best_d := INF
	for n in nodes:
		if n.resource != r or sectors[n.sector].owner != u.owner or n.depleted():
			continue
		var d := (n.pos.distance_to(u.pos) + 150.0) * (1.0 + 0.5 * float(_gatherers(n.id)))
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return false
	_set_job(u, SimUnit.Order.GATHER, best.id)
	return true


## Moves one gatherer from the resource most over its share to the one most under it.
## Returns false when the spread already matches the weights.
func _rebalance_once(owner: int) -> bool:
	var counts := gather_counts(owner)
	var n_all := 0
	for r in counts:
		n_all += int(counts[r])
	var targets := gather_targets(owner, n_all)
	var over := ""
	var under := ""
	var over_by := 0
	var under_by := 0
	for r in gather_resources(owner):
		var d := int(counts[r]) - int(targets.get(r, 0))
		if d > over_by:
			over_by = d
			over = r
		if -d > under_by:
			under_by = -d
			under = r
	if over == "" or under == "":
		return false
	# The one on the surplus resource closest to a pile of the short one, empty-handed first.
	var best: SimUnit = null
	var best_d := INF
	for u in workers_of(owner):
		if u.order != SimUnit.Order.GATHER or node(u.job) == null or node(u.job).resource != over:
			continue
		var d := _nearest_pile_dist(owner, under, u.pos) + (0.0 if u.carry_amount == 0 else 400.0)
		if d < best_d:
			best_d = d
			best = u
	return best != null and _send_to(best, under)


func _nearest_pile_dist(owner: int, r: String, p: Vector2) -> float:
	var best := INF
	for n in nodes:
		if n.resource == r and sectors[n.sector].owner == owner and not n.depleted():
			best = minf(best, n.pos.distance_to(p))
	return best


## The worker to pull off for a building or a recruit at p: an idle one if any (the
## nearest), else the gatherer whose leaving keeps the spread closest to the weights
## (one from the resource most over its share), the nearest of those. Null when every
## worker is already building or being drafted.
func spare_worker(owner: int, p: Vector2) -> SimUnit:
	var counts := gather_counts(owner)
	var n_all := 0
	for r in counts:
		n_all += int(counts[r])
	var targets := gather_targets(owner, maxi(n_all - 1, 0))
	var best: SimUnit = null
	var best_score := INF
	for u in workers_of(owner):
		if u.order == SimUnit.Order.DRAFT or u.order == SimUnit.Order.BUILD:
			continue
		var score := u.pos.distance_to(p)
		var n := node(u.job) if u.order == SimUnit.Order.GATHER else null
		if n == null:
			score -= 1.0e7  # not gathering: free to go
		else:
			score -= 1.0e4 * float(int(counts.get(n.resource, 0)) - int(targets.get(n.resource, 0)))
		if score < best_score:
			best_score = score
			best = u
	return best


func _gatherers(node_id: int) -> int:
	var n := 0
	for u in world.units:
		if u.order == SimUnit.Order.GATHER and u.job == node_id:
			n += 1
	return n


func _make_building(owner: int, kind: String, tier: int, p: Vector2, special: String = "") -> Building:
	var pl := player(owner)
	var keys: Dictionary = e["buildings"][pl.faction]
	var b := Building.new()
	b.id = _next_building
	_next_building += 1
	b.owner = owner
	b.kind = kind
	b.tier = tier
	b.pos = p
	if kind == "dwelling":
		b.key = keys["dwellings"][tier - 1]
		b.tiers = slot_tiers(tier)
		var line := world.catalog.faction_units(pl.faction)
		for t in b.tiers:
			b.units[t] = line[int(t) - 1]
		b.unit_type = b.unit_of(tier)
		b.radius = float(e["dwelling"]["radius"])
		b.build_seconds = float(e["dwelling"]["base_seconds"]) + float(e["dwelling"]["seconds_per_tier"]) * tier
	elif kind == "special":
		var d := special_def(pl.faction, special)
		b.special = special
		b.key = d["key"]
		b.radius = float(e["dwelling"]["radius"])
		b.build_seconds = float(d.get("seconds", float(e["dwelling"]["base_seconds"]) + float(e["dwelling"]["seconds_per_tier"]) * 3.0))
	else:
		b.key = keys["storehouse"]
		b.radius = float(e["storehouse"]["radius"])
		b.build_seconds = float(e["storehouse"]["seconds"])
	b.rally = p + Vector2(0, b.radius + 40.0)
	# Block the ground under it.
	var nav := world.nav
	var c := nav.cell_of(p)
	var rc := int(ceil(b.radius / NavGrid.CELL))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var cell := c + Vector2i(dx, dy)
			if nav.center_of(cell).distance_to(p) <= b.radius * 0.8 and not nav.is_blocked_cell(cell):
				nav.set_blocked(cell, true, NavGrid.Kind.BUILDING)
				b.cells.append(cell)
	buildings.append(b)
	world.push_out_of_blocked()
	return b


## The nearest free standing place for a unit of radius r at or around p: p itself, else
## rings of places around it (up to `rings`). A place is taken when a unit stands on it or
## one of this owner's units is already walking to it (`except` = the unit asking).
func free_spot(owner: int, p: Vector2, r: float, rings: int, except: int = -1) -> Vector2:
	var nav := world.nav
	var step := r * 2.0 + 8.0
	var heading: Array[Vector2] = []
	for o in world.units:
		if o.alive and o.owner == owner and o.id != except and o.order == SimUnit.Order.MOVE:
			heading.append(o.order_point)
	for ring in rings + 1:
		var n := 1 if ring == 0 else ring * 6
		for i in n:
			var a := TAU * float(i) / float(n) + float(ring) * 0.5
			var q := p + Vector2(cos(a), sin(a)) * step * float(ring)
			if nav.is_blocked(q):
				continue
			var taken := false
			for o: SimUnit in world.nearby(q, step + 20.0):
				if o.id != except and o.pos.distance_to(q) < r + o.radius() + 2.0:
					taken = true
					break
			if not taken:
				for h in heading:
					if h.distance_to(q) < step - 2.0:
						taken = true
						break
			if not taken:
				return q
	return p


func _step_building(b: Building, dt: float) -> void:
	if b.kind == "storehouse" and b.done():
		_step_study(b, dt)
		return
	if not b.done() or b.kind != "dwelling":
		return
	if b.refit_left > 0.0:
		b.refit_left -= dt
		if b.refit_left <= 0.0:
			b.refit_left = 0.0
			var t := b.refit_tier
			b.upgraded_tiers[t] = true
			b.upgraded = true
			b.units[t] = world.catalog.upgrade_of_unit(b.unit_of(t))
			b.unit_type = b.unit_of(b.tier)
			world.events.append({"type": "dwelling_upgraded", "building": b.id, "owner": b.owner, "tier": t})
		return
	if b.queue.is_empty():
		return
	if b.has_recruit:
		b.train_left -= dt
		if b.train_left <= 0.0:
			var t: String = b.queue.pop_front()
			b.has_recruit = false
			var u := world.spawn(t, b.owner, b.pos + Vector2(0, b.radius + 14.0))
			u.pos = free_spot(b.owner, u.pos, u.radius(), 3, u.id)  # beside the last one out, not on it
			u.prev_pos = u.pos
			var pl := player(b.owner)
			pl.trained[t] = int(pl.trained.get(t, 0)) + 1
			# Each recruit gets its own place by the rally point, so a queue of them
			# lines up there instead of shoving for one spot.
			world.command_move([u.id], free_spot(b.owner, b.rally, u.radius(), 8, u.id))
			world.events.append({"type": "trained", "unit": u.id, "owner": b.owner})
		return
	# Some factions raise these units without a worker.
	var head_tier := int(world.catalog.get_unit(String(b.queue[0]))["tier"])
	if raises_without_worker(b.owner, head_tier):
		b.has_recruit = true
		b.recruit = -1
		b.train_left = train_seconds(String(b.queue[0])) \
			* float(twist(b.owner, "raised_time_factor", 1.0))
		b.train_total = b.train_left
		return
	# Draft a free worker: training starts at once, and the worker walks off to its
	# nearest settlement centre (hall, town, village) and leaves the map there.
	var best := spare_worker(b.owner, b.pos)
	if best == null:
		if world.tick % (world.tick_rate * 5) == 0:
			_notice(b.owner, "%s needs a worker to train" % building_name(b))
		return
	_set_job(best, SimUnit.Order.DRAFT, -1)
	b.recruit = -1
	b.has_recruit = true
	b.train_left = train_seconds(String(b.queue[0]))
	b.train_total = b.train_left


# --- Worker behaviour (called from SimWorld._think) ---------------------------------

func think_worker(u: SimUnit) -> void:
	match u.order:
		SimUnit.Order.GATHER:
			_think_gather(u)
		SimUnit.Order.BUILD:
			var b := building(u.job)
			if b != null and b.done() and b.is_fort():
				b = _next_piece(u, b)  # a wall: on to the next unbuilt piece of it
				if b != null:
					u.job = b.id
			if b == null or b.done():
				auto_job(u)
				if u.order == SimUnit.Order.BUILD:
					world.go_idle(u)
				return
			# The footprint is square on the grid: a worker at its corner is close enough.
			if _at_site(u, b):
				b.progress = minf(1.0, b.progress + world.dt / b.build_seconds)
				u.since_attack = 0.0 if world.tick % 10 == 0 else u.since_attack
				if b.done():
					world.events.append({"type": "built", "building": b.id, "owner": b.owner})
			else:
				_walk_to(u, b.pos)
		SimUnit.Order.DRAFT:
			# Drafted: its unit is already training. It walks to the nearest centre and
			# leaves the map there (at once if its owner holds none).
			var c := _nearest_centre(u)
			if c == Vector2.INF or u.pos.distance_to(c) <= u.radius() + 70.0 \
					or u.pos.distance_to(world.nav.nearest_free(c)) <= u.radius() + 16.0:
				world.retire(u)
			else:
				_walk_to(u, c)


## Building sites (dwellings, storehouses) come first: one nobody is working on, because its
## builder was drafted, killed or sent elsewhere, gets the nearest free worker at once.
func _staff_sites() -> void:
	var manned := {}
	for u in world.units:
		if u.order == SimUnit.Order.BUILD and u.role() == "worker":
			manned[u.job] = true
	for b in buildings:
		if b.done() or b.is_fort() or manned.has(b.id) or b.owner < 0 or b.owner == NEUTRAL:
			continue
		var u := spare_worker(b.owner, b.pos)
		if u != null:
			_set_job(u, SimUnit.Order.BUILD, b.id)
			manned[b.id] = true


## The unbuilt piece of the same wall nearest the worker, or null.
func _next_piece(u: SimUnit, done_piece: Building) -> Building:
	var best: Building = null
	for b in buildings:
		if b.is_fort() and b.chain == done_piece.chain and b.owner == u.owner and not b.done():
			if best == null or b.pos.distance_to(u.pos) < best.pos.distance_to(u.pos):
				best = b
	return best


func _think_gather(u: SimUnit) -> void:
	var n := node(u.job)
	var g: Dictionary = e["gather"]
	# An emptied pile: bring home what is carried, then find other work.
	var dry := n != null and n.depleted()
	if n == null or sectors[n.sector].owner != u.owner or (dry and u.carry_amount == 0):
		world.go_idle(u)
		auto_job(u)
		return
	if u.carry_amount >= int(g["carry"]) or dry:
		var drop := _nearest_drop(u)
		if drop == Vector2.INF:
			return
		if u.pos.distance_to(drop) <= 70.0:
			var pl := player(u.owner)
			# A faction twist can make some loads worth more (Thornwood's timber).
			# Storehouse upgrades add their share on top; parts of a unit carry over to the next load.
			var bonus: Dictionary = twist(u.owner, "gather_factor", {})
			var exact := u.carry_amount * float(bonus.get(u.carry_type, 1.0)) * (1.0 + gather_bonus(u.owner, u.carry_type) + pl.income_bonus)
			if gather_level(u.owner, u.carry_type) == 0 and pl.income_bonus <= 0.0:
				exact = round(exact)
			exact += float(pl.gather_frac.get(u.carry_type, 0.0))
			var amount := int(floor(exact + 0.0001))
			pl.gather_frac[u.carry_type] = maxf(0.0, exact - amount)
			pl.earn(u.carry_type, amount)
			world.events.append({"type": "deposit", "unit": u.id, "owner": u.owner, "resource": u.carry_type,
				"amount": amount})
			u.carry_amount = 0
			u.path = PackedVector2Array()
		else:
			_walk_to(u, drop)
		return
	if u.pos.distance_to(n.pos) <= float(g["reach"]) + u.radius():
		u.gather_timer += world.dt
		if u.gather_timer >= float(g["seconds"]):
			u.gather_timer = 0.0
			u.carry_amount = n.take(int(g["carry"]))
			u.carry_type = n.resource
			u.path = PackedVector2Array()
			if n.depleted():
				_pile_ran_dry(n)
	else:
		_walk_to(u, n.pos)


## An emptied pile: tells the view and the sector's owner.
func _pile_ran_dry(n: ResNode) -> void:
	var owner := sectors[n.sector].owner
	world.events.append({"type": "pile_depleted", "node": n.id, "resource": n.resource, "sector": n.sector,
		"owner": owner})
	if owner >= 0 and owner != NEUTRAL:
		var left := int(sector_remaining(n.sector).get(n.resource, 0))
		var what := String(e["resources"][n.resource])
		_notice(owner, "A %s pile has run dry%s" % [what.to_lower(),
			"" if left != 0 else " - no %s left in that sector" % what.to_lower()])


## Settlement centres (not waystones), and finished storehouses, of the owner.
func _nearest_drop(u: SimUnit) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for s in sectors:
		if s.owner == u.owner and s.size != "waystone":
			var d := u.pos.distance_to(s.center)
			if d < best_d:
				best_d = d
				best = s.center
	for b in buildings:
		if b.owner == u.owner and b.kind == "storehouse" and b.done():
			var d := u.pos.distance_to(b.pos)
			if d < best_d:
				best_d = d
				best = b.pos
	return best


## The nearest settlement centre (hall, town, village; not a waystone or storehouse)
## its owner holds, or Vector2.INF.
func _nearest_centre(u: SimUnit) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for s in sectors:
		if s.owner == u.owner and s.size != "waystone":
			var d := u.pos.distance_to(s.center)
			if d < best_d:
				best_d = d
				best = s.center
	return best


## A worker is at a building when it is beside its footprint (square on the grid, so a
## corner counts), or has walked as close as the ground lets it: the nearest free spot
## to the building, which next to rock or another building can lie a little farther out.
func _at_site(u: SimUnit, b: Building) -> bool:
	var d := u.pos.distance_to(b.pos)
	if d <= b.radius * 1.3 + u.radius() + 10.0:
		return true
	return d <= b.radius * 2.0 + u.radius() and u.pos.distance_to(world.nav.nearest_free(b.pos)) <= u.radius() + 16.0


func _walk_to(u: SimUnit, p: Vector2) -> void:
	# Paths end at the nearest free spot to p (p itself may be under a building).
	if u.path.is_empty() or u.path_i >= u.path.size() \
			or u.path[u.path.size() - 1].distance_to(world.nav.nearest_free(p)) > 60.0:
		world.set_path(u, p)
	world.follow_path(u)
