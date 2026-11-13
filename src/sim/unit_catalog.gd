class_name UnitCatalog
extends RefCounted
## Unit definitions (data/units.json) and combat rules (data/rules.json).
## Loaded once; validate() lists every problem so tests can fail loudly.

const ROLES := ["infantry", "ranged", "cavalry", "flyer", "support", "heavy", "worker"]
## Abilities the simulation implements. Data may only list these.
const ABILITIES := ["reach", "flying", "ranged", "heal", "charge", "regenerate", "shield_wall", "curse", "poison", "brace", "relentless",
	"life_drain", "armor_pierce", "cleave", "stun", "double_strike", "sunder", "first_strike", "aura", "fear", "splash",
	"burn", "bleed", "frost"]
## What a blow can be. Each unit has a defense against each (units.json "defense").
const DAMAGE_TYPES := ["melee", "ranged", "magic"]
## Damage over time abilities (rules.json "dots"); poison has its own older rules entry.
const DOTS := ["burn", "bleed", "frost"]
## Specials only upgraded units carry (rules.json upgrade_specials): the reason to buy a dwelling upgrade.
const UPGRADE_SPECIALS := ["life_drain", "armor_pierce", "cleave", "stun", "double_strike", "sunder", "first_strike",
	"aura", "fear", "splash"]
const UNIT_FIELDS := ["name", "faction", "tier", "role", "hp", "armor_pct", "damage", "attack_interval",
	"range", "speed", "sight", "radius", "abilities", "cost", "sprite", "damage_type", "defense", "building_damage"]

static var _default: UnitCatalog

var units: Dictionary = {}
var factions: Array = []
var rules: Dictionary = {}
var economy: Dictionary = {}
var building_names: Dictionary = {}
## Units that are not trained (heroes, registered by HeroCatalog): looked up by get_unit only.
var extra: Dictionary = {}


static func get_default() -> UnitCatalog:
	if _default == null:
		_default = UnitCatalog.new()
		_default.load_files("res://data/units.json", "res://data/rules.json", "res://data/economy.json")
	return _default


func load_files(units_path: String, rules_path: String, economy_path: String) -> void:
	var u: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(units_path))
	units = u.get("units", {})
	factions = u.get("factions", [])
	building_names = u.get("building_names", {})
	rules = JSON.parse_string(FileAccess.get_file_as_string(rules_path))
	economy = JSON.parse_string(FileAccess.get_file_as_string(economy_path))


func get_unit(id: String) -> Dictionary:
	return units.get(id, extra.get(id, {}))


## Base units of a faction (tiers 1-8, no workers, no upgraded units), cheapest tier first.
func faction_units(faction: String) -> Array:
	var out: Array = []
	for id in units:
		if units[id]["faction"] == faction and int(units[id]["tier"]) >= 1 and not units[id].has("upgrade_of"):
			out.append(id)
	out.sort_custom(func(a, b): return int(units[a]["tier"]) < int(units[b]["tier"]))
	return out


## The upgraded unit a base unit's dwelling trains once upgraded ("" = none).
func upgrade_of_unit(id: String) -> String:
	return String(units.get(id, {}).get("upgrade", ""))


func worker_type(faction: String) -> String:
	return "worker_" + faction


## Resources this faction's workers gather (gold comes from settlements).
func faction_resources(faction: String) -> Array:
	return economy["faction_resources"].get(faction, [])


## The kind of damage a unit's blows deal. Units without the field (heroes, structures): their
## missiles are ranged, anything else melee.
static func damage_type_of(d: Dictionary) -> String:
	if d.has("damage_type"):
		return String(d["damage_type"])
	return "ranged" if "ranged" in d.get("abilities", []) else "melee"


## Share of damage of a type the unit shrugs off: its defense against that type, else its armour.
static func defense_of(d: Dictionary, dtype: String) -> float:
	var df: Dictionary = d.get("defense", {})
	if df.has(dtype):
		return float(df[dtype])
	return float(d.get("armor_pct", 0.0))


## Damage of one blow against a building, wall, gate or tower (defaults to its usual damage).
static func building_damage_of(d: Dictionary) -> float:
	return float(d.get("building_damage", d.get("damage", 0.0)))


func matchup(attacker_role: String, target_role: String) -> float:
	var row: Dictionary = rules.get("role_matchups", {}).get(attacker_role, {})
	return float(row.get(target_role, 1.0))


func validate() -> Array[String]:
	var errors: Array[String] = []
	if int(rules.get("tick_rate", 0)) <= 0:
		errors.append("rules: tick_rate must be positive")
	var curse: Dictionary = rules.get("curse", {})
	if not (float(curse.get("damage_factor", 0.0)) > 0.0 and float(curse.get("damage_factor", 0.0)) <= 1.0) \
			or float(curse.get("seconds", 0.0)) <= 0.0:
		errors.append("rules: curse needs damage_factor in (0, 1] and positive seconds")
	if float(rules.get("speed_scale", 1.0)) <= 0.0:
		errors.append("rules: speed_scale must be positive")
	if float(rules.get("vision_scale", 1.0)) < 1.0:
		errors.append("rules: vision_scale must be at least 1 (units see as far as they fight)")
	var poison: Dictionary = rules.get("poison", {})
	if float(poison.get("fraction", 0.0)) <= 0.0 or float(poison.get("seconds", 0.0)) <= 0.0:
		errors.append("rules: poison needs a positive fraction and seconds")
	var dots: Dictionary = rules.get("dots", {})
	for k in DOTS:
		var dd: Dictionary = dots.get(k, {})
		if float(dd.get("seconds", 0.0)) <= 0.0:
			errors.append("rules: dots.%s needs positive seconds" % k)
		if k == "frost":
			if float(dd.get("slow", 0.0)) <= 0.0 or float(dd.get("slow", 0.0)) > 0.8:
				errors.append("rules: dots.frost needs slow in (0, 0.8]")
		elif float(dd.get("fraction", 0.0)) <= 0.0:
			errors.append("rules: dots.%s needs a positive fraction" % k)
	if float(rules.get("relentless", {}).get("stagger_seconds", 0.0)) <= 0.0:
		errors.append("rules: relentless needs positive stagger_seconds")
	for k in ["provoke_seconds", "fight_memory_seconds"]:
		if float(rules.get(k, 0.0)) <= 0.0:
			errors.append("rules: %s must be positive" % k)
	var bf := float(rules.get("brace", {}).get("charge_bonus_factor", -1.0))
	if bf < 0.0 or bf > 1.0:
		errors.append("rules: brace needs charge_bonus_factor in [0, 1]")
	errors.append_array(_validate_veterans())
	var rh: Dictionary = rules.get("rest_heal", {})
	if float(rh.get("per_second", -1.0)) < 0.0 or float(rh.get("per_second", 0.0)) > 0.05 \
			or float(rh.get("radius", 0.0)) <= 0.0 or float(rh.get("calm_seconds", -1.0)) < 0.0:
		errors.append("rules: rest_heal needs per_second in [0, 0.05], radius > 0, calm_seconds >= 0")
	if float(rules.get("retreat", {}).get("speed_factor", 0.0)) < 1.0:
		errors.append("rules: retreat needs speed_factor >= 1")
	var us: Dictionary = rules.get("upgrade_specials", {})
	for a in UPGRADE_SPECIALS:
		if not us.has(a):
			errors.append("rules: upgrade_specials lacks %s" % a)
	for f in factions:
		if f == "neutral":
			continue
		for id in faction_units(f):
			if not units[id].has("upgrade"):
				errors.append("%s: no upgraded version" % id)
	for role in rules.get("role_matchups", {}):
		if not role in ROLES:
			errors.append("rules: unknown role %s" % role)
		for other in rules["role_matchups"][role]:
			if not other in ROLES:
				errors.append("rules: unknown target role %s" % other)
	for id in units:
		var d: Dictionary = units[id]
		for f in UNIT_FIELDS:
			if not d.has(f):
				errors.append("%s: missing %s" % [id, f])
		if errors.size() > 0 and not d.has("role"):
			continue
		if not d["role"] in ROLES:
			errors.append("%s: unknown role %s" % [id, d["role"]])
		if not d["faction"] in factions:
			errors.append("%s: unknown faction %s" % [id, d["faction"]])
		for a in d["abilities"]:
			if not a in ABILITIES:
				errors.append("%s: ability %s has no effect" % [id, a])
		for f in ["hp", "damage", "attack_interval", "speed", "sight", "radius"]:
			if float(d[f]) <= 0.0:
				errors.append("%s: %s must be positive" % [id, f])
		if float(d["armor_pct"]) < 0.0 or float(d["armor_pct"]) >= 0.9:
			errors.append("%s: armor_pct out of range" % id)
		if not String(d["damage_type"]) in DAMAGE_TYPES:
			errors.append("%s: unknown damage_type %s" % [id, d["damage_type"]])
		var df: Dictionary = d["defense"] if d["defense"] is Dictionary else {}
		for k in DAMAGE_TYPES:
			if not df.has(k) or float(df[k]) < 0.0 or float(df[k]) >= 0.9:
				errors.append("%s: defense.%s missing or out of [0, 0.9)" % [id, k])
		for k in df:
			if not k in DAMAGE_TYPES:
				errors.append("%s: defense against unknown damage type %s" % [id, k])
		if float(d["building_damage"]) < 0.0:
			errors.append("%s: building_damage must not be negative" % id)
		if d.has("bloodless") and not d["bloodless"] is bool:
			errors.append("%s: bloodless must be true or false" % id)
		if d["role"] == "ranged" and float(d["range"]) < 100.0:
			errors.append("%s: ranged unit needs range >= 100" % id)
		if d["role"] == "worker" and d["faction"] != "neutral" and id != worker_type(d["faction"]):
			errors.append("%s: worker id must be worker_<faction>" % id)
		if not ResourceLoader.exists(d["sprite"]):
			errors.append("%s: sprite %s missing" % [id, d["sprite"]])
		if d.has("upgrade"):
			var up: Dictionary = units.get(String(d["upgrade"]), {})
			if up.is_empty() or String(up.get("upgrade_of", "")) != id:
				errors.append("%s: upgrade %s missing or not marked upgrade_of it" % [id, d["upgrade"]])
			elif up["faction"] != d["faction"] or int(up["tier"]) != int(d["tier"]):
				errors.append("%s: upgrade %s must share faction and tier" % [id, d["upgrade"]])
		if d.has("upgrade_of") and String(units.get(String(d["upgrade_of"]), {}).get("upgrade", "")) != id:
			errors.append("%s: its base %s does not name it as upgrade" % [id, d["upgrade_of"]])
		if not d.has("upgrade_of"):
			for a in d["abilities"]:
				if a in UPGRADE_SPECIALS:
					errors.append("%s: %s is for upgraded units only" % [id, a])
	for f in factions:
		if f == "neutral":
			continue
		if not units.has(worker_type(f)):
			errors.append("%s: no worker unit" % f)
		if not economy.get("faction_resources", {}).has(f):
			errors.append("economy: %s gathers nothing" % f)
		if not economy.get("buildings", {}).has(f):
			errors.append("economy: %s has no buildings" % f)
		else:
			var b: Dictionary = economy["buildings"][f]
			if b["dwellings"].size() != 8:
				errors.append("economy: %s needs 8 dwellings" % f)
			for key in [b["hall"], b["storehouse"]] + b["dwellings"]:
				if not ResourceLoader.exists("res://assets/buildings/%s.png" % key):
					errors.append("economy: art for %s missing" % key)
	for size in economy.get("settlements", {}):
		if not ResourceLoader.exists("res://assets/settlements/%s.png" % size):
			errors.append("economy: art for settlement %s missing" % size)
		var nxt: String = economy["settlements"][size]["next"]
		if nxt != "" and not economy["settlements"].has(nxt):
			errors.append("economy: %s upgrades to unknown %s" % [size, nxt])
	for r in economy.get("node_resources", []):
		if not ResourceLoader.exists("res://assets/resources/%s.png" % r):
			errors.append("economy: art for resource %s missing" % r)
	var pa: Dictionary = economy.get("pile_amounts", {})
	for k in ["wood", "ore", "rare", "home_factor"]:
		if not pa.has(k):
			errors.append("economy: pile_amounts needs %s" % k)
		elif k != "home_factor" and (int(pa[k]) == 0 or int(pa[k]) < -1):
			errors.append("economy: pile_amounts %s must be positive (or -1 for endless)" % k)
	if float(pa.get("home_factor", 1.0)) < 1.0:
		errors.append("economy: pile_amounts home_factor must be at least 1")
	if float(economy.get("capture_speed", 1.0)) <= 0.0:
		errors.append("economy: capture_speed must be positive")
	var seen_tiers: Array = []
	for sl in economy.get("dwelling_slots", []):
		for t in sl:
			seen_tiers.append(int(t))
	seen_tiers.sort()
	if seen_tiers != [1, 2, 3, 4, 5, 6, 7, 8]:
		errors.append("economy: dwelling_slots must hold tiers 1-8 once each, in order")
	errors.append_array(_validate_faction_buildings())
	var decay: Dictionary = economy.get("capture_decay", {})
	if float(decay.get("empty", 0.0)) <= 0.0 or float(decay.get("defended", 0.0)) <= 0.0:
		errors.append("economy: capture_decay needs positive empty and defended rates")
	if float(economy.get("militia_guard_radius", 0.0)) <= 0.0:
		errors.append("economy: militia_guard_radius must be positive")
	if float(economy.get("settlement_clearance", 110.0)) < 0.0:
		errors.append("economy: settlement_clearance must not be negative")
	if float(economy.get("home_capture_factor", 1.0)) <= 0.0:
		errors.append("economy: home_capture_factor must be positive")
	var ai: Dictionary = economy.get("ai_difficulty", {})
	for d in EconomyAi.DIFFICULTIES:
		if not ai.has(d):
			errors.append("economy: ai_difficulty %s missing" % d)
			continue
		if float(ai[d].get("think_every", 0.0)) <= 0.0 or int(ai[d].get("first_wave", 0)) < 1 \
				or int(ai[d].get("wave_growth", -1)) < 0:
			errors.append("economy: ai_difficulty %s needs think_every > 0, first_wave >= 1, wave_growth >= 0" % d)
		var a: Dictionary = ai[d]
		if int(a.get("expand", 0)) < 0 or int(a.get("expand", 0)) > 8:
			errors.append("economy: ai_difficulty %s expand must be 0-8" % d)
		if float(a.get("attack_edge", 0.0)) < 0.0 or float(a.get("regroup_ratio", 0.0)) < 0.0 \
				or float(a.get("regroup_ratio", 0.0)) >= 1.0:
			errors.append("economy: ai_difficulty %s needs attack_edge >= 0 and regroup_ratio in [0, 1)" % d)
		if int(a.get("protect_rank", 0)) < 0 or int(a.get("protect_rank", 0)) > 5:
			errors.append("economy: ai_difficulty %s protect_rank must be 0-5" % d)
		var lo := float(a.get("retreat_hp", 0.3))
		var hi := float(a.get("rejoin_hp", 0.8))
		if lo <= 0.0 or hi > 1.0 or lo >= hi:
			errors.append("economy: ai_difficulty %s needs 0 < retreat_hp < rejoin_hp <= 1" % d)
		if int(a.get("hall_army", 6)) < 0 or float(a.get("income_bonus", 0.0)) < 0.0 or float(a.get("income_bonus", 0.0)) > 1.0:
			errors.append("economy: ai_difficulty %s needs hall_army >= 0 and income_bonus in [0, 1]" % d)
	for k: String in ai:
		if not k.begins_with("_") and not k in EconomyAi.DIFFICULTIES:
			errors.append("economy: ai_difficulty %s is not a difficulty" % k)
	var wu: Dictionary = economy.get("worker_upgrades", {})
	var wn: int = (wu.get("bonus", []) as Array).size()
	if wn == 0:
		errors.append("economy: worker_upgrades needs at least one level")
	for k in ["hall", "seconds", "cost", "rare"]:
		if (wu.get(k, []) as Array).size() != wn:
			errors.append("economy: worker_upgrades %s needs one entry per level" % k)
	for b in wu.get("bonus", []):
		if float(b) <= 0.0:
			errors.append("economy: worker_upgrades bonus must be positive")
	var tw: Dictionary = economy.get("twists", {})
	for f in economy.get("faction_resources", {}):
		if not tw.has(f):
			errors.append("economy: faction %s has no twist" % f)
			continue
		if float(tw[f].get("regen_per_second", 0.0)) < 0.0 or float(tw[f].get("regen_reach", 64.0)) <= 0.0 \
				or not tw[f].get("regen_near", "forest") in SimWorld.REGEN_KINDS:
			errors.append("economy: %s regen needs a non-negative rate, a positive reach and forest or water" % f)
		var gf: Dictionary = tw[f].get("gather_factor", {})
		for r in gf:
			if not r in economy.get("node_resources", []) or float(gf[r]) <= 0.0:
				errors.append("economy: %s gather_factor for %s is invalid" % [f, r])
		if float(tw[f].get("road_speed_factor", 1.0)) <= 0.0:
			errors.append("economy: %s road_speed_factor must be positive" % f)
		if float(tw[f].get("unit_gold_factor", 1.0)) <= 0.0:
			errors.append("economy: %s unit_gold_factor must be positive" % f)
		if float(tw[f].get("sight_factor", 1.0)) <= 0.0 or float(tw[f].get("first_strike_factor", 1.0)) <= 0.0:
			errors.append("economy: %s sight_factor and first_strike_factor must be positive" % f)
		if float(tw[f].get("kill_heal", 0.0)) < 0.0 or float(tw[f].get("kill_heal", 0.0)) > 1.0:
			errors.append("economy: %s kill_heal must be between 0 and 1" % f)
		if float(tw[f].get("capture_time_factor", 1.0)) <= 0.0:
			errors.append("economy: %s capture_time_factor must be positive" % f)
		var plunder: Dictionary = tw[f].get("plunder", {})
		for size in plunder:
			if not economy.get("settlements", {}).has(size) or int(plunder[size]) < 0:
				errors.append("economy: %s plunder for %s is invalid" % [f, size])
		for t in tw[f].get("no_worker_tiers", []):
			if int(t) < 1 or int(t) > 8:
				errors.append("economy: %s no_worker_tiers has tier %s" % [f, t])
	return errors


## rules.json "veterans": five levels with rising thresholds and a bonus list per level.
func _validate_veterans() -> Array[String]:
	var errors: Array[String] = []
	var v: Dictionary = rules.get("veterans", {})
	var th: Array = v.get("thresholds", [])
	if th.size() != 5 or float(th[0]) != 0.0:
		return ["rules: veterans needs 5 thresholds starting at 0"]
	for i in range(1, 5):
		if float(th[i]) <= float(th[i - 1]):
			errors.append("rules: veterans thresholds must rise")
	for k in ["damage", "ward", "hp", "names"]:
		if (v.get(k, []) as Array).size() != 5:
			errors.append("rules: veterans %s needs one entry per level" % k)
	for k in ["damage", "ward", "hp"]:
		for x in v.get(k, []):
			if float(x) < 0.0 or float(x) >= 0.8:
				errors.append("rules: veterans %s must be in [0, 0.8)" % k)
	if int(v.get("promote_level", 0)) < 2 or int(v.get("promote_level", 0)) > 5:
		errors.append("rules: veterans promote_level must be 2-5")
	if float(v.get("kill_bonus", -1.0)) < 0.0:
		errors.append("rules: veterans kill_bonus must not be negative")
	return errors


## economy.json faction_buildings: two per house, in that house's dwelling art, with known effects.
func _validate_faction_buildings() -> Array[String]:
	var errors: Array[String] = []
	var fb: Dictionary = economy.get("faction_buildings", {})
	var levels := (economy.get("hall_levels", []) as Array).size()
	for f in economy.get("buildings", {}):
		var list: Array = fb.get(f, [])
		if list.size() != 2:
			errors.append("faction_buildings: %s needs two" % f)
		var ids: Array = []
		for d: Dictionary in list:
			var where := "faction_buildings %s %s" % [f, d.get("id", "?")]
			if d.get("id", "") == "" or d["id"] in ids:
				errors.append(where + ": missing or repeated id")
			ids.append(d.get("id", ""))
			if not String(d.get("key", "")) in economy["buildings"][f]["dwellings"]:
				errors.append(where + ": key must be one of the house's dwelling arts")
			if String(d.get("name", "")) == "" or String(d.get("text", "")) == "":
				errors.append(where + ": needs a name and text")
			if int(d.get("hall", 0)) < 1 or int(d.get("hall", 0)) > levels or int(d.get("limit", 0)) < 1:
				errors.append(where + ": hall must be 1-%d and limit at least 1" % levels)
			var costs: Array = [d.get("cost", {})]
			var fx: Dictionary = d.get("effect", {})
			var kind := String(fx.get("kind", ""))
			if not kind in FactionBuildings.KINDS:
				errors.append(where + ": unknown effect kind " + kind)
				continue
			for k in ["cost", "give"]:
				if fx.has(k):
					costs.append(fx[k])
			if fx.has("take"):
				costs.append(fx["take"])
			for c: Dictionary in costs:
				for r in c:
					if r != "gold" and not r in faction_resources(f):
						errors.append(where + ": %s is not a resource of the house" % r)
			if fx.has("unit") and get_unit(String(fx["unit"])).is_empty():
				errors.append(where + ": unknown unit " + String(fx["unit"]))
			for side in ["own", "foe"]:
				for st in fx.get(side, {}):
					if st != "heal" and not st in FactionBuildings.STATUSES:
						errors.append(where + ": unknown status " + st)
			if fx.has("status") and not fx["status"] in FactionBuildings.STATUSES:
				errors.append(where + ": unknown status " + String(fx["status"]))
			var need: Dictionary = {"aura": ["radius"], "tower": ["range", "count", "damage", "interval"],
				"raise": ["radius", "unit", "seconds", "max"], "income": ["resource", "per_minute"],
				"spawn": ["unit", "seconds", "max"], "trade": ["give", "take"], "market": ["amount", "rate", "rare_rate"],
				"gate": ["radius", "cooldown", "from"], "research": ["cost", "taken_factor", "seconds"],
				"feast": ["cost", "status", "value", "seconds", "cooldown"]}
			for k in need[kind]:
				if not fx.has(k):
					errors.append(where + ": %s needs %s" % [kind, k])
			if kind == "gate" and not fx.get("from", "") in ["hall", "gate"]:
				errors.append(where + ": gate from must be hall or gate")
	return errors
