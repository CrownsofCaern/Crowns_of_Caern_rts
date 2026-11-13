class_name HeroSystem
extends RefCounted
## Hero rules (headless, deterministic): spawning, XP and levels, skill points, casting,
## autocast, auras, damage over time, summons, death and revival, and the story heroes'
## talents (StoryTrees.TALENTS; SimWorld calls the hooks under "Talents").
## Players and the AI only use the command_* methods.

## Where a hero appears and revives: in front of the home hall (the 3D hall is ~11 m wide).
const HALL_SPAWN := Vector2(0.0, 230.0)

var world: SimWorld
var cat: HeroCatalog
var r: Dictionary  ## heroes.json rules
## owner -> HeroState (one hero per player)
var heroes: Dictionary = {}
## Damage over time areas: {pos, radius, dps, left, owner, source}
var dots: Array[Dictionary] = []
## Players whose skills the computer runs (all autocasts on, instant auto-learn).
var ai_owners: Dictionary = {}
var _ev_from: int = 0  ## world.events already read this tick
## Loot, worn items, bag and potions.
var gear: HeroGear
## Campaign checkpoints: owner -> where a fallen hero returns (free, after checkpoint_seconds).
## Without one a hero is revived at its hall for gold, as in skirmish.
var respawn_at: Dictionary = {}
var checkpoint_seconds: float = 10.0
## Units that fell lately (Resurrection, Raise the Fallen, Corpse Burst): {type_id, owner, pos, time}.
## Heroes, workers and summoned units leave no body to call back.
var fallen: Array[Dictionary] = []
const FALLEN_SECONDS := 30.0
const FALLEN_MAX := 80
## True once a hero with talents is on the field: SimWorld only calls the talent hooks then.
var has_talents: bool = false
## Talent rules (world pixels, seconds).
const EXECUTE_BELOW := 0.3
const BERSERK_BELOW := 0.5
const FORTRESS_BELOW := 0.4
const CLOSE := 100.0  ## "close by" for Shoulder to Shoulder and Pack Hunter
const CLOSE_MAX := 8
const NEAR := 240.0  ## "near the hero" for deaths (Last Rites, Sworn Vengeance, Harvest of the Fallen, Mercy)
const SPLASH := 48.0  ## Heavy Hand and Giant-Kin: enemies next to the target
const RISE_SECONDS := 20.0


func _init(w: SimWorld) -> void:
	world = w


func _ensure_catalog() -> void:
	if cat == null:
		cat = HeroCatalog.get_default()
		r = cat.rules
		cat.register(world.catalog)
		gear = HeroGear.new(self)


# --- Setup -----------------------------------------------------------------------

## Gives a player their hero (one per player). Returns the unit.
func spawn_hero(owner: int, class_id: String, p: Vector2, ai: bool = false) -> SimUnit:
	_ensure_catalog()
	var h := HeroState.new()
	h.class_id = class_id
	h.owner = owner
	h.kit = cat.kit(class_id).duplicate()
	h.points = 1
	heroes[owner] = h
	if ai:
		ai_owners[owner] = true
		h.autocast = [true, true, true, true]
	_recompute(h)
	h.mana = h.max_mana
	return _place(h, p)


## A campaign hero for a battle: its level, chosen skills and their ranks, passives and gear.
## It earns no XP or skill points here (the campaign adds the battle's XP to the StoryHero).
func spawn_story_hero(owner: int, story: StoryHero, p: Vector2, worn: Dictionary = {}, ai: bool = false) -> SimUnit:
	_ensure_catalog()
	var h := HeroState.new()
	h.class_id = story.class_id
	h.owner = owner
	h.story = true
	h.level = story.level
	h.auto_learn = false
	h.kit = story.slots.duplicate()
	var known := story.known_skills()
	for i in 4:
		h.ranks[i] = int(known.get(h.kit[i], 0)) if h.kit[i] != "" else 0
	h.bonus = story.passive_mods()
	_set_talents(h, story.talents())
	h.worn = worn.duplicate()
	heroes[owner] = h
	if ai:
		ai_owners[owner] = true
		h.autocast = [true, true, true, true]
	gear.refresh(h)
	h.mana = h.max_mana
	return _place(h, p)


## A campaign hero's StoryHero changed mid-battle (a level, a skill learned): takes over its
## level, slots, ranks and passives; the living hero keeps its share of health.
func refresh_story(owner: int, story: StoryHero) -> void:
	var h := hero_of(owner)
	if h == null or not h.story:
		return
	h.level = story.level
	h.kit = story.slots.duplicate()
	var known := story.known_skills()
	for i in 4:
		h.ranks[i] = int(known.get(h.kit[i], 0)) if h.kit[i] != "" else 0
	h.bonus = story.passive_mods()
	_set_talents(h, story.talents())
	gear.refresh(h)


func _set_talents(h: HeroState, t: Dictionary) -> void:
	h.talents = t
	if not t.is_empty():
		has_talents = true


func _place(h: HeroState, p: Vector2) -> SimUnit:
	var def := hero_def(h)
	var u := world.spawn(HeroCatalog.type_id(h.class_id), h.owner, p, def)
	u.hero = h
	h.unit_id = u.id
	h.cast_slot = -1
	world.events.append({"type": "hero_spawn", "unit": u.id, "owner": h.owner})
	return u


func hero_of(owner: int) -> HeroState:
	return heroes.get(owner)


func hero_unit(owner: int) -> SimUnit:
	var h := hero_of(owner)
	return world.get_unit(h.unit_id) if h != null and h.unit_id >= 0 else null


## Attributes, mana and power for the current level and gear.
func _recompute(h: HeroState) -> void:
	h.attributes = cat.attributes_with(h.class_id, h.level, h.gear)
	var k := float(h.attributes["knowledge"])
	var old_max := h.max_mana
	h.max_mana = float(r["mana_base"]) + float(r["mana_per_knowledge"]) * k + float(h.gear.get("mana", 0.0))
	h.mana_regen = float(r["mana_regen"]) + float(r["mana_regen_per_knowledge"]) * k \
		+ float(h.gear.get("mana_regen", 0.0))
	h.power_factor = (1.0 + float(r["power_pct"]) * float(h.attributes["power"])) \
		* (1.0 + float(h.gear.get("skill_pct", 0.0)))
	h.mana += maxf(0.0, h.max_mana - old_max)
	h.mana = minf(h.mana, h.max_mana)


## The hero's unit definition at its level, with its gear.
func hero_def(h: HeroState) -> Dictionary:
	return cat.make_def(h.class_id, h.level, world.catalog, h.gear)


## New level or gear: recomputes the stats; the living hero keeps its share of health.
func restat(h: HeroState) -> void:
	_recompute(h)
	var u := world.get_unit(h.unit_id) if h.unit_id >= 0 else null
	if u != null:
		var ratio := u.hp_ratio()
		u.def = hero_def(h)
		u.max_hp = float(u.def["hp"])
		u.hp = maxf(1.0, u.max_hp * ratio)


# --- Commands --------------------------------------------------------------------

## Spends a skill point on a kit slot. Returns false when that rank is not open yet.
func command_learn(owner: int, slot: int) -> bool:
	var h := hero_of(owner)
	if h == null or not can_learn(h, slot):
		return false
	h.ranks[slot] += 1
	h.points -= 1
	h.unspent_time = 0.0
	world.events.append({"type": "hero_learn", "owner": owner, "slot": slot, "rank": h.ranks[slot]})
	return true


func can_learn(h: HeroState, slot: int) -> bool:
	if h.points <= 0 or slot < 0 or slot > 3:
		return false
	var sid: String = h.kit[slot]
	var rank := h.ranks[slot]
	if rank >= cat.max_rank(sid):
		return false
	if slot == 3:
		return h.level >= int(r["ultimate_level"])
	return h.level >= 2 * (rank + 1) - 1  # rank N opens at level 2N-1


func command_set_autocast(owner: int, slot: int, on: bool) -> void:
	var h := hero_of(owner)
	if h != null and slot >= 0 and slot <= 3:
		h.autocast[slot] = on


func command_set_auto_learn(owner: int, on: bool) -> void:
	var h := hero_of(owner)
	if h != null:
		h.auto_learn = on


## Why a cast cannot start now ("" = it can).
func cast_problem(h: HeroState, slot: int) -> String:
	if slot < 0 or slot > 3 or h.ranks[slot] <= 0:
		return "not learned"
	var s := cat.skill(h.kit[slot])
	if s["target"] == "aura":
		return "passive"
	if h.cooldowns[slot] > 0.0:
		return "cooldown"
	if h.mana < HeroCatalog.at_rank(s["mana"], h.ranks[slot]):
		return "mana"
	return ""


## Casts a kit skill: at a unit (enemy/ally skills), at a point (point skills) or at once (self).
## The hero walks into range first. Returns false when the cast is not possible.
func command_cast(owner: int, slot: int, target_id: int = -1, point: Vector2 = Vector2.ZERO) -> bool:
	var u := hero_unit(owner)
	if u == null:
		return false
	var h := u.hero
	if cast_problem(h, slot) != "":
		return false
	var s := cat.skill(h.kit[slot])
	match String(s["target"]):
		"enemy", "ally":
			var t := world.get_unit(target_id)
			if t == null or (s["target"] == "enemy") == (t.owner == owner):
				return false
		"point":
			target_id = -1
	h.cast_slot = slot
	h.cast_target = target_id
	h.cast_point = point
	u.order = SimUnit.Order.CAST
	u.path = PackedVector2Array()
	think_cast(u)
	return true


# --- Casting ---------------------------------------------------------------------

## The CAST order: walk until the target is in range, then cast and go idle.
func think_cast(u: SimUnit) -> void:
	var h := u.hero
	if h == null or h.cast_slot < 0 or cast_problem(h, h.cast_slot) != "":
		_end_cast(u)
		return
	var s := cat.skill(h.kit[h.cast_slot])
	var at := u.pos
	match String(s["target"]):
		"enemy", "ally":
			var t := world.get_unit(h.cast_target)
			if t == null:
				_end_cast(u)
				return
			at = t.pos
		"point":
			at = h.cast_point
	var reach := float(s["range"]) + u.radius() + 6.0
	if s["target"] != "self" and u.pos.distance_to(at) > reach:
		if u.path.is_empty() or u.path_i >= u.path.size():
			world.set_path(u, at)
		world.follow_path(u)
		return
	_cast(u, h.cast_slot, h.cast_target, at)
	_end_cast(u)


func _end_cast(u: SimUnit) -> void:
	if u.hero != null:
		u.hero.cast_slot = -1
	if u.order == SimUnit.Order.CAST:
		world.go_idle(u)


func _cast(u: SimUnit, slot: int, target_id: int, at: Vector2) -> void:
	var h := u.hero
	var sid: String = h.kit[slot]
	var s := cat.skill(sid)
	var rank := h.ranks[slot]
	h.casts += 1
	var echo := talent(h, "echo")
	if echo <= 0.0 or h.casts % int(echo) != 0:  # Resonance and friends: every Nth cast is free
		h.mana -= HeroCatalog.at_rank(s["mana"], rank)
	h.cooldowns[slot] = HeroCatalog.at_rank(s["cooldown"], rank) \
		* (1.0 - minf(float(gear.ir["cooldown_cap"]), float(h.gear.get("cooldown_pct", 0.0))))
	if at.x != u.pos.x:
		u.facing = signf(at.x - u.pos.x)
	u.since_attack = 0.0
	world.events.append({"type": "skill", "unit": u.id, "owner": u.owner, "skill": sid, "pos": at,
		"target": target_id})
	var radius := float(s.get("radius", 0))
	var centre := at if s["target"] == "point" else u.pos
	for e: Dictionary in s["effects"]:
		_apply(u, s, e, rank, target_id, centre, radius)


## Units an effect touches: the target unit, or every enemy/ally in the area.
func _targets(u: SimUnit, s: Dictionary, side: String, target_id: int, centre: Vector2, radius: float) -> Array:
	if s["target"] == "enemy" or s["target"] == "ally":
		var t := world.get_unit(target_id)
		return [t] if t != null else []
	if radius <= 0.0:
		return [u] if side == "ally" else []
	var out: Array = []
	for o: SimUnit in world.nearby(centre, radius):
		if (o.owner == u.owner) == (side == "ally"):
			out.append(o)
	return out


## Effects that hinder a unit (Purify lifts them; Pack Hunter and the like count them).
const HINDRANCES := ["stun", "slow", "weak", "exposed", "taunted"]


static func _side(e: Dictionary) -> String:
	match String(e["type"]):
		"heal", "heal_pct":
			return "ally"
		"status", "aura":
			return "ally" if e["kind"] in ["haste", "might", "ward", "venom"] else "enemy"
	return "enemy"


## As _targets, but an effect marked "self" touches only the caster.
func _effect_targets(u: SimUnit, s: Dictionary, e: Dictionary, side: String, target_id: int, centre: Vector2,
		radius: float) -> Array:
	if e.get("self", false):
		return [u]
	return _targets(u, s, side, target_id, centre, radius)


func _apply(u: SimUnit, s: Dictionary, e: Dictionary, rank: int, target_id: int, centre: Vector2,
		radius: float) -> void:
	var pf := u.hero.power_factor
	match String(e["type"]):
		"leap":
			u.pos = world.nav.nearest_free(centre)
			u.prev_pos = u.pos
			u.path = PackedVector2Array()
		"damage":
			var amount := HeroCatalog.at_rank(e["amount"], rank) * pf
			for t: SimUnit in _targets(u, s, "enemy", target_id, centre, radius):
				var bonus := float(e["bonus"]) if t.hp_ratio() < float(e.get("bonus_below", 0.0)) else 0.0
				world.deal_damage(t, amount * (1.0 + bonus), u.id)
		"drain":
			var amount := HeroCatalog.at_rank(e["amount"], rank) * pf
			for t: SimUnit in _targets(u, s, "enemy", target_id, centre, radius):
				world.deal_damage(t, amount, u.id)
				_heal(u, u, amount)
		"heal":
			var amount := HeroCatalog.at_rank(e["amount"], rank) * pf * (1.0 + talent(u.hero, "heal_pct"))
			for t: SimUnit in _effect_targets(u, s, e, "ally", target_id, centre, radius):
				_skill_heal(u, t, amount)
		"heal_pct":
			var pct := HeroCatalog.at_rank(e["pct"], rank) * (1.0 + talent(u.hero, "heal_pct"))
			for t: SimUnit in _effect_targets(u, s, e, "ally", target_id, centre, radius):
				_skill_heal(u, t, t.max_hp * pct)
		"status":
			var secs := HeroCatalog.at_rank(e["seconds"], rank) * (1.0 + talent(u.hero, "status_pct"))
			var val := HeroCatalog.at_rank(e["value"], rank)
			for t: SimUnit in _effect_targets(u, s, e, _side(e), target_id, centre, radius):
				t.add_status(e["kind"], secs, val)
		"dot":
			dots.append({"pos": centre, "radius": maxf(radius, 48.0), "owner": u.owner, "source": u.id,
				"dps": HeroCatalog.at_rank(e["dps"], rank) * pf * (1.0 + talent(u.hero, "dot_pct")),
				"left": HeroCatalog.at_rank(e["seconds"], rank)})
		"summon":
			_summon(u, int(e["tier"]), int(HeroCatalog.at_rank(e["count"], rank)),
				HeroCatalog.at_rank(e["seconds"], rank))
		"taunt":
			var secs := HeroCatalog.at_rank(e["seconds"], rank) * (1.0 + talent(u.hero, "status_pct"))
			for t: SimUnit in _targets(u, s, "enemy", target_id, centre, radius):
				if t.passive or t.is_worker():
					continue
				t.target_id = u.id
				t.provoked_by = u.id
				t.provoked_left = secs
				t.add_status("taunted", secs, 1.0)
		"chain":
			_chain(u, world.get_unit(target_id), HeroCatalog.at_rank(e["amount"], rank) * pf,
				int(HeroCatalog.at_rank(e["jumps"], rank)))
		"resurrect":
			_call_back(u, centre, radius, int(HeroCatalog.at_rank(e["count"], rank)),
				HeroCatalog.at_rank(e["pct"], rank), true, 0.0)
		"raise":
			_call_back(u, centre, radius, int(HeroCatalog.at_rank(e["count"], rank)),
				HeroCatalog.at_rank(e["pct"], rank), false, HeroCatalog.at_rank(e["seconds"], rank))
		"corpse_burst":
			_corpse_burst(u, centre, radius, HeroCatalog.at_rank(e["amount"], rank) * pf)
		"cleanse":
			for t: SimUnit in _targets(u, s, "ally", target_id, centre, radius):
				for k in HINDRANCES:
					t.status.erase(k)
				t.poison_left = 0.0
				t.poison_dps = 0.0
				t.dots.clear()
				t.cursed = 0.0
		"self_damage":
			u.hp = maxf(1.0, u.hp - u.max_hp * HeroCatalog.at_rank(e["pct"], rank))
		"mana":
			u.hero.mana = minf(u.hero.max_mana, u.hero.mana + HeroCatalog.at_rank(e["amount"], rank))
		"knockback", "pull":
			var dist := HeroCatalog.at_rank(e["distance"], rank)
			for t: SimUnit in _targets(u, s, "enemy", target_id, centre, radius):
				_shove(t, centre, dist, e["type"] == "pull")


func _heal(src: SimUnit, t: SimUnit, amount: float) -> void:
	if t == null or not t.alive:
		return
	var got := minf(amount, t.max_hp - t.hp)
	if got <= 0.0:
		return
	t.hp += got
	world.events.append({"type": "heal", "unit": src.id, "target": t.id, "amount": got})


## A skill heal, with the healer's talents (Aegis of Mercy wards whoever it heals).
func _skill_heal(src: SimUnit, t: SimUnit, amount: float) -> void:
	_heal(src, t, amount)
	var ward := talent(src.hero, "heal_ward")
	if ward > 0.0 and t != null and t.alive:
		t.add_status("ward", 4.0, ward)


func _summon(u: SimUnit, tier: int, count: int, seconds: float) -> void:
	var faction: String = cat.classes[u.hero.class_id]["faction"]
	var type := ""
	for id in world.catalog.faction_units(faction):
		if int(world.catalog.get_unit(id)["tier"]) == tier:
			type = id
			break
	if type == "":
		return
	count += int(talent(u.hero, "summon_count"))
	for i in count:
		var a := TAU * float(i) / float(count) + float(u.id % 7)
		_make_summon(u, type, u.pos + Vector2(cos(a), sin(a)) * 50.0, seconds, 1.0)


## A unit fighting for the hero for `seconds`, with the hero's summoning talents; hp_share of its
## health (a raised body comes back hurt).
func _make_summon(u: SimUnit, type: String, p: Vector2, seconds: float, hp_share: float) -> SimUnit:
	var m := world.spawn(type, u.owner, world.nav.nearest_free(p))
	m.expires = seconds * (1.0 + talent(u.hero, "summon_time"))
	var might := talent(u.hero, "summon_might")
	if might > 0.0:
		m.def = m.def.duplicate()
		m.def["damage"] = float(m.def["damage"]) * (1.0 + might)
		m.max_hp *= 1.0 + might
	m.hp = m.max_hp * hp_share
	world.events.append({"type": "summon", "unit": m.id, "owner": u.owner})
	return m


## Resurrection (own: your soldiers, for good) and Raise the Fallen (any side, for a while): calls
## back up to `count` bodies near `centre` that fell in the last FALLEN_SECONDS, the strongest
## (highest tier) first, then the latest.
func _call_back(u: SimUnit, centre: Vector2, radius: float, count: int, hp_share: float, own: bool,
		seconds: float) -> void:
	var picks := _bodies(u, centre, radius, own)
	picks.sort_custom(func(a, b):
		var ta := int(world.catalog.get_unit(a["type_id"]).get("tier", 0))
		var tb := int(world.catalog.get_unit(b["type_id"]).get("tier", 0))
		return ta > tb if ta != tb else float(a["time"]) > float(b["time"]))
	for i in mini(count, picks.size()):
		var b: Dictionary = picks[i]
		fallen.erase(b)
		if own:
			var m := world.spawn(b["type_id"], u.owner, world.nav.nearest_free(b["pos"]))
			m.hp = m.max_hp * hp_share
			world.events.append({"type": "revive", "unit": m.id, "owner": u.owner})
		else:
			var m := _make_summon(u, b["type_id"], b["pos"], seconds, hp_share)
			world.events.append({"type": "revive", "unit": m.id, "owner": u.owner})


## Bodies near a point that can still be called back (own = only the hero's side).
func _bodies(u: SimUnit, centre: Vector2, radius: float, own: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now := _now()
	for b in fallen:
		if now - float(b["time"]) > FALLEN_SECONDS or (b["pos"] as Vector2).distance_to(centre) > radius:
			continue
		if own and int(b["owner"]) != u.owner:
			continue
		out.append(b)
	return out


## Corpse Burst: each body near the point bursts (at most 6), hurting the enemies around it.
func _corpse_burst(u: SimUnit, centre: Vector2, radius: float, amount: float) -> void:
	var bodies := _bodies(u, centre, radius, false)
	for i in mini(6, bodies.size()):
		var b: Dictionary = bodies[i]
		fallen.erase(b)
		world.events.append({"type": "corpse_burst", "unit": u.id, "owner": u.owner, "pos": b["pos"]})
		for o: SimUnit in world.nearby(b["pos"], 64.0):
			if o.owner != u.owner:
				world.deal_damage(o, amount, u.id)


## Chain Lightning: hits the target, then leaps to the nearest enemy not yet hit (within 140),
## 15% weaker each leap.
func _chain(u: SimUnit, first: SimUnit, amount: float, jumps: int) -> void:
	var hit := {}
	var t := first
	var from := u.pos
	for i in jumps + 1:
		if t == null:
			return
		hit[t.id] = true
		world.events.append({"type": "chain", "unit": u.id, "from": from, "to": t.pos})
		from = t.pos
		world.deal_damage(t, amount, u.id)
		amount *= 0.85
		var next: SimUnit = null
		var best := INF
		for o: SimUnit in world.nearby(from, 140.0):
			if o.owner == u.owner or hit.has(o.id) or not o.alive:
				continue
			var d := from.distance_squared_to(o.pos)
			if d < best:
				best = d
				next = o
		t = next


## Steam Blast pushes away from the centre, Riptide drags towards it.
func _shove(t: SimUnit, centre: Vector2, dist: float, pull: bool) -> void:
	var d := t.pos - centre
	if d.length() < 1.0:
		d = Vector2.RIGHT.rotated(float(t.id % 12) * TAU / 12.0)
	var step := d.normalized() * dist
	if pull:
		step = -d.normalized() * minf(dist, maxf(0.0, d.length() - 20.0))
	t.pos = world.nav.nearest_free(t.pos + step)
	t.prev_pos = t.pos
	t.path = PackedVector2Array()


func _now() -> float:
	return float(world.tick) / float(world.tick_rate)


# --- Tick ------------------------------------------------------------------------

func step() -> void:
	if heroes.is_empty():
		return
	var dt := world.dt
	_ev_from = 0
	_step_dots(dt)
	_step_summons(dt)
	_read_events()
	var owners := heroes.keys()
	owners.sort()
	for o in owners:
		var h: HeroState = heroes[o]
		var u := world.get_unit(h.unit_id) if h.unit_id >= 0 else null
		if u == null:
			if h.unit_id >= 0:
				_on_death(h)
			else:
				_step_dead(h, dt)
			continue
		for i in 4:
			h.cooldowns[i] = maxf(0.0, h.cooldowns[i] - dt)
		h.undying_cd = maxf(0.0, h.undying_cd - dt)
		h.ally_undying_cd = maxf(0.0, h.ally_undying_cd - dt)
		h.mana = minf(h.max_mana, h.mana + h.mana_regen * dt)
		_step_learning(h, dt)
		h.aura_timer -= dt
		if h.aura_timer <= 0.0:
			h.aura_timer = float(r["aura_pulse"])
			_pulse_auras(u)
		h.autocast_timer -= dt
		if h.autocast_timer <= 0.0 and h.cast_slot < 0 and not u.stunned():
			h.autocast_timer = float(r["autocast_interval"])
			_autocast(u)
	_read_events()  # kills by this tick's casts
	gear.step(dt)


func _step_dots(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for d in dots:
		for o: SimUnit in world.nearby(d["pos"], float(d["radius"])):
			if o.owner != int(d["owner"]):
				world.deal_damage(o, float(d["dps"]) * dt, int(d["source"]))
		d["left"] = float(d["left"]) - dt
		if float(d["left"]) > 0.0:
			keep.append(d)
	dots = keep


func _step_summons(dt: float) -> void:
	for u in world.units:
		if u.alive and u.expires > 0.0:
			u.expires -= dt
			if u.expires <= 0.0:
				world.retire(u)
				_summon_gone(u.owner)


## Blood Bond: a summoned unit fell or faded; its master heals.
func _summon_gone(owner: int) -> void:
	var h := hero_of(owner)
	if h == null or talent(h, "summon_bond") <= 0.0:
		return
	var hu := hero_unit(owner)
	if hu != null:
		_heal(hu, hu, talent(h, "summon_bond"))


## XP for enemies that died near a hero this tick, and for settlements taken; hero deaths.
func _read_events() -> void:
	var evs := world.events
	var from := _ev_from
	_ev_from = evs.size()
	for i in range(from, evs.size()):
		var ev: Dictionary = evs[i]
		if ev["type"] == "death":
			_on_unit_death(ev)
			var victim_owner := int(ev["owner"])
			var tier := int(world.catalog.get_unit(ev["type_id"]).get("tier", 0))
			var amount := int(r["xp_per_tier"]) * tier if tier > 0 else int(r["xp_worker"])
			if String(ev["type_id"]).begins_with("hero_"):
				amount = int(r["xp_per_tier"]) * 5
			for o in heroes:
				if o == victim_owner:
					continue
				var hu := hero_unit(o)
				if hu != null and hu.pos.distance_to(ev["pos"]) <= float(r["xp_radius"]):
					add_xp(heroes[o], amount)
					var coin: Dictionary = r["coin"]
					earn_marks(o, int(coin["per_kill_tier"]) * tier if tier > 0 else int(coin["worker"]))
			if heroes.has(victim_owner) and heroes[victim_owner].unit_id == int(ev["unit"]):
				_on_death(heroes[victim_owner])
		elif ev["type"] == "capture":
			gear.on_capture(ev)
			if heroes.has(int(ev["owner"])):
				add_xp(heroes[int(ev["owner"])], int(r["xp_capture"]))
				earn_marks(int(ev["owner"]), int(r["coin"]["capture"]))


## The hero's coin: earned in the field, spent at merchants. Never the army's gold.
func earn_marks(owner: int, amount: int) -> void:
	if heroes.has(owner) and amount > 0:
		heroes[owner].marks += amount


func spend_marks(owner: int, amount: int) -> bool:
	if not heroes.has(owner) or heroes[owner].marks < amount:
		return false
	heroes[owner].marks -= amount
	return true


func add_xp(h: HeroState, amount: int) -> void:
	if h.story:
		h.xp += amount  # banked for the campaign; story levels come from the StoryHero
		return
	if h.level >= int(r["max_level"]):
		return
	h.xp += int(round(float(amount) * (1.0 + float(h.gear.get("xp_pct", 0.0)))))
	while h.level < int(r["max_level"]) and h.xp >= cat.xp_to_next(h.level):
		h.xp -= cat.xp_to_next(h.level)
		h.level += 1
		h.points += 1
		restat(h)
		world.events.append({"type": "hero_level", "owner": h.owner, "level": h.level})
	if h.level >= int(r["max_level"]):
		h.xp = 0


func _step_learning(h: HeroState, dt: float) -> void:
	if h.points <= 0 or not h.auto_learn:
		h.unspent_time = 0.0
		return
	h.unspent_time += dt
	var delay := 0.0 if ai_owners.has(h.owner) else float(r["auto_learn_delay"])
	if h.unspent_time < delay:
		return
	for slot in cat.classes[h.class_id]["learn_order"]:
		if command_learn(h.owner, int(slot)):
			return
	for slot in 4:  # the order is used up: anything still open
		if command_learn(h.owner, slot):
			return


func _on_death(h: HeroState) -> void:
	h.unit_id = -1
	h.deaths += 1
	h.cast_slot = -1
	h.respawn = float(r["respawn_base"]) + float(r["respawn_per_level"]) * h.level
	if respawn_at.has(h.owner):
		h.respawn = checkpoint_seconds
	world.events.append({"type": "hero_death", "owner": h.owner, "respawn": h.respawn})


func revive_cost(h: HeroState) -> Dictionary:
	return {"gold": int(r["revive_gold_per_level"]) * h.level}


## Revival at the home hall once the timer runs out and the gold is there.
func _step_dead(h: HeroState, dt: float) -> void:
	h.respawn = maxf(0.0, h.respawn - dt)
	if h.respawn > 0.0:
		return
	var p := Vector2.ZERO
	var pl := world.economy.player(h.owner)
	if respawn_at.has(h.owner):
		p = respawn_at[h.owner]
	elif pl != null:
		var hall := world.economy.hall_of(h.owner)
		if hall == null:
			return
		var cost := revive_cost(h)
		if not pl.can_pay(cost):
			return
		pl.pay(cost)
		p = hall.center + HALL_SPAWN
	else:
		return  # a plain battle has no hall: the hero stays dead
	var u := _place(h, p)
	h.mana = h.max_mana
	u.hp = u.max_hp


## Auras: a short status on every own unit in range, refreshed each pulse.
func _pulse_auras(u: SimUnit) -> void:
	var h := u.hero
	var k: Array = h.kit
	for slot in 4:
		if h.ranks[slot] <= 0:
			continue
		var s := cat.skill(k[slot])
		if s["target"] != "aura":
			continue
		for e: Dictionary in s["effects"]:
			var val := HeroCatalog.at_rank(e["value"], h.ranks[slot])
			for o: SimUnit in world.nearby(u.pos, float(s["radius"]) * (1.0 + talent(h, "aura_radius"))):
				if o.owner == u.owner:
					o.add_status(e["kind"], float(r["aura_pulse"]) * 2.0, val)
	# Army auras from gear (banners and some uniques) and story passives.
	var army_r := float(gear.ir["aura_radius"]) * (1.0 + talent(h, "aura_radius"))
	for stat in ItemCatalog.AURAS:
		var v := minf(float(gear.ir["aura_cap"]), float(h.gear.get(stat, 0.0)))
		if v <= 0.0:
			continue
		for o: SimUnit in world.nearby(u.pos, army_r):
			if o.owner == u.owner:
				o.add_status(ItemCatalog.AURAS[stat], float(r["aura_pulse"]) * 2.0, v)
	if not h.talents.is_empty():
		_pulse_talents(u, army_r)


# --- Autocast --------------------------------------------------------------------

## Fires the first ready autocast skill whose rule holds (slots in order, ultimate first).
func _autocast(u: SimUnit) -> void:
	var h := u.hero
	for slot in [3, 0, 1, 2]:
		if not h.autocast[slot] or cast_problem(h, slot) != "":
			continue
		var s := cat.skill(h.kit[slot])
		if not s.has("autocast"):
			continue
		var pick := _autocast_target(u, s)
		if pick.is_empty():
			continue
		var prev_order := u.order
		var prev_target := u.target_id
		var prev_path := u.path
		var prev_i := u.path_i
		var prev_point := u.order_point
		_cast(u, slot, int(pick.get("target", -1)), pick.get("pos", u.pos))
		# An autocast does not cancel what the hero was doing.
		u.order = prev_order
		u.target_id = prev_target
		u.path = prev_path
		u.path_i = prev_i
		u.order_point = prev_point
		return


## {target, pos} for a skill whose autocast rule holds right now, or {} when it does not.
## Only targets already in range: an autocast never walks the hero anywhere.
func _autocast_target(u: SimUnit, s: Dictionary) -> Dictionary:
	var rule: Dictionary = s["autocast"]
	if u.hp_ratio() < float(rule.get("min_hp", 0.0)):
		return {}  # Blood Price is not paid by a dying hero
	var reach := float(s.get("range", 0)) + u.radius()
	var radius := float(s.get("radius", 0))
	match String(rule["when"]):
		"fallen_near":
			if _bodies(u, u.pos, radius, rule.get("side", "own") == "own").size() >= int(rule.get("count", 1)):
				return {"pos": u.pos}
		"ally_hindered":
			var n := 0
			for o: SimUnit in world.nearby(u.pos, radius):
				if o.owner == u.owner and _hindered(o):
					n += 1
			if n >= int(rule.get("count", 1)):
				return {"pos": u.pos}
		"self_hurt":
			if u.hp_ratio() < float(rule.get("below", 0.5)):
				return {"pos": u.pos}
		"enemies_near":
			if _count(u, u.pos, radius + 10.0, false) >= int(rule.get("count", 1)):
				return {"pos": u.pos}
		"fighting":
			if _count(u, u.pos, float(r["sight"]), false) >= int(rule.get("count", 1)):
				return {"pos": u.pos}
		"enemy_in_range":
			var t := _nearest_enemy(u, reach)
			if t != null:
				return {"target": t.id, "pos": t.pos}
		"enemy_far":
			var t := _nearest_enemy(u, reach)
			if t != null and t.pos.distance_to(u.pos) >= float(rule.get("min", 0)):
				return {"pos": t.pos}
		"cluster":
			# The enemy in range with the most other enemies around it.
			var best: SimUnit = null
			var best_n := 0
			for o: SimUnit in world.nearby(u.pos, reach):
				if o.owner == u.owner or o.owner < 0:
					continue
				var n := _count(u, o.pos, radius, false)
				if n > best_n:
					best_n = n
					best = o
			if best != null and best_n >= int(rule.get("count", 1)):
				return {"pos": best.pos}
		"ally_hurt":
			var below := float(rule.get("below", 0.5))
			if s["target"] == "ally":
				var worst: SimUnit = null
				for o: SimUnit in world.nearby(u.pos, reach):
					if o.owner == u.owner and o.hp_ratio() < below and (worst == null or o.hp_ratio() < worst.hp_ratio()):
						worst = o
				if worst != null:
					return {"target": worst.id, "pos": worst.pos}
			else:
				var n := 0
				for o: SimUnit in world.nearby(u.pos, radius):
					if o.owner == u.owner and o.hp_ratio() < below:
						n += 1
				if n >= int(rule.get("count", 1)):
					return {"pos": u.pos}
	return {}


func _count(u: SimUnit, p: Vector2, radius: float, allies: bool) -> int:
	var n := 0
	for o: SimUnit in world.nearby(p, radius):
		if (o.owner == u.owner) == allies:
			n += 1
	return n


func _nearest_enemy(u: SimUnit, reach: float) -> SimUnit:
	var best: SimUnit = null
	var best_d := INF
	for o: SimUnit in world.nearby(u.pos, reach):
		if o.owner == u.owner:
			continue
		var d := u.pos.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


# --- Talents ---------------------------------------------------------------------

func talent(h: HeroState, type: String) -> float:
	return float(h.talents.get(type, 0.0)) if h != null else 0.0


static func _hindered(t: SimUnit) -> bool:
	for k in HINDRANCES:
		if t.status.has(k):
			return true
	return t.poison_left > 0.0 or not t.dots.is_empty()


func _own_close(u: SimUnit) -> int:
	var n := 0
	for o: SimUnit in world.nearby(u.pos, CLOSE):
		if o.owner == u.owner and o != u and not o.is_worker():
			n += 1
	return mini(n, CLOSE_MAX)


## Damage bonus of a hero's blows and skills against `t`: Honed Edge, Wounded Beast, Ambush,
## Deadeye, Pack Hunter and their kin.
func damage_factor(u: SimUnit, t: SimUnit) -> float:
	var h := u.hero
	if h.talents.is_empty():
		return 1.0
	var f := 1.0
	if t.hp_ratio() < EXECUTE_BELOW:
		f += talent(h, "execute")
	if u.hp_ratio() < BERSERK_BELOW:
		f += talent(h, "berserk")
	if t.hp >= t.max_hp:
		f += talent(h, "first_strike")
	if talent(h, "debuff_bonus") > 0.0 and _hindered(t):
		f += talent(h, "debuff_bonus")
	if talent(h, "pack") > 0.0:
		f += talent(h, "pack") * float(_own_close(u))
	return f


## A hero's blow (SimWorld._attack): the damage bonus, and every Nth blow a double hit (Keen Eye).
func blow_factor(u: SimUnit, t: SimUnit) -> float:
	var h := u.hero
	h.swings += 1
	var f := damage_factor(u, t)
	var every := int(talent(h, "crit_every"))
	if every > 0 and h.swings % every == 0:
		f *= 2.0
		world.events.append({"type": "crit", "unit": u.id, "target": t.id})
	return f


## Damage a hero takes after armour (dmg <= 0: the blow missed). src may be null.
func hero_taken(t: SimUnit, src: SimUnit, dmg: float, ranged: bool, skill: bool) -> float:
	var h := t.hero
	if h.talents.is_empty():
		return dmg
	if not skill:
		h.struck += 1
		var every := int(talent(h, "evade_every"))
		if every > 0 and h.struck % every == 0:
			return 0.0
	var cut := 0.0
	if t.hp_ratio() < FORTRESS_BELOW:
		cut += talent(h, "fortress")
	if ranged:
		cut += talent(h, "ranged_ward")
	elif not skill:
		cut += talent(h, "melee_ward")
	if talent(h, "phalanx") > 0.0:
		cut += talent(h, "phalanx") * float(_own_close(t))
	return dmg * (1.0 - minf(0.75, cut))


## A killing blow is about to land on `t`: Unyielding/Deathless save the hero, Chaplain/Mercy save
## a soldier near a hero of its side.
func spare_from_death(t: SimUnit) -> void:
	if t.hero != null:
		var own := t.hero
		if talent(own, "undying") > 0.0 and own.undying_cd <= 0.0:
			own.undying_cd = talent(own, "undying")
			t.hp = 1.0
			t.add_status("ward", 3.0, 0.5)
			world.events.append({"type": "undying", "unit": t.id, "owner": t.owner})
		return
	if t.expires > 0.0 or t.is_worker():
		return
	var h := hero_of(t.owner)
	if h == null or talent(h, "ally_undying") <= 0.0 or h.ally_undying_cd > 0.0:
		return
	var hu := hero_unit(t.owner)
	if hu == null or hu.pos.distance_to(t.pos) > NEAR:
		return
	h.ally_undying_cd = talent(h, "ally_undying")
	t.hp = t.max_hp * 0.3
	world.events.append({"type": "undying", "unit": t.id, "owner": t.owner})


## After a hit landed: the striker's talents (a hero's blow or skill) and the struck hero's.
func after_hit(t: SimUnit, src: SimUnit, dmg: float, ranged: bool, skill: bool) -> void:
	if src != null and src.hero != null and src.alive and src.owner != t.owner:
		var h := src.hero
		if skill:
			if talent(h, "spell_vamp") > 0.0:
				_heal(src, src, dmg * talent(h, "spell_vamp"))
		else:
			if talent(h, "lifesteal") > 0.0:
				_heal(src, src, dmg * talent(h, "lifesteal"))
			var burn := talent(h, "ignite") + src.status_value("venom")
			if burn > 0.0 and t.alive:
				var dps := dmg * burn / 3.0 * (1.0 + talent(h, "dot_pct"))
				t.poison_dps = maxf(t.poison_dps, dps) if t.poison_left > 0.0 else dps
				t.poison_left = 3.0
				t.poison_by = src.id
			if talent(h, "chill") > 0.0 and t.alive:
				t.add_status("slow", 2.0, talent(h, "chill"))
			var every := int(talent(h, "heavy_blow"))
			if every > 0:
				h.landed += 1
				if h.landed % every == 0 and t.alive:
					t.add_status("stun", 1.0, 1.0)
			if talent(h, "cleave_attacks") > 0.0:
				for o: SimUnit in world.nearby(t.pos, SPLASH):
					if o != t and o.owner != src.owner and o.alive and o.owner == t.owner:
						world.deal_damage(o, dmg * talent(h, "cleave_attacks"), src.id, "melee")
	if t.hero != null and src != null and src.alive and not ranged and not skill and src.owner != t.owner:
		var th := t.hero
		if talent(th, "thorns") > 0.0:
			world.deal_damage(src, dmg * talent(th, "thorns"), t.id, "melee")
		if talent(th, "attacker_weak") > 0.0:
			src.add_status("weak", 3.0, talent(th, "attacker_weak"))


## A death (SimWorld event): the body is kept for calling back, and the heroes' talents react.
func _on_unit_death(ev: Dictionary) -> void:
	var type_id := String(ev["type_id"])
	var udef := world.catalog.get_unit(type_id)
	var summoned := bool(ev.get("summoned", false))
	var victim_owner := int(ev["owner"])
	var pos: Vector2 = ev["pos"]
	var body := not summoned and not type_id.begins_with("hero_") and not udef.is_empty() \
		and String(udef.get("role", "")) != "worker"
	if body:
		fallen.append({"type_id": type_id, "owner": victim_owner, "pos": pos, "time": _now()})
		if fallen.size() > FALLEN_MAX:
			fallen.pop_front()
	if summoned:
		_summon_gone(victim_owner)
	if not has_talents:
		return
	var owners := heroes.keys()
	owners.sort()
	for o in owners:
		var h: HeroState = heroes[o]
		if h.talents.is_empty():
			continue
		var hu := hero_unit(o)
		if hu == null:
			continue
		if int(ev.get("killer", -1)) == hu.id and victim_owner != o:
			_on_hero_kill(h, hu, pos)
		if hu.pos.distance_to(pos) > NEAR or not body:
			continue
		if victim_owner == o:
			h.mana = minf(h.max_mana, h.mana + talent(h, "last_rites"))
			if talent(h, "avenge") > 0.0:
				for a: SimUnit in world.nearby(hu.pos, 160.0):
					if a.owner == o:
						a.add_status("might", 5.0, talent(h, "avenge"))
		else:
			_contagion(h, o, ev)
			var every := int(talent(h, "fallen_rise"))
			if every > 0:
				h.enemies_fallen += 1
				if h.enemies_fallen % every == 0:
					fallen.pop_back()  # the body just recorded gets up
					var m := _make_summon(hu, type_id, pos, RISE_SECONDS, 1.0)
					world.events.append({"type": "revive", "unit": m.id, "owner": o})


func _on_hero_kill(h: HeroState, hu: SimUnit, pos: Vector2) -> void:
	if talent(h, "kill_heal") > 0.0:
		_heal(hu, hu, hu.max_hp * talent(h, "kill_heal"))
	h.mana = minf(h.max_mana, h.mana + talent(h, "kill_mana"))
	if talent(h, "kill_cooldown") > 0.0:
		for i in 4:
			h.cooldowns[i] = maxf(0.0, h.cooldowns[i] - talent(h, "kill_cooldown"))
	if talent(h, "kill_haste") > 0.0:
		hu.add_status("haste", 4.0, talent(h, "kill_haste"))
	if talent(h, "kill_rally") > 0.0:
		for a: SimUnit in world.nearby(hu.pos, 200.0):
			if a.owner == hu.owner:
				a.add_status("might", 4.0, talent(h, "kill_rally"))
	if talent(h, "kill_burst") > 0.0:
		world.events.append({"type": "corpse_burst", "unit": hu.id, "owner": hu.owner, "pos": pos})
		for o: SimUnit in world.nearby(pos, 60.0):
			if o.owner != hu.owner:
				world.deal_damage(o, talent(h, "kill_burst") * h.power_factor, hu.id)


## Contagion: the hexes on a fallen enemy jump to the enemies around it.
func _contagion(h: HeroState, owner: int, ev: Dictionary) -> void:
	var reach := talent(h, "contagion")
	if reach <= 0.0 or not ev.has("status"):
		return
	var st: Dictionary = ev["status"]
	for o: SimUnit in world.nearby(ev["pos"], reach):
		if o.owner == owner or o.owner != int(ev["owner"]):
			continue
		for k in ["slow", "weak", "exposed"]:
			if st.has(k):
				o.add_status(k, maxf(2.0, float(st[k][0])), float(st[k][1]))


## Every aura pulse: Field Dressings and Blessed Ground heal the army, Second Wind and Gills the
## hurt hero, Steady Ranks lifts stuns and slows.
func _pulse_talents(u: SimUnit, radius: float) -> void:
	var h := u.hero
	var pulse := float(r["aura_pulse"])
	var regen := talent(h, "army_regen")
	if regen > 0.0:
		for o: SimUnit in world.nearby(u.pos, radius):
			if o.owner == u.owner and o.alive and o.hp < o.max_hp:
				o.hp = minf(o.max_hp, o.hp + regen * pulse)
	if talent(h, "low_regen") > 0.0 and u.hp_ratio() < FORTRESS_BELOW:
		u.hp = minf(u.max_hp, u.hp + u.max_hp * talent(h, "low_regen") * pulse)
	if talent(h, "cleanse_pulse") > 0.0:
		h.cleanse_timer -= pulse
		if h.cleanse_timer <= 0.0:
			h.cleanse_timer = talent(h, "cleanse_pulse")
			for o: SimUnit in world.nearby(u.pos, radius):
				if o.owner == u.owner:
					o.status.erase("stun")
					o.status.erase("slow")
