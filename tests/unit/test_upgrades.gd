extends "res://tests/test_case.gd"
## The hall's 4 levels (the home grows with it) and dwellings' permanent upgrades.

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_ai_upgrades_dwellings_late_and_same_seed_same_game"]


func _run(w: SimWorld, seconds: float, ai: EconomyAi = null) -> void:
	for i in int(seconds * w.tick_rate):
		if ai != null:
			ai.update(w)
		w.step()


func _rich(eco: Economy, owner: int) -> void:
	for r in eco.player(owner).res.keys():
		eco.player(owner).res[r] = 20000


func _first_dwelling(eco: Economy, owner: int) -> Building:
	for b in eco.buildings:
		if b.owner == owner and b.kind == "dwelling":
			return b
	return null


func test_hall_has_four_levels_and_the_home_follows_it() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	assert_eq(eco.e["hall_levels"].size(), 4)
	var home := eco.hall_of(0)
	var pl := eco.player(0)
	_rich(eco, 0)
	assert_false(eco.command_upgrade_settlement(0, home.id), "the home grows only with the hall")
	var last_workers := 0
	var last_gold := 0
	for lv in range(1, 5):
		var st := eco.settlement(home)
		assert_eq(st["next"], "", "no separate growth at hall %d" % lv)
		assert_gt(int(st["workers"]), last_workers, "more workers at hall %d" % lv)
		assert_gt(int(st["gold_per_min"]), last_gold, "more gold at hall %d" % lv)
		assert_eq(eco.max_tier(0), lv * 2, "tiers at hall %d" % lv)
		last_workers = int(st["workers"])
		last_gold = int(st["gold_per_min"])
		if lv < 4:
			assert_true(eco.command_upgrade_hall(0))
			_run(w, float(eco.e["hall_levels"][lv]["seconds"]) + 0.5)
			assert_eq(pl.hall_level, lv + 1)
	assert_false(eco.command_upgrade_hall(0), "IV is the top")
	assert_eq(int(eco.settlement(home)["workers"]), int(eco.e["settlements"]["city"]["workers"]), "hall IV = a city's workers")


func test_taken_home_is_an_ordinary_town() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var home := eco.hall_of(1)
	eco.player(1).hall_level = 4
	assert_eq(int(eco.settlement(home)["workers"]), 16)
	home.owner = 0
	assert_eq(int(eco.settlement(home)["workers"]), int(eco.e["settlements"]["town"]["workers"]))


func test_every_base_unit_has_an_upgrade() -> void:
	var cat := UnitCatalog.get_default()
	for f in cat.factions:
		if f == "neutral":
			continue
		var ids := cat.faction_units(f)
		assert_eq(ids.size(), 8, "%s has 8 base units" % f)
		for id in ids:
			var up := cat.upgrade_of_unit(id)
			assert_ne(up, "", "%s has an upgrade" % id)
			var b := cat.get_unit(id)
			var u := cat.get_unit(up)
			assert_eq(int(u["tier"]), int(b["tier"]))
			assert_true(float(u["hp"]) >= float(b["hp"]) and float(u["damage"]) > float(b["damage"]), "%s is better" % up)
			assert_gt(float(u["cost"]["gold"]), float(b["cost"]["gold"]), "%s costs more" % up)


func test_dwelling_upgrade_trains_the_upgraded_unit() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b := _first_dwelling(eco, 0)
	var base := b.unit_type
	var up := w.catalog.upgrade_of_unit(base)
	var pl := eco.player(0)
	assert_false(eco.command_upgrade_dwelling(0, b.id), "too dear at the start")
	_rich(eco, 0)
	var gold0 := pl.amount("gold")
	assert_true(eco.command_upgrade_dwelling(0, b.id))
	assert_lt(pl.amount("gold"), gold0, "paid")
	assert_false(eco.command_train(0, b.id), "no training while it is upgraded")
	assert_false(eco.command_upgrade_dwelling(0, b.id), "not twice at once")
	_run(w, eco.dwelling_upgrade_seconds(b.tier) + 0.5)
	assert_true(b.upgraded)
	assert_eq(b.unit_type, up)
	assert_true(eco.can_upgrade_dwelling(b, 2), "the shared tier 2 keeps its own upgrade")
	assert_false(eco.can_upgrade_dwelling(b, 1), "permanent, once")
	assert_true(eco.command_train(0, b.id))
	_run(w, 40.0)
	var n := 0
	for u in w.units:
		if u.owner == 0 and u.type_id == up:
			n += 1
	assert_eq(n, 1, "the upgraded unit came out")


func test_upgrade_waits_for_an_empty_queue() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b := _first_dwelling(eco, 0)
	_rich(eco, 0)
	assert_true(eco.command_train(0, b.id))
	assert_false(eco.command_upgrade_dwelling(0, b.id), "finish training first")


func test_upgrade_costs_rise_with_tier_and_need_rares_late() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var c1 := eco.dwelling_upgrade_cost(0, 1)
	var c8 := eco.dwelling_upgrade_cost(0, 8)
	assert_gt(int(c8["gold"]), int(c1["gold"]))
	assert_gt(int(c1["gold"]), int(eco.dwelling_cost(1)["gold"]) * 3, "dearer than the dwelling itself")
	assert_eq(c1.size(), 3, "tier 1: gold, timber, ore")
	assert_eq(c8.size(), 4, "tier 8 also asks for the faction's rare")


func _duel(attacker: String, target: String, seconds: float) -> Array:
	var w := SimWorld.new(3)
	w.setup_map(40, 20)
	var a := w.spawn(attacker, 0, Vector2(300, 300))
	var t := w.spawn(target, 1, Vector2(320, 300))
	for i in int(seconds * w.tick_rate):
		w.step()
	return [w, a, t]


func test_life_drain_heals_the_attacker() -> void:
	var r := _duel("gibbet_lord", "gibbet_knight", 6.0)
	var a: SimUnit = r[1]
	var t: SimUnit = r[2]
	assert_true(a.alive)
	# Equal-ish foes: the drainer ends healthier than its plain twin.
	assert_gt(a.hp_ratio(), t.hp_ratio() if t.alive else 0.0)


func test_upgraded_unit_beats_its_base() -> void:
	var cat := UnitCatalog.get_default()
	var wins := 0
	for f in ["concord", "hollow", "ashen", "frostmarch"]:
		var base: String = cat.faction_units(f)[3]
		var r := _duel(cat.upgrade_of_unit(base), base, 40.0)
		var a: SimUnit = r[1]
		var t: SimUnit = r[2]
		if a.alive and (not t.alive or a.hp_ratio() > t.hp_ratio()):
			wins += 1
	assert_eq(wins, 4, "tier 4 upgrades win their duels")


func test_aura_strengthens_nearby_allies() -> void:
	var w := SimWorld.new(3)
	w.setup_map(40, 20)
	w.spawn("dawn_confessor", 0, Vector2(300, 300))
	var ally := w.spawn("pike_militia", 0, Vector2(340, 300))
	var far := w.spawn("pike_militia", 0, Vector2(900, 300))
	for i in 12:
		w.step()
	assert_gt(ally.damage_factor(), 1.0)
	assert_eq(far.damage_factor(), 1.0)


func test_cleave_and_splash_hit_more_than_one() -> void:
	for attacker in ["charnel_behemoth", "brimstone_bombardier"]:
		var w := SimWorld.new(5)
		w.setup_map(40, 20)
		var a := w.spawn(attacker, 0, Vector2(200, 300))
		var foes: Array = []
		for i in 3:
			foes.append(w.spawn("worker_concord", 1, Vector2(240 + (180 if a.is_ranged() else 0), 290 + i * 10)))
		w.command_attack([a.id], foes[1].id)
		for i in int(8.0 * w.tick_rate):
			w.step()
		var hurt := 0
		for f: SimUnit in foes:
			if not f.alive or f.hp < f.max_hp:
				hurt += 1
		assert_gt(hurt, 1, "%s hit more than its target" % attacker)


func test_ai_upgrades_dwellings_late_and_same_seed_same_game() -> void:
	var sums: Array = []
	for run in 2:
		var w := SkirmishScenario.build_skirmish(6)
		var eco := w.economy
		var ai := EconomyAi.new(1, "hard")
		eco.player(1).hall_level = 4
		_rich(eco, 1)
		_run(w, 240.0, ai)
		var ups := 0
		for b in eco.buildings:
			if b.owner == 1 and b.upgraded:
				ups += 1
		assert_gt(ups, 0, "the AI bought a dwelling upgrade")
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])


func test_tiers_one_and_two_share_a_dwelling() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b := _first_dwelling(eco, 0)
	assert_eq(b.tiers, [1, 2])
	assert_eq(eco.dwelling_of(0, 2), b)
	assert_eq(eco.slot_heads(), [1, 3, 5, 6, 7, 8])
	_rich(eco, 0)
	assert_true(eco.command_train(0, b.id, 2), "hall I opens tiers 1 and 2")
	assert_true(eco.command_train(0, b.id, 1))
	assert_eq(b.queue, [b.unit_of(2), b.unit_of(1)])
	var ids: Array = []
	for u in eco.workers_of(0):
		ids.append(u.id)
	var spot := EconomyAi.find_spot(eco, eco.hall_of(0), float(eco.e["dwelling"]["radius"]))
	assert_true(eco.command_build(ids, 0, "dwelling", 2, spot) == null, "tier 2 is already in the tier 1 dwelling")
	assert_true(eco.command_build(ids, 0, "dwelling", 4, spot) == null, "tiers 3-4 need hall II")
	eco.player(0).hall_level = 2
	var b34 := eco.command_build(ids, 0, "dwelling", 4, spot)
	assert_true(b34 != null and b34.tiers == [3, 4], "asking for tier 4 builds the 3-4 dwelling")
	_run(w, 60.0)
	var n := 0
	for u in w.units:
		if u.owner == 0 and (u.type_id == b.unit_of(1) or u.type_id == b.unit_of(2)):
			n += 1
	assert_eq(n, 2, "both queued units came out")


func test_two_upgrades_in_one_dwelling() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b := _first_dwelling(eco, 0)
	_rich(eco, 0)
	assert_true(eco.command_upgrade_dwelling(0, b.id, 2))
	assert_false(eco.command_upgrade_dwelling(0, b.id, 1), "one upgrade at a time")
	_run(w, eco.dwelling_upgrade_seconds(2) + 0.5)
	assert_true(eco.command_upgrade_dwelling(0, b.id, 1))
	_run(w, eco.dwelling_upgrade_seconds(1) + 0.5)
	var cat := w.catalog
	var line := cat.faction_units(eco.player(0).faction)
	assert_eq(b.unit_of(1), cat.upgrade_of_unit(line[0]))
	assert_eq(b.unit_of(2), cat.upgrade_of_unit(line[1]))
