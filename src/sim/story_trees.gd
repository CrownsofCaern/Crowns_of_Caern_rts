class_name StoryTrees
extends RefCounted
## Story skill trees (data/skill_trees.json): three trees per class (two for its archetype, one
## for its faction), 8 nodes each in 4 rows. Passive nodes are talents (a mechanic, see TALENTS,
## carried out by HeroSystem) and/or army auras (ItemCatalog stats per rank); active nodes teach a
## heroes.json skill. Used by StoryHero; validate() lists every problem.

## Talent types: what a passive node does, with one value per rank. "fmt" is how a value reads:
## pct (a share), num (an amount), sec (seconds), every (every Nth). "min" talents combine by
## taking the smallest value (a shorter wait, a smaller N); the others add up.
## The text's %s is the value; HeroSystem carries every type out (a test checks each is used).
const TALENTS := {
	"execute": {"fmt": "pct", "text": "+%s damage (blows and skills) to enemies below 30%% health."},
	"lifesteal": {"fmt": "pct", "text": "The hero's blows heal it for %s of the damage they deal."},
	"cleave_attacks": {"fmt": "pct", "text": "Blows also hit enemies next to the target for %s of their damage."},
	"berserk": {"fmt": "pct", "text": "+%s damage while the hero is below half health."},
	"kill_haste": {"fmt": "pct", "text": "Each kill by the hero gives it %s attack speed for 4 s."},
	"first_strike": {"fmt": "pct", "text": "+%s damage to enemies that are still unhurt."},
	"fortress": {"fmt": "pct", "text": "The hero takes %s less damage while below 40%% health."},
	"heavy_blow": {"fmt": "every", "text": "Every %s blow stuns the target for 1 s."},
	"kill_cooldown": {"fmt": "sec", "text": "Each kill by the hero takes %s off every skill cooldown."},
	"thorns": {"fmt": "pct", "text": "Enemies striking the hero in melee take %s of the damage back."},
	"ranged_ward": {"fmt": "pct", "text": "The hero takes %s less damage from arrows and missiles."},
	"melee_ward": {"fmt": "pct", "text": "The hero takes %s less damage from melee blows."},
	"evade_every": {"fmt": "every", "text": "Every %s blow aimed at the hero misses."},
	"status_pct": {"fmt": "pct", "text": "Stuns, slows, curses and blessings from the hero's skills last %s longer."},
	"low_regen": {"fmt": "pct", "text": "Below 40%% health the hero heals %s of its health per second."},
	"undying": {"fmt": "sec", "text": "A killing blow leaves the hero at 1 health and warded instead (once every %s)."},
	"cleanse_pulse": {"fmt": "sec", "text": "Every %s, stuns and slows are lifted from your units around the hero."},
	"aura_radius": {"fmt": "pct", "text": "The hero's auras reach %s farther."},
	"army_regen": {"fmt": "num", "text": "Your units around the hero heal %s health per second."},
	"summon_might": {"fmt": "pct", "text": "Units the hero summons or raises have %s more health and damage."},
	"summon_time": {"fmt": "pct", "text": "Units the hero summons or raises stay %s longer."},
	"summon_count": {"fmt": "num", "text": "Summoning skills call %s more unit(s)."},
	"summon_bond": {"fmt": "num", "text": "When a unit the hero summoned falls or fades, the hero heals %s health."},
	"crit_every": {"fmt": "every", "text": "Every %s blow deals double damage."},
	"kill_mana": {"fmt": "num", "text": "Each kill by the hero restores %s mana."},
	"debuff_bonus": {"fmt": "pct", "text": "+%s damage to enemies that are stunned, slowed, weakened or exposed."},
	"chill": {"fmt": "pct", "text": "The hero's blows slow the target by %s for 2 s."},
	"echo": {"fmt": "every", "text": "Every %s skill cast costs no mana."},
	"dot_pct": {"fmt": "pct", "text": "The hero's lingering damage (fire, poison, bleeding ground) is %s stronger."},
	"attacker_weak": {"fmt": "pct", "text": "Enemies striking the hero in melee deal %s less damage for 3 s."},
	"contagion": {"fmt": "num", "text": "When a hexed enemy dies, its hexes jump to enemies within %s."},
	"spell_vamp": {"fmt": "pct", "text": "Damage from the hero's skills heals it for %s of the amount."},
	"heal_pct": {"fmt": "pct", "text": "The hero's healing skills heal %s more."},
	"last_rites": {"fmt": "num", "text": "When one of your units falls near the hero, it gains %s mana."},
	"heal_ward": {"fmt": "pct", "text": "Allies the hero heals take %s less damage for 4 s."},
	"ally_undying": {"fmt": "sec", "text": "A killing blow on one of your soldiers near the hero leaves it at 30%% health instead (once every %s)."},
	"fallen_rise": {"fmt": "every", "text": "Every %s enemy that falls near the hero rises to fight for it for 20 s."},
	"phalanx": {"fmt": "pct", "text": "The hero takes %s less damage for each of your units close by (up to 8)."},
	"avenge": {"fmt": "pct", "text": "When one of your units falls near the hero, those around gain %s damage for 5 s."},
	"kill_rally": {"fmt": "pct", "text": "Each kill by the hero gives your units around it %s damage for 4 s."},
	"ignite": {"fmt": "pct", "text": "The hero's blows set the target burning for %s of their damage over 3 s."},
	"kill_burst": {"fmt": "num", "text": "Enemies the hero kills burst into flame, dealing %s damage around them."},
	"pack": {"fmt": "pct", "text": "+%s damage for each of your units close to the hero (up to 8)."},
	"kill_heal": {"fmt": "pct", "text": "Each kill by the hero heals it for %s of its health."},
}
const MIN_TALENTS := ["heavy_blow", "evade_every", "undying", "cleanse_pulse", "crit_every", "echo", "ally_undying",
	"fallen_rise"]
## Passive icons (assets/ui/passives/<stat>.png): a stat, or "marks".
const ICONS := ["attack", "defense", "power", "knowledge", "damage", "damage_pct", "attack_speed", "hp", "hp_regen",
	"mana", "mana_regen", "move_pct", "cooldown_pct", "skill_pct", "xp_pct", "aura_might", "aura_ward", "aura_haste",
	"marks"]

static var _default: StoryTrees

var rules: Dictionary = {}
var trees: Dictionary = {}
var nodes: Dictionary = {}  ## node id -> node, with "tree" added


static func get_default() -> StoryTrees:
	if _default == null:
		_default = StoryTrees.new()
		_default.load_file("res://data/skill_trees.json")
	return _default


func load_file(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	rules = d.get("rules", {})
	trees = d.get("trees", {})
	nodes.clear()
	for tid in trees:
		for n: Dictionary in trees[tid]["nodes"]:
			var copy := n.duplicate()
			copy["tree"] = tid
			nodes[n["id"]] = copy


## The trees a class learns from: its archetype's (data order), then its faction's.
func class_trees(heroes: HeroCatalog, class_id: String) -> Array:
	var c: Dictionary = heroes.classes[class_id]
	var out: Array = []
	for tid in trees:
		if trees[tid].get("archetype", "") == c["archetype"]:
			out.append(tid)
	for tid in trees:
		if trees[tid].get("faction", "") == c["faction"]:
			out.append(tid)
	return out


func xp_to_next(level: int) -> int:
	return int(rules["xp_base"]) + int(rules["xp_per_level"]) * level


func max_rank(heroes: HeroCatalog, node_id: String) -> int:
	var n: Dictionary = nodes[node_id]
	if n["kind"] == "active":
		return heroes.max_rank(n["skill"])
	return int(n["max_rank"])


## The talent's value at a rank (0 below rank 1).
static func talent_value(n: Dictionary, rank: int) -> float:
	if rank <= 0 or not n.has("talent"):
		return 0.0
	var vals: Array = n["talent"]["value"]
	return float(vals[mini(rank, vals.size()) - 1])


## A value as the tooltip shows it.
static func format_value(type: String, v: float) -> String:
	match String(TALENTS[type]["fmt"]):
		"pct":
			return "%s%%" % _num(v * 100.0)
		"sec":
			return "%s s" % _num(v)
		"every":
			var n := int(v)
			var suffix := "th"
			if n % 100 < 11 or n % 100 > 13:
				suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
			return "%d%s" % [n, suffix]
	return _num(v)


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)


## The talent's line for the tooltip: its text with every rank's value ("4% / 7% / 10%").
## The current rank's value is marked with brackets.
static func talent_text(n: Dictionary, rank: int) -> String:
	var type: String = n["talent"]["type"]
	var parts: Array[String] = []
	var vals: Array = n["talent"]["value"]
	for i in vals.size():
		var s := format_value(type, float(vals[i]))
		parts.append("[%s]" % s if i + 1 == rank else s)
	return String(TALENTS[type]["text"]) % " / ".join(parts)


## The passive icon's name (assets/ui/passives/<icon>.png).
static func node_icon(n: Dictionary) -> String:
	if n.has("icon"):
		return n["icon"]
	for k in n.get("mods", {}):
		return k
	return "hp"


func validate(heroes: HeroCatalog) -> Array[String]:
	var errors: Array[String] = []
	for k in ["max_level", "xp_base", "xp_per_level", "start_points", "points_per_level", "row_points",
			"ultimate_level"]:
		if not rules.has(k):
			errors.append("skill_trees rules: missing " + k)
	var seen := {}
	for tid in trees:
		var t: Dictionary = trees[tid]
		var owner_ok: bool = heroes.archetypes.has(t.get("archetype", "")) or t.has("faction")
		if not owner_ok:
			errors.append("tree %s: needs an archetype or a faction" % tid)
		var list: Array = t.get("nodes", [])
		if list.size() != 8:
			errors.append("tree %s: has %d nodes, wants 8" % [tid, list.size()])
		var ults := 0
		for n: Dictionary in list:
			var nid: String = n.get("id", "")
			if seen.has(nid):
				errors.append("tree %s: node id %s is used twice" % [tid, nid])
			seen[nid] = true
			if int(n.get("row", -1)) < 0 or int(n.get("row", -1)) >= (rules["row_points"] as Array).size():
				errors.append("node %s: bad row" % nid)
			match String(n.get("kind", "")):
				"active":
					if not heroes.skills.has(n.get("skill", "")):
						errors.append("node %s: unknown skill %s" % [nid, n.get("skill", "")])
					elif heroes.skills[n["skill"]].get("ultimate", false):
						ults += 1
						if int(n["row"]) != 3:
							errors.append("node %s: ultimates sit in the last row" % nid)
				"passive":
					if int(n.get("max_rank", 0)) < 1:
						errors.append("node %s: needs a max_rank" % nid)
					if (n.get("mods", {}) as Dictionary).is_empty() and not n.has("talent"):
						errors.append("node %s: a passive needs a talent or mods" % nid)
					if not String(n.get("icon", "")) in ICONS:
						errors.append("node %s: unknown icon %s" % [nid, n.get("icon", "")])
					if n.has("talent"):
						var tal: Dictionary = n["talent"]
						if not TALENTS.has(tal.get("type", "")):
							errors.append("node %s: unknown talent %s" % [nid, tal.get("type", "")])
						var vals: Array = tal.get("value", [])
						if vals.size() != int(n.get("max_rank", 0)):
							errors.append("node %s: the talent needs one value per rank" % nid)
						for v in vals:
							if float(v) <= 0.0:
								errors.append("node %s: talent values are positive" % nid)
					for k in n.get("mods", {}):
						if not k in ItemCatalog.STATS:
							errors.append("node %s: unknown stat %s" % [nid, k])
				_:
					errors.append("node %s: kind is active or passive" % nid)
		if ults != 1:
			errors.append("tree %s: needs exactly one ultimate" % tid)
	for cid in heroes.classes:
		var ts := class_trees(heroes, cid)
		var c: Dictionary = heroes.classes[cid]
		var n_arch := 0
		for tid in ts:
			if trees[tid].has("archetype"):
				n_arch += 1
		if n_arch != 2:
			errors.append("class %s: its archetype needs 2 trees" % cid)
		if ts.size() - n_arch > 1:
			errors.append("faction %s: more than one tree" % c["faction"])
	return errors
