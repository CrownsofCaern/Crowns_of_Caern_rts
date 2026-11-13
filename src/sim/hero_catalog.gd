class_name HeroCatalog
extends RefCounted
## Hero data (data/heroes.json): archetypes, classes with their 4-skill kits, skills, rules.
## Builds a hero's combat stats for a level; validate() lists every problem.

const TARGETS := ["self", "enemy", "ally", "point", "aura"]
const EFFECTS := ["damage", "heal", "heal_pct", "status", "dot", "leap", "summon", "drain", "aura", "taunt", "chain",
	"resurrect", "raise", "corpse_burst", "cleanse", "self_damage", "mana", "knockback", "pull"]
## exposed: takes more damage; venom: the unit's own blows poison.
const STATUS_KINDS := ["stun", "slow", "haste", "might", "weak", "ward", "exposed", "venom"]
const AUTOCAST := ["enemies_near", "enemy_far", "enemy_in_range", "fighting", "cluster", "ally_hurt", "fallen_near",
	"ally_hindered", "self_hurt"]
const ATTRIBUTES := ["attack", "defense", "power", "knowledge"]
const WEAPONS := ["sword", "axe", "club", "great_weapon", "polearm", "scythe", "bow", "thrown", "dagger", "staff",
	"shield"]

static var _default: HeroCatalog

var rules: Dictionary = {}
var archetypes: Dictionary = {}
var classes: Dictionary = {}
var skills: Dictionary = {}


static func get_default() -> HeroCatalog:
	if _default == null:
		_default = HeroCatalog.new()
		_default.load_file("res://data/heroes.json")
	return _default


func load_file(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	rules = d.get("rules", {})
	archetypes = d.get("archetypes", {})
	classes = d.get("classes", {})
	skills = d.get("skills", {})


static func type_id(class_id: String) -> String:
	return "hero_" + class_id


## Classes a faction can pick, in data order.
func faction_classes(faction: String) -> Array:
	var out: Array = []
	for id in classes:
		if classes[id]["faction"] == faction:
			out.append(id)
	return out


func kit(class_id: String) -> Array:
	return classes[class_id]["kit"]


func skill(id: String) -> Dictionary:
	return skills.get(id, {})


func max_rank(skill_id: String) -> int:
	return (skills[skill_id]["mana"] as Array).size()


## Value of a per-rank array at a rank (1-based); the last entry repeats.
static func at_rank(values: Array, rank: int) -> float:
	return float(values[clampi(rank - 1, 0, values.size() - 1)])


func xp_to_next(level: int) -> int:
	return int(rules["xp_base"]) + int(rules["xp_per_level"]) * level


func attributes_at(class_id: String, level: int) -> Dictionary:
	var a: Dictionary = archetypes[classes[class_id]["archetype"]]
	var out := {}
	for k in ATTRIBUTES:
		out[k] = float(a["start"][k]) + float(a["per_level"][k]) * float(level - 1)
	return out


## Attributes at a level plus the attribute points from gear (gear: ItemCatalog stat -> value).
func attributes_with(class_id: String, level: int, gear: Dictionary) -> Dictionary:
	var at := attributes_at(class_id, level)
	for k in ATTRIBUTES:
		at[k] = float(at[k]) + float(gear.get(k, 0.0))
	return at


## The unit definition of a hero at a level (the same fields as units.json), with its gear.
func make_def(class_id: String, level: int, cat: UnitCatalog, gear: Dictionary = {}) -> Dictionary:
	var c: Dictionary = classes[class_id]
	var a: Dictionary = archetypes[c["archetype"]]
	var at := attributes_with(class_id, level, gear)
	var d := float(at["defense"])
	var stand: Dictionary = cat.get_unit(c["stand_in"])
	var dmg := (float(a["damage"]) + float(gear.get("damage", 0.0))) \
		* (1.0 + float(rules["damage_per_attack"]) * float(at["attack"])) * (1.0 + float(gear.get("damage_pct", 0.0)))
	var move := minf(float(rules["move_cap"]), float(gear.get("move_pct", 0.0)))
	return {
		"id": type_id(class_id), "name": c["name"], "faction": c["faction"], "tier": 0, "role": a["role"],
		"hp": float(a["hp"]) + float(rules["hp_per_level"]) * (level - 1) + float(rules["hp_per_defense"]) * d
			+ float(gear.get("hp", 0.0)),
		"armor_pct": minf(float(rules["armor_cap"]), d / (d + 20.0)),
		"damage": dmg,
		"attack_interval": float(a["attack_interval"]) / (1.0 + float(gear.get("attack_speed", 0.0))),
		"range": float(a["range"]), "speed": float(a["speed"]) * (1.0 + move),
		"sight": float(rules["sight"]), "radius": float(rules["radius"]), "abilities": a["abilities"] + c.get("abilities", []),
		"damage_type": String(a.get("damage_type", "ranged" if "ranged" in a["abilities"] else "melee")),
		"cost": {}, "sprite": stand.get("sprite", ""), "hero": true, "class": class_id,
		"weapons": c["weapons"],
	}


## Lets get_unit() find every hero type (level 1 stats), for the view and corpses.
func register(cat: UnitCatalog) -> void:
	for id in classes:
		cat.extra[type_id(id)] = make_def(id, 1, cat)


func validate(cat: UnitCatalog) -> Array[String]:
	var errors: Array[String] = []
	for k in ["max_level", "xp_base", "xp_per_level", "xp_radius", "ultimate_level", "respawn_base", "coin"]:
		if not rules.has(k):
			errors.append("rules: missing " + k)
	for k in ["name", "per_kill_tier", "worker", "capture"]:
		if not rules.get("coin", {}).has(k):
			errors.append("rules coin: missing " + k)
	for id in archetypes:
		var a: Dictionary = archetypes[id]
		if not a.get("role", "") in UnitCatalog.ROLES:
			errors.append("archetype %s: bad role" % id)
		if a.has("damage_type") and not String(a["damage_type"]) in UnitCatalog.DAMAGE_TYPES:
			errors.append("archetype %s: unknown damage_type" % id)
		for ab in a.get("abilities", []):
			if not ab in UnitCatalog.ABILITIES:
				errors.append("archetype %s: unknown ability %s" % [id, ab])
		for k in ATTRIBUTES:
			if not a.get("start", {}).has(k) or not a.get("per_level", {}).has(k):
				errors.append("archetype %s: missing attribute %s" % [id, k])
		for s in a.get("skills", []):
			if not skills.has(s):
				errors.append("archetype %s: unknown skill %s" % [id, s])
	for id in classes:
		var c: Dictionary = classes[id]
		if not archetypes.has(c.get("archetype", "")):
			errors.append("class %s: unknown archetype" % id)
		if String(c.get("text", "")).is_empty():
			errors.append("class %s: needs a text" % id)
		if not c.get("faction", "") in cat.factions:
			errors.append("class %s: unknown faction %s" % [id, c.get("faction", "")])
		if cat.get_unit(c.get("stand_in", "")).is_empty():
			errors.append("class %s: unknown stand-in unit" % id)
		for ab in c.get("abilities", []):
			if not ab in UnitCatalog.ABILITIES:
				errors.append("class %s: unknown ability %s" % [id, ab])
		for w in c.get("weapons", []):
			if not w in WEAPONS:
				errors.append("class %s: unknown weapon %s" % [id, w])
		var k: Array = c.get("kit", [])
		if k.size() != 4:
			errors.append("class %s: a kit has 4 skills" % id)
			continue
		for i in 4:
			if not skills.has(k[i]):
				errors.append("class %s: unknown skill %s" % [id, k[i]])
			elif (i == 3) != bool(skills[k[i]].get("ultimate", false)):
				errors.append("class %s: only the 4th skill is the ultimate" % id)
		# The learn order must spend exactly the 10 points of levels 1-10 on a full kit.
		var lo: Array = c.get("learn_order", [])
		var counts := [0, 0, 0, 0]
		for i in lo:
			counts[int(i)] += 1
		for i in 4:
			if skills.has(k[i]) and counts[i] != max_rank(k[i]):
				errors.append("class %s: learn_order ranks skill %d %d times" % [id, i, counts[i]])
	for id in skills:
		var s: Dictionary = skills[id]
		if not s.get("target", "") in TARGETS:
			errors.append("skill %s: bad target" % id)
		var n := (s.get("mana", []) as Array).size()
		var want := 1 if s.get("ultimate", false) else 3
		if n != want or (s.get("cooldown", []) as Array).size() != want:
			errors.append("skill %s: needs %d ranks of mana and cooldown" % [id, want])
		if s.get("target") in ["enemy", "ally", "point"] and float(s.get("range", 0)) <= 0.0:
			errors.append("skill %s: needs a range" % id)
		if s.get("target") == "aura" and float(s.get("radius", 0)) <= 0.0:
			errors.append("skill %s: an aura needs a radius" % id)
		if s.has("autocast") and not s["autocast"].get("when", "") in AUTOCAST:
			errors.append("skill %s: unknown autocast rule" % id)
		var effects: Array = s.get("effects", [])
		if effects.is_empty():
			errors.append("skill %s: no effects" % id)
		for e: Dictionary in effects:
			var t: String = e.get("type", "")
			if not t in EFFECTS:
				errors.append("skill %s: unknown effect %s" % [id, t])
			if (t == "status" or t == "aura") and not e.get("kind", "") in STATUS_KINDS:
				errors.append("skill %s: unknown status %s" % [id, e.get("kind", "")])
			if (t == "aura") != (s.get("target") == "aura"):
				errors.append("skill %s: aura effects belong to aura skills" % id)
			for key in e:
				if e[key] is Array and (e[key] as Array).size() != want:
					errors.append("skill %s: %s needs %d values" % [id, key, want])
			if t == "summon":
				for f in cat.factions:
					var ok := false
					for u in cat.faction_units(f):
						if int(cat.get_unit(u)["tier"]) == int(e.get("tier", 0)):
							ok = true
					if f != "neutral" and not ok:
						errors.append("skill %s: %s has no tier %d unit" % [id, f, int(e.get("tier", 0))])
	return errors
