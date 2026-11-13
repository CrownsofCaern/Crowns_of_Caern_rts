extends SceneTree
## Open-field battles between the factions' armies of equal value, and how fast each role tears
## down a building. Run it before and after a change to unit stats (rules.json, units.json).
##   godot --headless --path . --script res://tools/combat_parity.gd -- [seeds] [out.md] [tiers] [upgraded]
## tiers: the highest tier in each army (default 6); upgraded: 1 = the dwellings' upgraded units.
## Each pair fights `seeds` times on each side. An army spends the same value on every tier it
## fields; a battle ends when one side is wiped out or after 4 minutes, and scores by the share of
## value (health-weighted) each side has left, so a narrow win counts less than a rout.

const PERSON_VALUE := 15.0  ## a drafted worker, in gold
const RARE_VALUE := 12.0  ## one rare resource, in gold
const BUDGET := 3600.0
const FACTIONS := ["concord", "hollow", "ashen", "thornwood", "forge", "fishmen", "darkelf", "frostmarch"]

var seeds := 3
var max_tier := 6
var upgraded := false
var out := ""
var cat: UnitCatalog


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = int(args[0])
	if args.size() > 1 and args[1] != "-":
		out = args[1]
	if args.size() > 2:
		max_tier = int(args[2])
	if args.size() > 3:
		upgraded = args[3] == "1"
	cat = UnitCatalog.get_default()
	var lines: Array[String] = ["# Combat parity (tiers 1-%d%s, %d seeds a side)" % [max_tier, ", upgraded" if upgraded else "", seeds], ""]
	var wins := {}
	var games := {}
	var matrix := {}
	for f in FACTIONS:
		wins[f] = 0.0
		games[f] = 0
	for i in FACTIONS.size():
		for j in range(i + 1, FACTIONS.size()):
			var a: String = FACTIONS[i]
			var b: String = FACTIONS[j]
			var score := 0.0
			for s in seeds:
				for side in 2:
					var fa: String = a if side == 0 else b
					var fb: String = b if side == 0 else a
					var r := _battle(fa, fb, 9000 + s * 7 + i * 31 + j)
					var a_won := r if side == 0 else 1.0 - r
					score += a_won
			var n := seeds * 2
			matrix[a + ">" + b] = score / n
			wins[a] += score
			wins[b] += n - score
			games[a] += n
			games[b] += n
	lines.append("| faction | score |")
	lines.append("|---|---|")
	for f in FACTIONS:
		lines.append("| %s | %d%% |" % [f, roundi(100.0 * wins[f] / maxf(1.0, games[f]))])
	lines.append("")
	lines.append("Pairs (row beats column):")
	lines.append("")
	var head := "| |"
	for f in FACTIONS:
		head += " %s |" % f.substr(0, 5)
	lines.append(head)
	var sep := "|---|"
	for f in FACTIONS:
		sep += "---|"
	lines.append(sep)
	for a in FACTIONS:
		var row := "| %s |" % a
		for b in FACTIONS:
			if a == b:
				row += " - |"
			elif matrix.has(a + ">" + b):
				row += " %d |" % roundi(100.0 * matrix[a + ">" + b])
			else:
				row += " %d |" % roundi(100.0 * (1.0 - matrix[b + ">" + a]))
		lines.append(row)
	lines.append("")
	lines.append_array(_raze_report())
	var text := "\n".join(lines)
	print(text)
	if out != "":
		var fh := FileAccess.open(out, FileAccess.WRITE)
		fh.store_string(text)
	quit()


func _value(id: String) -> float:
	var c: Dictionary = cat.get_unit(id)["cost"]
	var v := PERSON_VALUE
	for r in c:
		v += float(c[r]) if r == "gold" else float(c[r]) * RARE_VALUE
	return v


func _army(faction: String) -> Array:
	var ids: Array = []
	for id in cat.faction_units(faction):
		if int(cat.get_unit(id)["tier"]) <= max_tier:
			ids.append(cat.upgrade_of_unit(id) if upgraded and cat.upgrade_of_unit(id) != "" else id)
	var out_ids: Array = []
	var per := BUDGET / float(ids.size())
	for id in ids:
		var n := maxi(1, roundi(per / _value(id)))
		for k in n:
			out_ids.append(id)
	return out_ids


## Side 0's score: 0.5 + half the difference in the share of value each side has left (1.0 =
## side 0 won without a scratch, 0.0 = side 1 did).
func _battle(fa: String, fb: String, seed_value: int) -> float:
	var w := SimWorld.new(seed_value)
	w.setup_map(90, 50)
	var sides := [_army(fa), _army(fb)]
	var ids := [[], []]
	for side in 2:
		var list: Array = sides[side]
		var x0 := 500.0 if side == 0 else 2380.0
		var dir := -1.0 if side == 0 else 1.0
		var melee := 0
		var back := 0
		for id in list:
			var d := cat.get_unit(id)
			var behind: bool = d["role"] in ["ranged", "support"]
			var k := back if behind else melee
			var x := x0 + dir * (float(k / 20) * 28.0 + (170.0 if behind else 0.0))
			var y := 800.0 + (float(k % 20) - 9.5) * 30.0
			ids[side].append(w.spawn(id, side, Vector2(x, y)).id)
			if behind:
				back += 1
			else:
				melee += 1
	w.command_attack_move(ids[0], Vector2(2380, 800))
	w.command_attack_move(ids[1], Vector2(500, 800))
	for i in 20 * 240:
		w.step()
		if w.count_alive(0) == 0 or w.count_alive(1) == 0:
			break
	var left := [0.0, 0.0]
	var full := [0.0, 0.0]
	for side in 2:
		for id in sides[side]:
			full[side] += _value(id)
	for u in w.units:
		if u.alive and u.owner < 2 and not u.is_structure():
			left[u.owner] += _value(u.type_id) * u.hp_ratio()
	var a: float = left[0] / full[0]
	var b: float = left[1] / full[1]
	return clampf(0.5 + 0.5 * (a - b), 0.0, 1.0)


## Seconds 1000 gold of each role needs to bring down a hall-I-sized building (no arrows).
func _raze_report() -> Array[String]:
	var hp := 2400.0
	var armor := float(cat.economy["building_defense"]["armor_pct"])
	var by_role := {}
	var by_unit: Array = []
	for f in FACTIONS:
		for base in cat.faction_units(f):
			var id: String = base
			var d := cat.get_unit(id)
			var w := SimWorld.new(5)
			w.setup_map(40, 30)
			var st := w.add_structure("building", 1, Vector2(640, 480), {"id": "building", "name": "Target", "role": "structure",
				"faction": "", "hp": hp, "armor_pct": armor, "speed": 0.0, "damage": 0.0, "attack_interval": 1.0,
				"range": 0.0, "sight": 0.0, "radius": 40.0, "abilities": [], "cost": {}, "sprite": ""})
			var n := maxi(1, roundi(1000.0 / _value(id)))
			var mine: Array = []
			for k in n:
				mine.append(w.spawn(id, 0, Vector2(640 + cos(k * 0.7) * 140.0, 480 + sin(k * 0.7) * 140.0)).id)
			w.command_attack(mine, st.id)
			var t := 0
			while st.alive and t < 20 * 600:
				w.step()
				t += 1
			var secs := t / 20.0
			var role := String(d["role"])
			if not by_role.has(role):
				by_role[role] = []
			by_role[role].append(secs)
			by_unit.append([secs, id])
	var lines: Array[String] = ["Seconds for 1000 gold of a unit to raze a 2400 hp building (mean by role):", ""]
	for role in ["infantry", "ranged", "cavalry", "flyer", "support", "heavy"]:
		if by_role.has(role):
			var s := 0.0
			for v in by_role[role]:
				s += v
			lines.append("- %s: %.0f s" % [role, s / by_role[role].size()])
	by_unit.sort_custom(func(x, y): return x[0] < y[0])
	lines.append("")
	lines.append("Fastest: " + ", ".join(by_unit.slice(0, 6).map(func(x): return "%s %.0f s" % [x[1], x[0]])))
	lines.append("Slowest: " + ", ".join(by_unit.slice(by_unit.size() - 6).map(func(x): return "%s %.0f s" % [x[1], x[0]])))
	return lines
