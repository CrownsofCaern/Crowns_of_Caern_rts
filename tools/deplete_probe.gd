extends SceneTree
## How much each pile gives up over AI matches.
##   godot --headless --path . --script res://tools/deplete_probe.gd -- [games] [minutes]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 4
	var minutes := float(args[1]) if args.size() > 1 else 30.0
	for g in games:
		var w := SkirmishScenario.build_skirmish(100 + g, ["concord", "hollow"] if g % 2 == 0 else ["hollow", "concord"])
		var ais := [EconomyAi.new(0), EconomyAi.new(1)]
		var eco := w.economy
		var taken := {}
		var by_min := {}
		var tick := 0
		var limit := int(minutes * 60.0 * w.tick_rate)
		while tick < limit and eco.winner() < 0:
			for ai in ais:
				ai.update(w)
			w.step()
			tick += 1
			for e in w.events:
				if e["type"] == "deposit":
					var u: SimUnit = w.get_unit(int(e["unit"]))
					if u != null:
						taken[u.job] = int(taken.get(u.job, 0)) + int(e["amount"])
						var m := tick / (w.tick_rate * 5)
						by_min[m] = int(by_min.get(m, 0)) + int(e["amount"])
		var vals: Array = taken.values()
		vals.sort()
		vals.reverse()
		var per_kind := {}
		for n in eco.nodes:
			per_kind[n.resource] = int(per_kind.get(n.resource, 0)) + 1
		print("game %d: %.1f min winner %d nodes %d %s sectors %d" % [g, tick / float(w.tick_rate) / 60.0, eco.winner(), eco.nodes.size(), per_kind, eco.sectors.size()])
		print("  top piles: ", vals.slice(0, 12))
		var home_ids := []
		for n in eco.nodes:
			if eco.sectors[n.sector].home_of >= 0:
				home_ids.append([n.resource, taken.get(n.id, 0)])
		print("  home piles: ", home_ids)
		var kmax := {}
		var ksum := {}
		for n in eco.nodes:
			var t := int(taken.get(n.id, 0))
			kmax[n.resource] = maxi(int(kmax.get(n.resource, 0)), t)
			ksum[n.resource] = int(ksum.get(n.resource, 0)) + t
		print("  per kind max ", kmax, " sum ", ksum)
		for s in eco.sectors:
			var ks := []
			for n in eco.nodes:
				if n.sector == s.id:
					ks.append("%s:%d/%d" % [n.resource, int(taken.get(n.id, 0)), n.amount if "amount" in n else -1])
			print("  sector %d %s home %d owner %d: %s" % [s.id, s.size, s.home_of, s.owner, ks])
	quit()
