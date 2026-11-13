extends "res://tests/test_case.gd"
## Combat depth: damage types against three defences, building damage, and damage over time
## (burn, bleed, frost).


func _world() -> SimWorld:
	var w := SimWorld.new(7)
	w.setup_map(60, 30)
	return w


func _first_hit(w: SimWorld, attacker: int) -> float:
	for i in 120:
		w.step()
		for e in w.events:
			if e["type"] == "hit" and e["attacker"] == attacker:
				return float(e["damage"])
	return 0.0


func _target_building(w: SimWorld, hp: float = 5000.0) -> SimUnit:
	return w.add_structure("building", 1, Vector2(800, 480), {"id": "building", "name": "Target", "role": "structure",
		"faction": "", "hp": hp, "armor_pct": 0.35, "speed": 0.0, "damage": 0.0, "attack_interval": 1.0, "range": 0.0,
		"sight": 0.0, "radius": 40.0, "abilities": [], "cost": {}, "sprite": ""})


func test_units_fit_their_type() -> void:
	var c := UnitCatalog.get_default()
	assert_eq(UnitCatalog.damage_type_of(c.get_unit("lancer")), "melee")
	assert_eq(UnitCatalog.damage_type_of(c.get_unit("longbowman")), "ranged")
	assert_eq(UnitCatalog.damage_type_of(c.get_unit("ash_witch")), "magic", "witches cast")
	assert_eq(UnitCatalog.damage_type_of(c.get_unit("wailing_shade")), "magic", "spirits strike with magic")
	var sw: Dictionary = c.get_unit("shieldwarden")["defense"]
	assert_gt(float(sw["ranged"]), float(sw["melee"]), "a shield stops arrows best")
	var witch: Dictionary = c.get_unit("ash_witch")["defense"]
	assert_gt(float(witch["magic"]), float(witch["melee"]) + 0.3, "a caster resists spells, not steel")
	var shade: Dictionary = c.get_unit("wailing_shade")["defense"]
	assert_gt(float(shade["melee"]), float(shade["magic"]) + 0.3, "steel passes through a spirit")
	var bones: Dictionary = c.get_unit("shambler")["defense"]
	assert_gt(float(bones["ranged"]), float(bones["magic"]), "arrows pass through bone, holy light does not")
	# Siege: engines, colossi and giants tear buildings down; archers and flyers barely scratch them.
	for id in ["bastion_colossus", "thunder_bombard", "molten_engine", "cairn_giant", "rootbound_ancient"]:
		var d := c.get_unit(id)
		assert_gt(float(d["building_damage"]), float(d["damage"]) * 2.0, "%s is a wrecker" % id)
	for id in ["longbowman", "sunhawk_rider", "lancer"]:
		var d := c.get_unit(id)
		assert_lt(float(d["building_damage"]), float(d["damage"]) * 0.7, "%s is poor against walls" % id)


func test_variety_survives() -> void:
	## Every faction keeps several damage types, and the defences are not all alike.
	var c := UnitCatalog.get_default()
	var profiles := {}
	for f in ["concord", "hollow", "ashen", "thornwood", "forge", "fishmen", "darkelf", "frostmarch"]:
		var types := {}
		for id in c.faction_units(f):
			var d := c.get_unit(id)
			types[UnitCatalog.damage_type_of(d)] = true
			var df: Dictionary = d["defense"]
			profiles["%.2f/%.2f/%.2f" % [float(df["melee"]) - float(d["armor_pct"]),
				float(df["ranged"]) - float(d["armor_pct"]), float(df["magic"]) - float(d["armor_pct"])]] = true
		assert_gt(types.size(), 1.0, "%s fields more than one damage type" % f)
	assert_gt(profiles.size(), 15.0, "many different defence shapes")


func test_defense_matches_the_damage_type() -> void:
	var w := _world()
	var t := w.spawn("shieldwarden", 1, Vector2(800, 480))
	for dtype in ["melee", "ranged", "magic"]:
		var hp := t.hp
		w.deal_damage(t, 100.0, -1, dtype)
		assert_between(hp - t.hp, 100.0 * (1.0 - t.defense(dtype)) - 0.5, 100.0 * (1.0 - t.defense(dtype)) + 0.5,
			"%s meets the %s defence" % [dtype, dtype])


func test_shield_wall_stops_arrows_not_spells() -> void:
	var hits := {}
	for shooter in ["longbowman", "ash_witch"]:
		var w := _world()
		var s := w.spawn(shooter, 0, Vector2(600, 480))
		var t := w.spawn("shieldwarden", 1, Vector2(760, 480))
		w.command_hold([t.id])
		w.command_attack([s.id], t.id)
		var hit := _first_hit(w, s.id)
		var raw := float(s.def["damage"]) * w.catalog.matchup(s.role(), t.role())
		hits[shooter] = hit / (raw * (1.0 - t.defense(s.damage_type())))
	assert_lt(float(hits["longbowman"]), 0.6, "the shield halves an arrow")
	assert_gt(float(hits["ash_witch"]), 0.85, "a spell goes past the shield")


func test_siege_units_wreck_buildings() -> void:
	var dealt := {}
	for id in ["bastion_colossus", "longbowman"]:
		var w := _world()
		var st := _target_building(w)
		var u := w.spawn(id, 0, Vector2(700, 480))
		w.command_attack([u.id], st.id)
		var hit := _first_hit(w, u.id)
		var want := float(u.def["building_damage"]) * (1.0 - 0.35)
		assert_between(hit, want * 0.85, want * 1.15, "%s hits a building with its building damage" % id)
		dealt[id] = hit / float(u.def["damage"])
	assert_gt(float(dealt["bastion_colossus"]), float(dealt["longbowman"]) * 4.0, "a colossus is the wrecker")


func test_burn_sets_a_building_alight() -> void:
	var w := _world()
	var st := _target_building(w)
	var u := w.spawn("brimstone_hurler", 0, Vector2(650, 480))
	w.command_attack([u.id], st.id)
	_first_hit(w, u.id)
	for i in 10:
		w.step()  # the missile lands
	assert_true(st.dots.has("burn"), "the building burns")
	u.alive = false
	var hp := st.hp
	for i in int(w.tick_rate * 4):
		w.step()
	assert_lt(st.hp, hp - 1.0, "fire keeps eating the building")
	assert_false(st.dots.has("burn"), "and goes out")


func test_bleed_spares_the_bloodless() -> void:
	var w := _world()
	var a := w.spawn("road_cutthroat", 0, Vector2(600, 400))
	var undead := w.spawn("shambler", 1, Vector2(620, 400))
	var b := w.spawn("road_cutthroat", 0, Vector2(600, 600))
	var man := w.spawn("pike_militia", 1, Vector2(620, 600))
	w.command_hold([undead.id, man.id])
	w.command_attack([a.id], undead.id)
	w.command_attack([b.id], man.id)
	_first_hit(w, a.id)
	_first_hit(w, b.id)
	assert_true(man.dots.has("bleed"), "a man bleeds")
	assert_false(undead.dots.has("bleed"), "the dead don't")
	b.alive = false
	man.cooldown = 99.0
	var hp := man.hp
	for i in int(w.tick_rate * 2):
		w.step()
	assert_lt(man.hp, hp, "the wound keeps bleeding")


func test_frost_slows() -> void:
	var w := _world()
	var s := w.spawn("frost_shaman", 0, Vector2(600, 480))
	var t := w.spawn("pike_militia", 1, Vector2(760, 480))
	w.command_hold([t.id])
	w.command_attack([s.id], t.id)
	_first_hit(w, s.id)
	for i in 10:
		w.step()
	assert_gt(t.status_value("slow"), 0.2, "frost slows the target")
	assert_lt(t.speed_factor(), 0.8)


func test_mystic_heroes_cast_magic() -> void:
	var hc := HeroCatalog.get_default()
	var c := UnitCatalog.get_default()
	assert_eq(UnitCatalog.damage_type_of(hc.make_def("warlock", 1, c)), "magic")
	assert_eq(UnitCatalog.damage_type_of(hc.make_def("knight", 1, c)), "melee")
