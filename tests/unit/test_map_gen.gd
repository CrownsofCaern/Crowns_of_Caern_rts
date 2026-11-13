extends "res://tests/test_case.gd"
## The skirmish map generator (MapGen, data/map_templates.json).

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_every_template_builds_and_is_connected"]

const OLD_AREA := {2: 144 * 96, 3: 192 * 128, 4: 192 * 128}  ## maps before the generator
const POOLS := {2: ["concord", "hollow"], 3: ["ashen", "frostmarch", "darkelf"], 4: ["concord", "thornwood", "forge", "fishmen"]}


func test_templates_are_valid() -> void:
	assert_eq(MapGen.validate(), [] as Array[String])
	assert_gt(MapGen.template_ids(2).size(), 5, "many two-player maps")
	assert_gt(MapGen.template_ids(4).size(), 2, "several four-player maps")
	assert_eq(MapGen.template_ids(3), MapGen.template_ids(4), "three players use the corner maps")
	for id: String in MapGen.template_ids(2) + MapGen.template_ids(4):
		assert_ne(MapGen.template_name(id), id, "%s has a name" % id)
		assert_ne(MapGen.template_desc(id), "", "%s has a description" % id)


## Every template, for every player count it takes: bigger than before, one home per
## player, everything reachable on foot from every home, guarded lairs.
func test_every_template_builds_and_is_connected() -> void:
	for players: int in [2, 3, 4]:
		for id: String in MapGen.template_ids(players):
			var w := SkirmishScenario.build_skirmish(31, POOLS[players], id)
			var tag := "%s/%d" % [id, players]
			assert_eq(w.map_info["template"], id, tag)
			assert_gt(w.nav.width * w.nav.height, int(OLD_AREA[players] * 1.5) - 1, "%s is 50%% bigger" % tag)
			var eco := w.economy
			var homes := 0
			for s: Sector in eco.sectors:
				if s.home_of >= 0:
					homes += 1
			assert_eq(homes, players, "%s: one home each" % tag)
			for o in players:
				var seen := _flood(w, eco.hall_of(o).center)
				for s: Sector in eco.sectors:
					assert_true(_reached(w, seen, s.center), "%s: sector %d reachable from home %d" % [tag, s.id, o])
				for key: String in ["lairs", "shrines", "merchants"]:
					for site: Array in w.map_info[key] if key == "lairs" else w.map_info[key].map(func(p: Vector2) -> Array: return [p]):
						assert_true(_reached(w, seen, site[0]), "%s: %s at %s reachable" % [tag, key, site[0]])
			assert_gt(w.map_info["lairs"].size(), 1, "%s has lairs" % tag)
			for n: ResNode in eco.nodes:
				assert_false(w.nav.is_blocked(n.pos), "%s: pile %d on open ground" % [tag, n.id])


func test_same_seed_same_map() -> void:
	for id: String in ["sundered_isles", "river_cross"]:
		var fs: Array = POOLS[2] if id == "sundered_isles" else POOLS[4]
		var a := SkirmishScenario.build_skirmish(77, fs, id)
		var b := SkirmishScenario.build_skirmish(77, fs, id)
		assert_eq(a.checksum(), b.checksum(), id)
		assert_eq(a.map_info["props"].size(), b.map_info["props"].size())
		var c := SkirmishScenario.build_skirmish(78, fs, id)
		assert_ne(_kinds_hash(a), _kinds_hash(c), "%s: another seed, another map" % id)


func test_random_template_is_picked_by_seed() -> void:
	var seen := {}
	for s in 12:
		var w := SkirmishScenario.build_skirmish(100 + s, POOLS[2])
		seen[w.map_info["template"]] = true
		assert_true(MapGen.template_ids(2).has(w.map_info["template"]))
	assert_gt(seen.size(), 2, "random maps vary")


## Two-player maps are symmetric: a cell and its image (mirror or half turn) share a kind.
func test_two_player_maps_are_symmetric() -> void:
	for id: String in MapGen.template_ids(2):
		var w := SkirmishScenario.build_skirmish(5, POOLS[2], id)
		var sym := String(MapGen.data()["templates"][id]["symmetry"])
		var nav := w.nav
		var bad := 0
		for y in nav.height:
			for x in nav.width:
				var m := Vector2i(nav.width - 1 - x, y if sym == "mirror_x" else nav.height - 1 - y)
				var a := nav.kind_at(Vector2i(x, y))
				var b := nav.kind_at(m)
				# Set pieces can sit a cell off their image; only terrain must match.
				if a != b and a != NavGrid.Kind.BUILDING and b != NavGrid.Kind.BUILDING:
					bad += 1
		assert_lt(float(bad) / (nav.width * nav.height), 0.01, "%s is symmetric" % id)
		var h0 := w.economy.hall_of(0).center
		var h1 := w.economy.hall_of(1).center
		var size := nav.world_size()
		var img := Vector2(size.x - h1.x, h1.y) if sym == "mirror_x" else size - h1
		assert_lt(h0.distance_to(img), 1.0, "%s: homes are images" % id)


func test_chokepoint_maps_have_their_bridges() -> void:
	var w := SkirmishScenario.build_skirmish(3, POOLS[2], "twin_bridges")
	assert_eq(w.map_info["bridges"].size(), 2, "the river has two bridges")
	var isles := SkirmishScenario.build_skirmish(3, POOLS[2], "sundered_isles")
	assert_gt(isles.map_info["bridges"].size(), 1, "islands are bridged")
	assert_eq(isles.map_info["border"], "sea")
	# Water really splits the field: without the bridges the far home is out of reach.
	var nav := w.nav
	for br: Array in w.map_info["bridges"]:
		var a: Vector2 = br[0]
		var b: Vector2 = br[1]
		for i in 21:
			var p := a.lerp(b, i / 20.0)
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var c := nav.cell_of(p) + Vector2i(dx, dy)
					if nav.in_bounds(c) and nav.kind_at(c) == NavGrid.Kind.GROUND:
						nav.set_blocked(c, true, NavGrid.Kind.WATER)
	# ... and the fords to the temple isle in the middle.
	var mid := nav.world_size() * 0.5
	for y in nav.height:
		for x in nav.width:
			var c := Vector2i(x, y)
			if nav.center_of(c).distance_to(mid) < nav.height * NavGrid.CELL * 0.16 and nav.kind_at(c) == NavGrid.Kind.GROUND:
				nav.set_blocked(c, true, NavGrid.Kind.WATER)
	var seen := _flood(w, w.economy.hall_of(0).center)
	assert_false(_reached(w, seen, w.economy.hall_of(1).center), "only the bridges and the isle cross the river")


func test_set_pieces_use_real_models_and_lairs_hold_guards() -> void:
	var w := SkirmishScenario.build_skirmish(12, POOLS[2], "lake_crown")
	assert_gt(w.map_info["props"].size(), 10, "ruins and temples stand on the map")
	for pr: Array in w.map_info["props"]:
		assert_true(ResourceLoader.exists("res://assets/props3d/%s.glb" % pr[0]), "model %s" % pr[0])
	for lair: Array in w.map_info["lairs"]:
		var guards := 0
		for u: SimUnit in w.units:
			if u.owner == Economy.NEUTRAL and u.alive and u.pos.distance_to(lair[0]) < 400.0:
				guards += 1
		assert_gt(guards, 0, "lair at %s is guarded" % lair[0])
	var regions: Array = w.map_info["regions"]
	var names := {}
	for r: Array in regions:
		names[r[1]] = true
	assert_gt(names.size(), 1, "more than one biome on the map")


func _flood(w: SimWorld, from: Vector2) -> PackedByteArray:
	var nav := w.nav
	var seen := PackedByteArray()
	seen.resize(nav.width * nav.height)
	var start := nav.cell_of(nav.nearest_free(from))
	var todo: Array[Vector2i] = [start]
	seen[start.y * nav.width + start.x] = 1
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if nav.in_bounds(n) and seen[n.y * nav.width + n.x] == 0 and not nav.is_blocked_cell(n):
				seen[n.y * nav.width + n.x] = 1
				todo.append(n)
	return seen


## Reached when a free cell within a few cells of p was reached (p itself may hold a building).
func _reached(w: SimWorld, seen: PackedByteArray, p: Vector2) -> bool:
	var c := w.nav.cell_of(p)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var n := c + Vector2i(dx, dy)
			if w.nav.in_bounds(n) and seen[n.y * w.nav.width + n.x] == 1:
				return true
	return false


func _kinds_hash(w: SimWorld) -> int:
	var h := 0
	for y in w.nav.height:
		for x in w.nav.width:
			h = (h * 31 + w.nav.kind_at(Vector2i(x, y))) % 1000000007
	return h


## Every map has high ground: plateaus ringed by cliffs (rock in the sim) with ramps where
## the roads come in, so the top is reachable (the connectivity test checks that too).
func test_plateaus_have_cliffs_and_ramps() -> void:
	for id: String in ["classic", "twin_bridges", "lake_crown"]:
		var w := SkirmishScenario.build_skirmish(13, POOLS[2], id)
		var pls: Array = w.map_info["plateaus"]
		assert_gt(pls.size(), 0, "%s has a plateau" % id)
		var pl: Array = pls[0]
		var rock := 0
		var open := 0
		for a in 72:
			var p: Vector2 = (pl[0] as Vector2) + Vector2.from_angle(a * TAU / 72.0) * (float(pl[1]) + float(pl[3]) * 0.5)
			var c := w.nav.cell_of(p)
			if not w.nav.in_bounds(c):
				continue
			if w.nav.kind_at(c) == NavGrid.Kind.ROCK:
				rock += 1
			elif w.nav.kind_at(c) == NavGrid.Kind.GROUND:
				open += 1
		assert_gt(rock, 12, "%s: a cliff runs round the plateau" % id)
		assert_gt(open, 2, "%s: and a ramp leads up" % id)
		assert_gt(float(pl[2]), 2.9, "%s: the plateau stands well above the land" % id)


func test_home_timber_and_ore_lie_just_outside_the_town() -> void:
	# Every player's base resources sit close to the hall, outside the town's footprint (so
	# the town model never hides them) and in a straight walk from it.
	for players in [2, 4]:
		var facs: Array = ["concord", "hollow", "ashen", "forge"].slice(0, players)
		for id: String in MapGen.template_ids(players):
			var w := SkirmishScenario.build_skirmish(5, facs, id)
			var town := float(w.economy.e["settlement_clearance"])
			for s: Sector in w.economy.sectors:
				if s.home_of < 0:
					continue
				for res in ["wood", "ore"]:
					var best: ResNode = null
					for n: ResNode in w.economy.nodes:
						if n.resource == res and (best == null or n.pos.distance_to(s.center) < best.pos.distance_to(s.center)):
							best = n
					var d := best.pos.distance_to(s.center)
					assert_gt(d, town, "%s p%d: %s outside the town" % [id, s.home_of, res])
					assert_lt(d, town + 6.0 * NavGrid.CELL, "%s p%d: %s close to the hall" % [id, s.home_of, res])
					assert_true(w.nav.line_clear(s.center, best.pos), "%s p%d: straight walk to the %s" % [id, s.home_of, res])


## Neutral settlements are held by varied garrisons (data "garrisons"), many of them mixed,
## each scaled to the settlement's militia strength; copies of a zone get the same group, and
## the units standing there are the ones the map lists.
func test_settlements_hold_varied_mixed_garrisons() -> void:
	var cat := UnitCatalog.get_default()
	for size: String in ["farmstead", "hamlet", "village", "town", "city"]:
		assert_gt(MapGen.garrison_options(size, "").size(), 2, "%s: several groups fit" % size)
		var budget := MapGen.garrison_budget(size)
		for o: Array in MapGen.garrison_options(size, "swamp"):
			var g: Dictionary = o[0]
			var counts := MapGen.garrison_fit(g, budget)
			var worth := 0.0
			for k in counts.size():
				worth += int(counts[k]) * MapGen.unit_worth(cat.get_unit(String(g["units"][k][0])))
			assert_between(worth / budget, 0.8, 1.25, "%s at a %s" % [g["id"], size])
			assert_gt(int(counts[0]), 0, "%s keeps its leader" % g["id"])
	var groups := {}
	var mixed := 0
	for s in 3:
		var w := SkirmishScenario.build_skirmish(100 + s, POOLS[2], "classic")
		var gar: Dictionary = w.map_info["garrisons"]
		var by_pos := {}
		for sec: Sector in w.economy.sectors:
			if sec.owner != -1 or int(w.economy.e["settlements"][sec.size]["militia"]) == 0:
				assert_false(gar.has(sec.id), "no garrison at sector %d" % sec.id)
				continue
			assert_true(gar.has(sec.id), "sector %d is held" % sec.id)
			var g: Dictionary = gar[sec.id]
			groups[g["id"]] = true
			if (g["units"] as Array).size() > 1:
				mixed += 1
			var want := {}
			for e: Array in g["units"]:
				want[e[0]] = int(e[1])
			var have := {}
			for u: SimUnit in w.units:
				if u.owner == Economy.NEUTRAL and u.guard_radius > 0.0 and u.pos.distance_to(sec.center) < 110.0:
					have[u.type_id] = int(have.get(u.type_id, 0)) + 1
			for k: String in want:
				assert_gt(int(have.get(k, 0)), int(want[k]) - 1, "sector %d: %d %s" % [sec.id, want[k], k])
			by_pos[Vector2i(roundi(sec.center.x), roundi(sec.center.y))] = g
		# Mirror images hold the same group.
		var W := w.nav.world_size().x
		for p: Vector2i in by_pos:
			for q: Vector2i in by_pos:
				if Vector2(p).distance_to(Vector2(W - q.x, q.y)) < 2.0:
					assert_eq(by_pos[p], by_pos[q], "mirrored settlements at %s and %s" % [p, q])
	assert_gt(groups.size(), 4, "many kinds of garrison")
	assert_gt(mixed, 3, "mixed garrisons")


## Handcrafted campaign maps keep the plain militia they were tuned with.
func test_campaign_layouts_keep_plain_militia() -> void:
	var layout: Dictionary = MapGen.data()["templates"]["classic"].duplicate(true)
	layout["symmetry"] = "none"
	layout["players"] = [1]
	var w := SimWorld.new(4)
	MapGen.build_layout(w, 4, ["concord", "hollow"], layout)
	assert_true(w.map_info["garrisons"].is_empty())
	var held := 0
	for sec: Sector in w.economy.sectors:
		for u: SimUnit in w.units:
			if u.owner == Economy.NEUTRAL and u.guard_radius > 0.0 and u.pos.distance_to(sec.center) < 90.0:
				assert_eq(u.type_id, "militia")
				held += 1
	assert_gt(held, 0, "the settlements are held")
