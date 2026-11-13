class_name HeroGear
extends RefCounted
## Hero gear in a skirmish (headless, deterministic): loot on the ground, pickup, the 7 worn slots,
## a small bag, health and mana potions, and what the gear adds to the hero.
## Kept light: every neutral settlement drops one item and a potion the
## first time it is taken. Gear is kept through death and lost when the match ends.
## Players and the AI only use the command_* methods.

var hs: HeroSystem
var world: SimWorld
var icat: ItemCatalog
var ir: Dictionary  ## items.json rules
## Items lying on the map, oldest first: {uid, pos, item} or {uid, pos, potion: "health"|"mana"}.
var ground: Array[Dictionary] = []
var _next_uid: int = 1
var _rng: GameRng  ## made at the first drop, so games without loot keep their random stream
var _looted: Dictionary = {}  ## sector id -> true once it has dropped its loot


func _init(system: HeroSystem) -> void:
	hs = system
	world = system.world
	icat = ItemCatalog.get_default()
	ir = icat.rules


# --- Drops ---------------------------------------------------------------------------

## A settlement taken from the neutral militia drops its loot (once per settlement).
func on_capture(ev: Dictionary) -> void:
	var from := int(ev.get("from", -1))
	if from >= 0 and from != Economy.NEUTRAL:
		return
	var sid := int(ev["sector"])
	if _looted.has(sid):
		return
	var s: Sector = null
	for x in world.economy.sectors:
		if x.id == sid:
			s = x
	if s == null:
		return
	_looted[sid] = true
	var minutes := float(world.tick) / float(world.tick_rate) / 60.0
	var level := icat.drop_level(s.size, minutes)
	drop_item(icat.roll_drop(rng(), "capture", level), s.center + Vector2(-14.0, 6.0))
	for i in int(icat.drops["capture"].get("potions", 0)):
		var kind := "health" if rng().chance(0.6) else "mana"
		_put({"potion": kind}, s.center + Vector2(14.0 + 10.0 * i, 6.0))


func rng() -> GameRng:
	if _rng == null:
		_rng = world.rng.fork(0x17E5)
	return _rng


## Puts an item on the ground (it gets its uid here).
func drop_item(item: Dictionary, p: Vector2) -> void:
	_put({"item": item}, p)


func _put(entry: Dictionary, p: Vector2) -> void:
	entry["uid"] = _next_uid
	entry["pos"] = p
	if entry.has("item"):
		entry["item"]["uid"] = _next_uid
	_next_uid += 1
	ground.append(entry)
	while ground.size() > int(ir["ground_max"]):
		ground.pop_front()
	world.events.append({"type": "loot_drop", "uid": entry["uid"], "pos": p})


# --- Per tick ----------------------------------------------------------------------

func step(dt: float) -> void:
	var owners := hs.heroes.keys()
	owners.sort()
	for o in owners:
		var h: HeroState = hs.heroes[o]
		h.potion_cd = maxf(0.0, h.potion_cd - dt)
		var u := hs.hero_unit(o)
		if u == null or not u.alive:
			continue
		_pick_up(h, u)
		var regen := float(h.gear.get("hp_regen", 0.0))
		if regen > 0.0 and u.hp < u.max_hp:
			u.hp = minf(u.max_hp, u.hp + regen * dt)
		if hs.ai_owners.has(o):
			_ai_potions(h, u)


func _pick_up(h: HeroState, u: SimUnit) -> void:
	var reach := float(ir["pickup_radius"]) + u.radius()
	var keep: Array[Dictionary] = []
	for g in ground:
		if u.pos.distance_to(g["pos"]) > reach or not _take(h, g):
			keep.append(g)
		else:
			world.events.append({"type": "loot_pickup", "owner": h.owner, "uid": g["uid"],
				"name": g["item"]["name"] if g.has("item") else g["potion"] + " potion"})
	ground = keep


func _take(h: HeroState, g: Dictionary) -> bool:
	if g.has("potion"):
		var k: String = g["potion"]
		if int(h.potions.get(k, 0)) >= int(ir["potion_max"]):
			return false
		h.potions[k] = int(h.potions.get(k, 0)) + 1
		return true
	return give(h, g["item"])


## Hands an item to a hero: worn at once if its slot is free (or, for the computer, if it is
## better than what is worn), otherwise into the bag. False if there is no room.
func give(h: HeroState, item: Dictionary) -> bool:
	var arch := archetype(h)
	if icat.can_wear(arch, item):
		if not h.worn.has(item["slot"]) and _blocker(h, item) == "":
			_wear(h, item)
			return true
		if hs.ai_owners.has(h.owner) and h.worn.has(item["slot"]) \
				and icat.score(item) > icat.score(h.worn[item["slot"]]) and _blocker(h, item) == "":
			var old: Dictionary = h.worn[item["slot"]]
			h.worn.erase(item["slot"])
			_wear(h, item)
			if not _stash(h, old):
				_put({"item": old}, _hero_pos(h))
			return true
	return _stash(h, item)


func _stash(h: HeroState, item: Dictionary) -> bool:
	if h.bag.size() >= int(ir["bag_size"]):
		return false
	h.bag.append(item)
	return true


## The worn slot that stops this item from being worn ("" = none): two-handers and shields.
func _blocker(h: HeroState, item: Dictionary) -> String:
	if item["slot"] == "weapon" and icat.two_handed(item) and h.worn.has("shield"):
		return "shield"
	if item["slot"] == "shield" and h.worn.has("weapon") and icat.two_handed(h.worn["weapon"]):
		return "weapon"
	return ""


func _wear(h: HeroState, item: Dictionary) -> void:
	h.worn[item["slot"]] = item
	refresh(h)


## Recomputes what the gear adds and applies it to the living hero.
func refresh(h: HeroState) -> void:
	var m := icat.total_mods(h.worn)
	ItemCatalog._add(m, h.bonus)
	h.gear = m
	hs.restat(h)


func archetype(h: HeroState) -> String:
	return hs.cat.classes[h.class_id]["archetype"]


func _hero_pos(h: HeroState) -> Vector2:
	var u := hs.hero_unit(h.owner)
	return u.pos if u != null else Vector2.ZERO


func _ai_potions(h: HeroState, u: SimUnit) -> void:
	if u.hp_ratio() < 0.35:
		command_drink(h.owner, "health")
	elif h.max_mana > 0.0 and h.mana / h.max_mana < 0.2 and u.target_id >= 0:
		command_drink(h.owner, "mana")


# --- Commands ----------------------------------------------------------------------

## Wears an item from the bag; what it replaces (and a shield or two-hander in the way) goes into the bag.
func command_equip(owner: int, bag_index: int) -> bool:
	var h := hs.hero_of(owner)
	if h == null or bag_index < 0 or bag_index >= h.bag.size():
		return false
	var item: Dictionary = h.bag[bag_index]
	if not icat.can_wear(archetype(h), item):
		return false
	var out: Array[String] = []
	if h.worn.has(item["slot"]):
		out.append(item["slot"])
	var b := _blocker(h, item)
	if b != "":
		out.append(b)
	if h.bag.size() - 1 + out.size() > int(ir["bag_size"]):
		return false
	h.bag.remove_at(bag_index)
	for s in out:
		h.bag.append(h.worn[s])
		h.worn.erase(s)
	_wear(h, item)
	world.events.append({"type": "gear_change", "owner": owner})
	return true


## Takes a worn item off into the bag.
func command_unequip(owner: int, slot: String) -> bool:
	var h := hs.hero_of(owner)
	if h == null or not h.worn.has(slot) or h.bag.size() >= int(ir["bag_size"]):
		return false
	h.bag.append(h.worn[slot])
	h.worn.erase(slot)
	refresh(h)
	world.events.append({"type": "gear_change", "owner": owner})
	return true


## Drops a bag item at the hero's feet (a living hero only).
func command_drop(owner: int, bag_index: int) -> bool:
	var h := hs.hero_of(owner)
	var u := hs.hero_unit(owner)
	if h == null or u == null or bag_index < 0 or bag_index >= h.bag.size():
		return false
	var item: Dictionary = h.bag[bag_index]
	h.bag.remove_at(bag_index)
	# Out of reach for a moment, or the hero would pick it straight up again.
	_put({"item": item}, u.pos + Vector2(0.0, float(ir["pickup_radius"]) + u.radius() + 8.0))
	return true


## Drinks a health potion (heals a share of health) or a mana potion.
func command_drink(owner: int, kind: String) -> bool:
	var h := hs.hero_of(owner)
	var u := hs.hero_unit(owner)
	if h == null or u == null or h.potion_cd > 0.0 or int(h.potions.get(kind, 0)) <= 0:
		return false
	if kind == "health":
		if u.hp >= u.max_hp:
			return false
		u.hp = minf(u.max_hp, u.hp + u.max_hp * float(ir["potion_heal_pct"]))
	elif kind == "mana":
		if h.mana >= h.max_mana:
			return false
		h.mana = minf(h.max_mana, h.mana + h.max_mana * float(ir["potion_mana_pct"]))
	else:
		return false
	h.potions[kind] = int(h.potions[kind]) - 1
	h.potion_cd = float(ir["potion_cooldown"])
	world.events.append({"type": "potion", "owner": owner, "kind": kind, "unit": u.id})
	return true


## The weapon meshes the hero holds: the worn weapon's and shield's kinds, or the class default.
func weapon_kinds(owner: int) -> Array:
	var h := hs.hero_of(owner)
	if h == null:
		return []
	if not h.worn.has("weapon"):
		return hs.cat.classes[h.class_id]["weapons"]
	var out: Array = [h.worn["weapon"]["kind"]]
	if h.worn.has("shield") and h.worn["shield"]["kind"] == "shield":
		out.append("shield")
	return out
