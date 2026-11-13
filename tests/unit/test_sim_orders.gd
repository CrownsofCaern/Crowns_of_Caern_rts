extends "res://tests/test_case.gd"


func _open_world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(40, 30)
	return w


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func test_move_reaches_point() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(100, 100))
	w.command_move([u.id], Vector2(700, 500))
	_run(w, 15.0)
	assert_lt(u.pos.distance_to(Vector2(700, 500)), 10.0)
	assert_eq(u.order, SimUnit.Order.IDLE)


func test_path_goes_around_a_wall() -> void:
	var w := SimWorld.new(1)
	var wall: Array = []
	for y in range(0, 25):
		wall.append(Vector2i(20, y))
	w.setup_map(40, 30, wall)
	var u := w.spawn("pike_militia", 0, Vector2(300, 300))
	w.command_move([u.id], Vector2(1000, 300))
	_run(w, 40.0)
	assert_lt(u.pos.distance_to(Vector2(1000, 300)), 12.0)
	assert_false(w.nav.is_blocked(u.pos))


func test_group_move_keeps_units_apart() -> void:
	var w := _open_world()
	var ids: Array = []
	for i in 20:
		ids.append(w.spawn("pike_militia", 0, Vector2(100 + (i % 5) * 25, 100 + (i / 5) * 25)).id)
	w.command_move(ids, Vector2(800, 600))
	_run(w, 25.0)
	var c := Vector2.ZERO
	for u in w.units:
		c += u.pos
	c /= w.units.size()
	assert_lt(c.distance_to(Vector2(800, 600)), 40.0, "group arrives as a block")
	for a in w.units:
		for b in w.units:
			if a.id < b.id:
				assert_gt(a.pos.distance_to(b.pos), a.radius() + b.radius() - 4.0, "no deep overlap")


func test_move_order_ignores_enemies() -> void:
	var w := _open_world()
	var u := w.spawn("lancer", 0, Vector2(100, 300))
	w.spawn("shambler", 1, Vector2(400, 330))
	w.command_move([u.id], Vector2(900, 300))
	_run(w, 12.0)
	assert_lt(u.pos.distance_to(Vector2(900, 300)), 12.0)


func test_attack_move_engages_enemies() -> void:
	var w := _open_world()
	var u := w.spawn("lancer", 0, Vector2(100, 300))
	var e := w.spawn("shambler", 1, Vector2(500, 300))
	w.command_attack_move([u.id], Vector2(1100, 300))
	_run(w, 15.0)
	assert_false(e.alive, "attack-move kills the enemy on the way")


func test_hold_position_does_not_chase() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(300, 300))
	w.spawn("longbowman", 1, Vector2(500, 300))
	w.command_hold([u.id])
	_run(w, 5.0)
	assert_lt(u.pos.distance_to(Vector2(300, 300)), 3.0)


func test_idle_units_defend_themselves_and_return() -> void:
	var w := _open_world()
	var u := w.spawn("shieldwarden", 0, Vector2(300, 300))
	var e := w.spawn("shambler", 1, Vector2(420, 300))
	_run(w, 15.0)
	assert_false(e.alive)
	assert_lt(u.pos.distance_to(Vector2(300, 300)), 12.0, "returns to its spot")


func test_stop_cancels_move() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(100, 100))
	w.command_move([u.id], Vector2(1000, 100))
	_run(w, 2.0)
	w.command_stop([u.id])
	var p := u.pos
	_run(w, 3.0)
	assert_lt(u.pos.distance_to(p), 3.0)


func test_ground_melee_cannot_hit_flyers() -> void:
	var w := _open_world()
	var s := w.spawn("shambler", 0, Vector2(300, 300))
	var f := w.spawn("sunhawk_rider", 1, Vector2(330, 300))
	w.command_attack([s.id], f.id)
	assert_eq(s.target_id, -1, "attack order refused")
	var pike := w.spawn("pike_militia", 0, Vector2(300, 340))
	w.command_attack([pike.id], f.id)
	assert_eq(pike.target_id, f.id, "reach can hit flyers")


func test_group_marches_at_slowest_pace() -> void:
	var w := _open_world()
	var fast := w.spawn("lancer", 0, Vector2(100, 300))
	var slow := w.spawn("shambler", 0, Vector2(100, 340))
	w.command_move([fast.id, slow.id], Vector2(1000, 320))
	_run(w, 5.0)
	assert_lt(absf(fast.pos.x - slow.pos.x), 40.0, "lancer waits for the shambler")
	_run(w, 20.0)
	assert_eq(fast.order, SimUnit.Order.IDLE)
	assert_eq(fast.group_speed, 0.0, "pace limit ends on arrival")


func test_right_click_pulls_a_fighting_unit_out() -> void:
	# A unit caught in a melee is ordered away: it breaks off and reaches the point,
	# instead of auto-attack pulling it straight back into the fight.
	var w := _open_world()
	var u := w.spawn("lancer", 0, Vector2(300, 300))
	var foes: Array = []
	for i in 3:
		foes.append(w.spawn("pike_militia", 1, Vector2(330, 280 + i * 20)))
	_run(w, 1.5)
	assert_true(w.in_fight([u.id]), "the lancer is in the fight")
	var goal := Vector2(1100, 800)
	w.command_smart_move([u.id], goal)
	assert_eq(u.order, SimUnit.Order.MOVE, "a unit in a fight retreats on a plain move")
	var targeted := false
	for i in int(14.0 * w.tick_rate):
		w.step()
		if u.order == SimUnit.Order.MOVE and u.target_id != -1:
			targeted = true
	assert_false(targeted, "no new target while walking away")
	assert_true(u.alive)
	assert_lt(u.pos.distance_to(goal), 40.0, "it arrives where it was sent")


func test_right_click_marches_ready_when_calm() -> void:
	var w := _open_world()
	var u := w.spawn("lancer", 0, Vector2(100, 300))
	var e := w.spawn("shambler", 1, Vector2(500, 300))
	w.command_smart_move([u.id], Vector2(1100, 300))
	assert_eq(u.order, SimUnit.Order.ATTACK_MOVE, "out of a fight, troops march ready to fight")
	_run(w, 15.0)
	assert_false(e.alive, "and engage the enemy they meet")

