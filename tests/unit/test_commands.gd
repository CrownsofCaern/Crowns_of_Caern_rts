extends "res://tests/test_case.gd"
## The capture order and shift-queued orders (SimWorld.command_capture, queue_command).


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _open_world() -> SimWorld:
	var w := SimWorld.new(7)
	w.setup_map(40, 30)
	return w


func _neutral_town(w: SimWorld) -> Sector:
	for s in w.economy.sectors:
		if s.owner == -1 and s.size != "waystone":
			return s
	return null


func test_capture_order_takes_the_settlement_and_waits_there() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var target := _neutral_town(w)
	assert_true(target != null)
	var ids: Array = []
	for i in 30:
		ids.append(w.spawn("pike_militia", 0, target.center + Vector2(-260 + (i % 6) * 20, -40 + (i / 6) * 20)).id)
	assert_true(w.command_capture(ids, target.id))
	assert_eq(w.get_unit(ids[0]).order, SimUnit.Order.CAPTURE)
	_run(w, w.economy.capture_seconds(target) + 30.0)
	assert_eq(target.owner, 0, "captured")
	var near := 0
	for id in ids:
		var u := w.get_unit(id)
		if u != null:
			assert_ne(u.order, SimUnit.Order.CAPTURE, "the order ends once it is ours")
			if u.pos.distance_to(target.center) < float(w.economy.e["capture_radius"]) + 60.0:
				near += 1
	assert_gt(near, 10, "the troops stay in the settlement")


func test_capture_order_refuses_own_settlement_and_leaves_workers_out() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var home := w.economy.hall_of(0)
	var u := w.spawn("pike_militia", 0, home.center + Vector2(300, 0))
	assert_false(w.command_capture([u.id], home.id), "already ours")
	var target := _neutral_town(w)
	var worker: SimUnit = w.economy.workers_of(0)[0]
	assert_false(w.command_capture([worker.id], target.id), "workers don't capture")
	assert_ne(worker.order, SimUnit.Order.CAPTURE)


func test_queued_waypoints_are_walked_in_order() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(100, 100))
	var a := Vector2(700, 150)
	var b := Vector2(700, 700)
	w.queue_command([u.id], {"type": "move", "point": a})
	assert_eq(u.order_point.distance_to(a) < 1.0, true, "an idle unit starts the first order at once")
	w.queue_command([u.id], {"type": "move", "point": b})
	assert_eq(w.plan_points(u).size(), 2)
	var closest_a := INF
	for i in int(30.0 * w.tick_rate):
		w.step()
		closest_a = minf(closest_a, u.pos.distance_to(a))
	assert_lt(closest_a, 12.0, "went by the first waypoint")
	assert_lt(u.pos.distance_to(b), 12.0, "ends at the second")
	assert_eq(u.plan_id, -1, "the queue is used up")
	assert_true(w.plans.is_empty())


func test_queue_waits_for_the_current_order() -> void:
	var w := _open_world()
	var ids: Array = []
	for i in 6:
		ids.append(w.spawn("pike_militia", 0, Vector2(100 + (i % 3) * 25, 100 + (i / 3) * 25)).id)
	var a := Vector2(800, 150)
	var b := Vector2(150, 750)
	w.command_move(ids, a)
	w.queue_command(ids, {"type": "move", "point": b})
	_run(w, 3.0)
	var u := w.get_unit(ids[0])
	assert_lt(u.order_point.distance_to(a), 120.0, "still on the first order")
	_run(w, 50.0)
	var c := Vector2.ZERO
	for id in ids:
		c += w.get_unit(id).pos
	c /= ids.size()
	assert_lt(c.distance_to(b), 60.0, "the group went on to the queued point")


func test_order_without_shift_drops_the_queue() -> void:
	var w := _open_world()
	var u := w.spawn("pike_militia", 0, Vector2(100, 100))
	w.queue_command([u.id], {"type": "move", "point": Vector2(800, 100)})
	w.queue_command([u.id], {"type": "move", "point": Vector2(800, 800)})
	w.command_stop([u.id])
	assert_eq(u.plan_id, -1)
	assert_true(w.plans.is_empty())
	_run(w, 5.0)
	assert_lt(u.pos.distance_to(Vector2(100, 100)), 30.0, "stopped means stopped")


func test_part_of_a_queued_group_starts_its_own_queue() -> void:
	var w := _open_world()
	var a := w.spawn("pike_militia", 0, Vector2(100, 100))
	var b := w.spawn("pike_militia", 0, Vector2(130, 100))
	w.queue_command([a.id, b.id], {"type": "move", "point": Vector2(600, 100)})
	w.queue_command([a.id, b.id], {"type": "move", "point": Vector2(600, 600)})
	w.queue_command([b.id], {"type": "move", "point": Vector2(100, 700)})
	assert_ne(a.plan_id, b.plan_id)
	_run(w, 40.0)
	assert_lt(a.pos.distance_to(Vector2(600, 600)), 40.0)
	assert_lt(b.pos.distance_to(Vector2(100, 700)), 40.0)


func test_queued_capture_after_a_waypoint() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var target := _neutral_town(w)
	var ids: Array = []
	for i in 30:
		ids.append(w.spawn("pike_militia", 0, target.center + Vector2(-300 + (i % 6) * 20, 200 + (i / 6) * 20)).id)
	var via := w.nav.nearest_free(target.center + Vector2(-300, 0))
	w.queue_command(ids, {"type": "move", "point": via})
	w.queue_command(ids, {"type": "capture", "sector": target.id})
	assert_eq(w.plan_points(w.get_unit(ids[0])).size(), 2)
	_run(w, w.economy.capture_seconds(target) + 45.0)
	assert_eq(target.owner, 0, "captured after the waypoint")


func test_queued_gather_for_a_worker() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var worker: SimUnit = w.economy.workers_of(0)[0]
	var node: ResNode = null
	for n in w.economy.nodes:
		if w.economy.uses(0, n.resource):
			node = n
			break
	w.command_move([worker.id], worker.pos + Vector2(60, 0))
	w.queue_command([worker.id], {"type": "gather", "node": node.id})
	_run(w, 5.0)
	assert_eq(worker.order, SimUnit.Order.GATHER)
	assert_eq(worker.job, node.id)


func test_every_cursor_action_has_its_art() -> void:
	assert_true("capture" in CommandCursor.ACTIONS)
	for act in CommandCursor.ACTIONS:
		var path := CommandCursor.texture_path(act)
		assert_true(ResourceLoader.exists(path), "cursor art for " + act)
		var tex: Texture2D = load(path)
		assert_eq(tex.get_width(), 40)
		assert_eq(tex.get_height(), 40)
