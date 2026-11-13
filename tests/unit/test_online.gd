extends "res://tests/test_case.gd"
## Online skirmish: commands as data (WorldCommands), the lockstep that keeps two
## computers' worlds identical (Lockstep), the start message (OnlineGame) and a
## real ENet connection on this computer (NetSession).

const SEED := 4


func _world() -> SimWorld:
	return SkirmishScenario.build_skirmish(SEED, ["concord", "hollow"])


func test_commands_only_touch_the_senders_units() -> void:
	var w := _world()
	var mine := w.spawn("pike_militia", 0, w.economy.hall_of(0).center + Vector2(80, 0))
	var theirs := w.spawn("pike_militia", 1, w.economy.hall_of(1).center + Vector2(80, 0))
	var goal := mine.pos + Vector2(200, 0)
	# Player 1 tries to march player 0's soldier away: nothing happens.
	assert_false(WorldCommands.apply(w, 1, {"t": "order", "ids": [mine.id], "cmd": {"type": "move", "point": goal}, "queued": false}))
	assert_eq(mine.order, SimUnit.Order.IDLE)
	assert_true(WorldCommands.apply(w, 1, {"t": "order", "ids": [mine.id, theirs.id], "cmd": {"type": "move", "point": goal}, "queued": false}))
	assert_eq(mine.order, SimUnit.Order.IDLE, "still only its own player can order it")
	assert_ne(theirs.order, SimUnit.Order.IDLE)
	# Spending is always the sender's: player 1 can't raise player 0's hall.
	var before := w.economy.player(0).res.duplicate()
	WorldCommands.apply(w, 1, {"t": "hall"})
	assert_eq(w.economy.player(0).res, before)


func test_broken_commands_are_ignored() -> void:
	var w := _world()
	for c: Variant in [{}, {"t": "nope"}, {"t": "order"}, {"t": "order", "ids": "x", "cmd": 3},
			{"t": "order", "ids": [1], "cmd": {"type": "explode"}}, {"t": "build", "point": "here"},
			{"t": "buy", "site": 1, "what": [1]}, {"t": "cast", "slot": "q"}]:
		assert_false(WorldCommands.apply(w, 0, c), str(c))
	assert_false(WorldCommands.is_command({"t": "nope"}))
	assert_true(WorldCommands.is_command({"t": "stop", "ids": []}))


func test_commands_cross_the_wire_unchanged() -> void:
	var c := {"t": "order", "ids": [3, 9], "cmd": {"type": "move", "point": Vector2(123.456, 7.25)}, "queued": true}
	var back: Variant = bytes_to_var(var_to_bytes(c))
	assert_eq(back, c)
	assert_true(back["cmd"]["point"] is Vector2)


## Passes messages between lockstep peers, each arriving `lag` steps after it was sent.
class Wire:
	var queue: Array = []  ## [due, to_index, msg]
	var now: int = 0

	func post(from: int, peers: Array, msgs: Array, lag: int) -> void:
		for m: Dictionary in msgs:
			for i in peers.size():
				if i != from:
					queue.append([now + lag, i, bytes_to_var(var_to_bytes(m))])

	func deliver(peers: Array) -> void:
		now += 1
		var keep: Array = []
		for q: Array in queue:
			if int(q[0]) <= now:
				(peers[int(q[1])] as Lockstep).receive(q[2])
			else:
				keep.append(q)
		queue = keep


func test_a_turn_waits_for_every_player() -> void:
	var a := Lockstep.new([0, 1], 0)
	var b := Lockstep.new([0, 1], 1)
	var wa := _world()
	var tick := func() -> void: wa.step()
	# The first DELAY_TURNS turns are empty for everyone and run at once.
	for i in Lockstep.DELAY_TURNS:
		assert_true(a.can_run())
		a.run_turn(wa, tick)
	assert_false(a.can_run(), "turn 2 needs player 1's commands")
	assert_eq(a.waiting_for(), [1])
	# B runs its turn 0 and so sends its commands for turn 2.
	var wb := _world()
	b.run_turn(wb, func() -> void: wb.step())
	for m in b.take_outbox():
		a.receive(m)
	assert_true(a.can_run())
	assert_eq(wa.tick, Lockstep.DELAY_TURNS * Lockstep.TICKS_PER_TURN)
	# A player who left is not waited for.
	a.run_turn(wa, tick)
	assert_false(a.can_run())
	a.drop_player(1)
	assert_true(a.can_run())


## Two computers play the same match with different frame rates and a laggy wire;
## commands from both sides must land on the same tick everywhere.
func _play_pair(turns: int, nudge_at: int = -1) -> Array:
	var worlds := [_world(), _world()]
	var peers := [Lockstep.new([0, 1], 0), Lockstep.new([0, 1], 1)]
	var units: Array = []
	for o in 2:
		for w: SimWorld in worlds:
			var u := w.spawn("pike_militia", o, w.economy.hall_of(o).center + Vector2(90, 40))
			if w == worlds[0]:
				units.append(u.id)
	var wire := Wire.new()
	var rng := GameRng.new(99)
	var goals := [Vector2(900, 700), Vector2(1500, 1100)]
	var steps := 0
	while (peers[0].turn < turns or peers[1].turn < turns) and steps < turns * 40:
		steps += 1
		if peers[0].failed or peers[1].failed:
			break
		# Each side gets a turn now and then, in no fixed rhythm.
		var i := rng.next_int(0, 1)
		var ls: Lockstep = peers[i]
		var w: SimWorld = worlds[i]
		ls.repair(w)
		if ls.turn < turns and ls.can_run():
			if ls.turn % 7 == i + 2:
				var hall := w.economy.hall_of(i)
				var target: Vector2 = hall.center + goals[i] * (0.1 + 0.02 * float(ls.turn % 5))
				ls.issue({"t": "order", "ids": [units[i]], "cmd": {"type": "move", "point": target}, "queued": false})
			if ls.turn == 30 + i:
				ls.issue({"t": "weight", "res": "wood", "weight": 7})
			ls.run_turn(w, func() -> void: w.step())
			if i == 1 and ls.turn == nudge_at:
				w.get_unit(units[1]).pos += Vector2(5, 0)  # a bug on one computer only
		wire.post(i, peers, ls.take_outbox(), rng.next_int(0, 6))
		wire.deliver(peers)
	# Let the last fingerprints arrive.
	for k in 10:
		wire.deliver(peers)
	return [worlds, peers, units]


func test_two_computers_stay_identical() -> void:
	var r := _play_pair(120)
	var worlds: Array = r[0]
	var peers: Array = r[1]
	var units: Array = r[2]
	var w0: SimWorld = worlds[0]
	var w1: SimWorld = worlds[1]
	assert_eq(w0.tick, w1.tick)
	assert_eq(w0.tick, 120 * Lockstep.TICKS_PER_TURN)
	assert_eq(Lockstep.fingerprint(w0), Lockstep.fingerprint(w1), "the two worlds drifted apart")
	assert_eq(peers[0].desync_turn, -1)
	assert_eq(peers[1].desync_turn, -1)
	# Both players' orders were carried out (on both computers).
	for o in 2:
		assert_eq(w0.get_unit(units[o]).pos, w1.get_unit(units[o]).pos)
	for o in 2:
		var u := w0.get_unit(units[o])
		assert_gt(u.pos.distance_to(w0.economy.hall_of(o).center + Vector2(90, 40)), 30.0, "player %d's soldier marched" % o)
	assert_eq(w0.economy.gather_weight(1, "wood"), 7)
	assert_eq(w1.economy.gather_weight(1, "wood"), 7)


func test_a_drift_is_repaired() -> void:
	var r := _play_pair(90, 25)
	var worlds: Array = r[0]
	var peers: Array = r[1]
	for ls: Lockstep in peers:
		assert_false(ls.failed)
		assert_eq(ls.repairs, 1, "one repair on each computer")
		assert_eq(ls.desync_turn, -1, "no drift since the repair")
		assert_eq(ls.turn, 90, "play went on after the repair")
	assert_eq(Lockstep.fingerprint(worlds[0]), Lockstep.fingerprint(worlds[1]))


## Runs a world with its computer players for a while.
func _run(w: SimWorld, ais: Array, ticks: int) -> void:
	for i in ticks:
		for a: EconomyAi in ais:
			a.update(w)
		w.step()


func test_a_snapshot_makes_two_worlds_play_alike() -> void:
	# Two copies of a computer-vs-computer game; the second gets different orders, so
	# everything about it differs (places, paths, plans, money, the computers' plans).
	var a := _world()
	var b := _world()
	var ais_a: Array = [EconomyAi.new(0, "normal"), EconomyAi.new(1, "normal")]
	var ais_b: Array = [EconomyAi.new(0, "normal"), EconomyAi.new(1, "normal")]
	_run(a, ais_a, 200)
	_run(b, ais_b, 200)
	var workers: Array = []
	for u in b.units:
		if u.owner == 0 and u.is_worker():
			workers.append(u.id)
	b.command_move(workers, b.economy.hall_of(0).center + Vector2(-150, 60))
	b.economy.player(0).res["gold"] = 5
	b.rng.next_u32()
	_run(b, ais_b, 20)
	_run(a, ais_a, 20)
	assert_ne(Lockstep.fingerprint(a), Lockstep.fingerprint(b))
	var snap := WorldSnapshot.unpack(WorldSnapshot.pack(WorldSnapshot.capture(a, ais_a)))
	assert_true(WorldSnapshot.apply(b, snap, ais_b))
	assert_eq(Lockstep.fingerprint(a), Lockstep.fingerprint(b), "the same right after the copy")
	# And they go on alike: the copy took everything that steers the game.
	_run(a, ais_a, 600)
	_run(b, ais_b, 600)
	assert_eq(Lockstep.fingerprint(a), Lockstep.fingerprint(b), "still the same 30 s later")
	assert_eq(a.units.size(), b.units.size())
	assert_eq(a.rng.state, b.rng.state)


func test_a_snapshot_of_a_different_army_is_refused() -> void:
	var a := _world()
	var b := _world()
	b.spawn("pike_militia", 1, b.economy.hall_of(1).center + Vector2(80, 0))
	var before := Lockstep.fingerprint(b)
	assert_false(WorldSnapshot.apply(b, WorldSnapshot.capture(a)))
	assert_eq(Lockstep.fingerprint(b), before, "a refused copy changes nothing")
	assert_true(WorldSnapshot.unpack(PackedByteArray([1, 2, 3])).is_empty())


func test_mixed_computers_are_pointed_out() -> void:
	assert_eq(NetSession.mixed_warning([{"platform": "macOS arm64"}, {"platform": "macOS arm64"}]), "")
	assert_true(NetSession.mixed_warning([{"platform": "macOS arm64"}, {"platform": "Windows x86_64"}]).contains("Windows"))


func test_start_message_sets_up_both_computers() -> void:
	var people := [{"id": 1, "name": "Host", "faction": "concord", "hero": "random"},
		{"id": 4711, "name": "Guest", "faction": "random", "hero": "random"}]
	var msg := OnlineGame.make_start(people, 1, "random", 1234)
	var again := OnlineGame.make_start(people, 1, "random", 1234)
	assert_eq(msg, again, "the same roll gives the same match")
	assert_eq(msg["seats"], [1, 4711, -1])
	var setup := SkirmishSetup.from_dict(msg["setup"])
	assert_eq(setup.factions().size(), 3)
	assert_eq(setup.factions()[0], "concord")
	assert_false(setup.factions().has("random"))
	assert_ne(setup.seed_value, 0)
	assert_eq(setup.active_slots()[2]["type"], "computer")
	var guest := NetSession.new("test")
	guest.my_id = 4711
	assert_eq(OnlineGame.begin_from(guest, bytes_to_var(var_to_bytes(msg))), "")
	var g := OnlineGame.current
	assert_eq(g.me, 1)
	assert_eq(g.lockstep.players, [0, 1], "the computer player sends no turns")
	assert_eq(SkirmishSetup.current.seed_value, setup.seed_value)
	var stranger := NetSession.new("test")
	stranger.my_id = 99
	assert_ne(OnlineGame.begin_from(stranger, msg), "")
	OnlineGame.current = null
	SkirmishSetup.current = null


func _pump(sessions: Array, inbox: Array, until: Callable, seconds: float = 3.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		for i in sessions.size():
			(inbox[i] as Array).append_array((sessions[i] as NetSession).poll())
		if until.call():
			return true
		OS.delay_msec(5)
	return false


func _has(box: Array, kind: String) -> bool:
	return box.any(func(m: Dictionary) -> bool: return m["t"] == kind)


func test_host_and_join_on_this_computer() -> void:
	var port := 24790 + Time.get_ticks_usec() % 100
	var host := NetSession.new("test-build")
	var guest := NetSession.new("test-build")
	assert_eq(host.host("Ash", port), "")
	assert_eq(guest.join("127.0.0.1:%d" % port, "Bram"), "")
	var boxes := [[], []]
	assert_true(_pump([host, guest], boxes, func() -> bool: return _has(boxes[1], "welcome") and guest.people.size() == 2),
		"the guest is let in and sees both players")
	assert_eq(host.people[1]["name"], "Bram")
	guest.set_my_pick("hollow", "random")
	assert_true(_pump([host, guest], boxes, func() -> bool: return String(host.people[1]["faction"]) == "hollow"))
	# The start, then a turn's commands each way (the host passes the guest's on).
	var start := OnlineGame.make_start(host.people, 0, "random", 77)
	host.send(start)
	assert_true(_pump([host, guest], boxes, func() -> bool: return _has(boxes[1], "start")))
	host.send({"t": "cmds", "turn": 2, "player": 0, "cmds": []})
	guest.send({"t": "cmds", "turn": 2, "player": 1, "cmds": [{"t": "stop", "ids": [5]}]})
	assert_true(_pump([host, guest], boxes, func() -> bool: return _has(boxes[0], "cmds") and _has(boxes[1], "cmds")))
	var got: Dictionary = boxes[0].filter(func(m: Dictionary) -> bool: return m["t"] == "cmds")[0]
	assert_eq(got["cmds"], [{"t": "stop", "ids": [5]}])
	# Leaving is noticed.
	guest.close()
	assert_true(_pump([host], [boxes[0]], func() -> bool: return _has(boxes[0], "_left")))
	assert_eq(host.people.size(), 1)
	host.close()


func test_a_different_build_is_turned_away() -> void:
	var port := 24890 + Time.get_ticks_usec() % 100
	var host := NetSession.new("build-a")
	var guest := NetSession.new("build-b")
	assert_eq(host.host("Ash", port), "")
	assert_eq(guest.join("127.0.0.1", "Bram", port), "")
	var boxes := [[], []]
	assert_true(_pump([host, guest], boxes, func() -> bool: return _has(boxes[1], "_closed")))
	var closed: Dictionary = boxes[1].filter(func(m: Dictionary) -> bool: return m["t"] == "_closed")[0]
	assert_true(String(closed["reason"]).contains("version"), String(closed["reason"]))
	assert_eq(host.people.size(), 1)
	host.close()


func test_version_names_the_data() -> void:
	var v := NetSession.version()
	assert_true(v.length() > 10)
	assert_eq(v, NetSession.version())
	assert_eq(NetSession.clean_name("  Mara\n  "), "Mara")
