extends "res://tests/test_case.gd"

var hc: HeroCatalog = HeroCatalog.get_default()


func _world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 40)
	return w


func _step(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func test_hero_data_is_valid() -> void:
	var errors := hc.validate(catalog)
	assert_eq(errors.size(), 0, "\n".join(errors))


## Factions whose hero classes are still being written (the hero thread removes them here).
const HEROES_PENDING := []


func test_four_classes_per_playable_faction() -> void:
	for f in catalog.factions:
		if f == "neutral" or (f in HEROES_PENDING and hc.faction_classes(f).is_empty()):
			continue
		assert_eq(hc.faction_classes(f).size(), 4, f)
		var seen := {}
		for c in hc.faction_classes(f):
			seen[hc.classes[c]["archetype"]] = true
		assert_eq(seen.size(), 4, f + " has four different archetypes")
	var archetypes := {}
	for id in hc.classes:
		archetypes[hc.classes[id]["archetype"]] = true
	assert_eq(archetypes.size(), 6, "all six archetypes are used")


func test_every_signature_casts() -> void:
	for id in hc.classes:
		var w := _world()
		var u := w.heroes.spawn_hero(0, id, Vector2(400, 400))
		u.hero.autocast = [false, false, false, false]
		assert_true(w.heroes.command_learn(0, 0), id)
		var s := hc.skill(hc.kit(id)[0])
		var foe := w.spawn("pike_militia", 1, Vector2(420, 400))
		var friend := w.spawn("pike_militia", 0, Vector2(380, 400))
		friend.hp = friend.max_hp * 0.5
		w.command_hold([foe.id, friend.id])
		var tid := -1
		match String(s["target"]):
			"enemy":
				tid = foe.id
			"ally":
				tid = friend.id
		assert_true(w.heroes.command_cast(0, 0, tid, foe.pos), id + " casts " + String(s["name"]))
		_step(w, 0.5)
		assert_gt(u.hero.cooldowns[0], 0.0, id)


func test_class_abilities() -> void:
	var d := hc.make_def("nightstalker", 1, catalog)
	assert_true("poison" in d["abilities"] and "ranged" in d["abilities"], "archetype and class abilities")
	assert_true("relentless" in hc.make_def("thane", 1, catalog)["abilities"])
	assert_false("relentless" in hc.make_def("reaver", 1, catalog)["abilities"])


func test_stats_grow_with_level() -> void:
	for id in hc.classes:
		var d1 := hc.make_def(id, 1, catalog)
		var d10 := hc.make_def(id, 10, catalog)
		assert_gt(float(d10["hp"]), float(d1["hp"]) + 400.0, id)
		assert_true(float(d10["damage"]) >= float(d1["damage"]), id)
		assert_between(float(d1["hp"]), 300.0, 600.0, id + " is worth a few tier 1 units at level 1")


func test_spawn_and_learn_first_skill() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	assert_true(u.is_hero())
	assert_eq(u.hero.points, 1)
	assert_false(w.heroes.command_learn(0, 3), "ultimate needs level 6")
	assert_true(w.heroes.command_learn(0, 0))
	assert_eq(u.hero.ranks[0], 1)
	assert_false(w.heroes.command_learn(0, 0), "no points left")
	assert_eq(w.catalog.get_unit("hero_knight")["name"], "Knight", "the view can look heroes up")


func test_rank_gates() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "warlord", Vector2(400, 400))
	var h := u.hero
	h.points = 5
	assert_true(w.heroes.command_learn(0, 1))
	assert_false(w.heroes.command_learn(0, 1), "rank 2 opens at level 3")
	w.heroes.add_xp(h, hc.xp_to_next(1) + hc.xp_to_next(2))
	assert_eq(h.level, 3)
	assert_true(w.heroes.command_learn(0, 1))


func test_levels_to_ten_with_full_kit() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "necromancer", Vector2(400, 400), true)
	var h := u.hero
	var hp1 := u.max_hp
	w.heroes.add_xp(h, 100000)
	assert_eq(h.level, 10)
	assert_eq(h.points, 10)
	_step(w, 0.5)  # the AI spends points at once
	assert_eq(h.points, 0)
	assert_eq(h.ranks, [3, 3, 3, 1] as Array[int])
	assert_gt(u.max_hp, hp1)
	assert_gt(h.max_mana, 100.0)


func test_xp_curve_total() -> void:
	var total := 0
	for l in range(1, 10):
		total += hc.xp_to_next(l)
	assert_eq(total, 5400)


func test_human_auto_learn_waits() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "oracle", Vector2(400, 400))
	_step(w, 2.0)
	assert_eq(u.hero.points, 1, "the player gets a moment to choose")
	_step(w, 10.0)
	assert_eq(u.hero.points, 0)
	assert_eq(u.hero.ranks[0], 1, "auto-learn follows the class order")


func test_cast_damage_and_cooldown() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "warlock", Vector2(400, 400))
	w.heroes.command_learn(0, 0)  # Cinderfall
	var t := w.spawn("pike_militia", 1, Vector2(600, 400))
	w.command_hold([t.id])
	var mana := u.hero.mana
	assert_true(w.heroes.command_cast(0, 0, t.id))
	assert_lt(t.hp, t.max_hp, "Cinderfall hit")
	assert_lt(u.hero.mana, mana)
	assert_gt(u.hero.cooldowns[0], 0.0)
	assert_eq(w.heroes.cast_problem(u.hero, 0), "cooldown")
	assert_false(w.heroes.command_cast(0, 0, t.id))


func test_cast_walks_into_range() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "templar", Vector2(300, 400))
	u.hero.autocast = [false, false, false, false]
	w.heroes.command_learn(0, 0)  # Judgement, melee range
	var t := w.spawn("pike_militia", 1, Vector2(900, 400))
	w.command_hold([t.id])
	assert_true(w.heroes.command_cast(0, 0, t.id))
	assert_eq(u.order, SimUnit.Order.CAST)
	_step(w, 15.0)
	assert_gt(u.hero.cooldowns[0] + float(t.max_hp - t.hp), 0.0)
	assert_true(t.hp < t.max_hp or not t.alive, "the hero walked over and struck")


func test_stun_stops_a_unit() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	u.hero.ranks[1] = 1  # Shield Bash
	var t := w.spawn("pike_militia", 1, Vector2(430, 400))
	assert_true(w.heroes.command_cast(0, 1, t.id))
	assert_true(t.stunned())
	var p := t.pos
	w.command_move([t.id], Vector2(900, 400))
	_step(w, 1.0)
	assert_true(t.pos.distance_to(p) < 20.0, "a stunned unit does not walk")
	_step(w, 2.0)
	assert_false(t.stunned())


func test_aura_and_ward() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "gravewarden", Vector2(400, 400))
	u.hero.ranks[2] = 3  # Defend Aura
	var friend := w.spawn("shambler", 0, Vector2(450, 400))
	var far := w.spawn("shambler", 0, Vector2(1400, 400))
	_step(w, 0.2)
	assert_gt(friend.status_value("ward"), 0.1)
	assert_eq(far.status_value("ward"), 0.0)
	assert_lt(friend.taken_factor(), 1.0)


func test_summons_fade() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "tormentor", Vector2(400, 400))
	u.hero.autocast = [false, false, false, false]
	u.hero.ranks[1] = 1  # Summon: 2 cinderlings for 40 s
	assert_true(w.heroes.command_cast(0, 1))
	_step(w, 0.1)
	assert_eq(w.count_alive(0), 3)
	_step(w, 41.0)
	assert_eq(w.count_alive(0), 1)


func test_kills_near_hero_give_xp() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "warlord", Vector2(400, 400))
	var a := w.spawn("cinderling", 0, Vector2(460, 400))
	var t := w.spawn("pike_militia", 1, Vector2(500, 400))
	t.hp = 1.0
	w.command_attack([a.id], t.id)
	_step(w, 3.0)
	assert_false(t.alive)
	assert_eq(u.hero.xp, 20, "an ally's kill near the hero counts")


func test_hero_revives_at_hall_for_gold() -> void:
	var w := SkirmishScenario.build_skirmish(5, ["concord", "ashen"])
	var hall := w.economy.hall_of(0)
	var u := w.heroes.spawn_hero(0, "knight", hall.center + Vector2(0, 80))
	var h := u.hero
	w.economy.player(0).res["gold"] = 500
	w.deal_damage(u, 99999.0, -1)
	_step(w, 0.1)
	assert_eq(h.unit_id, -1)
	assert_eq(h.deaths, 1)
	_step(w, 17.0)
	assert_true(w.heroes.hero_unit(0) == null, "still waiting: 15 s + 3 s per level")
	_step(w, 1.5)
	assert_true(w.heroes.hero_unit(0) != null, "revived")
	assert_eq(int(w.economy.player(0).spent.get("gold", 0)), 50, "revival costs 50 gold per level")


func test_autocast_fires_in_a_fight() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "ranger", Vector2(400, 400), true)
	_step(w, 0.2)  # learns Pinning Shafts
	var t := w.spawn("pike_militia", 1, Vector2(600, 400))
	w.command_hold([t.id])
	_step(w, 1.0)
	assert_gt(u.hero.cooldowns[0], 0.0, "autocast used the skill")
	assert_gt(t.status_value("slow"), 0.0)


func test_heroes_are_deterministic() -> void:
	var sums: Array = []
	for run in 2:
		var w := _world(42)
		w.heroes.spawn_hero(0, "blightcaller", Vector2(300, 400), true)
		w.heroes.spawn_hero(1, "barrow_lord", Vector2(900, 400), true)
		var ids0: Array = []
		var ids1: Array = []
		for i in 8:
			ids0.append(w.spawn("shambler", 0, Vector2(330, 300 + i * 25)).id)
			ids1.append(w.spawn("cinderling", 1, Vector2(870, 300 + i * 25)).id)
		ids0.append(w.heroes.hero_unit(0).id)
		ids1.append(w.heroes.hero_unit(1).id)
		w.heroes.add_xp(w.heroes.hero_of(0), 3000)
		w.heroes.add_xp(w.heroes.hero_of(1), 3000)
		w.command_attack_move(ids0, Vector2(900, 400))
		w.command_attack_move(ids1, Vector2(300, 400))
		_step(w, 30.0)
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])
