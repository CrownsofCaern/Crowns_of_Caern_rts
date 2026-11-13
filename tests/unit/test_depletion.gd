extends "res://tests/test_case.gd"
## Resource piles hold a fixed amount and run dry (economy.json pile_amounts).

## A whole AI game on tiny piles; run with ./run_tests.sh --slow.
const SLOW := ["test_ai_moves_on_when_its_piles_run_dry"]


func _run(w: SimWorld, seconds: float, ais: Array = []) -> void:
	for i in int(seconds * w.tick_rate):
		for ai: EconomyAi in ais:
			ai.update(w)
		w.step()


func _home_piles(eco: Economy, owner: int) -> Array[ResNode]:
	var out: Array[ResNode] = []
	for n in eco.nodes:
		if n.sector == eco.hall_of(owner).id:
			out.append(n)
	return out


func test_piles_start_with_the_listed_amounts() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var pa: Dictionary = eco.e["pile_amounts"]
	var home := eco.hall_of(0).id
	var seen_home := false
	var seen_away := false
	for n in eco.nodes:
		assert_false(n.endless(), "pile %d is finite" % n.id)
		assert_eq(n.amount, n.full)
		var base := int(pa.get(n.resource, pa["rare"]))
		if eco.sectors[n.sector].home_of >= 0:
			assert_eq(n.amount, int(round(base * float(pa["home_factor"]))), "home piles hold more")
			seen_home = seen_home or n.sector == home
		else:
			assert_eq(n.amount, base, "%s pile" % n.resource)
			seen_away = true
	assert_true(seen_home and seen_away)
	assert_eq(eco.pile_amount("crystal"), int(pa["rare"]), "rares share one size")


func test_a_worked_pile_runs_dry_and_its_worker_moves_on() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var pl := eco.player(0)
	var n: ResNode = null
	for m in _home_piles(eco, 0):
		if m.resource == "wood":
			n = m
	assert_true(n != null, "a timber pile at home")
	# Give the home a second timber pile to move on to.
	var spare := eco.add_node(w.nav.nearest_free(eco.hall_of(0).center + Vector2(0, 160)), "wood")
	assert_eq(spare.sector, eco.hall_of(0).id)
	var carry := int(eco.e["gather"]["carry"])
	n.amount = carry + 2  # one full load, then a short one
	n.full = 100
	var ws := eco.workers_of(0)
	for u in ws:
		eco.command_gather([u.id], n.id) if u == ws[0] else eco.command_gather([u.id], spare.id)
	var worker := ws[0]
	var dried := []
	var loads := []
	for i in int(90.0 * w.tick_rate):
		w.step()
		for e in w.events:
			if e["type"] == "pile_depleted":
				dried.append(int(e["node"]))
			if e["type"] == "deposit" and int(e["unit"]) == worker.id and loads.size() < 2:
				loads.append(int(e["amount"]))
	assert_eq(n.amount, 0)
	assert_true(n.depleted())
	assert_eq(dried, [n.id], "one pile ran dry, once")
	assert_eq(eco.sector_remaining(eco.hall_of(0).id).get("wood", 0), spare.amount, "only the spare holds timber now")
	assert_eq(loads, [carry, 2], "a full load, then the short last one is brought home too")
	assert_true(worker.order == SimUnit.Order.GATHER and worker.job != n.id, "the worker found other work")
	assert_eq(eco.live_node(n.id), null)
	assert_true(pl.amount("wood") > 0)
	# An empty pile takes no orders and blocks no building.
	eco.command_gather([worker.id], n.id)
	assert_ne(worker.job, n.id)
	assert_true(eco.notices.size() > 0 and String(eco.notices[-1]["text"]).contains("run dry"))


func test_remaining_sums_the_piles_a_player_holds() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var want := {}
	for r in eco.gather_resources(0):
		want[r] = 0
	for n in eco.nodes:
		if eco.sectors[n.sector].owner == 0 and want.has(n.resource):
			want[n.resource] += n.amount
	assert_eq(eco.remaining(0), want)
	assert_gt(float(want["wood"]), 0.0)
	# An endless pile makes its resource endless; an empty one drops out.
	var home := eco.hall_of(0).id
	var piles := _home_piles(eco, 0)
	var r := piles[0].resource
	piles[0].amount = 0
	var rest := 0
	for n in piles:
		if n.resource == r:
			rest += n.amount
	assert_eq(int(eco.sector_remaining(home).get(r, 0)), rest, "the empty pile drops out")
	eco.add_node(w.nav.nearest_free(eco.hall_of(0).center + Vector2(0, 160)), "ore", -1)
	assert_eq(int(eco.remaining(0)["ore"]), -1)
	assert_eq(int(eco.sector_remaining(home)["ore"]), -1)


func test_snapshots_carry_what_is_left() -> void:
	var a := SkirmishScenario.build_skirmish(4)
	var b := SkirmishScenario.build_skirmish(4)
	a.economy.nodes[3].amount = 17
	assert_ne(Lockstep.fingerprint(a), Lockstep.fingerprint(b), "the fingerprint sees piles")
	assert_true(WorldSnapshot.apply(b, WorldSnapshot.unpack(WorldSnapshot.pack(WorldSnapshot.capture(a)))))
	assert_eq(b.economy.nodes[3].amount, 17)


func test_ai_knows_when_it_runs_short() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var ai := EconomyAi.new(1)
	assert_eq(ai._running_short(eco), [] as Array[String])
	for n in eco.nodes:
		if eco.sectors[n.sector].owner == 1 and n.resource == "wood":
			n.amount = 10
	assert_eq(ai._running_short(eco), ["wood"] as Array[String])


func test_ai_moves_on_when_its_piles_run_dry() -> void:
	var w := SkirmishScenario.build_skirmish(6)
	var eco := w.economy
	for o in 2:
		for n in _home_piles(eco, o):
			n.amount = 150
			n.full = 150
	var ais := [EconomyAi.new(0), EconomyAi.new(1)]
	_run(w, 12.0 * 60.0, ais)
	for o in 2:
		for n in _home_piles(eco, o):
			assert_true(n.depleted(), "home piles ran dry")
		assert_gt(float(eco.sectors_of(o)), 1.0, "player %d took more ground" % o)
		var working := 0
		for u in eco.workers_of(o):
			if u.order == SimUnit.Order.GATHER and eco.live_node(u.job) != null:
				working += 1
		assert_gt(float(working), 0.0, "player %d still has gatherers at work" % o)
