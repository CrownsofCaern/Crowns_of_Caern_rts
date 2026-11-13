extends SceneTree
## Prints, for every skirmish template and a few seeds, how far each home hall is from its
## nearest wood and ore (walking distance, px). Usage:
## godot --headless --path . --script res://tools/base_resources_probe.gd -- [seeds]


func _path_len(w: SimWorld, a: Vector2, b: Vector2) -> float:
	var p := w.nav.find_path(w.nav.nearest_free(a), b)
	if p.is_empty():
		return INF
	var d := 0.0
	var prev := a
	for q in p:
		d += prev.distance_to(q)
		prev = q
	return d


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 4
	var worst := 0.0
	var nearest := INF
	for players in [2, 4]:
		var facs: Array = ["concord", "hollow", "ashen", "forge"].slice(0, players)
		for tid: String in MapGen.template_ids(players):
			for s in range(1, seeds + 1):
				var w := SkirmishScenario.build_skirmish(s, facs, tid)
				var line := "%s seed %d:" % [tid, s]
				for sec: Sector in w.economy.sectors:
					if sec.home_of < 0:
						continue
					for res in ["wood", "ore"]:
						var best := INF
						var best_air := INF
						for n: ResNode in w.economy.nodes:
							if n.resource == res:
								best_air = minf(best_air, n.pos.distance_to(sec.center))
						for n: ResNode in w.economy.nodes:
							if n.resource == res and n.pos.distance_to(sec.center) < best_air + 400.0:
								best = minf(best, _path_len(w, sec.center, n.pos))
						worst = maxf(worst, best)
						nearest = minf(nearest, best_air)
						line += " p%d %s %d/%d" % [sec.home_of, res, int(best_air), int(best)]
				print(line)
	print("worst walk: ", int(worst), "  nearest: ", int(nearest))
	quit()
