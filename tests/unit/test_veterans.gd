extends "res://tests/test_case.gd"
## Veteran ranks (rules.json "veterans", SimWorld.gain_xp / set_veteran) and the retreat
## order (SimWorld.command_retreat, rules.json "retreat").


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _open_world() -> SimWorld:
	var w := SimWorld.new(7)
	w.setup_map(40, 30)
	return w


func test_rules_validate() -> void:
	var errors := UnitCatalog.get_default().validate()
	assert_eq(errors.size(), 0, ", ".join(errors))


func test_fighting_earns_rank() -> void:
	var w := _open_world()
	var u := w.spawn("lancer", 0, Vector2(100, 300))
	assert_eq(u.veteran, 1)
	for i in 4:
		w.spawn("shambler", 1, Vector2(300 + i * 30, 300))
	w.command_attack_move([u.id], Vector2(800, 300))
	_run(w, 30.0)
	assert_true(u.alive, "the lancer survives four shamblers")
	assert_gt(u.vet_xp, 1.5, "damage dealt and kills count")
	assert_gt(float(u.veteran), 1.5, "it ranked up")


func test_rank_bonuses_and_promotion() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(100, 300))
	var base_dmg := u.damage_factor()
	var base_taken := u.taken_factor()
	u.hp = u.max_hp * 0.5
	w.set_veteran(u, 2)
	assert_eq(u.type_id, "pike_militia", "level 2 keeps its form")
	assert_gt(u.damage_factor(), base_dmg)
	assert_lt(u.taken_factor(), base_taken)
	w.set_veteran(u, 3)
	assert_eq(u.type_id, "pike_veteran", "promoted at level 3")
	assert_eq(String(u.def["id"]), "pike_veteran")
	assert_between(u.hp_ratio(), 0.49, 0.51, "keeps its share of health")
	var promoted := false
	for e in w.events:
		if e["type"] == "veteran" and e["promoted"] == "pike_veteran":
			promoted = true
	assert_true(promoted, "a veteran event tells the view")
	var hp4 := u.max_hp
	w.set_veteran(u, 5)
	assert_true(u.is_ascendant())
	assert_between(u.max_hp, hp4 * 1.19, hp4 * 1.21, "Ascendant: +20% hit points")
	assert_eq(u.display_name(), "Ascendant Pike Veteran")
	w.gain_xp(u, 99999.0)
	assert_eq(u.veteran, 5, "level 5 is the top")


func test_upgraded_recruits_start_at_promote_level_and_workers_never_rank() -> void:
	var w := _open_world()
	var vet := w.spawn("pike_veteran", 0, Vector2(100, 300))
	assert_eq(vet.veteran, int(w.catalog.rules["veterans"]["promote_level"]))
	var worker := w.spawn("worker_concord", 0, Vector2(200, 300))
	w.gain_xp(worker, 10000.0)
	assert_eq(worker.veteran, 1)


func test_healers_earn_rank_by_healing() -> void:
	var w := _open_world()
	var healer := w.spawn("lightbearer", 0, Vector2(100, 300))
	var hurt := w.spawn("shieldwarden", 0, Vector2(130, 300))
	for i in 20:
		hurt.hp = hurt.max_hp * 0.3
		_run(w, 2.0)
	assert_gt(healer.vet_xp, 0.0, "healing counts")


func test_snapshot_carries_a_promotion() -> void:
	var a := SkirmishScenario.build_skirmish(4)
	var b := SkirmishScenario.build_skirmish(4)
	var p := a.economy.hall_of(0).center + Vector2(300, 0)
	var ua := a.spawn("pike_militia", 0, p)
	var ub := b.spawn("pike_militia", 0, p)
	a.set_veteran(ua, 3)
	assert_true(WorldSnapshot.apply(b, WorldSnapshot.capture(a)))
	assert_eq(ub.type_id, "pike_veteran")
	assert_eq(String(ub.def["id"]), "pike_veteran", "the form follows the copied type")
	assert_eq(ub.veteran, 3)


func test_retreat_runs_home_fast_and_ignores_enemies() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var home := w.economy.hall_of(0)
	var start := home.center + Vector2(900, 0)
	if w.nav.is_blocked(start):
		start = w.nav.nearest_free(start)
	var u := w.spawn("pike_militia", 0, start)
	var foe := w.spawn("shambler", 1, start + Vector2(30, 0))
	_run(w, 1.0)
	assert_true(w.command_retreat([u.id]) == 1)
	assert_eq(u.order, SimUnit.Order.RETREAT)
	var hit_back := false
	for i in 20 * 40:
		w.step()
		if u.order != SimUnit.Order.RETREAT:
			break
		for e in w.events:
			if e["type"] == "attack" and int(e["unit"]) == u.id:
				hit_back = true
	assert_false(hit_back, "no blows on the way home")
	assert_true(u.alive, "it outruns the shambler")
	assert_lt(u.pos.distance_to(home.center), 200.0, "it reached the capital")
	assert_eq(u.order, SimUnit.Order.IDLE, "and stands there")
	assert_true(foe != null)


func test_retreat_is_faster_than_a_move() -> void:
	var a := SkirmishScenario.build_skirmish(4)
	var b := SkirmishScenario.build_skirmish(4)
	var p := a.economy.hall_of(0).center + Vector2(700, 0)
	var ua := a.spawn("pike_militia", 0, a.nav.nearest_free(p))
	var ub := b.spawn("pike_militia", 0, b.nav.nearest_free(p))
	a.command_retreat([ua.id])
	b.command_move([ub.id], a.retreat_point(ua))
	var d0 := ua.pos.distance_to(ua.order_point)
	_run(a, 3.0)
	_run(b, 3.0)
	var ga := d0 - ua.pos.distance_to(ua.order_point)
	var gb := d0 - ub.pos.distance_to(a.retreat_point(ua))
	assert_between(ga / gb, 1.25, 1.7, "about 40% faster")


func test_retreat_command_through_world_commands() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var u := w.spawn("pike_militia", 0, w.economy.hall_of(0).center + Vector2(600, 0))
	var other := w.spawn("pike_militia", 1, w.economy.hall_of(1).center + Vector2(600, 0))
	assert_true(WorldCommands.apply(w, 0, {"t": "retreat", "ids": [u.id, other.id]}))
	assert_eq(u.order, SimUnit.Order.RETREAT)
	assert_ne(other.order, SimUnit.Order.RETREAT, "only your own units")
