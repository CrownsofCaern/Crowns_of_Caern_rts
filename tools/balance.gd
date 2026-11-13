extends SceneTree
## Skirmish balance report: the economy AI plays itself on many seeds.
##   godot --headless --path . --script res://tools/balance.gd -- [games] [minutes] [out.md] [faction_a,faction_b]
## Factions swap sides every other game, so side and faction effects can be told apart.

var games := 12
var minutes := 25.0
var out := ""
var pair: Array = ["concord", "hollow"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		games = int(args[0])
	if args.size() > 1:
		minutes = float(args[1])
	if args.size() > 2 and args[2] != "-":
		out = args[2]
	if args.size() > 3:
		pair = Array(args[3].split(","))
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for g in games:
		var factions := [pair[0], pair[1]] if g % 2 == 0 else [pair[1], pair[0]]
		rows.append(_play(100 + g / 2, factions))
		var r: Dictionary = rows[-1]
		print("game %d: %s vs %s -> %s after %.1f min (sectors %s, by 5 min %s, peak %s, lost %s, hall %d/%d)" % [g + 1,
			factions[0], factions[1], r["winner_faction"], r["minutes"], r["sectors_end"], r["at_min"], r["peak"],
			r["lost"], r["players"][0]["hall"], r["players"][1]["hall"]])
	var report := _report(rows, (Time.get_ticks_msec() - t0) / 1000.0)
	print(report)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(report)
	quit()


func _play(seed_value: int, factions: Array) -> Dictionary:
	var w := SkirmishScenario.build_skirmish(seed_value, factions)
	var ais := [EconomyAi.new(0), EconomyAi.new(1)]
	var eco := w.economy
	var limit := int(minutes * 60.0 * w.tick_rate)
	var peak := [0, 0]
	var lost := [0, 0]
	var at_min: Dictionary = {}  ## minute -> [sectors0, sectors1]
	var first_fight := -1.0
	var tick := 0
	while tick < limit and eco.winner() < 0:
		for ai in ais:
			ai.update(w)
		w.step()
		tick += 1
		for e in w.events:
			if e["type"] == "death" and int(e["owner"]) < 2:
				lost[int(e["owner"])] += 1
				if first_fight < 0.0:
					first_fight = tick / float(w.tick_rate) / 60.0
		if tick % (w.tick_rate * 10) == 0:
			for o in 2:
				var army := 0
				for u in w.units:
					if u.owner == o and not u.is_worker():
						army += 1
				peak[o] = maxi(peak[o], army)
		if tick % (w.tick_rate * 300) == 0:
			at_min[tick / (w.tick_rate * 60)] = [eco.sectors_of(0), eco.sectors_of(1)]
	var win := eco.winner()
	var r := {"factions": factions, "winner": win, "winner_faction": factions[win] if win >= 0 else "none",
		"minutes": tick / float(w.tick_rate) / 60.0, "sectors_end": [eco.sectors_of(0), eco.sectors_of(1)],
		"peak": peak, "lost": lost, "at_min": at_min, "first_fight": first_fight, "players": []}
	for o in 2:
		var pl := eco.player(o)
		r["players"].append({"faction": pl.faction, "gathered": pl.gathered.duplicate(), "spent": pl.spent.duplicate(),
			"left": pl.res.duplicate(), "trained": pl.trained.duplicate(), "hall_times": pl.hall_times.duplicate(),
			"hall": pl.hall_level})
	return r


func _report(rows: Array, secs: float) -> String:
	var L: Array = []
	L.append("# Warbound skirmish balance report")
	L.append("")
	L.append("%d games, AI vs AI, at most %.0f minutes each (%.0f s to run)." % [rows.size(), minutes, secs])
	L.append("")
	var wins := {pair[0]: 0, pair[1]: 0, "none": 0}
	var side := [0, 0]
	var len_sum := 0.0
	var ended := 0
	for r in rows:
		wins[r["winner_faction"]] += 1
		if r["winner"] >= 0:
			side[r["winner"]] += 1
			len_sum += r["minutes"]
			ended += 1
	L.append("## Results")
	L.append("")
	L.append("- Wins: %s %d, %s %d, no winner %d" % [str(pair[0]).capitalize(), wins[pair[0]],
		str(pair[1]).capitalize(), wins[pair[1]], wins["none"]])
	L.append("- Wins by side: west %d, east %d" % [side[0], side[1]])
	L.append("- Average length of decided games: %s" % ("%.1f min" % (len_sum / ended) if ended > 0 else "-"))
	var ff := 0.0
	var ffn := 0
	for r in rows:
		if r["first_fight"] >= 0.0:
			ff += r["first_fight"]
			ffn += 1
	L.append("- First death between players, average: %s" % ("%.1f min" % (ff / ffn) if ffn > 0 else "never"))
	L.append("")
	for fac in pair:
		var g := {}
		var sp := {}
		var left := {}
		var trained := {}
		var hall := [0, 0, 0, 0]
		var hall2 := 0.0
		var hall2n := 0
		var peak := 0
		var lost := 0
		var n := 0
		for r in rows:
			for o in 2:
				var p: Dictionary = r["players"][o]
				if p["faction"] != fac:
					continue
				n += 1
				for k in p["gathered"]:
					g[k] = g.get(k, 0) + p["gathered"][k]
				for k in p["spent"]:
					sp[k] = sp.get(k, 0) + p["spent"][k]
				for k in p["left"]:
					left[k] = left.get(k, 0) + p["left"][k]
				for k in p["trained"]:
					trained[k] = trained.get(k, 0) + p["trained"][k]
				hall[int(p["hall"]) - 1] += 1
				if not p["hall_times"].is_empty():
					hall2 += float(p["hall_times"][0]) / 60.0
					hall2n += 1
				peak += r["peak"][o]
				lost += r["lost"][o]
		L.append("## %s (%d games)" % [fac.capitalize(), n])
		L.append("")
		L.append("| Resource | Brought in | Spent | Left at end |")
		L.append("|---|---|---|---|")
		var keys := ["gold", "wood", "ore", "mercury", "sulfur", "crystal", "gems"]
		for k in keys:
			if g.has(k) or sp.has(k) or left.has(k):
				L.append("| %s | %d | %d | %d |" % [k, g.get(k, 0) / maxi(n, 1), sp.get(k, 0) / maxi(n, 1),
					left.get(k, 0) / maxi(n, 1)])
		L.append("")
		L.append("- Hall level at the end: I %d, II %d, III %d, IV %d; hall II after %s" % [hall[0], hall[1], hall[2],
			hall[3], "%.1f min" % (hall2 / hall2n) if hall2n > 0 else "never"])
		L.append("- Army peak %.0f, units lost %.0f (per game)" % [float(peak) / maxi(n, 1), float(lost) / maxi(n, 1)])
		var tl: Array = []
		var cat := UnitCatalog.get_default()
		for id in cat.faction_units(fac):
			tl.append("%s %.1f" % [cat.get_unit(id)["name"], float(trained.get(id, 0)) / maxi(n, 1)])
		L.append("- Trained per game: " + ", ".join(tl))
		L.append("")
	return "\n".join(L) + "\n"
