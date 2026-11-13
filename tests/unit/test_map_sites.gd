extends "res://tests/test_case.gd"
## Lairs, shrines and merchants: places on the skirmish map where heroes find loot, healing and gear.

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_computer_heroes_clear_lairs"]


func _bare(seed_value: int = 3) -> SimWorld:
	var w := SkirmishScenario.build_skirmish(seed_value, ["concord", "hollow"])
	for u in w.units:
		u.alive = false
	w.sites.all.clear()  # only the sites a test places
	w.step()
	return w


func _hero(w: SimWorld, owner: int, p: Vector2) -> SimUnit:
	var cls: String = HeroCatalog.get_default().faction_classes(w.economy.player(owner).faction)[0]
	return w.heroes.spawn_hero(owner, cls, p)


func test_data_is_valid() -> void:
	assert_eq(MapSites.validate(), [] as Array[String])


func test_skirmish_places_mirrored_sites() -> void:
	# The map generator (MapGen) places the sites its template names, mirrored for every player.
	for id: String in MapGen.template_ids(2):
		var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"], id)
		var lairs := w.sites.of_kind("lair")
		assert_gt(lairs.size(), 3, "%s: lairs on both sides" % id)
		assert_eq(lairs.size(), w.map_info["lairs"].size())
		assert_eq(w.sites.of_kind("shrine").size(), w.map_info["shrines"].size())
		assert_eq(w.sites.of_kind("merchant").size(), w.map_info["merchants"].size())
		for s in w.sites.all:
			assert_false(w.nav.is_blocked(s["pos"]), "%s: %s on open ground" % [id, s["kind"]])
		for s in lairs:
			assert_gt(w.sites.guards_alive(s), 1, "%s: lair guarded" % id)
		var tiers := {}
		for s in lairs:
			tiers[int(s["tier"])] = int(tiers.get(int(s["tier"]), 0)) + 1
		assert_true(tiers.has(1) and tiers.has(3), "%s: weak dens and a strong hoard" % id)
	var w4 := SkirmishScenario.build_skirmish(7, ["concord", "hollow", "ashen", "forge"])
	assert_gt(w4.sites.of_kind("lair").size(), 8, "four-player maps get sites too")


func test_guards_stay_home() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var s: Dictionary = w.sites.of_kind("lair")[0]
	for i in int(30 * w.tick_rate):
		w.step()
	for id in s["guards"]:
		var u := w.get_unit(int(id))
		assert_lt(u.pos.distance_to(s["pos"]), 160.0, "guards keep to their lair")


func test_guards_fight_back_against_archers_out_of_reach() -> void:
	var w := _bare()
	var s := w.sites.add_lair(Vector2(900, 900), 1, ["pike_militia", "pike_militia"])
	var g := w.get_unit(int(s["guards"][0]))
	var mate := w.get_unit(int(s["guards"][1]))
	var leash := g.guard_radius * 1.5
	var archer := w.spawn("longbowman", 0, g.pos + Vector2(leash + 25.0, 0))
	archer.hp = 40.0
	w.command_attack([archer.id], g.id)
	var mate_went := false
	for i in int(15 * w.tick_rate):
		w.step()
		mate_went = mate_went or mate.target_id == archer.id
		if not archer.alive:
			break
	assert_false(archer.alive, "the guard chases down the archer shooting it from beyond its leash")
	assert_true(mate_went, "the other guards of the lair join in")
	for i in int(15 * w.tick_rate):
		w.step()
	for id in s["guards"]:
		var u := w.get_unit(int(id))
		if u != null:
			assert_lt(u.pos.distance_to(s["pos"]), 160.0, "and then go back to the lair")


func test_cleared_lair_pays_out() -> void:
	var w := _bare()
	var s := w.sites.add_lair(Vector2(900, 900), 2, ["pike_militia"])
	var h := _hero(w, 0, Vector2(960, 900))
	var hs := w.heroes.hero_of(0)
	var gold := w.economy.player(0).amount("gold")
	var marks := hs.marks
	var ground := w.heroes.gear.ground.size()
	w.get_unit(int(s["guards"][0])).hp = 1.0
	w.command_attack([h.id], int(s["guards"][0]))
	var cleared := false
	for i in int(10 * w.tick_rate):
		w.step()
		for e in w.events:
			cleared = cleared or e["type"] == "lair_cleared"
		if cleared:
			break
	assert_true(cleared and s["cleared"], "the lair is cleared")
	assert_eq(s["by"], 0)
	var t: Dictionary = w.sites.d["lair"]["tiers"]["2"]
	assert_gt(hs.marks, marks + int(t["marks"]) - 1, "the hoard pays the hero in marks")
	assert_lt(w.economy.player(0).amount("gold"), gold + 20, "and not the army in gold")
	assert_true(hs.level > 1 or hs.xp > 0, "the hero gains experience")
	assert_eq(w.heroes.gear.ground.size(), ground + int(t["items"]) + int(t["potions"]), "loot on the ground")


func test_shrine_heals_and_blesses_then_rests() -> void:
	var w := _bare()
	var s := w.sites.add_shrine(Vector2(900, 900))
	var h := _hero(w, 0, Vector2(910, 900))
	h.hp = h.max_hp * 0.3
	for i in 20:
		w.step()
	assert_gt(h.hp, h.max_hp * 0.85, "healed")
	assert_gt(h.status_value("might"), 0.0, "blessed")
	assert_gt(s["ready_in"], 100.0, "and then the shrine rests")
	h.hp = h.max_hp * 0.3
	for i in 20:
		w.step()
	assert_lt(h.hp, h.max_hp * 0.5, "a resting shrine does nothing")


func test_merchant_sells_to_a_hero_standing_by() -> void:
	var w := _bare()
	var s := w.sites.add_merchant(Vector2(900, 900))
	assert_eq(s["stock"].size(), 3)
	var h := _hero(w, 0, Vector2(1400, 900))
	var hs := w.heroes.hero_of(0)
	assert_eq(w.sites.buy_problem(0, s["id"], "health"), "Your hero must stand at the merchant")
	h.pos = Vector2(930, 900)
	var pl := w.economy.player(0)
	assert_eq(w.sites.buy_problem(0, s["id"], "health"), "Not enough marks", "army gold does not buy hero gear")
	var army_gold := pl.amount("gold")
	w.heroes.earn_marks(0, 2000)
	var marks := hs.marks
	var potions := int(hs.potions["health"])
	assert_true(w.sites.command_buy(0, s["id"], "health"))
	assert_eq(int(hs.potions["health"]), potions + 1)
	assert_eq(hs.marks, marks - w.sites.potion_price("health"))
	var item: Dictionary = s["stock"][0]
	var price := w.sites.item_price(item)
	marks = hs.marks
	assert_true(w.sites.command_buy(0, s["id"], 0), "buys an item")
	assert_eq(hs.marks, marks - price)
	assert_eq(pl.amount("gold"), army_gold, "the army's gold is untouched")
	assert_eq(s["stock"].size(), 2)
	var owned := hs.bag.has(item) or hs.worn.values().has(item)
	assert_true(owned, "the hero has it")
	w.heroes.spend_marks(0, hs.marks)
	assert_eq(w.sites.buy_problem(0, s["id"], 0), "Not enough marks")


func test_merchant_restocks() -> void:
	var w := _bare()
	var s := w.sites.add_merchant(Vector2(900, 900))
	s["stock"].clear()
	s["restock_in"] = 0.2
	for i in 20:
		w.step()
	assert_eq(s["stock"].size(), 3)


func test_computer_heroes_clear_lairs() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["concord", "hollow"])
	var ais := [EconomyAi.new(0, "normal"), EconomyAi.new(1, "normal")]
	for o in 2:
		var cls: String = HeroCatalog.get_default().faction_classes(w.economy.player(o).faction)[0]
		w.heroes.spawn_hero(o, cls, w.economy.hall_of(o).center + Vector2(0, 70), true)
	var cleared := {}
	for i in int(300 * w.tick_rate):
		for a in ais:
			a.update(w)
		w.step()
		for e in w.events:
			if e["type"] == "lair_cleared":
				cleared[e["owner"]] = true
	assert_true(cleared.has(0) and cleared.has(1), "both computer players clear a lair: %s" % [cleared])


func test_heroes_earn_marks_from_kills_near_them() -> void:
	var w := _bare()
	var h := _hero(w, 0, Vector2(900, 900))
	var hs := w.heroes.hero_of(0)
	var foe := w.spawn("pike_militia", 1, Vector2(930, 900))
	foe.hp = 1.0
	w.command_attack([h.id], foe.id)
	for i in int(5 * w.tick_rate):
		w.step()
		if not foe.alive:
			break
	var coin: Dictionary = w.heroes.r["coin"]
	assert_eq(hs.marks, int(coin["per_kill_tier"]) * int(foe.def["tier"]), "a kill pays marks by tier")
