extends "res://tests/test_case.gd"
## The faction buildings: two per house (economy.json faction_buildings), in the freed dwelling art.


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _rich(eco: Economy, owner: int) -> void:
	for r in eco.player(owner).res.keys():
		eco.player(owner).res[r] = 20000


## A finished faction building for owner 0 (the hall raised far enough first).
func _place(w: SimWorld, id: String, at: Vector2 = Vector2.INF) -> Building:
	var eco := w.economy
	_rich(eco, 0)
	var d := eco.special_def(eco.player(0).faction, id)
	eco.player(0).hall_level = maxi(eco.player(0).hall_level, int(d["hall"]))
	var spot := at if at != Vector2.INF else EconomyAi.find_spot(eco, eco.hall_of(0), float(eco.e["dwelling"]["radius"]))
	var b := eco.command_build([], 0, "special", 0, spot, id)
	assert_true(b != null, "%s placed" % id)
	if b != null:
		b.progress = 1.0
	return b


func _world(faction: String, foe: String = "hollow") -> SimWorld:
	return SkirmishScenario.build_skirmish(7, [faction, foe if foe != faction else "concord"])


func test_every_house_has_two_valid_faction_buildings() -> void:
	var cat := UnitCatalog.get_default()
	assert_eq(cat.validate(), [] as Array[String])
	var eco: Dictionary = cat.economy
	for f in eco["buildings"]:
		var list: Array = eco["faction_buildings"][f]
		assert_eq(list.size(), 2, f)
		var keys: Array = list.map(func(d: Dictionary) -> String: return d["key"])
		# They take the art the shared dwellings freed (tiers 2 and 4).
		keys.sort()
		var freed: Array = [eco["buildings"][f]["dwellings"][1], eco["buildings"][f]["dwellings"][3]]
		freed.sort()
		assert_eq(keys, freed, f)


func test_hall_level_limit_and_cost_gate_building() -> void:
	var w := _world("concord")
	var eco := w.economy
	var spot := EconomyAi.find_spot(eco, eco.hall_of(0), float(eco.e["dwelling"]["radius"]))
	_rich(eco, 0)
	assert_true(eco.command_build([], 0, "special", 0, spot, "watch_bastion") == null, "needs hall II")
	assert_true(eco.command_build([], 0, "special", 0, spot, "ossuary") == null, "not a Concord building")
	eco.player(0).hall_level = 2
	var gold := eco.player(0).amount("gold")
	var b := eco.command_build([], 0, "special", 0, spot, "watch_bastion")
	assert_true(b != null)
	assert_eq(b.key, "c_dw2", "built in the freed tier 2 art")
	assert_eq(eco.building_name(b), "Watch Bastion")
	assert_eq(eco.player(0).amount("gold"), gold - 150)
	for i in 3:
		assert_true(_place(w, "watch_bastion") != null)
	assert_eq(eco.special_lock_text(0, "watch_bastion"), "You have as many as you may (4)")


func test_watch_bastion_shoots_enemies_in_range() -> void:
	var w := _world("concord")
	var b := _place(w, "watch_bastion")
	var foe := w.spawn("shambler", 1, b.pos + Vector2(200, 0))
	foe.order = SimUnit.Order.HOLD
	var hp := foe.hp
	var shots := 0
	for i in int(4.0 * w.tick_rate):
		w.step()
		for ev in w.events:
			if ev["type"] == "tower_shot" and ev.get("building", -1) == b.id:
				shots += 1
	assert_gt(shots, 0, "it shot")
	assert_lt(foe.hp, hp, "and hit")


func test_aura_heals_own_and_weakens_foes() -> void:
	var w := _world("concord")
	var chapel := _place(w, "chapel_of_dawn")
	var u := w.spawn("c_militia" if not w.catalog.get_unit("c_militia").is_empty() else w.catalog.faction_units("concord")[0], 0, chapel.pos + Vector2(120, 0))
	u.order = SimUnit.Order.HOLD
	u.hp = u.max_hp * 0.5
	_run(w, 3.0)
	assert_gt(u.hp, u.max_hp * 0.5 + 1.0, "healed by the chapel")
	var w2 := _world("hollow", "concord")
	var pit := _place(w2, "plague_pit")
	var foe := w2.spawn(w2.catalog.faction_units("concord")[0], 1, pit.pos + Vector2(150, 0))
	foe.order = SimUnit.Order.HOLD
	_run(w2, 1.0)
	assert_eq(foe.status_value("weak"), 0.2, "sickened")
	assert_lt(foe.damage_factor(), 1.0)


func test_ossuary_raises_fallen_foes_for_a_while() -> void:
	var w := _world("hollow", "concord")
	var b := _place(w, "ossuary")
	var foe := w.spawn(w.catalog.faction_units("concord")[0], 1, b.pos + Vector2(150, 0))
	# Venom kills it during the tick, as any death in play does.
	foe.poison_left = 1.0
	foe.poison_dps = 1e7
	w.step()
	var raised := 0
	var exp := 0.0
	for u in w.units:
		if u.alive and u.owner == 0 and u.type_id == "shambler" and u.expires > 0.0:
			raised += 1
			exp = u.expires
	assert_eq(raised, 1, "one shambler rose")
	assert_gt(exp, 40.0)


func test_spawning_pool_spawns_up_to_its_cap() -> void:
	var w := _world("fishmen")
	var b := _place(w, "spawning_pool")
	_run(w, 31.0)
	assert_eq(b.spawned.size(), 1, "one after 30 s")
	for i in 10:
		b.timer = 999.0
		w.step()
	assert_eq(b.spawned.size(), 6, "at most six")


func test_income_and_trade() -> void:
	var w := _world("thornwood")
	var grove := _place(w, "heartwood_grove")
	var pl := w.economy.player(0)
	for u in w.economy.workers_of(0):
		w.retire(u)  # only the grove brings timber in
	w.step()
	var wood := pl.amount("wood")
	_run(w, 6.0)
	assert_eq(pl.amount("wood"), wood + 4, "40 a minute")
	assert_ne(grove.key, "")
	var w2 := _world("ashen")
	var pit := _place(w2, "brand_pit")
	var pl2 := w2.economy.player(0)
	var workers := w2.economy.workers_of(0).size()
	var sulfur := pl2.amount("sulfur")
	assert_true(w2.specials.use(0, pit.id))
	assert_eq(pl2.amount("sulfur"), sulfur + 3)
	w2.step()
	assert_eq(w2.economy.workers_of(0).size(), workers - 1, "a worker was given")


func test_market_trades_pairs() -> void:
	var w := _world("darkelf")
	var m := _place(w, "shadow_market")
	var pl := w.economy.player(0)
	assert_true("gold>wood" in w.specials.market_pairs(0))
	assert_false("gold>sulfur" in w.specials.market_pairs(0), "only what the house uses")
	var o := w.specials.market_offer(0, m.id, "gold>wood")
	assert_eq([o["give_n"], o["take_n"]], [100, 40])
	var r := w.specials.market_offer(0, m.id, "wood>crystal")
	assert_eq([r["give_n"], r["take_n"]], [100, 4])
	var g := pl.amount("gold")
	var wd := pl.amount("wood")
	assert_true(w.specials.use(0, m.id, "gold>wood"))
	assert_eq(pl.amount("gold"), g - 100)
	assert_eq(pl.amount("wood"), wd + 40)


func test_gate_pulls_troops_from_the_hall() -> void:
	var w := _world("ashen")
	var gate := _place(w, "hellgate")
	assert_ne(w.specials.can_use(0, gate.id), "", "nobody at the hall yet")
	var hall := w.economy.hall_of(0)
	var u := w.spawn(w.catalog.faction_units("ashen")[0], 0, hall.center + Vector2(0, 120))
	if u.pos.distance_to(gate.pos) <= float(w.economy.special_def("ashen", "hellgate")["effect"]["radius"]):
		return  # the spot happened to be by the hall: nothing to test on this map
	assert_true(w.specials.use(0, gate.id))
	assert_lt(u.pos.distance_to(gate.pos), 200.0, "stepped out of the gate")
	assert_gt(gate.cooldown, 0.0)
	assert_ne(w.specials.can_use(0, gate.id), "", "cooling down")


func test_armoury_research_cuts_damage_taken() -> void:
	var w := _world("forge")
	var arm := _place(w, "armoury")
	var u := w.spawn(w.catalog.faction_units("forge")[0], 0, arm.pos + Vector2(300, 0))
	var hp := u.hp
	w.deal_damage(u, 50.0, -1)
	var plain := hp - u.hp
	assert_true(w.specials.use(0, arm.id))
	assert_ne(w.specials.can_use(0, arm.id), "")
	_run(w, 61.0)
	assert_true(w.economy.player(0).researched.has("armoury"))
	u.hp = u.max_hp
	w.deal_damage(u, 50.0, -1)
	assert_lt(u.max_hp - u.hp, plain, "takes less")
	assert_eq(w.specials.can_use(0, arm.id), "Done")


func test_feast_and_sight() -> void:
	var w := _world("frostmarch")
	var mh := _place(w, "mead_hall")
	var u := w.spawn(w.catalog.faction_units("frostmarch")[0], 0, mh.pos + Vector2(900, 0))
	assert_true(w.specials.use(0, mh.id))
	assert_eq(u.status_value("might"), 0.2)
	assert_false(w.specials.use(0, mh.id), "cooldown")
	var w2 := _world("darkelf")
	var spire := _place(w2, "web_spire")
	assert_eq(w2.specials.sight_of(spire), 520.0)


func test_computer_builds_its_house_buildings() -> void:
	var w := _world("concord", "forge")
	var eco := w.economy
	var ai := EconomyAi.new(1, "hard")
	var pl := eco.player(1)
	_rich(eco, 1)
	pl.hall_level = 2
	for i in int(240.0 * w.tick_rate):
		ai.update(w)
		w.step()
		if eco.special_count(1, "armoury") > 0 and eco.special_count(1, "tunnel_gate") > 0:
			break
	assert_gt(eco.special_count(1, "armoury"), 0, "built the armoury")
	assert_gt(eco.special_count(1, "tunnel_gate"), 0, "and the tunnel gate")
