extends "res://tests/test_case.gd"
## Walls, gates and towers (Fortifications).

const ROCK_X := 20  ## a ridge of rock down the map at this column...
const GAP := [8, 9, 10, 11]  ## ...with a pass through these rows


## 40 x 20 cells: a rock ridge at x = 20 with a 4-cell pass. Player 0 lives west, 1 east.
func _world(seed_value: int = 5) -> SimWorld:
	var w := SimWorld.new(seed_value)
	var rock: Array = []
	for y in 20:
		if not (y in GAP):
			rock.append(Vector2i(ROCK_X, y))
	w.setup_map(40, 20, rock)
	for o in 2:
		var pl := w.economy.add_player(o, "concord")
		pl.res = {"gold": 2000, "wood": 2000, "ore": 2000}
	return w


func _cell(x: int, y: int) -> Vector2:
	return Vector2(x * 32 + 16, y * 32 + 16)


## Walls the pass (player 0) and finishes the pieces at once.
func _seal(w: SimWorld, owner: int = 0) -> Array[Building]:
	var made := w.forts.command_build_wall([], owner, _cell(ROCK_X, GAP[0]), _cell(ROCK_X, GAP[-1]))
	for b in made:
		b.progress = 1.0
	w.step()
	return made


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func test_wall_lines_never_step_diagonally() -> void:
	for target: Vector2i in [Vector2i(7, 3), Vector2i(-5, 9), Vector2i(4, -4), Vector2i(0, 6), Vector2i(-8, -1)]:
		var cells := Fortifications.line_cells(Vector2i(2, 2), Vector2i(2, 2) + target)
		assert_eq(cells[cells.size() - 1], Vector2i(2, 2) + target)
		for i in range(1, cells.size()):
			var d: Vector2i = cells[i] - cells[i - 1]
			assert_eq(absi(d.x) + absi(d.y), 1, "cells %s and %s share a side" % [cells[i - 1], cells[i]])


func test_wall_seals_a_pass() -> void:
	var w := _world()
	var made := _seal(w)
	assert_gt(made.size(), 0.0)
	var cost_paid := 2000 - w.economy.player(0).amount("wood")
	assert_eq(cost_paid, int(w.forts.conf()["wall"]["cost"]["wood"]) * made.size(), "paid per piece")
	var u := w.spawn("pike_militia", 1, _cell(30, 10))
	w.command_move([u.id], _cell(8, 10))
	_run(w, 30.0)
	assert_gt(u.pos.x, float(ROCK_X * 32), "the soldier is still east of the wall")
	assert_lt(u.pos.distance_to(_cell(ROCK_X + 1, 10)), 120.0, "it walked up to the wall, not some far shore")


func test_diagonal_wall_has_no_gaps() -> void:
	# Open ground; a slanted wall from rock to rock must still stop everyone on foot.
	var w := SimWorld.new(3)
	var rock: Array = []
	for x in 40:
		rock.append(Vector2i(x, 0))
		rock.append(Vector2i(x, 19))
	w.setup_map(40, 20, rock)
	w.economy.add_player(0, "concord").res = {"wood": 9000, "ore": 9000}
	w.economy.add_player(1, "hollow")
	w.forts.conf()["max_cells"] = 60
	var made := w.forts.command_build_wall([], 0, _cell(12, 1), _cell(26, 18))
	assert_gt(made.size(), 0.0, "planned")
	for b in made:
		b.progress = 1.0
	var ids: Array = []
	for i in 8:
		ids.append(w.spawn("pike_militia", 1, _cell(30 + i % 3, 4 + i)).id)
	w.command_move(ids, _cell(5, 14))
	_run(w, 40.0)
	for id in ids:
		var u := w.get_unit(id)
		var side := (u.pos - _cell(12, 1)).cross(_cell(26, 18) - _cell(12, 1))
		assert_gt(side, 0.0, "unit %d stayed on its side of the wall" % id)


func test_wall_ends_snap_onto_rock() -> void:
	var w := _world()
	# Ask for a wall two cells short at both ends: it still reaches the rock.
	var p := w.forts.plan(0, _cell(ROCK_X, GAP[0] + 1), _cell(ROCK_X, GAP[-1] - 1))
	assert_eq(p["problem"], "")
	var free: Array = p["free"]
	for y in GAP:
		assert_true(Vector2i(ROCK_X, y) in free, "row %d walled" % y)


func test_cannot_wall_next_to_a_settlement_or_enemy() -> void:
	var w := _world()
	var s := w.economy.add_sector(_cell(10, 10), "village", 1)
	assert_ne(w.forts.plan(0, _cell(10, 12), _cell(10, 16))["problem"], "", "not in a settlement's square")
	assert_ne(w.forts.plan(0, _cell(14, 4), _cell(14, 8))["problem"], "", "not under the enemy's walls")
	s.owner = 0
	assert_eq(w.forts.plan(0, _cell(14, 4), _cell(14, 8))["problem"], "", "fine near your own")


func test_soldiers_break_a_wall_in_their_way() -> void:
	var w := _world()
	var made := _seal(w)
	var ids: Array = []
	for i in 5:
		ids.append(w.spawn("pike_militia", 1, _cell(30, 8 + i)).id)
	w.command_attack_move(ids, _cell(6, 10))
	_run(w, 90.0)
	var broken := 0
	for b in made:
		if w.economy.building(b.id) == null:
			broken += 1
	assert_gt(broken, 0.0, "a piece fell")
	var through := 0
	for id in ids:
		var u := w.get_unit(id)
		if u != null and u.pos.x < float(ROCK_X * 32):
			through += 1
	assert_gt(through, 2.0, "they marched on through the breach")


func test_flyers_ignore_walls() -> void:
	var w := _world()
	_seal(w)
	var flyer := ""
	for id in w.catalog.units:
		if w.catalog.units[id].get("abilities", []).has("flying"):
			flyer = id
			break
	assert_ne(flyer, "")
	var u := w.spawn(flyer, 1, _cell(30, 10))
	w.command_move([u.id], _cell(8, 10))
	_run(w, 20.0)
	assert_lt(u.pos.x, float(ROCK_X * 32), "flew over")


func test_gate_opens_for_its_owner_only() -> void:
	var w := _world()
	var made := _seal(w)
	assert_eq(made.size(), 1)
	assert_true(w.forts.command_upgrade(0, made[0].id, "gate"))
	_run(w, float(w.forts.conf()["gate"]["seconds"]) + 0.5)
	assert_eq(made[0].kind, "gate")
	var foe := w.spawn("pike_militia", 1, _cell(30, 10))
	w.command_move([foe.id], _cell(8, 10))
	_run(w, 25.0)
	assert_gt(foe.pos.x, float(ROCK_X * 32), "the enemy waits at a shut gate")
	foe.alive = false
	_run(w, 0.1)
	var friend := w.spawn("pike_militia", 0, _cell(6, 10))
	w.command_move([friend.id], _cell(32, 10))
	_run(w, 25.0)
	assert_gt(friend.pos.x, float((ROCK_X + 4) * 32), "the owner's soldier walked through")
	_run(w, 5.0)
	assert_false(made[0].gate_open, "and it shut behind")


func _tower(w: SimWorld) -> Building:
	var made := _seal(w)
	w.forts.command_upgrade(0, made[0].id, "tower")
	_run(w, float(w.forts.conf()["tower"]["seconds"]) + 0.5)
	return made[0]


func test_tower_takes_two_archers() -> void:
	var w := _world()
	var t := _tower(w)
	assert_eq(t.kind, "tower")
	assert_gt(w.get_unit(t.structure).max_hp, float(w.forts.conf()["wall"]["hp"]), "a tower is sturdier")
	var ids: Array = []
	for i in 3:
		ids.append(w.spawn("longbowman", 0, _cell(14, 8 + i)).id)
	ids.append(w.spawn("pike_militia", 0, _cell(14, 12)).id)
	assert_eq(w.forts.command_garrison(ids, t.id), 2, "room for two, archers only")
	_run(w, 10.0)
	assert_eq(t.garrison.size(), 2)
	var inside := w.get_unit(t.garrison[0])
	assert_eq(inside.garrison_of, t.id)
	assert_gt(w._reach(inside), float(inside.def["range"]), "shoots farther from up there")
	# Ordered away: down it comes, on its own side.
	w.command_move([inside.id], _cell(6, 6))
	_run(w, 3.0)
	assert_eq(inside.garrison_of, -1)
	assert_lt(inside.pos.x, float(ROCK_X * 32))
	assert_eq(t.garrison.size(), 1)


func test_only_ranged_and_flyers_hurt_the_garrison() -> void:
	var w := _world()
	var t := _tower(w)
	var archer := w.spawn("longbowman", 0, _cell(14, 10))
	w.forts.command_garrison([archer.id], t.id)
	_run(w, 8.0)
	assert_eq(archer.garrison_of, t.id)
	var pike := w.spawn("pike_militia", 1, _cell(22, 10))
	var bow := w.spawn("longbowman", 1, _cell(26, 10))
	assert_false(w._can_hit(pike, archer), "a pike cannot reach it")
	assert_true(w._can_hit(bow, archer), "a bow can")
	# The tower falls: the archer drops out alive.
	w.deal_damage(w.get_unit(t.structure), 1e9, pike.id)
	_run(w, 0.2)
	assert_eq(w.economy.building(t.id), null, "the tower is gone")
	assert_eq(archer.garrison_of, -1)
	assert_true(archer.alive)
	assert_false(w.nav.is_blocked(archer.pos), "standing on open ground")
	assert_false(w.nav.is_blocked_cell(Vector2i(ROCK_X, 10)), "the pass is open again")


func test_workers_build_a_wall_piece_by_piece() -> void:
	var w := _world()
	var ids: Array = []
	for i in 2:
		ids.append(w.spawn(w.catalog.worker_type("concord"), 0, _cell(16, 9 + i)).id)
	w.forts.conf()["piece_cells"] = 2
	var made := w.forts.command_build_wall(ids, 0, _cell(ROCK_X, GAP[0]), _cell(ROCK_X, GAP[-1]))
	assert_eq(made.size(), 2)
	var st := w.get_unit(made[0].structure)
	assert_lt(st.hp, st.max_hp * 0.2, "a fresh site is weak")
	_run(w, float(w.forts.conf()["wall"]["seconds"]) * 2.0 + 15.0)
	for b in made:
		assert_true(b.done(), "piece %d built" % b.id)
		var s := w.get_unit(b.structure)
		assert_gt(s.hp, s.max_hp * 0.95, "and at full strength")


func test_walls_are_deterministic() -> void:
	var sums := []
	for k in 2:
		var w := _world(9)
		_seal(w)
		var ids: Array = []
		for i in 4:
			ids.append(w.spawn("pike_militia", 1, _cell(30, 8 + i)).id)
		w.command_attack_move(ids, _cell(6, 10))
		_run(w, 30.0)
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])


func test_fort_numbers_are_complete() -> void:
	var cf := SimWorld.new(1).forts.conf()
	for k in ["piece_cells", "max_cells", "snap_cells", "settlement_clearance", "enemy_clearance"]:
		assert_gt(float(cf.get(k, 0)), 0.0, k)
	for kind in ["wall", "gate", "tower"]:
		var d: Dictionary = cf[kind]
		assert_gt(float(d["hp"]), 0.0, kind + " hp")
		assert_gt(float(d["seconds"]), 0.0, kind + " seconds")
		assert_false((d["cost"] as Dictionary).is_empty(), kind + " cost")
	assert_eq(int(cf["tower"]["garrison"]), 2)
	assert_gt(float(cf["tower"]["range_factor"]), 1.0)
	assert_gt(float(cf["gate"]["open_reach"]), 0.0)


func test_nearest_free_worker_takes_the_job() -> void:
	# B with nothing selected: the nearest worker that is not already building goes.
	var w := _world()
	var wt := w.catalog.worker_type("concord")
	var busy := w.spawn(wt, 0, _cell(15, 9))
	var near := w.spawn(wt, 0, _cell(12, 9))
	var far := w.spawn(wt, 0, _cell(3, 9))
	w.spawn(wt, 1, _cell(17, 9))  # the enemy's worker never answers
	busy.order = SimUnit.Order.BUILD
	near.order = SimUnit.Order.IDLE
	far.order = SimUnit.Order.IDLE
	var got := w.economy.spare_worker(0, _cell(18, 9))
	assert_true(got != null and got.id == near.id, "the nearest idle worker")
	near.order = SimUnit.Order.BUILD
	got = w.economy.spare_worker(0, _cell(18, 9))
	assert_true(got != null and got.id == far.id, "then the next free one")
	far.order = SimUnit.Order.DRAFT
	assert_true(w.economy.spare_worker(0, _cell(18, 9)) == null, "none left")


func test_walls_are_cheap_next_to_a_dwelling() -> void:
	var eco := SimWorld.new(1).economy
	var wall: Dictionary = eco.e["forts"]["wall"]["cost"]
	var total := 0
	for r in wall:
		total += int(wall[r])
	assert_lt(float(total), 30.0, "a wall piece costs little: %s" % str(wall))
