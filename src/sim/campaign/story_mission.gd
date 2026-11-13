class_name StoryMission
extends RefCounted
## One campaign chapter being played (data/campaigns/<chapter>.json): builds its handcrafted
## map, places the story hero, companions, NPCs and enemy groups, and runs its quests,
## dialogues and triggers on top of SimWorld. Headless and deterministic: it changes the
## world only through its own rules and the sim's commands; the view reads `dialogue`,
## `quests`, `events` and calls the command_* methods.
##
## Conditions and actions are small dictionaries (one key names the kind); CONDITIONS and
## ACTIONS list them, CampaignCatalog.validate() checks every mission against them.

const PLAYER := 0
const ENEMY := 1
const NPC := 7  ## owner of campaign NPCs (passive units)
const TALK_RANGE := 72.0  ## px: how close the hero must stand to talk
const CHECK_TICKS := 5  ## conditions are checked every 5 ticks (4 times a second)
const DEATH_MARKS_LOSS := 0.1
const MAX_COMPANIONS := 3
## On hero maps the hero's band heals out of a fight: after REST_SECONDS without dealing or
## taking a blow, REST_HEAL of its health per second.
const REST_SECONDS := 5.0
const REST_HEAL := 0.03  ## named companions that follow the hero into the next chapter
## On hero maps a named companion who falls (Orrin, Maelis) gets back up beside the hero once
## the hero has been out of the fight this long, at RISE_HP of its health.
const RISE_SECONDS := 8.0
const RISE_HP := 0.5

const CONDITIONS := ["flag", "not", "all", "any", "quest", "step", "dead", "alive", "near", "cleared", "marks",
	"time", "hero_level", "talked", "spawned", "held", "holds", "companion"]
const ACTIONS := ["start_quest", "advance", "complete_quest", "fail_quest", "flag", "unflag", "xp", "marks",
	"item", "potion", "spawn", "attack", "hostile", "join", "leave", "remove", "move", "say", "dialogue",
	"checkpoint", "res", "win", "lose"]
const QUEST_STATES := ["new", "active", "done", "failed"]

var def: Dictionary
var progress: CampaignProgress
var world: SimWorld
var factions: Array = []
var time: float = 0.0
var flags: Dictionary = {}  ## flags set this chapter (and those carried in), flag -> true
var quests: Dictionary = {}  ## quest id -> {state: new|active|done|failed, step: int}
var quest_order: Array = []  ## quest ids in the order they started (the quest log's order)
var npcs: Dictionary = {}  ## npc id -> unit id (-1 once gone)
var groups: Dictionary = {}  ## group id -> Array of unit ids (empty until spawned)
var spawned: Dictionary = {}  ## group id -> true once spawned
var fired: Dictionary = {}  ## trigger index -> true once fired (repeating: the time it may fire again)
var talked: Dictionary = {}  ## npc id -> times talked to
## The open conversation: {id (dialogue), node, npc} or empty. The sim should not run while
## one is open (the view pauses it).
var dialogue: Dictionary = {}
var talk_target: String = ""  ## an npc the hero walks to, to talk on arrival
var outcome: String = ""  ## "" while playing, "won" or "lost"
var lose_text: String = ""
## What happened since the view last looked: {type: quest_start|quest_step|quest_done|quest_failed|
## say|level|xp|marks|item|join|checkpoint|outcome, ...}. The view clears it.
var events: Array[Dictionary] = []
var _queue: Array = []  ## dialogues waiting while another is open
var _leaving: Dictionary = {}  ## unit id -> true: walks off and vanishes on arrival
var companions: Dictionary = {}  ## unit id -> true: units that follow the hero to the next chapter
var _named: Dictionary = {}  ## companion unit id -> [type, name] for the named ones (they get back up)
var _hero_uid: int = -1


func _init(mission_def: Dictionary, p: CampaignProgress) -> void:
	def = mission_def
	progress = p
	for f in p.flags:
		flags[f] = true


## War chapters run the RTS (settlements, workers, an enemy computer player); hero chapters
## have no economy.
func is_war() -> bool:
	return String(def.get("kind", "hero")) == "war"


## Builds the chapter's world. Returns it (also kept in `world`).
func build() -> SimWorld:
	var players: Array = def.get("players", [{"faction": progress.faction}])
	factions = players.map(func(x: Dictionary) -> String: return String(x["faction"]))
	world = SimWorld.new(int(def.get("seed", 1)))
	world.economy.settlements_active = is_war()
	world.economy.tier_cap = int(def.get("max_tier", 0))
	HeroCatalog.get_default().register(world.catalog)
	MapGen.build_layout(world, int(def.get("seed", 1)), factions, def["map"], String(def["id"]))
	for q in def.get("quests", {}):
		quests[q] = {"state": "new", "step": 0}
	_spawn_hero()
	for n: Dictionary in def.get("npcs", []):
		_spawn_npc(n)
	for g: Dictionary in def.get("groups", []):
		groups[g["id"]] = []
		if g.get("spawn", true):
			_spawn_group(g["id"])
	if not is_war():
		# Hero chapters: a fallen hero wakes at the last shrine. War chapters use the RTS rule
		# (revived at the hall for gold).
		world.heroes.respawn_at[PLAYER] = pos_of(def.get("checkpoint", def.get("hero", {}).get("at", [0.1, 0.5])))
	_run(def.get("start", []), "")
	if is_war() and world.economy.tier_cap > 0:
		events.append({"type": "tier_cap", "tier": world.economy.tier_cap})
	return world


func _spawn_hero() -> void:
	var at := pos_of(def.get("hero", {}).get("at", [0.1, 0.5]))
	var h := world.heroes.spawn_story_hero(PLAYER, progress.story, at, progress.worn)
	var hs := world.heroes.hero_of(PLAYER)
	hs.marks = progress.marks
	for item in progress.bag:
		hs.bag.append(item)
	for k in progress.potions:
		hs.potions[k] = int(progress.potions[k])
	_hero_uid = h.id
	h.label = progress.hero_name
	_apply_boost()
	var i := 0
	var absent: Array = def.get("absent", [])
	for c: Dictionary in progress.companions:
		if world.catalog.get_unit(String(c["type"])).is_empty():  # hero bodies (Maelis, Edda) live in extra
			continue
		if absent.has(String(c.get("name", ""))):
			continue  # away (or dead) this chapter; dropped unless they join again
		var a := float(i) * 1.3 + 2.0
		var u := world.spawn(String(c["type"]), PLAYER, at + Vector2(cos(a), sin(a)) * 50.0)
		u.label = String(c.get("name", ""))
		companions[u.id] = true
		_named[u.id] = [u.type_id, u.label]
		i += 1


## A hero chapter's "hero_boost" (ItemCatalog stats) on top of the story passives: one hero
## against monster bands is tuned higher than one hero inside an army.
func _apply_boost() -> void:
	var boost: Dictionary = def.get("hero_boost", {})
	var h := world.heroes.hero_of(PLAYER)
	if boost.is_empty() or h == null:
		return
	var b := progress.story.passive_mods()
	for k in boost:
		b[k] = float(b.get(k, 0.0)) + float(boost[k])
	h.bonus = b
	world.heroes.gear.refresh(h)


func _spawn_npc(n: Dictionary) -> void:
	if n.has("if") and not check(n["if"]):
		npcs[n["id"]] = -1
		return
	var u := world.spawn(String(n["look"]), NPC, pos_of(n["at"]))
	u.passive = true
	u.label = String(n["name"])
	u.facing = float(n.get("facing", -1.0))
	npcs[n["id"]] = u.id


func _spawn_group(gid: String) -> void:
	var g := group_def(gid)
	# A "waves" group may come again (each spawn adds a fresh band); others spawn once.
	if g.is_empty() or (spawned.has(gid) and not g.get("waves", false)):
		return
	spawned[gid] = true
	var owner := owner_of_group(g)
	var centre := pos_of(g["at"])
	var ids: Array = []
	var types: Array = []
	for pair: Array in g.get("units", []):
		for k in int(pair[1]):
			types.append(String(pair[0]))
	var n := types.size() + (1 if g.has("hero") else 0)
	var i := 0
	if g.has("hero"):
		var hd: Dictionary = g["hero"]
		var hu := world.heroes.spawn_hero(owner, String(hd["class"]), centre, true)
		var hh := world.heroes.hero_of(owner)
		while hh.level < mini(int(hd.get("level", 1)), int(world.heroes.r["max_level"])):
			world.heroes.add_xp(hh, world.heroes.cat.xp_to_next(hh.level))
		hu.hp = hu.max_hp
		hu.label = String(hd.get("name", ""))
		hu.scripted = owner != PLAYER
		_guard(hu, g)
		ids.append(hu.id)
		i += 1
	for t: String in types:
		var a := float(i) / float(maxi(n, 1)) * TAU + 0.3
		var r := 0.0 if n == 1 else 40.0 + 12.0 * float(i % 3)
		var u := world.spawn(t, NPC if g.get("passive", false) else owner, centre + Vector2(cos(a), sin(a)) * r)
		u.passive = bool(g.get("passive", false))
		# Enemy bands follow the story, not the enemy's computer player.
		u.scripted = owner != PLAYER
		_guard(u, g)
		ids.append(u.id)
		i += 1
	if g.get("waves", false):
		ids = group_units(gid).map(func(u: SimUnit) -> int: return u.id) + ids
	groups[gid] = ids
	if g.has("attack"):
		world.command_attack_move(ids, pos_of(g["attack"]))


func _guard(u: SimUnit, g: Dictionary) -> void:
	if float(g.get("guard", 0.0)) > 0.0:
		u.guard_radius = float(g["guard"]) * NavGrid.CELL


static func owner_of_group(g: Dictionary) -> int:
	var o: Variant = g.get("owner", "wild")
	if o is String:
		return Economy.NEUTRAL if o == "wild" else ENEMY
	return int(o)


## The settlement of a map zone (by its id), or null.
func sector_of(zone: String) -> Sector:
	var ref: Dictionary = world.map_info.get("refs", {}).get(zone, {})
	if not ref.has("sector"):
		return null
	var i := int(ref["sector"])
	return world.economy.sectors[i] if i >= 0 and i < world.economy.sectors.size() else null


func _sectors_of(owner: int) -> int:
	var n := 0
	for sec in world.economy.sectors:
		if sec.owner == owner:
			n += 1
	return n


func group_def(gid: String) -> Dictionary:
	for g: Dictionary in def.get("groups", []):
		if g["id"] == gid:
			return g
	return {}


func npc_def(nid: String) -> Dictionary:
	for n: Dictionary in def.get("npcs", []):
		if n["id"] == nid:
			return n
	return {}


func hero_unit() -> SimUnit:
	return world.heroes.hero_unit(PLAYER)


func npc_unit(nid: String) -> SimUnit:
	return world.get_unit(int(npcs.get(nid, -1)))


## The npc id of a unit ("" if it is not a campaign NPC).
func npc_of(unit_id: int) -> String:
	for nid in npcs:
		if int(npcs[nid]) == unit_id:
			return nid
	return ""


## Living units of a group.
func group_units(gid: String) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for id in groups.get(gid, []):
		var u := world.get_unit(int(id))
		if u != null:
			out.append(u)
	return out


## A place in px: [fx, fy] (map fractions), [x, y, "px"], "hero", or the id of an npc,
## group, zone or site.
func pos_of(ref: Variant) -> Vector2:
	if ref is Array:
		var a: Array = ref
		if a.size() >= 3 and String(a[2]) == "px":
			return Vector2(float(a[0]), float(a[1]))
		return Vector2(float(a[0]), float(a[1])) * world.nav.world_size()
	var id := String(ref)
	if id == "hero":
		var hu := hero_unit()
		return hu.pos if hu != null else world.heroes.respawn_at.get(PLAYER, Vector2.ZERO)
	if npcs.has(id):
		var u := npc_unit(id)
		if u != null:
			return u.pos
		return pos_of(npc_def(id)["at"])
	if groups.has(id):
		var alive := group_units(id)
		if not alive.is_empty():
			var c := Vector2.ZERO
			for u in alive:
				c += u.pos
			return c / float(alive.size())
		return pos_of(group_def(id)["at"])
	var refs: Dictionary = world.map_info.get("refs", {})
	if refs.has(id):
		return refs[id]["pos"]
	push_error("mission: unknown place " + id)
	return Vector2.ZERO


# --- Tick ------------------------------------------------------------------------------

## Call once after every world.step().
func step() -> void:
	if outcome != "":
		return
	time += world.dt
	_bank_xp()
	_read_world_events()
	_step_talk()
	_step_leaving()
	if not is_war():
		_rest()
		if world.tick % CHECK_TICKS == 0:
			_raise_fallen()
	if world.tick % CHECK_TICKS == 0:
		_step_rules()


## XP the battle banked on the story hero goes to the StoryHero; levels apply at once.
func _bank_xp() -> void:
	var h := world.heroes.hero_of(PLAYER)
	if h == null or h.xp <= 0:
		return
	var amount := h.xp
	h.xp = 0
	_give_xp(amount)


func _give_xp(amount: int) -> void:
	var gained := progress.story.add_xp(amount)
	if gained > 0:
		world.heroes.refresh_story(PLAYER, progress.story)
		_apply_boost()
		events.append({"type": "level", "level": progress.story.level, "points": progress.story.points})


func _rest() -> void:
	for u in world.units:
		if u.owner == PLAYER and u.alive and u.hp < u.max_hp and u.since_hit > REST_SECONDS \
				and u.since_attack > REST_SECONDS:
			u.hp = minf(u.max_hp, u.hp + u.max_hp * REST_HEAL * world.dt)


func _raise_fallen() -> void:
	var hu := hero_unit()
	if hu == null or hu.since_hit < RISE_SECONDS or hu.since_attack < RISE_SECONDS:
		return
	var ids: Array = _named.keys()
	ids.sort()
	for id: int in ids:
		if world.get_unit(id) != null:
			continue
		var t: Array = _named[id]
		_named.erase(id)
		companions.erase(id)
		var a := float(id % 7) * 0.9
		var u := world.spawn(String(t[0]), PLAYER, hu.pos + Vector2(cos(a), sin(a)) * 45.0)
		u.label = String(t[1])
		u.hp = u.max_hp * RISE_HP
		companions[u.id] = true
		_named[u.id] = t
		events.append({"type": "rise", "name": u.label})


func _read_world_events() -> void:
	for e in world.events:
		match String(e["type"]):
			"hero_death":
				if int(e["owner"]) == PLAYER:
					var hs := world.heroes.hero_of(PLAYER)
					if hs != null and not is_war():
						var loss := int(floor(float(hs.marks) * DEATH_MARKS_LOSS))
						hs.marks -= loss
						events.append({"type": "hero_down", "marks": loss, "seconds": e["respawn"]})
					talk_target = ""
			"shrine":
				# A shrine the hero touches is where it wakes after a fall.
				if int(e["owner"]) == PLAYER:
					var site := world.sites.get_site(int(e["site"]))
					if not site.is_empty() and world.heroes.respawn_at.get(PLAYER, Vector2.ZERO) != site["pos"]:
						world.heroes.respawn_at[PLAYER] = site["pos"]
						events.append({"type": "checkpoint"})


func _step_talk() -> void:
	if talk_target == "" or not dialogue.is_empty():
		return
	var hu := hero_unit()
	var nu := npc_unit(talk_target)
	if hu == null or nu == null:
		talk_target = ""
		return
	if hu.pos.distance_to(nu.pos) <= TALK_RANGE:
		var nid := talk_target
		talk_target = ""
		world.command_stop([hu.id])
		_talk(nid)


func _step_rules() -> void:
	# Quests: the current step of every active quest, in the order they started.
	for q in quest_order.duplicate():
		var st: Dictionary = quests[q]
		while st["state"] == "active":
			var steps: Array = def["quests"][q]["steps"]
			var s: Dictionary = steps[int(st["step"])]
			if not s.has("done") or not check(s["done"]):
				break
			_advance(q)
	# Triggers: each fires once, in file order; one with "repeat" (seconds) fires again that
	# long after, as often as its condition still holds.
	var trs: Array = def.get("triggers", [])
	for i in trs.size():
		if outcome != "":
			break
		var t: Dictionary = trs[i]
		var again := float(t.get("repeat", 0.0))
		if fired.has(i) and (again <= 0.0 or time < float(fired[i])):
			continue
		if check(t["when"]):
			fired[i] = time + again if again > 0.0 else true
			_run(t.get("do", []), "")
	# War chapters are lost when the player holds no settlement any more.
	if outcome == "" and is_war() and _sectors_of(PLAYER) == 0:
		_act({"lose": "Your last settlement has fallen."}, "")
	if outcome == "" and not dialogue.is_empty():
		return
	if outcome == "" and not _queue.is_empty() and dialogue.is_empty():
		var nxt: Array = _queue.pop_front()
		_open(nxt[0], nxt[1])


# --- Conditions -------------------------------------------------------------------------

func check(c: Variant) -> bool:
	if c is bool:
		return c
	if c is Array:
		for x in c:
			if not check(x):
				return false
		return true
	var d: Dictionary = c
	if d.is_empty():
		return true
	if d.has("flag"):
		return flags.has(String(d["flag"]))
	if d.has("not"):
		return not check(d["not"])
	if d.has("all"):
		return check(d["all"] as Array)
	if d.has("any"):
		for x in d["any"]:
			if check(x):
				return true
		return false
	if d.has("quest"):
		return quests.get(String(d["quest"]), {}).get("state", "") == String(d.get("is", "active"))
	if d.has("step"):
		var qs: Dictionary = quests.get(String(d["step"][0]), {})
		return qs.get("state", "") == "active" and int(qs["step"]) == int(d["step"][1])
	if d.has("dead"):
		var gid := String(d["dead"])
		return spawned.has(gid) and group_units(gid).is_empty()
	if d.has("alive"):
		var id := String(d["alive"])
		if npcs.has(id):
			return npc_unit(id) != null
		return not group_units(id).is_empty()
	if d.has("spawned"):
		return spawned.has(String(d["spawned"]))
	if d.has("near"):
		var hu := hero_unit()
		if hu == null:
			return false
		return hu.pos.distance_to(pos_of(d["near"])) <= float(d.get("r", 5.0)) * NavGrid.CELL
	if d.has("cleared"):
		var refs: Dictionary = world.map_info.get("refs", {})
		var site: Dictionary = world.sites.get_site(int(refs.get(String(d["cleared"]), {}).get("site", -1)))
		return bool(site.get("cleared", false))
	if d.has("marks"):
		var hs := world.heroes.hero_of(PLAYER)
		return hs != null and hs.marks >= int(d["marks"])
	if d.has("time"):
		return time >= float(d["time"])
	if d.has("hero_level"):
		return progress.story.level >= int(d["hero_level"])
	if d.has("talked"):
		return talked.has(String(d["talked"]))
	if d.has("held"):
		# A zone's settlement belongs to the player (or to "by").
		var sec := sector_of(String(d["held"]))
		return sec != null and sec.owner == int(d.get("by", PLAYER))
	if d.has("companion"):
		# A named companion (by name) marches with the hero.
		for uid in companions:
			var cu := world.get_unit(int(uid))
			if cu != null and cu.label == String(d["companion"]):
				return true
		return false
	if d.has("holds"):
		# [owner, n]: that side holds at least n settlements.
		return _sectors_of(int(d["holds"][0])) >= int(d["holds"][1])
	push_error("mission: unknown condition %s" % d)
	return false


# --- Actions ----------------------------------------------------------------------------

func _run(actions: Array, npc_id: String) -> void:
	for a: Dictionary in actions:
		if outcome != "":
			return
		if a.has("if") and not check(a["if"]):
			continue
		_act(a, npc_id)


func _act(a: Dictionary, npc_id: String) -> void:
	if a.has("start_quest"):
		var q := String(a["start_quest"])
		if quests[q]["state"] == "new":
			quests[q]["state"] = "active"
			quests[q]["step"] = 0
			quest_order.append(q)
			events.append({"type": "quest_start", "quest": q, "title": def["quests"][q]["title"]})
	elif a.has("advance"):
		var q := String(a["advance"])
		if quests[q]["state"] == "active":
			_advance(q)
	elif a.has("complete_quest"):
		var q := String(a["complete_quest"])
		if quests[q]["state"] == "new":
			_act({"start_quest": q}, npc_id)
		while quests[q]["state"] == "active":
			_advance(q)
	elif a.has("fail_quest"):
		var q := String(a["fail_quest"])
		if quests[q]["state"] in ["new", "active"]:
			quests[q]["state"] = "failed"
			if not quest_order.has(q):
				quest_order.append(q)
			events.append({"type": "quest_failed", "quest": q, "title": def["quests"][q]["title"]})
	elif a.has("flag"):
		flags[String(a["flag"])] = true
	elif a.has("unflag"):
		flags.erase(String(a["unflag"]))
	elif a.has("xp"):
		events.append({"type": "xp", "amount": int(a["xp"])})
		_give_xp(int(a["xp"]))
	elif a.has("marks"):
		var hs := world.heroes.hero_of(PLAYER)
		if hs != null:
			hs.marks = maxi(0, hs.marks + int(a["marks"]))
			events.append({"type": "marks", "amount": int(a["marks"])})
	elif a.has("item"):
		var item := _make_item(a["item"])
		if not item.is_empty():
			world.heroes._ensure_catalog()
			world.heroes.gear.drop_item(item, pos_of("hero") + Vector2(10.0, 8.0))
			events.append({"type": "item", "name": item["name"], "rarity": item["rarity"]})
	elif a.has("potion"):
		var h := world.heroes.hero_of(PLAYER)
		if h != null:
			var k := String(a["potion"])
			h.potions[k] = int(h.potions.get(k, 0)) + int(a.get("n", 1))
			events.append({"type": "potion", "kind": k, "n": int(a.get("n", 1))})
	elif a.has("spawn"):
		_spawn_group(String(a["spawn"]))
	elif a.has("attack"):
		var ids: Array = group_units(String(a["attack"])).map(func(u: SimUnit) -> int: return u.id)
		for id in ids:
			world.get_unit(id).guard_radius = 0.0
		world.command_attack_move(ids, pos_of(a.get("to", "hero")))
	elif a.has("hostile"):
		_make_hostile(String(a["hostile"]), int(a.get("owner", ENEMY)))
	elif a.has("join"):
		_join(String(a["join"]))
	elif a.has("leave"):
		_leave(String(a["leave"]), a.get("to", null))
	elif a.has("remove"):
		_remove(String(a["remove"]))
	elif a.has("move"):
		var u := npc_unit(String(a["move"]))
		if u != null:
			_walk(u, pos_of(a["to"]))
	elif a.has("say"):
		events.append({"type": "say", "who": _speaker_name(String(a.get("who", npc_id))), "text": String(a["say"])})
	elif a.has("dialogue"):
		var who := String(a.get("npc", npc_id))
		if dialogue.is_empty():
			_open(String(a["dialogue"]), who)
		else:
			_queue.append([String(a["dialogue"]), who])
	elif a.has("checkpoint"):
		world.heroes.respawn_at[PLAYER] = pos_of(a["checkpoint"])
		events.append({"type": "checkpoint"})
	elif a.has("res"):
		# War chapters: resources for the player's treasury.
		var pl := world.economy.player(PLAYER)
		if pl != null:
			for r: String in a["res"]:
				pl.res[r] = maxi(0, pl.amount(r) + int(a["res"][r]))
			events.append({"type": "res", "res": a["res"]})
	elif a.has("win"):
		_finish("won", "")
	elif a.has("lose"):
		_finish("lost", String(a["lose"]))


func _advance(q: String) -> void:
	var st: Dictionary = quests[q]
	var qd: Dictionary = def["quests"][q]
	var steps: Array = qd["steps"]
	var s: Dictionary = steps[int(st["step"])]
	st["step"] = int(st["step"]) + 1
	if int(st["step"]) >= steps.size():
		st["state"] = "done"
		st["step"] = steps.size() - 1
		events.append({"type": "quest_done", "quest": q, "title": qd["title"]})
		_run(s.get("do", []), "")
		_run(qd.get("reward", []), "")
	else:
		events.append({"type": "quest_step", "quest": q, "title": qd["title"], "text": steps[int(st["step"])]["text"]})
		_run(s.get("do", []), "")


func _make_item(spec: Variant) -> Dictionary:
	var icat := ItemCatalog.get_default()
	var d: Dictionary = spec if spec is Dictionary else {"unique": String(spec)}
	if d.has("unique"):
		return icat.make_unique(String(d["unique"]))
	var rng := world.rng.fork(0xC4A1 + world.tick)
	return icat.roll(rng, String(d.get("rarity", "magic")), int(d.get("level", 2)), String(d.get("slot", "")))


func _make_hostile(id: String, owner: int) -> void:
	if npcs.has(id):
		var u := npc_unit(id)
		if u != null:
			u.passive = false
			u.owner = owner
			u.anchor = u.pos
			world.go_idle(u)
		if dialogue.get("npc", "") == id:
			dialogue = {}
		return
	for u in group_units(id):
		u.passive = false
		u.owner = owner
		u.anchor = u.pos
		world.go_idle(u)


func _join(id: String) -> void:
	var units: Array[SimUnit] = []
	if npcs.has(id):
		var u := npc_unit(id)
		if u != null:
			u.passive = false
			units.append(u)
		npcs[id] = -1
	else:
		units = group_units(id)
	for u in units:
		u.passive = false
		u.owner = PLAYER
		u.guard_radius = 0.0
		u.anchor = u.pos
		world.go_idle(u)
		companions[u.id] = true
		if u.label != "":
			_named[u.id] = [u.type_id, u.label]
		events.append({"type": "join", "unit": u.id, "name": u.label if u.label != "" else String(u.def["name"])})


func _leave(id: String, to: Variant) -> void:
	var units: Array[SimUnit] = []
	if npcs.has(id):
		var u := npc_unit(id)
		if u != null:
			units.append(u)
	else:
		units = group_units(id)
	for u in units:
		_named.erase(u.id)  # gone on purpose: does not get back up
		u.passive = true
		u.owner = NPC
		u.guard_radius = 0.0
		u.expires = 0.0
		if to == null:
			world.retire(u)
		else:
			_walk(u, pos_of(to))
			_leaving[u.id] = true
	if npcs.has(id) and to == null:
		npcs[id] = -1


func _remove(id: String) -> void:
	if npcs.has(id):
		var u := npc_unit(id)
		if u != null:
			world.retire(u)
		npcs[id] = -1
		return
	for u in group_units(id):
		_named.erase(u.id)
		world.retire(u)


func _walk(u: SimUnit, p: Vector2) -> void:
	u.order = SimUnit.Order.MOVE
	u.order_point = p
	world.set_path(u, p)


## Leaving units vanish once they have arrived (called every tick by step via _step_leaving).
func _step_leaving() -> void:
	for id in _leaving.keys():
		var u := world.get_unit(int(id))
		if u == null:
			_leaving.erase(id)
		elif u.order == SimUnit.Order.IDLE:
			world.retire(u)
			_leaving.erase(id)


func _finish(result: String, text: String) -> void:
	if outcome != "":
		return
	outcome = result
	lose_text = text
	dialogue = {}
	events.append({"type": "outcome", "result": result, "text": text})


# --- Dialogue ---------------------------------------------------------------------------

## The talk entry an NPC offers now (first whose condition holds), or {}.
func talk_entry(nid: String) -> Dictionary:
	for e: Dictionary in npc_def(nid).get("talk", []):
		if not e.has("if") or check(e["if"]):
			return e
	return {}


## "!" (a quest to take), "?" (a quest to hand in), "" (nothing new) over an NPC.
func mark(nid: String) -> String:
	if npc_unit(nid) == null:
		return ""
	return String(talk_entry(nid).get("mark", ""))


## Talk to an NPC: at once when the hero stands close, otherwise the hero walks there first.
func command_talk(nid: String) -> bool:
	var nu := npc_unit(nid)
	var hu := hero_unit()
	if nu == null or hu == null or outcome != "" or talk_entry(nid).is_empty():
		return false
	if hu.pos.distance_to(nu.pos) <= TALK_RANGE:
		world.command_stop([hu.id])
		_talk(nid)
	else:
		talk_target = nid
		world.command_move([hu.id], nu.pos)
	return true


func _talk(nid: String) -> void:
	var e := talk_entry(nid)
	if e.is_empty():
		return
	talked[nid] = int(talked.get(nid, 0)) + 1
	_open(String(e["dialogue"]), nid)


func _open(did: String, nid: String) -> void:
	var dd: Dictionary = def["dialogues"][did]
	dialogue = {"id": did, "node": String(dd.get("start", "start")), "npc": nid}
	_enter_node()


func _enter_node() -> void:
	var n := current_node()
	_run(n.get("do", []), String(dialogue.get("npc", "")))


func current_node() -> Dictionary:
	if dialogue.is_empty():
		return {}
	return def["dialogues"][dialogue["id"]]["nodes"][dialogue["node"]]


## The speaker of the open line: an npc's name, the hero's class name, or a plain name.
func speaker() -> String:
	var who := String(current_node().get("who", dialogue.get("npc", "")))
	return _speaker_name(who)


func _speaker_name(who: String) -> String:
	if who == "hero":
		if progress.hero_name != "":
			return progress.hero_name
		return String(HeroCatalog.get_default().classes[progress.story.class_id]["name"])
	if npcs.has(who):
		return String(npc_def(who)["name"])
	var named: Dictionary = def.get("speakers", {})
	if named.has(who):
		return String(named[who])  # a companion carried in from an earlier chapter
	var g := group_def(who)
	if g.has("hero"):
		return String(g["hero"].get("name", who))  # an enemy hero speaks for its band
	return who


## The answers shown for the open line: [{index, text}] (those whose condition holds).
## A line without choices has one answer, "Continue" (or "Farewell" at the end).
func choices() -> Array:
	var n := current_node()
	if n.is_empty():
		return []
	var out: Array = []
	var cs: Array = n.get("choices", [])
	for i in cs.size():
		var c: Dictionary = cs[i]
		if not c.has("if") or check(c["if"]):
			out.append({"index": i, "text": String(c["text"])})
	if cs.is_empty():
		out.append({"index": -1, "text": "Continue" if n.has("next") else "Farewell"})
	return out


## Picks an answer (index from choices(), -1 for Continue / Farewell).
func command_choose(index: int) -> bool:
	var n := current_node()
	if n.is_empty():
		return false
	var nid := String(dialogue.get("npc", ""))
	var nxt := ""
	if index < 0:
		if not (n.get("choices", []) as Array).is_empty():
			return false
		nxt = String(n.get("next", ""))
	else:
		var cs: Array = n.get("choices", [])
		if index >= cs.size():
			return false
		var c: Dictionary = cs[index]
		if c.has("if") and not check(c["if"]):
			return false
		var did := String(dialogue["id"])
		_run(c.get("do", []), nid)
		if dialogue.is_empty() or String(dialogue.get("id", "")) != did:
			return true  # an action ended or replaced the conversation
		nxt = String(c.get("next", ""))
	if nxt == "":
		dialogue = {}
		if not _queue.is_empty():
			var q: Array = _queue.pop_front()
			_open(q[0], q[1])
	else:
		dialogue["node"] = nxt
		_enter_node()
	return true


# --- The hero's trees ------------------------------------------------------------------------

## Spends a skill point in the story trees (StoryHero.learn); the battle hero follows at once.
func command_learn(node_id: String) -> bool:
	if not progress.story.learn(node_id):
		return false
	world.heroes.refresh_story(PLAYER, progress.story)
	_apply_boost()
	return true


## Puts a known skill into a bar slot (0-2 basic, 3 ultimate).
func command_slot(slot: int, skill_id: String) -> bool:
	if not progress.story.set_slot(slot, skill_id):
		return false
	world.heroes.refresh_story(PLAYER, progress.story)
	_apply_boost()
	return true


# --- Hand back ---------------------------------------------------------------------------

## Writes the chapter's results into the campaign progress (call once the chapter is won).
func harvest() -> void:
	var h := world.heroes.hero_of(PLAYER)
	_bank_xp()
	if h != null:
		progress.worn = h.worn.duplicate(true)
		progress.bag = []
		for item in h.bag:
			progress.bag.append(item)
		progress.potions = h.potions.duplicate()
		progress.marks = h.marks
	progress.companions = []
	for u in world.units:
		if u.alive and u.owner == PLAYER and companions.has(u.id) and u.label != "" \
				and progress.companions.size() < MAX_COMPANIONS:
			progress.companions.append({"type": u.type_id, "name": u.label})
	for f in flags:
		progress.flags[f] = true
	if not progress.done.has(def["id"]):
		progress.done.append(def["id"])


## The closing text for the outcome: the first outro entry whose condition holds.
func outro() -> Array:
	for o: Dictionary in def.get("outro", []):
		if not o.has("if") or check(o["if"]):
			return o["text"]
	return []
