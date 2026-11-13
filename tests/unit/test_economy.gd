extends "res://tests/test_case.gd"
## M2: sectors, capture, workers, gathering, drafting, building.

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_every_faction_pairing_builds_a_fair_map", "test_ai_builds_trains_and_same_seed_same_game"]


func _run(w: SimWorld, seconds: float, ai: EconomyAi = null) -> void:
	for i in int(seconds * w.tick_rate):
		if ai != null:
			ai.update(w)
		w.step()


func _workers(w: SimWorld, owner: int) -> int:
	return w.economy.workers_of(owner).size()


func test_skirmish_map_is_mirrored_and_fair() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	assert_gt(eco.sectors.size(), 6)
	assert_ne(eco.hall_of(0).id, eco.hall_of(1).id)
	# The homes mirror each other (west/east, or opposite corners).
	var size := w.nav.world_size()
	var h0 := eco.hall_of(0).center
	var h1 := eco.hall_of(1).center
	assert_lt(minf(h0.distance_to(Vector2(size.x - h1.x, h1.y)), h0.distance_to(size - h1)), 40.0, "homes mirror")
	assert_eq(_workers(w, 0), 4)
	assert_eq(_workers(w, 1), 4)
	# Each side gets the same number of piles it can use.
	var usable := [0, 0]
	for n in eco.nodes:
		for o in 2:
			if eco.uses(o, n.resource):
				usable[o] += 1
		assert_false(w.nav.is_blocked(n.pos), "pile %d is in rock" % n.id)
	assert_eq(usable[0], usable[1], "usable piles")
	for s in eco.sectors:
		var total := 0
		for n in eco.nodes:
			if n.sector == s.id:
				total += 1
		if s.home_of >= 0:
			assert_gt(total, 1, "a home has piles of its own")
	# Neutral settlements are guarded.
	var militia := 0
	for u in w.units:
		if u.owner == Economy.NEUTRAL:
			militia += 1
	assert_gt(militia, 0)


func test_workers_gather_and_deliver() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var pl := w.economy.player(0)
	var wood0 := pl.amount("wood")
	var ore0 := pl.amount("ore")
	_run(w, 40.0)
	assert_gt(pl.amount("wood") + pl.amount("ore"), wood0 + ore0 + 30, "resources came in")
	assert_gt(pl.amount("gold"), 300, "the town pays gold")


func test_capture_needs_the_militia_gone() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var target: Sector = null
	for s in eco.sectors:
		if s.owner == -1 and s.size != "waystone":
			target = s
			break
	assert_true(target != null)
	var ids: Array = []
	for i in 30:
		ids.append(w.spawn("pike_militia", 0, target.center + Vector2(-200 + (i % 6) * 20, -40 + (i / 6) * 20)).id)
	w.command_attack_move(ids, target.center)
	var t := eco.capture_seconds(target)
	_run(w, t + 30.0)
	var left := 0
	for u in w.units:
		if u.owner == Economy.NEUTRAL and u.pos.distance_to(target.center) < 300.0:
			left += 1
	assert_eq(left, 0, "militia beaten")
	assert_eq(target.owner, 0, "captured")
	assert_gt(target.unsettled, 0.0, "a fresh capture is unsettled")


func test_militia_defend_their_village_then_return() -> void:
	# Village militia go for an enemy that comes near (not only one in pike reach), and
	# walk back to their posts once it is gone.
	var w := SkirmishScenario.build_skirmish(4)
	var m: SimUnit = null
	for u in w.units:
		if u.owner == Economy.NEUTRAL and u.type_id == "militia":
			m = u
			break
	assert_true(m != null, "a village has militia")
	var post := m.anchor
	var centre := w.economy.sector_at(post).center
	var out := (post - centre).normalized()
	var foe := w.spawn("pike_militia", 0, post + out * 150.0)
	w.command_hold([foe.id])
	_run(w, 5.0)
	assert_lt(foe.hp, foe.max_hp, "the militia attack an intruder near the village")
	assert_gt(m.pos.distance_to(post), 20.0, "they left their post to fight")
	foe.alive = false
	_run(w, 12.0)
	assert_lt(m.pos.distance_to(post), 20.0, "back at the post afterwards")
	assert_eq(m.order, SimUnit.Order.IDLE)


func test_waystone_capture_gives_no_workers() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var s: Sector = null
	for x in eco.sectors:
		if x.home_of < 0 and s == null:
			s = x
	s.size = "waystone"
	for u in w.units:
		if u.owner == Economy.NEUTRAL:
			u.alive = false
	w.spawn("pike_militia", 0, s.center + Vector2(20, 0))
	_run(w, 16.0)
	assert_eq(s.owner, 0)
	_run(w, 70.0)
	for x in w.units:
		assert_ne(x.home_sector, s.id, "waystones never spawn workers")


func test_training_drafts_a_worker() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b: Building = null
	for x in eco.buildings:
		if x.owner == 0:
			b = x
	assert_true(b != null and b.done(), "a dwelling stands from the start")
	assert_true(eco.command_train(0, b.id))
	_run(w, 40.0)
	var trained := 0
	for u in w.units:
		if u.owner == 0 and u.type_id == b.unit_type:
			trained += 1
	assert_eq(trained, 1)


func test_training_starts_at_once_and_the_worker_goes_home() -> void:
	# Drafting starts the clock at once; the worker walks to its nearest centre, not to
	# the dwelling, and leaves there. It is not counted twice against the population.
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b: Building = null
	for x in eco.buildings:
		if x.owner == 0 and x.kind == "dwelling":
			b = x
	var before := eco.people(0)
	assert_true(eco.command_train(0, b.id))
	_run(w, 0.5)
	assert_true(b.has_recruit, "training runs at once")
	assert_lt(b.train_left, b.train_total, "the clock already ticks")
	assert_eq(eco.people(0), before, "the drafted worker is not counted twice")
	var drafted: SimUnit = null
	for u in w.units:
		if u.owner == 0 and u.alive and u.order == SimUnit.Order.DRAFT:
			drafted = u
	if drafted != null:
		assert_eq(drafted.job, -1, "it is not sent to the dwelling")
	_run(w, 30.0)
	for u in w.units:
		assert_ne(u.order, SimUnit.Order.DRAFT, "no worker still on its way after 30 s")


func test_hall_level_gates_tiers_and_placement_rules() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var home := eco.hall_of(0)
	var ids: Array = []
	for u in eco.workers_of(0):
		ids.append(u.id)
	eco.player(0).res["gold"] = 5000
	eco.player(0).res["wood"] = 5000
	eco.player(0).res["ore"] = 5000
	var r := float(eco.e["dwelling"]["radius"])
	var spot := EconomyAi.find_spot(eco, home, r)
	assert_true(eco.command_build(ids, 0, "dwelling", 3, spot) == null, "tier 3 needs hall level 2")
	assert_false(eco.can_place(0, home.center, r), "not on the settlement")
	assert_false(eco.can_place(0, eco.hall_of(1).center + Vector2(450, 0), r), "not in enemy land")
	eco.player(0).hall_level = 2
	var b := eco.command_build(ids, 0, "dwelling", 3, spot)
	assert_true(b != null)
	assert_false(b.done())
	_run(w, 40.0)
	assert_true(b.done(), "workers built it")
	assert_true(w.nav.is_blocked(b.pos), "buildings block the ground")


func test_upgrade_settlement_grows_it() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var s: Sector = null
	for x in eco.sectors:
		if x.owner == -1 and x.size == "hamlet":
			s = x
	assert_true(s != null)
	s.owner = 0
	eco.player(0).res["gold"] = 5000
	assert_true(eco.command_upgrade_settlement(0, s.id))
	_run(w, float(eco.e["settlement_upgrade"]["seconds"]) + 1.0)
	assert_eq(s.size, "village")


func test_ai_builds_trains_and_same_seed_same_game() -> void:
	var sums: Array = []
	for run in 2:
		var w := SkirmishScenario.build_skirmish(6)
		var ai := EconomyAi.new(1)
		_run(w, 150.0, ai)
		var soldiers := 0
		for u in w.units:
			if u.owner == 1 and not u.is_worker() and not u.is_hero():
				soldiers += 1
		assert_gt(soldiers, 2, "AI trained an army")
		assert_true(w.economy.player(1).hall_level > 1 or w.economy.player(1).hall_upgrading > 0.0,
			"AI raised its hall for its next dwelling")
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])


func test_hollow_raise_tier_one_without_workers() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b: Building = null
	for x in eco.buildings:
		if x.owner == 1 and x.tier == 1:
			b = x
	var workers0 := _workers(w, 1)
	eco.player(1).res["gold"] = 1000
	assert_true(eco.command_train(1, b.id))
	assert_true(eco.command_train(1, b.id))
	_run(w, 45.0)
	var raised := 0
	for u in w.units:
		if u.owner == 1 and u.type_id == b.unit_type:
			raised += 1
	assert_eq(raised, 2)
	assert_true(_workers(w, 1) >= workers0, "no worker was drafted")


func test_concord_settlements_hold_longer() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var home := eco.hall_of(0)  # Concord
	for u in eco.workers_of(0):
		u.alive = false
	w.spawn("shambler", 1, home.center + Vector2(30, 0))
	var t := float(eco.settlement(home)["capture_time"]) / float(eco.e["capture_speed"])  # an ordinary settlement's time
	_run(w, t)
	assert_eq(home.owner, 0, "not taken in the normal time")
	assert_lt(home.capture, 0.8, "only about two thirds done")


func test_ashen_plunder_settlements_they_take() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["ashen", "concord"])
	var eco := w.economy
	assert_eq(eco.player(0).faction, "ashen")
	var target: Sector = null
	for s in eco.sectors:
		if s.owner == -1 and s.size != "waystone":
			target = s
			break
	for u in w.units:
		if u.owner == Economy.NEUTRAL:
			u.alive = false
	w.spawn("flayer", 0, target.center + Vector2(30, 0))
	var t := eco.capture_seconds(target)
	var paid := 0
	for i in int((t + 2.0) * w.tick_rate):
		var before := eco.player(0).amount("gold")
		w.step()
		for e in w.events:
			if e["type"] == "plunder":
				paid = int(e["gold"])
				assert_gt(eco.player(0).amount("gold"), before + paid - 1, "plunder paid into the stockpile")
	assert_eq(target.owner, 0, "captured")
	assert_eq(paid, int(eco.e["twists"]["ashen"]["plunder"][target.size]))
	assert_gt(paid, 0)


func test_every_faction_pairing_builds_a_fair_map() -> void:
	var cat := UnitCatalog.get_default()
	var fs: Array = cat.factions.filter(func(f: String) -> bool: return f != "neutral")
	assert_true("ashen" in fs)
	for a in fs:
		for b in fs:
			if a == b:
				continue
			var w := SkirmishScenario.build_skirmish(7, [a, b])
			assert_eq(w.economy.player(1).faction, b)
			assert_eq(w.economy.workers_of(0).size(), w.economy.workers_of(1).size(), "%s vs %s workers" % [a, b])
			for n in w.economy.nodes:
				var ok := n.resource in ["wood", "ore"] or w.economy.uses(0, n.resource) or w.economy.uses(1, n.resource)
				assert_true(ok, "%s vs %s: %s pile someone can use" % [a, b, n.resource])


func test_ai_difficulty_changes_pace() -> void:
	var easy := EconomyAi.new(1, "easy")
	var hard := EconomyAi.new(1, "hard")
	var odd := EconomyAi.new(1, "nonsense")
	assert_eq(odd.difficulty, "normal")
	assert_lt(hard.think_every, easy.think_every)
	assert_lt(hard.army_to_attack, easy.army_to_attack)
	assert_eq(EconomyAi.new(1).think_every, odd.think_every)


## Open ground at a settlement that is nobody's capital (troops resting at a capital mend: rest_heal).
func _open_ground(w: SimWorld) -> Vector2:
	for s in w.economy.sectors:
		if s.home_of < 0:
			return s.center
	return Vector2.INF


func test_thornwood_heals_beside_the_woods() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["thornwood", "concord"])
	var forest := Vector2i(-1, -1)
	for y in w.nav.height:
		for x in w.nav.width:
			if forest.x < 0 and w.nav.kind_at(Vector2i(x, y)) == NavGrid.Kind.FOREST \
					and w.nav.kind_at(Vector2i(x + 1, y)) == NavGrid.Kind.GROUND:
				forest = Vector2i(x, y)
	assert_true(forest.x >= 0, "map has woods")
	var by_wood := w.nav.center_of(forest + Vector2i(1, 0))
	var a := w.spawn("barkhide_warden", 0, by_wood)
	var b := w.spawn("barkhide_warden", 0, _open_ground(w))  # a settlement away from the capital (which mends)
	for u in [a, b]:
		u.hp = u.max_hp * 0.5
	w.command_hold([a.id, b.id])
	for u in w.units:
		if u.owner != 0:
			u.alive = false  # nobody to fight
	_run(w, 5.0)
	assert_gt(a.hp, a.max_hp * 0.55, "Thornwood heals by the woods")
	assert_lt(b.hp, b.max_hp * 0.51, "but not in the open")
	# Other factions have no Wildwalk.
	var w2 := SkirmishScenario.build_skirmish(4, ["concord", "thornwood"])
	var c := w2.spawn("pike_militia", 0, by_wood)
	c.hp = c.max_hp * 0.5
	for u in w2.units:
		if u.owner != 0:
			u.alive = false
	_run(w2, 5.0)
	assert_lt(c.hp, c.max_hp * 0.51, "Concord does not heal there")


func test_forge_marches_faster_on_roads() -> void:
	var dist := []
	for pair in [["forge", "concord"], ["concord", "forge"]]:
		var w := SkirmishScenario.build_skirmish(4, pair)
		var seg: Array = SkirmishScenario.roads(w.economy)[0]
		for u in w.units:
			u.alive = false
		var a := w.spawn("forge_thrall", 0, (seg[0] as Vector2).lerp(seg[1], 0.3))
		var start := a.pos
		w.command_move([a.id], (seg[0] as Vector2).lerp(seg[1], 0.7))
		_run(w, 1.0)
		dist.append(a.pos.distance_to(start))
	assert_gt(dist[1], 10.0, "the unit moved")
	assert_gt(dist[0], dist[1] * 1.3, "Forge (owner 0 in the first map) is faster on the road")


func test_fishmen_heal_beside_water() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["fishmen", "concord"], "twin_bridges")
	var water := Vector2i(-1, -1)
	for y in w.nav.height:
		for x in w.nav.width:
			if water.x < 0 and w.nav.kind_at(Vector2i(x, y)) == NavGrid.Kind.WATER \
					and w.nav.kind_at(Vector2i(x + 1, y)) == NavGrid.Kind.GROUND:
				water = Vector2i(x, y)
	assert_true(water.x >= 0, "map has ponds")
	for u in w.units:
		if u.owner != 0:
			u.alive = false
	var a := w.spawn("fm_shellback", 0, w.nav.center_of(water + Vector2i(1, 0)))
	var b := w.spawn("fm_shellback", 0, _open_ground(w))
	for u in [a, b]:
		u.hp = u.max_hp * 0.5
	w.command_hold([a.id, b.id])
	_run(w, 5.0)
	assert_gt(a.hp, a.max_hp * 0.55, "Fish-men heal by the water")
	assert_lt(b.hp, b.max_hp * 0.51, "but not away from it")


func test_thornwood_timber_loads_are_bigger() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["thornwood", "concord"])
	var f := float(w.economy.e["twists"]["thornwood"]["gather_factor"]["wood"])
	assert_gt(f, 1.0)
	var got := {0: 0, 1: 0}
	for i in int(120.0 * w.tick_rate):
		w.step()
		for e in w.events:
			if e["type"] == "deposit" and e["resource"] == "wood":
				got[e["owner"]] = maxi(got[e["owner"]], int(e["amount"]))
	assert_eq(got[1], int(w.economy.e["gather"]["carry"]), "Concord carries a normal load")
	assert_eq(got[0], int(round(got[1] * f)), "Thornwood's load counts for more")


func test_half_taken_settlement_recovers_when_the_takers_leave() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var target: Sector = null
	for s in eco.sectors:
		if s.owner == -1 and s.size == "waystone":
			target = s
			break
	assert_true(target != null)
	var u := w.spawn("pike_militia", 0, target.center)
	var t := eco.capture_seconds(target)
	_run(w, t * 0.5)
	assert_gt(target.capture, 0.3, "being taken")
	assert_eq(target.capturer, 0)
	w.command_move([u.id], target.center + Vector2(float(eco.e["capture_radius"]) + 300.0, 0))
	_run(w, t * 0.6 + 5.0)
	assert_eq(target.capture, 0.0, "the bar runs back down once nobody is taking it")
	assert_eq(target.capturer, -1, "and the taker is forgotten")
	assert_eq(target.owner, -1)


func test_capturing_is_quicker_than_the_listed_time() -> void:
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var target: Sector = null
	for s in eco.sectors:
		if s.owner == -1 and s.size == "waystone":
			target = s
			break
	var listed := float(eco.settlement(target)["capture_time"])
	assert_lt(eco.capture_seconds(target), listed * 0.8, "capture_speed shortens every capture")
	w.spawn("pike_militia", 0, target.center)
	_run(w, listed * 0.8)
	assert_eq(target.owner, 0, "taken well before the listed time")


func test_queued_recruits_line_up_at_the_rally_point() -> void:
	# A queue of recruits each takes its own place by the rally point instead of
	# shoving for the same spot.
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	var b: Building = null
	for x in eco.buildings:
		if x.owner == 0:
			b = x
	eco.player(0).res["gold"] = 5000
	for i in 4:
		eco.command_train(0, b.id)
	_run(w, 150.0)
	var men: Array = []
	for u in w.units:
		if u.owner == 0 and u.type_id == b.unit_type:
			men.append(u)
	assert_gt(men.size(), 2, "several recruits trained")
	for u: SimUnit in men:
		assert_eq(u.order, SimUnit.Order.IDLE, "each recruit got where it was sent")
		assert_lt(u.pos.distance_to(b.rally), 120.0, "near the rally point")
		for o: SimUnit in men:
			if u.id < o.id:
				assert_gt(u.pos.distance_to(o.pos), u.radius() + o.radius() - 2.0, "no two stand on one spot")


func test_an_abandoned_building_site_gets_a_worker_at_once() -> void:
	# From playtests: placed unit buildings sometimes got no worker. A site nobody works on (its
	# builder was drafted, killed or sent away) takes the nearest free worker straight away.
	var w := SkirmishScenario.build_skirmish(4)
	var eco := w.economy
	for r in ["gold", "wood", "ore"]:
		eco.player(0).res[r] = 5000
	var spot := EconomyAi.find_spot(eco, eco.hall_of(0), float(eco.e["storehouse"]["radius"]))
	var b := eco.command_build([], 0, "storehouse", 0, spot)  # placed with no worker at all
	assert_true(b != null, "the site is placed: %s" % str(eco.notices))
	if b == null:
		return
	_run(w, 1.0)
	var builders := 0
	for u in eco.workers_of(0):
		if u.order == SimUnit.Order.BUILD and u.job == b.id:
			builders += 1
	assert_eq(builders, 1, "one worker answers, the rest keep gathering")
	_run(w, 40.0)
	assert_true(b.done(), "and builds it")


func test_every_dwelling_gets_its_recruit() -> void:
	# From playtests: some unit buildings never got a worker. The nearest free spot to a tier-5
	# dwelling's door lay just past the old "arrived" distance, so the recruit stood
	# there for good. Every slot, two factions, must train its first unit.
	for fac in ["ashen", "forge"]:
		var w := SkirmishScenario.build_skirmish(5, [fac, "concord"])
		var eco := w.economy
		for r in eco.player(0).res:
			eco.player(0).res[r] = 50000
		eco.player(0).hall_level = 4
		var home := eco.hall_of(0)
		var sites: Array = []
		for t in [3, 5, 6, 7, 8]:
			var b := eco.command_build([], 0, "dwelling", t,
				EconomyAi.find_spot(eco, home, float(eco.e["dwelling"]["radius"])))
			if b != null:
				b.progress = 1.0
				sites.append(b)
		_run(w, 2.0)
		for b: Building in sites:
			eco.command_train(0, b.id)
		_run(w, 60.0)
		for b: Building in sites:
			assert_gt(int(eco.player(0).trained.get(b.unit_type, 0)), 0,
				"%s %s trained its unit" % [fac, b.key])
