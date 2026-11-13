extends "res://tests/test_case.gd"
## The storehouse sells worker upgrades: per resource, levels that make every load worth more.


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _rich(eco: Economy, owner: int) -> void:
	for r in ["gold", "wood", "ore", "crystal", "gems", "sulfur", "mercury"]:
		eco.player(owner).res[r] = 5000


func _store(w: SimWorld, owner: int) -> Building:
	var eco := w.economy
	var spot := EconomyAi.find_spot(eco, eco.hall_of(owner), float(eco.e["storehouse"]["radius"]))
	var b := eco.command_build([], owner, "storehouse", 0, spot)
	if b != null:
		b.progress = 1.0
	return b


func test_upgrade_needs_a_finished_storehouse_and_the_hall() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	_rich(eco, 0)
	var b := _store(w, 0)
	assert_true(b != null, "storehouse placed")
	if b == null:
		return
	b.progress = 0.5
	assert_eq(eco.gather_upgrade_lock(0, b.id, "wood"), "Still being built")
	b.progress = 1.0
	assert_eq(eco.gather_upgrade_lock(0, b.id, "wood"), "")
	assert_ne(eco.gather_upgrade_lock(0, b.id, "gold"), "", "gold comes from settlements, no track")
	assert_ne(eco.gather_upgrade_lock(1, b.id, "wood"), "", "not the enemy's")
	# Level 2 needs hall level 2.
	eco.player(0).gather_levels["wood"] = 1
	assert_eq(eco.gather_upgrade_lock(0, b.id, "wood"), "Needs hall level 2")
	eco.player(0).hall_level = 2
	assert_eq(eco.gather_upgrade_lock(0, b.id, "wood"), "")


func test_research_takes_time_and_one_at_a_time() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	_rich(eco, 0)
	var b := _store(w, 0)
	var gold := eco.player(0).amount("gold")
	assert_true(eco.command_gather_upgrade(0, b.id, "wood"))
	assert_eq(eco.player(0).amount("gold"), gold - 100, "level 1 costs 100 gold")
	assert_false(eco.command_gather_upgrade(0, b.id, "ore"), "the storehouse is busy")
	assert_eq(eco.gather_level(0, "wood"), 0)
	_run(w, float(eco.e["worker_upgrades"]["seconds"][0]) + 0.5)
	assert_eq(eco.gather_level(0, "wood"), 1, "done after its seconds")
	assert_eq(b.study, "")
	assert_true(eco.command_gather_upgrade(0, b.id, "ore"), "free again")


func test_rare_track_costs_its_own_resource_from_level_two() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	var rare := ""
	for r in eco.gather_resources(0):
		if not r in ["wood", "ore"]:
			rare = r
			break
	assert_ne(rare, "")
	assert_false(eco.gather_upgrade_cost(0, rare).has(rare), "level 1: common goods only")
	eco.player(0).gather_levels[rare] = 1
	assert_eq(int(eco.gather_upgrade_cost(0, rare).get(rare, 0)), 5)
	eco.player(0).gather_levels[rare] = eco.gather_levels_max()
	assert_true(eco.gather_upgrade_cost(0, rare).is_empty(), "maxed")


func test_upgraded_loads_are_worth_more() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	assert_between(eco.gather_bonus(0, "wood", 3), 0.499, 0.501, "+15%, +30%, +50%")
	_run(w, 5.0)
	# The same run twice, once with wood at level 3: the wood brought in rises by about half.
	var w2 := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	w2.economy.player(0).gather_levels["wood"] = 3
	_run(w2, 5.0)
	_run(w, 115.0)
	_run(w2, 115.0)
	var base := int(eco.player(0).gathered.get("wood", 0))
	var up := int(w2.economy.player(0).gathered.get("wood", 0))
	assert_gt(base, 0, "wood was gathered")
	assert_true(absf(float(up) / float(base) - 1.5) < 0.12, "about +50%%: %d vs %d" % [up, base])


func test_computer_buys_upgrades() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	var ai := EconomyAi.new(1, "normal")
	eco.player(1).hall_level = 2
	_rich(eco, 1)
	var b := _store(w, 1)
	ai._worker_upgrades(eco, eco.hall_of(1))
	assert_ne(b.study, "", "it starts one at once")
	assert_eq(b.study, "wood", "common goods first")


func test_computer_builds_a_storehouse_from_hall_two() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	var ai := EconomyAi.new(1, "normal")
	_rich(eco, 1)
	ai._worker_upgrades(eco, eco.hall_of(1))
	var stores := 0
	for b in eco.buildings:
		if b.owner == 1 and b.kind == "storehouse":
			stores += 1
	assert_eq(stores, 0, "not at hall level 1")
	eco.player(1).hall_level = 2
	ai._worker_upgrades(eco, eco.hall_of(1))
	for b in eco.buildings:
		if b.owner == 1 and b.kind == "storehouse":
			stores += 1
	assert_eq(stores, 1, "a storehouse at home")
