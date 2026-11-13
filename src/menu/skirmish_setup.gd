class_name SkirmishSetup
extends RefCounted
## What the skirmish setup screen chose: plain data, no Nodes. Player slots as in
## the main game's New Game screen (control, house, hero, computer level), plus
## the victory rule and seed. The menu sets SkirmishSetup.current before
## switching to the skirmish scene; the skirmish reads it in _ready (and keeps
## its own defaults when it is null). Slot i plays as owner i; slot 0 is you.

const TYPES := ["human", "computer", "closed"]
const TYPE_NAMES := {"human": "You", "computer": "Computer", "closed": "Closed"}
const DIFFICULTIES := ["easy", "normal", "hard", "very_hard", "brutal"]
const DIFFICULTY_NAMES := {"easy": "Easy", "normal": "Normal", "hard": "Hard", "very_hard": "Very hard",
	"brutal": "Brutal"}
const VICTORY := ["conquest"]
const VICTORY_NAMES := {"conquest": "Conquest: take every enemy settlement"}
## Player colours match the battle's rings (Skirmish.TEAM_COLORS, by owner).
const PLAYER_NAMES := ["Blue", "Red", "Green", "Gold", "Violet", "Teal"]
const PLAYER_COLORS := [Color(0.35, 0.6, 1.0), Color(0.95, 0.3, 0.25), Color(0.4, 0.85, 0.35),
	Color(0.95, 0.8, 0.25), Color(0.75, 0.4, 0.95), Color(0.3, 0.85, 0.85)]

## The setup of the battle being played (null: run the skirmish scene directly).
static var current: SkirmishSetup = null

## [{type, faction, hero, difficulty}]; faction and hero may be "random".
var slots: Array = []
var victory: String = "conquest"
var seed_value: int = 0  ## 0 = pick a new one when the battle starts
## Map template id (data/map_templates.json), or "random": picked by the seed among
## the templates that hold this many players.
var map: String = "random"

## Shortcuts for the 1v1 code paths: your house, the first computer's house and level.
var player_faction: String:
	get:
		return String(slots[0]["faction"])
	set(v):
		slots[0]["faction"] = v
var enemy_faction: String:
	get:
		return String(slots[1]["faction"])
	set(v):
		slots[1]["faction"] = v
var difficulty: String:
	get:
		return String(slots[1]["difficulty"])
	set(v):
		slots[1]["difficulty"] = v


func _init() -> void:
	slots = [new_slot("human", "concord"), new_slot("computer", "hollow")]


static func new_slot(type: String, faction: String) -> Dictionary:
	return {"type": type, "faction": faction, "hero": "random", "difficulty": "normal"}


## How many players a skirmish map can hold (SkirmishScenario.MAX_PLAYERS, else 2).
static func max_players() -> int:
	var consts: Dictionary = (SkirmishScenario as Script).get_script_constant_map()
	return clampi(int(consts.get("MAX_PLAYERS", 2)), 2, PLAYER_NAMES.size())


## Every faction in units.json that has units of its own (no neutral defenders).
static func playable_factions(catalog: UnitCatalog = null) -> Array:
	var c := catalog if catalog != null else UnitCatalog.get_default()
	var out: Array = []
	for f: String in c.factions:
		if f != "neutral" and not c.faction_units(f).is_empty():
			out.append(f)
	return out


## Hero classes a house can lead with (empty: no heroes for it yet).
static func hero_classes(faction: String) -> Array:
	return HeroCatalog.get_default().faction_classes(faction)


## The slots that take part (not closed), in owner order.
func active_slots() -> Array:
	return slots.filter(func(s: Dictionary) -> bool: return s["type"] != "closed")


## Sets the number of slots (2..max), opening new ones as computers.
func set_player_count(n: int) -> void:
	n = clampi(n, 2, PLAYER_NAMES.size())
	var pool := playable_factions()
	while slots.size() < n:
		slots.append(new_slot("computer", pool[slots.size() % pool.size()] if not pool.is_empty() else "concord"))
	slots.resize(n)


## Turns "random" and seed 0 into real choices, deterministically from `roll`
## (a seed from the caller, so tests can fix it). Returns a new setup.
func resolved(roll: int, catalog: UnitCatalog = null) -> SkirmishSetup:
	var out := copy()
	var all := playable_factions(catalog)
	var rng := GameRng.new(roll)
	if out.seed_value == 0:
		out.seed_value = rng.next_int(1, 999999)
	for s: Dictionary in out.slots:
		if s["faction"] == "random" or not all.has(s["faction"]):
			s["faction"] = all[rng.next_int(0, all.size() - 1)]
		var classes := hero_classes(s["faction"])
		if classes.is_empty():
			s["hero"] = ""
		elif s["hero"] == "random" or not classes.has(s["hero"]):
			s["hero"] = classes[rng.next_int(0, classes.size() - 1)]
		if not DIFFICULTIES.has(s["difficulty"]):
			s["difficulty"] = "normal"
		if not TYPES.has(s["type"]):
			s["type"] = "computer"
	if not VICTORY.has(out.victory):
		out.victory = "conquest"
	if not MapGen.template_ids(out.active_slots().size()).has(out.map):
		out.map = "random"
	return out


## The template id to build (empty: the seed picks one).
func map_template() -> String:
	return "" if map == "random" else map


## Houses of the players taking part, in owner order, as build_skirmish takes them.
func factions() -> Array:
	return active_slots().map(func(s: Dictionary) -> String: return String(s["faction"]))


## The hero class chosen for an owner ("" or "random" when none was fixed).
func hero_for(owner: int) -> String:
	var act := active_slots()
	if owner < 0 or owner >= act.size():
		return ""
	return String(act[owner].get("hero", ""))


func copy() -> SkirmishSetup:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "victory": victory, "seed": seed_value, "map": map}


static func from_dict(d: Dictionary) -> SkirmishSetup:
	var s := SkirmishSetup.new()
	if d.get("slots") is Array and (d["slots"] as Array).size() >= 2:
		s.slots = []
		for raw: Variant in d["slots"]:
			if raw is Dictionary:
				var slot := new_slot("computer", "concord")
				for k: String in slot:
					slot[k] = String((raw as Dictionary).get(k, slot[k]))
				s.slots.append(slot)
		while s.slots.size() < 2:
			s.slots.append(new_slot("computer", "hollow"))
		s.slots[0]["type"] = "human"
	else:
		# Settings saved before slots existed.
		s.player_faction = String(d.get("player_faction", "concord"))
		s.enemy_faction = String(d.get("enemy_faction", "hollow"))
		s.difficulty = String(d.get("difficulty", "normal"))
	s.victory = String(d.get("victory", s.victory))
	s.seed_value = int(d.get("seed", 0))
	s.map = String(d.get("map", "random"))
	return s
