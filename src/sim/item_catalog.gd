class_name ItemCatalog
extends RefCounted
## Hero gear data (data/items.json): base items, affixes, uniques, sets, rarities, drop tables.
## Rolls items with a GameRng (so a seed always gives the same loot) and checks who may wear what.
## An item is a plain Dictionary:
## {uid, id, base, slot, kind, rarity, name, level, mods: {stat: value}, affixes: [ids], set}

const SLOTS := ["weapon", "armor", "helm", "shield", "boots", "charm", "banner"]
const STATS := ["attack", "defense", "power", "knowledge", "damage", "damage_pct", "attack_speed", "hp", "hp_regen",
	"mana", "mana_regen", "move_pct", "cooldown_pct", "skill_pct", "xp_pct", "aura_might", "aura_ward", "aura_haste"]
const AURAS := {"aura_might": "might", "aura_ward": "ward", "aura_haste": "haste"}
## Stats shown with a percent sign.
const PERCENT := ["damage_pct", "attack_speed", "move_pct", "cooldown_pct", "skill_pct", "xp_pct", "aura_might",
	"aura_ward", "aura_haste"]
const STAT_TEXT := {
	"attack": "Attack", "defense": "Defense", "power": "Power", "knowledge": "Knowledge", "damage": "Damage",
	"damage_pct": "Damage", "attack_speed": "Attack speed", "hp": "Health", "hp_regen": "Health per second",
	"mana": "Mana", "mana_regen": "Mana per second", "move_pct": "Movement speed", "cooldown_pct": "Faster cooldowns",
	"skill_pct": "Skill strength", "xp_pct": "Experience", "aura_might": "Army aura: damage",
	"aura_ward": "Army aura: less damage taken", "aura_haste": "Army aura: attack speed",
}

static var _default: ItemCatalog

var rules: Dictionary = {}
var rarities: Dictionary = {}
var drops: Dictionary = {}
var rare_names: Dictionary = {}
var bases: Dictionary = {}
var affixes: Dictionary = {}
var uniques: Dictionary = {}
var sets: Dictionary = {}


static func get_default() -> ItemCatalog:
	if _default == null:
		_default = ItemCatalog.new()
		_default.load_file("res://data/items.json")
	return _default


func load_file(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	rules = d.get("rules", {})
	rarities = d.get("rarities", {})
	drops = d.get("drops", {})
	rare_names = d.get("rare_names", {})
	bases = d.get("bases", {})
	affixes = d.get("affixes", {})
	uniques = d.get("uniques", {})
	sets = d.get("sets", {})


# --- Rolling -----------------------------------------------------------------------

## The item level of loot from a settlement of this size after some minutes of play.
func drop_level(settlement_size: String, minutes: float) -> int:
	var base := int(drops["settlement_level"].get(settlement_size, 1))
	var extra := int(minutes / float(rules["minutes_per_item_level"]))
	return clampi(base + extra, 1, int(rules["max_item_level"]))


## Rolls one item from a drop table ("capture"). Uniques and sets fall back to rare
## when none is low enough for the item level.
func roll_drop(rng: GameRng, table: String, level: int) -> Dictionary:
	var weights: Dictionary = drops[table]["rarity"]
	var keys: Array = weights.keys()
	var w: Array = []
	for k in keys:
		w.append(float(weights[k]))
	var rarity: String = keys[rng.weighted_index(w)]
	if rarity == "unique" or rarity == "set":
		var pool: Array = []
		for id in uniques:
			var u: Dictionary = uniques[id]
			if int(u["level"]) <= level and (u.has("set") == (rarity == "set")):
				pool.append(id)
		if not pool.is_empty():
			return make_unique(pool[rng.next_int(0, pool.size() - 1)])
		rarity = "rare"
	return roll(rng, rarity, level)


## A random base item of a rarity, with its affixes rolled.
func roll(rng: GameRng, rarity: String, level: int, slot: String = "") -> Dictionary:
	var pool: Array = []
	for id in bases:
		if int(bases[id]["level"]) <= level and (slot == "" or bases[id]["slot"] == slot):
			pool.append(id)
	var base_id: String = pool[rng.next_int(0, pool.size() - 1)]
	var base: Dictionary = bases[base_id]
	var item := {
		"uid": 0, "id": base_id, "base": base_id, "slot": base["slot"], "kind": base["kind"], "rarity": rarity,
		"name": base["name"], "level": level, "mods": (base["mods"] as Dictionary).duplicate(), "affixes": [],
		"set": "",
	}
	var span: Array = rarities[rarity]["affixes"]
	var n := rng.next_int(int(span[0]), int(span[1]))
	var per_kind := 1 if rarity == "magic" else 2
	var taken := {"prefix": 0, "suffix": 0}
	var prefix := ""
	var suffix := ""
	for i in n:
		var choices: Array = []
		for aid in affixes:
			var a: Dictionary = affixes[aid]
			if base["slot"] in a["slots"] and not aid in item["affixes"] and taken[a["kind"]] < per_kind:
				choices.append(aid)
		if choices.is_empty():
			break
		var aid: String = choices[rng.next_int(0, choices.size() - 1)]
		var a: Dictionary = affixes[aid]
		taken[a["kind"]] += 1
		item["affixes"].append(aid)
		var v := affix_value(aid, level, rng.next_float())
		item["mods"][a["stat"]] = float(item["mods"].get(a["stat"], 0.0)) + v
		if a["kind"] == "prefix" and prefix == "":
			prefix = a["name"]
		elif a["kind"] == "suffix" and suffix == "":
			suffix = a["name"]
	if rarity == "magic":
		var parts := PackedStringArray()
		if prefix != "":
			parts.append(prefix)
		parts.append(base["name"])
		if suffix != "":
			parts.append(suffix)
		item["name"] = " ".join(parts)
	elif rarity == "rare":
		var first: Array = rare_names["first"]
		var second: Array = rare_names["second"]
		item["name"] = "%s%s %s" % [first[rng.next_int(0, first.size() - 1)], second[rng.next_int(0,
			second.size() - 1)], base["name"]]
	return item


## The value of an affix at an item level; roll is 0..1. Whole-number stats stay whole.
func affix_value(aid: String, level: int, roll_value: float) -> float:
	var a: Dictionary = affixes[aid]
	var v := lerpf(float(a["min"]), float(a["max"]), roll_value)
	v *= 1.0 + float(rules["grow_per_level"]) * float(level - 1)
	if a["stat"] in PERCENT or a["stat"] in ["hp_regen", "mana_regen"]:
		return snappedf(v, 0.01)
	return float(roundi(v))


func make_unique(id: String) -> Dictionary:
	var u: Dictionary = uniques[id]
	return {
		"uid": 0, "id": id, "base": "", "slot": u["slot"], "kind": u["kind"],
		"rarity": "set" if u.has("set") else "unique", "name": u["name"], "level": int(u["level"]),
		"mods": (u["mods"] as Dictionary).duplicate(), "affixes": [], "set": u.get("set", ""),
	}


# --- Wearing -----------------------------------------------------------------------

## Whether a hero of this archetype may wear the item at all.
func can_wear(archetype: String, item: Dictionary) -> bool:
	if item["slot"] == "weapon" or item["slot"] == "shield":
		return item["kind"] in rules["archetype_kinds"].get(archetype, [])
	return true


func two_handed(item: Dictionary) -> bool:
	return item.get("kind", "") in rules["two_handed"]


## Sum of the mods of the worn items plus their set bonuses.
func total_mods(worn: Dictionary) -> Dictionary:
	var out := {}
	var set_count := {}
	for slot in SLOTS:
		if not worn.has(slot):
			continue
		var it: Dictionary = worn[slot]
		_add(out, it["mods"])
		if it.get("set", "") != "":
			set_count[it["set"]] = int(set_count.get(it["set"], 0)) + 1
	var set_ids := set_count.keys()
	set_ids.sort()
	for sid in set_ids:
		for bonus: Dictionary in sets[sid]["bonuses"]:
			if int(set_count[sid]) >= int(bonus["pieces"]):
				_add(out, bonus["mods"])
	return out


static func _add(out: Dictionary, mods: Dictionary) -> void:
	for k in mods:
		out[k] = float(out.get(k, 0.0)) + float(mods[k])


## How good an item is, for the computer's choices.
func score(item: Dictionary) -> float:
	return float(rarities[item["rarity"]]["rank"]) * 100.0 + float(item["level"]) * 10.0 + float(item["affixes"].size())


## The inventory icon of an item (its base's for rolled items): assets/items/<id>.png, 64x64.
## Copied from the main game by tools/sync_item_icons.py.
static func icon_path(item: Dictionary) -> String:
	var id: String = item.get("base", "")
	if id == "":
		id = item.get("id", "")
	return "res://assets/items/%s.png" % id


func color(item: Dictionary) -> Color:
	return Color(String(rarities[item["rarity"]]["color"]))


## Tooltip lines: name, rarity and slot, then one line per stat, then the set bonuses.
func describe(item: Dictionary) -> Array[String]:
	var lines: Array[String] = [item["name"], "%s %s (level %d)" % [rarities[item["rarity"]]["name"],
		String(item["kind"]).replace("_", " "), int(item["level"])]]
	var keys: Array = item["mods"].keys()
	keys.sort_custom(func(a, b): return STATS.find(a) < STATS.find(b))
	for k in keys:
		lines.append(stat_line(k, float(item["mods"][k])))
	if item.get("set", "") != "":
		var s: Dictionary = sets[item["set"]]
		for bonus: Dictionary in s["bonuses"]:
			var parts: Array[String] = []
			for k in bonus["mods"]:
				parts.append(stat_line(k, float(bonus["mods"][k])))
			lines.append("%s, %d pieces: %s" % [s["name"], int(bonus["pieces"]), ", ".join(parts)])
	if uniques.has(item["id"]) and uniques[item["id"]].has("text"):
		lines.append(uniques[item["id"]]["text"])
	return lines


static func stat_line(stat: String, v: float) -> String:
	if stat in PERCENT:
		return "+%d%% %s" % [roundi(v * 100.0), STAT_TEXT[stat].to_lower()]
	if stat in ["hp_regen", "mana_regen"]:
		return "+%.1f %s" % [v, STAT_TEXT[stat].to_lower()]
	return "+%d %s" % [roundi(v), STAT_TEXT[stat].to_lower()]


# --- Validation --------------------------------------------------------------------

func validate(heroes: HeroCatalog) -> Array[String]:
	var errors: Array[String] = []
	for k in ["bag_size", "pickup_radius", "potion_max", "aura_radius", "grow_per_level", "max_item_level"]:
		if not rules.has(k):
			errors.append("items rules: missing " + k)
	for a in heroes.archetypes:
		if not rules.get("archetype_kinds", {}).has(a):
			errors.append("items rules: no weapon kinds for archetype " + a)
	for cid in heroes.classes:
		var c: Dictionary = heroes.classes[cid]
		for w in c["weapons"]:
			if not w in rules.get("archetype_kinds", {}).get(c["archetype"], []):
				errors.append("class %s: its own weapon %s is not allowed for a %s" % [cid, w, c["archetype"]])
	for r in ["common", "magic", "rare", "set", "unique"]:
		if not rarities.has(r):
			errors.append("items: missing rarity " + r)
	var all := bases.duplicate()
	all.merge(uniques)
	for id in all:
		var b: Dictionary = all[id]
		if not b.get("slot", "") in SLOTS:
			errors.append("item %s: bad slot" % id)
		for k in b.get("mods", {}):
			if not k in STATS:
				errors.append("item %s: unknown stat %s" % [id, k])
		if b.get("slot") == "weapon" and not b.get("kind", "") in HeroCatalog.WEAPONS:
			errors.append("item %s: unknown weapon kind %s" % [id, b.get("kind", "")])
		if b.has("set") and not sets.has(b["set"]):
			errors.append("item %s: unknown set %s" % [id, b["set"]])
		if not ResourceLoader.exists("res://assets/items/%s.png" % id):
			errors.append("item %s: no icon in assets/items (run tools/sync_item_icons.py)" % id)
	for slot in SLOTS:
		var found := false
		for id in bases:
			if bases[id]["slot"] == slot and int(bases[id]["level"]) == 1:
				found = true
		if not found:
			errors.append("items: no level 1 base for slot " + slot)
	for id in affixes:
		var a: Dictionary = affixes[id]
		if not a.get("stat", "") in STATS:
			errors.append("affix %s: unknown stat" % id)
		if not a.get("kind", "") in ["prefix", "suffix"]:
			errors.append("affix %s: kind is prefix or suffix" % id)
		for s in a.get("slots", []):
			if not s in SLOTS:
				errors.append("affix %s: bad slot %s" % [id, s])
	for sid in sets:
		var n := 0
		for id in uniques:
			if uniques[id].get("set", "") == sid:
				n += 1
		for bonus: Dictionary in sets[sid]["bonuses"]:
			if int(bonus["pieces"]) > n:
				errors.append("set %s: a bonus needs more pieces than exist" % sid)
			for k in bonus["mods"]:
				if not k in STATS:
					errors.append("set %s: unknown stat %s" % [sid, k])
	for table in drops:
		if table == "settlement_level":
			continue
		for r in drops[table].get("rarity", {}):
			if not rarities.has(r):
				errors.append("drops %s: unknown rarity %s" % [table, r])
	return errors
