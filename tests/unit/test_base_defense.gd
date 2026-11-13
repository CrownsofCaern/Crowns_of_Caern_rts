extends "res://tests/test_case.gd"
## Halls shoot arrows at enemies near them, harder with every hall level (BaseDefense).


## One hall for player 0 in the middle of an open map; player 1 owns nothing.
func _world(seed_value: int = 3) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 40)
	w.economy.add_player(0, "concord")
	w.economy.add_player(1, "hollow")
	var s := w.economy.add_sector(Vector2(960, 640), "village")
	s.owner = 0
	s.home_of = 0
	return w


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


## Damage the hall deals in `seconds` to a row of enemies that stand still in range.
func _damage_dealt(level: int, seconds: float) -> float:
	var w := _world()
	w.economy.player(0).hall_level = level
	var ids: Array = []
	for i in 6:
		var u := w.spawn("pike_militia", 1, Vector2(960 + 120, 560 + i * 30))
		u.max_hp = 100000.0
		u.hp = u.max_hp
		ids.append(u.id)
	w.command_hold(ids)
	_run(w, seconds)
	var dealt := 0.0
	for id in ids:
		var u := w.get_unit(id)
		dealt += u.max_hp - u.hp
	return dealt


func test_every_hall_level_has_arrows() -> void:
	var eco := SimWorld.new(1).economy
	for lv: Dictionary in eco.e["hall_levels"]:
		var a: Dictionary = lv.get("arrows", {})
		assert_gt(float(a.get("count", 0)), 0.0, "level %s has arrows" % lv["level"])
		assert_gt(float(a.get("damage", 0)), 0.0)
		assert_gt(float(a.get("interval", 0)), 0.0)
	assert_gt(float(eco.e["hall_defense"]["range"]), float(eco.e["capture_radius"]),
		"the hall reaches past its capture ring")


func test_hall_shoots_enemies_in_range() -> void:
	var w := _world()
	var foe := w.spawn("pike_militia", 1, Vector2(960 + 150, 640))
	w.command_hold([foe.id])
	var shots := 0
	for i in 5 * w.tick_rate:
		w.step()
		for e in w.events:
			if e["type"] == "tower_shot":
				shots += 1
	assert_gt(shots, 1, "volleys fired")
	assert_lt(foe.hp, foe.max_hp, "the arrows hit")
	for pr in w.projectiles:
		assert_eq(int(pr["attacker"]), -1, "no unit fired it")
		assert_gt(float(pr.get("lift", 0.0)), 1.0, "shot from the roof")


func test_hall_ignores_friends_and_far_enemies() -> void:
	var w := _world()
	var friend := w.spawn("pike_militia", 0, Vector2(960 + 80, 640))
	var far := w.spawn("pike_militia", 1, Vector2(960 + 600, 640))
	w.command_hold([friend.id, far.id])
	_run(w, 6.0)
	assert_eq(friend.hp, friend.max_hp)
	assert_eq(far.hp, far.max_hp)


func test_taken_hall_falls_silent() -> void:
	var w := _world()
	w.economy.sectors[0].owner = 1  # the enemy holds the home now
	var foe := w.spawn("pike_militia", 0, Vector2(960 + 120, 640))
	w.command_hold([foe.id])
	_run(w, 6.0)
	assert_eq(foe.hp, foe.max_hp, "a captured hall does not shoot for its taker or old owner")


func test_neutrals_are_shot_only_when_they_attack() -> void:
	var w := _world()
	var calm := w.spawn("militia", Economy.NEUTRAL, Vector2(960 + 120, 640))
	w.command_hold([calm.id])
	_run(w, 4.0)
	assert_eq(calm.hp, calm.max_hp, "a militiaman minding its own business is left alone")


func test_higher_hall_shoots_harder() -> void:
	var dealt := []
	for lv in [1, 2, 3, 4]:
		dealt.append(_damage_dealt(lv, 20.0))
	for i in 3:
		assert_gt(dealt[i + 1], dealt[i] * 1.2, "level %d beats level %d: %s" % [i + 2, i + 1, str(dealt)])
	assert_gt(dealt[3], dealt[0] * 3.0, "a full hall is several times a fresh one: %s" % str(dealt))


func test_soldiers_are_shot_before_workers() -> void:
	var w := _world()
	w.economy.player(0).hall_level = 1  # 2 arrows a volley
	var worker := w.spawn(w.catalog.worker_type("hollow"), 1, Vector2(960 + 60, 640))
	var soldier := w.spawn("pike_militia", 1, Vector2(960 + 200, 640))
	w.command_hold([worker.id, soldier.id])
	_run(w, 3.0)
	assert_lt(soldier.hp, soldier.max_hp)
	assert_eq(worker.hp, worker.max_hp, "the closer worker waits its turn")


func test_hall_breaks_a_small_early_push() -> void:
	# Six first-tier soldiers march on an empty level-1 hall to take it: the arrows
	# should cut down most of them before the capture completes.
	var w := _world(7)
	var ids: Array = []
	for i in 6:
		ids.append(w.spawn("pike_militia", 1, Vector2(960 + 500, 600 + i * 20)).id)
	w.command_move(ids, Vector2(960, 640))
	_run(w, 90.0)
	assert_lt(float(w.count_alive(1)), 3.0, "the push melts")
	assert_eq(w.economy.sectors[0].owner, 0, "the hall holds")


func test_same_seed_same_volleys() -> void:
	var a := _damage_dealt(2, 12.0)
	var b := _damage_dealt(2, 12.0)
	assert_eq(a, b)


# --- The capital is torn down, not taken -------------------------------------------------

func _hall(w: SimWorld) -> SimUnit:
	return w.defense.hall_structure(w.economy.sectors[0])


func test_hall_has_hit_points_by_level() -> void:
	var w := _world()
	w.step()
	var st := _hall(w)
	assert_true(st != null, "the capital gets hit points")
	assert_true(st.is_structure())
	var hp: Array = w.economy.e["hall_defense"]["hp"]
	assert_eq(hp.size(), w.economy.e["hall_levels"].size(), "one value per hall level")
	assert_eq(st.max_hp, float(hp[0]))
	assert_between(st.max_hp, 1500.0, 3000.0, "a first hall holds, but falls to a real push (about 60% under the old 6000)")
	for i in range(1, hp.size()):
		assert_gt(float(hp[i]), float(hp[i - 1]) * 1.3, "each hall level is clearly stronger")
	st.hp = st.max_hp * 0.5
	w.economy.player(0).hall_level = 2
	w.step()
	assert_eq(st.max_hp, float(hp[1]), "a higher hall has stronger walls")
	assert_between(st.hp, st.max_hp * 0.5 - 1.0, st.max_hp * 0.5 + 1.0, "the same share of damage carries over")


func test_capital_cannot_be_captured() -> void:
	var w := _world()
	var ids: Array = []
	for i in 8:
		var u := w.spawn("pike_militia", 1, Vector2(960 + 40 + (i % 4) * 20, 600 + (i / 4) * 40))
		u.max_hp = 100000.0
		u.hp = u.max_hp
		ids.append(u.id)
	w.command_hold(ids)
	_run(w, 120.0)
	var s: Sector = w.economy.sectors[0]
	assert_eq(s.owner, 0, "still theirs after two minutes")
	assert_eq(s.capture, 0.0, "no capture bar on a capital")


func test_other_settlements_still_captured() -> void:
	var w := _world()
	var t := w.economy.add_sector(Vector2(300, 300), "village")
	t.owner = 0
	var u := w.spawn("pike_militia", 1, Vector2(310, 300))
	w.command_hold([u.id])
	_run(w, 90.0)
	assert_eq(t.owner, 1, "a plain village is still taken")


func test_soldiers_on_attack_move_tear_the_hall_down() -> void:
	var w := _world()
	w.step()
	var st := _hall(w)
	st.hp = 300.0  # a nearly fallen hall, so the test stays short
	var ids: Array = []
	for i in 6:
		var u := w.spawn("pike_militia", 1, Vector2(1400, 560 + i * 30))
		u.max_hp = 100000.0
		u.hp = u.max_hp
		ids.append(u.id)
	w.command_attack_move(ids, Vector2(960, 640))
	var razed := false
	for i in 60 * w.tick_rate:
		w.step()
		for e in w.events:
			if e["type"] == "hall_destroyed":
				razed = true
				assert_eq(int(e["owner"]), 0)
				assert_eq(int(e["by"]), 1, "razed by player 1")
		if razed:
			break
	assert_true(razed, "the hall falls to an attack-move")


func test_fallen_hall_means_defeat() -> void:
	var w := _world()
	var village := w.economy.add_sector(Vector2(300, 300), "village")
	village.owner = 0
	var mine := w.spawn("pike_militia", 0, Vector2(400, 400))
	var foe := w.spawn("pike_militia", 1, Vector2(1500, 300))
	w.step()
	assert_eq(w.economy.winner(), 0, "only player 0 holds land so far")
	var t := w.economy.add_sector(Vector2(1500, 300), "village")
	t.owner = 1
	assert_eq(w.economy.winner(), -1)
	var st := _hall(w)
	w.deal_damage(st, st.max_hp * 10.0, foe.id)
	w.step()
	var s: Sector = w.economy.sectors[0]
	assert_true(w.economy.player(0).defeated, "the house is out")
	assert_eq(s.owner, -1, "the ruin is left empty")
	assert_eq(s.home_of, -1, "and is no longer a capital")
	assert_eq(village.owner, -1, "its other settlements fall empty too")
	assert_true(w.get_unit(mine.id) == null, "its people are gone")
	assert_true(w.get_unit(foe.id) != null)
	assert_eq(w.economy.winner(), 1, "the last house standing wins")


func test_hall_mends_when_left_alone() -> void:
	var w := _world()
	w.step()
	var st := _hall(w)
	st.hp = st.max_hp - 500.0
	st.since_hit = 0.0
	_run(w, 5.0)
	assert_eq(st.hp, st.max_hp - 500.0, "no mending right after a hit")
	_run(w, 30.0)
	assert_gt(st.hp, st.max_hp - 500.0, "mends once left alone")


# --- Unit buildings can be torn down ------------------------------------------------

## A finished dwelling of this tier for player 0 beside its hall.
func _dwelling(w: SimWorld, tier: int, p: Vector2 = Vector2(960, 900)) -> Building:
	var b := w.economy._make_building(0, "dwelling", tier, p)
	b.progress = 1.0
	w.step()
	return b


func test_unit_buildings_get_hit_points_by_tier() -> void:
	var w := _world()
	w.economy.player(0).hall_level = 4
	var low := _dwelling(w, 1, Vector2(700, 900))
	var high := _dwelling(w, 7, Vector2(1300, 900))
	var a := w.defense.building_structure(low)
	var b := w.defense.building_structure(high)
	assert_true(a != null and b != null, "dwellings carry hit points")
	assert_true(a.is_structure())
	assert_eq(a.max_hp, a.hp)
	assert_gt(b.max_hp, a.max_hp, "a higher tier dwelling is sturdier")
	assert_lt(b.max_hp, _hall(w).max_hp, "and still well below the hall")
	a.hp = a.max_hp * 0.5
	low.upgraded = true
	w.step()
	assert_gt(a.max_hp, float(w.economy.e["building_defense"]["hp_base"]), "an upgraded dwelling is sturdier")
	assert_between(a.hp, a.max_hp * 0.5 - 1.0, a.max_hp * 0.5 + 1.0, "the same share of damage carries over")


func test_storehouses_and_walls_are_not_unit_buildings() -> void:
	var b := Building.new()
	b.kind = "storehouse"
	assert_false(BaseDefense.destroyable(b))
	b.kind = "wall"
	assert_false(BaseDefense.destroyable(b))
	b.kind = "special"
	assert_true(BaseDefense.destroyable(b))


func test_site_hit_points_grow_with_the_work() -> void:
	var w := _world()
	var b := w.economy._make_building(0, "dwelling", 1, Vector2(960, 900))
	b.progress = 0.0
	w.step()
	var st := w.defense.building_structure(b)
	assert_lt(st.hp, st.max_hp * 0.2, "a fresh site is weak")
	b.progress = 1.0
	w.step()
	assert_between(st.hp, st.max_hp - 1.0, st.max_hp, "a finished one is whole")


func test_soldiers_on_attack_move_tear_a_dwelling_down() -> void:
	var w := _world()
	var p := Vector2(400, 300)
	var b := _dwelling(w, 1, p)
	var cells := b.cells.duplicate()
	assert_false(cells.is_empty())
	b.queue.append(b.unit_type)
	w.defense.building_structure(b).hp = 200.0  # nearly down, so the test stays short
	var ids: Array = []
	for i in 6:
		var u := w.spawn("pike_militia", 1, Vector2(150, 200 + i * 30))
		u.max_hp = 100000.0
		u.hp = u.max_hp
		ids.append(u.id)
	w.command_attack_move(ids, p)
	var razed := false
	for i in 40 * w.tick_rate:
		w.step()
		for e in w.events:
			if e["type"] == "building_destroyed":
				razed = true
				assert_eq(int(e["owner"]), 0)
				assert_eq(int(e["by"]), 1, "torn down by player 1")
		if razed:
			break
	assert_true(razed, "the dwelling falls to an attack-move")
	assert_true(w.economy.building(b.id) == null, "and is gone")
	for c: Vector2i in cells:
		assert_false(w.nav.is_blocked_cell(c), "its ground is open again")
	assert_eq(w.economy.sectors[0].owner, 0, "the house stands: only its hall decides the game")
	assert_false(w.economy.player(0).defeated)


func test_fallen_house_leaves_no_building_hit_points() -> void:
	var w := _world()
	var b := _dwelling(w, 1)
	var sid := b.structure
	var st := _hall(w)
	w.deal_damage(st, st.max_hp * 10.0, -1)
	w.step()
	assert_true(w.get_unit(sid) == null, "the dwelling's hit points are gone with the house")
	for s in w.structures:
		assert_ne(s.id, sid)
