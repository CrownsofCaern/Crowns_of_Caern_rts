extends "res://tests/test_case.gd"

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_four_computers_play_a_corner_map"]


func test_full_armies_are_150_each_on_free_ground() -> void:
	var w := SkirmishScenario.build(9)
	assert_eq(w.count_alive(0), 150)
	assert_eq(w.count_alive(1), 150)
	for u in w.units:
		if not u.is_flying():
			assert_false(w.nav.is_blocked(u.pos), "%s spawned in rock" % u.type_id)


func test_demo_ai_attacks_after_delay() -> void:
	var w := SkirmishScenario.build(9, ["concord", "hollow"], 0.2)
	var ai := DemoAi.new(1, 2.0)
	var start := Vector2.ZERO
	for u in w.units:
		if u.owner == 1:
			start += u.pos
	for i in 20 * 8:
		ai.update(w)
		w.step()
	var now := Vector2.ZERO
	for u in w.units:
		if u.owner == 1:
			now += u.pos
	assert_lt(now.x, start.x - 100.0, "enemy advanced to the left")


func test_three_and_four_player_maps_are_fair() -> void:
	for fs in [["concord", "hollow", "ashen"], ["concord", "hollow", "thornwood", "forge"]]:
		var w := SkirmishScenario.build_skirmish(9, fs)
		var eco := w.economy
		assert_eq(eco.players.size(), fs.size())
		assert_gt(eco.sectors.size(), 9, "big maps hold more sectors")
		var homes := {}
		for s in eco.sectors:
			if s.home_of >= 0:
				homes[s.home_of] = s
		assert_eq(homes.size(), fs.size(), "one home each")
		for o in fs.size():
			assert_eq(eco.workers_of(o).size(), int(eco.e["start"]["workers"]))
			var near := {}
			for n in eco.nodes:
				if n.pos.distance_to(homes[o].center) < 540.0:  # home piles lie settlement_clearance + 1.5-4 cells out
					near[n.resource] = int(near.get(n.resource, 0)) + 1
			assert_gt(int(near.get("wood", 0)), 0, "%s: wood at home" % fs[o])
			for res in near:
				assert_true(res in ["wood", "ore", "gems"] or eco.uses(o, res), "%s can use %s at home" % [fs[o], res])
		# Homes sit in the corners, mirrored.
		var size := w.nav.world_size()
		var c0: Vector2 = homes[0].center
		var c1: Vector2 = homes[1].center
		assert_lt(c0.distance_to(size - c1), 1.0, "players 0 and 1 face each other")
		if fs.size() == 3:
			var corners := [Vector2(size.x - c0.x, c0.y), Vector2(c0.x, size.y - c0.y), size - c0]
			var empty := 0
			for s in eco.sectors:
				for c: Vector2 in corners:
					if s.center.distance_to(c) < 1.0 and s.home_of < 0:
						assert_eq(s.size, "town")
						assert_eq(s.owner, -1)
						empty += 1
			assert_eq(empty, 1, "the spare corner is a neutral town")
		assert_eq(eco.winner(), -1)


func test_last_one_standing_wins() -> void:
	var w := SkirmishScenario.build_skirmish(9, ["concord", "hollow", "ashen"])
	var eco := w.economy
	for s in eco.sectors:
		if s.owner == 1 or s.owner == 2:
			s.owner = -1
	assert_eq(eco.winner(), 0)
	var w2 := SkirmishScenario.build_skirmish(9, ["concord", "hollow", "ashen"])
	for s in w2.economy.sectors:
		if s.owner == 1:
			s.owner = -1
	assert_eq(w2.economy.winner(), -1, "two still standing")


func test_four_computers_play_a_corner_map() -> void:
	var w := SkirmishScenario.build_skirmish(5, ["concord", "hollow", "ashen", "forge"])
	var ais: Array = []
	for o in 4:
		ais.append(EconomyAi.new(o))
	for i in int(120.0 * w.tick_rate):
		for a in ais:
			a.update(w)
		w.step()
	for o in 4:
		assert_gt(w.economy.player(o).gathered.get("wood", 0), 0, "player %d gathers" % o)
