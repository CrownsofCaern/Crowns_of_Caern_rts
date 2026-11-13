extends "res://tests/test_case.gd"
## Melee blocks (SimFormation): foot soldiers ordered together keep their ranks in a fight.


func _line(w: SimWorld, type_id: String, owner: int, n: int, x: float) -> Array:
	var ids: Array = []
	for i in n:
		ids.append(w.spawn(type_id, owner, Vector2(x + (i % 3) * 26, 200 + (i / 3) * 26)).id)
	return ids


func _clash(seed_value: int, n: int = 12) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 30)
	var a := _line(w, "shambler", 0, n, 300)
	var b := _line(w, "shambler", 1, n, 1400)
	w.command_attack_move(a, Vector2(1400, 300))
	w.command_attack_move(b, Vector2(300, 300))
	return w


func test_melee_group_forms_one_block() -> void:
	var w := SimWorld.new(1)
	w.setup_map(40, 30)
	var ids := _line(w, "shambler", 0, 9, 200)
	w.command_attack_move(ids, Vector2(900, 400))
	assert_eq(w.formations.size(), 1)
	for id in ids:
		assert_eq(w.get_unit(id).form_id, w.formations[0].id)


func test_cavalry_flyers_and_lone_units_stay_free() -> void:
	var w := SimWorld.new(1)
	w.setup_map(40, 30)
	var ids := _line(w, "pike_militia", 0, 5, 200)
	var horse := w.spawn("lancer", 0, Vector2(150, 300)).id
	var hawk := w.spawn("sunhawk_rider", 0, Vector2(150, 340)).id
	var bow := w.spawn("longbowman", 0, Vector2(150, 380)).id
	w.command_attack_move(ids + [horse, hawk, bow], Vector2(900, 400))
	assert_eq(w.get_unit(horse).form_id, -1, "cavalry flanks freely")
	assert_eq(w.get_unit(hawk).form_id, -1, "flyers fly freely")
	assert_ne(w.get_unit(bow).form_id, -1, "archers stand in the back rows")
	var f: SimFormation = w.formations[0]
	assert_eq(f.members.back(), bow, "ranged take the last places")
	# A lone unit, or archers on their own, form no block.
	var w2 := SimWorld.new(1)
	w2.setup_map(40, 30)
	var bows := _line(w2, "longbowman", 0, 6, 200)
	w2.command_attack_move(bows, Vector2(900, 400))
	assert_true(w2.formations.is_empty())


func test_blocks_meet_and_only_the_front_fights() -> void:
	var w := _clash(3)
	var max_fighting := 0
	var waited := false
	for i in 20 * 30:
		w.step()
		var fighting := 0
		for u in w.units:
			if u.owner == 0 and u.since_attack < 1.6:
				fighting += 1
		max_fighting = maxi(max_fighting, fighting)
		if fighting > 0 and w.count_alive(0) >= 10 and fighting < w.count_alive(0) - 2:
			waited = true
	assert_gt(max_fighting, 2, "the front row fights")
	assert_true(waited, "the rows behind wait in their places")


func test_blocks_stay_compact_in_the_fight() -> void:
	var w := _clash(5)
	for i in 20 * 14:
		w.step()
	# Mid fight: every standing member is near its place in the block.
	var far := 0
	var n := 0
	for f in w.formations:
		for id in f.members:
			var u := w.get_unit(id)
			n += 1
			if u.pos.distance_to(f.slot_of(id)) > f.step * 1.6:
				far += 1
	assert_gt(n, 8, "both blocks still stand")
	assert_lt(far, n / 4 + 1, "%d of %d members wandered off" % [far, n])


func test_ranks_close_up_when_the_front_falls() -> void:
	var w := SimWorld.new(1)
	w.setup_map(40, 30)
	var ids := _line(w, "shambler", 0, 9, 200)
	w.command_attack_move(ids, Vector2(240, 230))
	w.command_stop(ids)  # the whole block: it forms up where it stands
	for i in 20 * 6:
		w.step()
	var f: SimFormation = w.formations[0]
	var front_before: Array = []
	for id in f.members:
		if (f.slots[id] as Vector2).dot(f.fwd) > f.front_depth() - 1.0:
			front_before.append(id)
	assert_eq(front_before.size(), f.cols)
	w.deal_damage(w.get_unit(front_before[0]), 9999.0, -1)
	for i in 20 * 4:
		w.step()
	var front_after := 0
	for id in f.members:
		if (f.slots[id] as Vector2).dot(f.fwd) > f.front_depth() - 1.0:
			front_after += 1
	assert_eq(f.members.size(), 8)
	assert_eq(front_after, f.cols, "someone from behind stepped up")


func test_picking_a_target_sends_units_out_of_their_block() -> void:
	var w := SimWorld.new(1)
	w.setup_map(40, 30)
	var ids := _line(w, "shambler", 0, 12, 200)
	var foe := w.spawn("marrow_archer", 1, Vector2(1000, 600))
	w.command_attack_move(ids, Vector2(600, 300))
	w.command_attack(ids.slice(0, 3), foe.id)
	for id in ids.slice(0, 3):
		assert_eq(w.get_unit(id).form_id, -1)
		assert_eq(w.get_unit(id).order, SimUnit.Order.ATTACK)
	w.step()
	assert_eq(w.formations.size(), 1)
	assert_eq(w.formations[0].members.size(), 9)
	# A new order for part of a block makes it a block of its own.
	w.command_attack_move(ids.slice(3, 7), Vector2(400, 700))
	w.step()
	assert_eq(w.formations.size(), 2)


func test_stop_keeps_a_whole_block_but_not_a_part() -> void:
	var w := SimWorld.new(1)
	w.setup_map(40, 30)
	var ids := _line(w, "shambler", 0, 9, 200)
	w.command_attack_move(ids, Vector2(600, 300))
	w.command_stop(ids)
	assert_eq(w.formations[0].members.size(), 9)
	w.command_stop(ids.slice(0, 2))
	assert_eq(w.get_unit(ids[0]).form_id, -1)
	assert_eq(w.formations[0].members.size(), 7)


func test_block_fights_are_deterministic() -> void:
	var a := _clash(9)
	var b := _clash(9)
	for i in 20 * 25:
		a.step()
		b.step()
	assert_eq(a.checksum(), b.checksum())


func test_attack_move_marches_on_after_the_fight() -> void:
	var w := SimWorld.new(2)
	w.setup_map(60, 30)
	var ids := _line(w, "shieldwarden", 0, 9, 200)
	w.spawn("shambler", 1, Vector2(700, 230))
	w.command_attack_move(ids, Vector2(1500, 230))
	for i in 20 * 40:
		w.step()
	var c := Vector2.ZERO
	for id in ids:
		c += w.get_unit(id).pos
	c /= ids.size()
	assert_lt(c.distance_to(Vector2(1500, 230)), 120.0, "the block reached its goal after the skirmish")
