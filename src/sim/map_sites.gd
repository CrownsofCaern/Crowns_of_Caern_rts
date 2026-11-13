class_name MapSites
extends RefCounted
## Places on a skirmish map for heroes (headless, deterministic):
## - lairs: neutral creatures guard loot; once every guard is dead the lair drops items,
##   potions and marks (the hero's coin), and the hero of the player who cleared it gains XP;
## - shrines: heal, refill mana and bless a hero and its units nearby, then rest;
## - merchants: sell potions and a small rotating stock of items for marks, never the army's gold.
## The map generator places them after setup_map (add_lair, add_shrine, add_merchant).
## Players and the computer use them through the command_* methods. Data: data/sites.json.

const PATH := "res://data/sites.json"
const KINDS := ["lair", "shrine", "merchant"]
const STEP_TICKS := 10  ## lairs and shrines are checked twice a second

static var _data: Dictionary = {}

var world: SimWorld
var d: Dictionary
## Every site, in the order placed: {id, kind, pos, ...}. A lair also has tier, guards (unit ids),
## cleared and by (owner, -1); a shrine ready_in (seconds); a merchant stock (items) and restock_in.
var all: Array[Dictionary] = []
var _next_id: int = 1
var _rng: GameRng  ## made on first use, so maps without sites keep their random stream


func _init(w: SimWorld) -> void:
	world = w
	d = data()


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


func rng() -> GameRng:
	if _rng == null:
		_rng = world.rng.fork(0x517E)
	return _rng


## Loot goes through the heroes' gear (made on first use, also in games without heroes).
func _gear() -> HeroGear:
	world.heroes._ensure_catalog()
	return world.heroes.gear


func get_site(id: int) -> Dictionary:
	for s in all:
		if s["id"] == id:
			return s
	return {}


func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in all:
		if s["kind"] == kind:
			out.append(s)
	return out


func title(s: Dictionary) -> String:
	match s["kind"]:
		"lair":
			return String(d["lair"]["tiers"][str(s["tier"])]["name"])
		_:
			return String(d[s["kind"]]["name"])


# --- Placing (map generator) -------------------------------------------------------

## A lair of tier 1..3 guarded by these unit types (spread around pos, idle and leashed there).
## A campaign lair may have a [param keeper]: its guards belong to that player (the barrows of
## the dead, say), whose own units leave it alone and can't claim it.
func add_lair(pos: Vector2, tier: int, guard_types: Array, keeper: int = -1) -> Dictionary:
	tier = clampi(tier, 1, 3)
	var guards: Array[int] = []
	var n := guard_types.size()
	for i in n:
		var a := float(i) / float(maxi(n, 1)) * TAU + 0.4
		var r := 0.0 if n == 1 else 34.0 + 10.0 * float(i % 3)
		var p := pos + Vector2(cos(a), sin(a)) * r
		if not world.catalog.units.has(guard_types[i]):
			push_error("lair guard: unknown unit " + str(guard_types[i]))
			continue
		var u := world.spawn(guard_types[i], Economy.NEUTRAL if keeper < 0 else keeper, p)
		u.scripted = keeper >= 0
		u.guard_radius = float(d["lair"]["radius"])
		guards.append(u.id)
	var s := {"id": _next_id, "kind": "lair", "pos": pos, "tier": tier, "guards": guards,
		"cleared": false, "by": -1, "keeper": keeper}
	return _add(s)


func add_shrine(pos: Vector2) -> Dictionary:
	return _add({"id": _next_id, "kind": "shrine", "pos": pos, "ready_in": 0.0})


func add_merchant(pos: Vector2) -> Dictionary:
	var s := _add({"id": _next_id, "kind": "merchant", "pos": pos, "stock": [], "restock_in": 0.0})
	_restock(s)
	return s


func _add(s: Dictionary) -> Dictionary:
	_next_id += 1
	all.append(s)
	return s


# --- Per tick ----------------------------------------------------------------------

func step() -> void:
	if all.is_empty() or world.tick % STEP_TICKS != 0:
		return
	var dt := world.dt * STEP_TICKS
	for s in all:
		match s["kind"]:
			"lair":
				if not s["cleared"]:
					_check_lair(s)
			"shrine":
				s["ready_in"] = maxf(0.0, float(s["ready_in"]) - dt)
				if s["ready_in"] <= 0.0:
					_try_shrine(s)
			"merchant":
				s["restock_in"] = float(s["restock_in"]) - dt
				if s["restock_in"] <= 0.0:
					_restock(s)


func guards_alive(s: Dictionary) -> int:
	var n := 0
	for id in s["guards"]:
		var u := world.get_unit(int(id))
		if u != null and u.alive:
			n += 1
	return n


func _check_lair(s: Dictionary) -> void:
	if guards_alive(s) > 0:
		return
	# Whoever has the most fighters close by takes the hoard (ties: lowest player number).
	var counts := {}
	for u: SimUnit in world.nearby(s["pos"], float(d["lair"]["claim_radius"])):
		if u.alive and u.owner != Economy.NEUTRAL and u.owner != int(s.get("keeper", -1)) and not u.is_worker():
			counts[u.owner] = int(counts.get(u.owner, 0)) + 1
	var by := -1
	var best := 0
	var owners := counts.keys()
	owners.sort()
	for o in owners:
		if int(counts[o]) > best:
			best = int(counts[o])
			by = int(o)
	if by < 0:
		return  # killed from afar (or by venom) with nobody there: the loot waits
	s["cleared"] = true
	s["by"] = by
	var t: Dictionary = d["lair"]["tiers"][str(s["tier"])]
	var gear := _gear()
	var icat := gear.icat
	var minutes := float(world.tick) / float(world.tick_rate) / 60.0
	var level := clampi(1 + int(minutes / float(icat.rules["minutes_per_item_level"])) + int(t["level_bonus"]),
		1, int(icat.rules["max_item_level"]))
	var p: Vector2 = s["pos"]
	for i in int(t["items"]):
		gear.drop_item(icat.roll_drop(rng(), "lair_%d" % s["tier"], level), p + Vector2(-16.0 + 22.0 * i, 0.0))
	for i in int(t["potions"]):
		gear._put({"potion": "health" if i % 2 == 0 else "mana"}, p + Vector2(-10.0 + 14.0 * i, 18.0))
	world.heroes.earn_marks(by, int(t["marks"]))
	var h := world.heroes.hero_of(by)
	if h != null:
		world.heroes.add_xp(h, int(t["xp"]))
	world.events.append({"type": "lair_cleared", "site": s["id"], "owner": by, "pos": p, "marks": int(t["marks"])})


func _try_shrine(s: Dictionary) -> void:
	var sd: Dictionary = d["shrine"]
	var reach := float(sd["radius"])
	var owners := world.heroes.heroes.keys()
	owners.sort()
	for o in owners:
		var hu := world.heroes.hero_unit(o)
		if hu == null or not hu.alive or hu.pos.distance_to(s["pos"]) > reach:
			continue
		var h: HeroState = world.heroes.heroes[o]
		hu.hp = minf(hu.max_hp, hu.hp + hu.max_hp * float(sd["heal_pct"]))
		h.mana = minf(h.max_mana, h.mana + h.max_mana * float(sd["mana_pct"]))
		for u: SimUnit in world.nearby(s["pos"], reach * 2.0):
			if u.alive and u.owner == o:
				u.add_status(String(sd["blessing"]), float(sd["blessing_seconds"]), float(sd["blessing_value"]))
		s["ready_in"] = float(sd["cooldown"])
		world.events.append({"type": "shrine", "site": s["id"], "owner": o, "pos": s["pos"]})
		return


func _restock(s: Dictionary) -> void:
	var md: Dictionary = d["merchant"]
	var icat := _gear().icat
	var minutes := float(world.tick) / float(world.tick_rate) / 60.0
	var level := clampi(1 + int(minutes / float(icat.rules["minutes_per_item_level"])), 1, int(icat.rules["max_item_level"]))
	var stock: Array = []
	for i in int(md["stock"]):
		stock.append(icat.roll_drop(rng(), "merchant", level))
	s["stock"] = stock
	s["restock_in"] = float(md["restock_seconds"])


# --- Merchant ----------------------------------------------------------------------

func item_price(item: Dictionary) -> int:
	var md: Dictionary = d["merchant"]
	return int(md["price_by_rarity"].get(item["rarity"], 100)) + int(md["price_per_level"]) * int(item.get("level", 1))


func potion_price(kind: String) -> int:
	return int(d["merchant"]["potion_price"].get(kind, 0))


## The merchant this player's hero is standing at, or {}.
func merchant_near(owner: int) -> Dictionary:
	var hu := world.heroes.hero_unit(owner)
	if hu == null or not hu.alive:
		return {}
	for s in all:
		if s["kind"] == "merchant" and hu.pos.distance_to(s["pos"]) <= float(d["merchant"]["radius"]):
			return s
	return {}


## Why the hero can't buy this now ("" = it can). what: "health", "mana" or a stock index.
func buy_problem(owner: int, site_id: int, what: Variant) -> String:
	var s := get_site(site_id)
	if s.is_empty() or s["kind"] != "merchant":
		return "No merchant"
	if merchant_near(owner).get("id", -1) != site_id:
		return "Your hero must stand at the merchant"
	var h := world.heroes.hero_of(owner)
	if h == null:
		return "No hero"
	var price := 0
	if what is String:
		if not d["merchant"]["potion_price"].has(what):
			return "Not for sale"
		if int(h.potions.get(what, 0)) >= int(_gear().ir["potion_max"]):
			return "Potion belt is full"
		price = potion_price(what)
	else:
		var i := int(what)
		if i < 0 or i >= s["stock"].size():
			return "Sold out"
		price = item_price(s["stock"][i])
		if h.bag.size() >= int(_gear().ir["bag_size"]) and h.worn.has(s["stock"][i]["slot"]):
			return "Bag is full"
	if h.marks < price:
		return "Not enough %s" % String(world.heroes.r["coin"]["name"]).to_lower()
	return ""


## Buys a potion ("health"/"mana") or the stock item at an index. True when bought.
func command_buy(owner: int, site_id: int, what: Variant) -> bool:
	if buy_problem(owner, site_id, what) != "":
		return false
	var s := get_site(site_id)
	var h := world.heroes.hero_of(owner)
	if what is String:
		world.heroes.spend_marks(owner, potion_price(what))
		h.potions[what] = int(h.potions.get(what, 0)) + 1
		world.events.append({"type": "buy", "owner": owner, "site": site_id, "name": what + " potion"})
		return true
	var i := int(what)
	var item: Dictionary = s["stock"][i]
	var gear := _gear()
	if not item.has("uid"):
		item["uid"] = gear._next_uid
		gear._next_uid += 1
	if not _gear().give(h, item):
		return false
	world.heroes.spend_marks(owner, item_price(item))
	s["stock"].remove_at(i)
	world.events.append({"type": "buy", "owner": owner, "site": site_id, "name": item["name"]})
	return true


# --- Validation --------------------------------------------------------------------

static func validate(cat: UnitCatalog = null) -> Array[String]:
	var errors: Array[String] = []
	var sd := data()
	for k in KINDS:
		if not sd.has(k):
			errors.append("sites: missing " + k)
	if not errors.is_empty():
		return errors
	var icat := ItemCatalog.get_default()
	for t in ["1", "2", "3"]:
		var td: Dictionary = sd["lair"]["tiers"].get(t, {})
		for k in ["name", "xp", "marks", "items", "potions", "level_bonus"]:
			if not td.has(k):
				errors.append("sites lair tier %s: missing %s" % [t, k])
		if not icat.drops.has("lair_" + t):
			errors.append("items drops: missing lair_" + t)
	for k in ["name", "radius", "heal_pct", "mana_pct", "blessing", "blessing_value", "blessing_seconds", "cooldown"]:
		if not sd["shrine"].has(k):
			errors.append("sites shrine: missing " + k)
	if not String(sd["shrine"].get("blessing", "")) in HeroCatalog.STATUS_KINDS:
		errors.append("sites shrine: unknown blessing status")
	for k in ["name", "radius", "stock", "restock_seconds", "potion_price", "price_by_rarity", "price_per_level"]:
		if not sd["merchant"].has(k):
			errors.append("sites merchant: missing " + k)
	for r in sd["merchant"].get("price_by_rarity", {}):
		if not icat.rarities.has(r):
			errors.append("sites merchant: unknown rarity " + r)
	if not icat.drops.has("merchant"):
		errors.append("items drops: missing merchant")
	return errors
