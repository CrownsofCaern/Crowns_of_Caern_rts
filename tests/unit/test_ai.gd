extends "res://tests/test_case.gd"
## The computer player's judgement (EconomyAi): strength estimates, taking free land fast,
## keeping hurt veterans alive, calling back a losing wave, the difficulty levels, and the
## slow mending of troops resting at their capital (rules.json rest_heal).

func _run(w: SimWorld, seconds: float, ais: Array = []) -> void:
	for i in int(seconds * w.tick_rate):
		for ai in ais:
			ai.update(w)
		w.step()


## A two-house skirmish with the computer's own economy switched off, so only its army moves.
func _war_only(level: String) -> Array:
	var w := SkirmishScenario.build_skirmish(11, ["concord", "hollow"])
	var ai := EconomyAi.new(1, level)
	return [w, ai]


## One think right now (the AI otherwise waits think_every between them); a world step first
## so the spatial grid knows freshly spawned units.
func _think(w: SimWorld, ai: EconomyAi) -> void:
	w.step()
	ai._timer = 0.0
	ai.update(w)


func _soldiers(w: SimWorld, type_id: String, owner: int, at: Vector2, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(w.spawn(type_id, owner, at + Vector2(float(i % 4) * 22.0, float(i / 4) * 22.0)))
	return out


func test_every_level_validates_and_loads() -> void:
	var errors := UnitCatalog.get_default().validate()
	assert_eq(errors.size(), 0, ", ".join(errors))
	for d in EconomyAi.DIFFICULTIES:
		assert_true(d in SkirmishSetup.DIFFICULTIES, "%s is offered in the setup" % d)
		assert_true(SkirmishSetup.DIFFICULTY_NAMES.has(d), "%s has a name" % d)
		assert_eq(EconomyAi.new(1, d).difficulty, d)
	var normal := EconomyAi.new(1, "normal")
	var very := EconomyAi.new(1, "very_hard")
	var brutal := EconomyAi.new(1, "brutal")
	assert_lt(very.think_every, normal.think_every, "very hard thinks faster")
	assert_gt(float(very.expand), float(EconomyAi.new(1, "easy").expand), "and takes more land at once")
	assert_eq(very.income_bonus, 0.0, "very hard plays fair")
	assert_gt(brutal.income_bonus, 0.0, "brutal gathers more")


func test_power_counts_numbers_ranks_and_wounds() -> void:
	var w := SimWorld.new(3)
	w.setup_map(40, 30)
	var one := _soldiers(w, "pike_militia", 0, Vector2(100, 100), 1)
	var four := _soldiers(w, "pike_militia", 0, Vector2(300, 100), 4)
	var p1 := EconomyAi.power_of(one)
	var p4 := EconomyAi.power_of(four)
	assert_between(p4 / p1, 3.9, 4.1, "four alike are four times as strong")
	var vet := _soldiers(w, "pike_militia", 0, Vector2(100, 300), 1)
	w.set_veteran(vet[0], 4)
	assert_gt(EconomyAi.power_of(vet), p1 * 1.15, "a hardened veteran is worth more")
	(one[0] as SimUnit).hp *= 0.25
	assert_between(EconomyAi.power_of(one) / p1, 0.45, 0.55, "a unit at a quarter health: half the strength")
	assert_eq(EconomyAi.power_of([]), 0.0)


func test_squads_take_free_settlements_at_once() -> void:
	var w := SkirmishScenario.build_skirmish(11, ["concord", "hollow"])
	var eco := w.economy
	var home := eco.hall_of(1)
	_soldiers(w, "lancer", 1, home.center + Vector2(0, 120), 8)
	var ai := EconomyAi.new(1, "hard")
	var before := eco.sectors_of(1)
	_think(w, ai)
	assert_gt(float(ai._squads.size()), 0.0, "squads leave on the first think, long before a wave of 10")
	var capturing := 0
	for u in w.units:
		if u.owner == 1 and u.order == SimUnit.Order.CAPTURE:
			capturing += 1
	assert_gt(float(capturing), 0.0)
	assert_lt(float(capturing), 8.0, "only as many as the militia there call for")
	_run(w, 150.0, [ai])
	assert_gt(float(eco.sectors_of(1)), float(before), "free land taken within two and a half minutes")


func test_hurt_veterans_go_home_and_rest() -> void:
	var r := _war_only("very_hard")
	var w: SimWorld = r[0]
	var ai: EconomyAi = r[1]
	var home := w.economy.hall_of(1)
	var away := w.economy.hall_of(0).center.lerp(home.center, 0.5)
	var squad := _soldiers(w, "lancer", 1, away, 4)
	var vet: SimUnit = squad[0]
	var green: SimUnit = squad[1]
	w.set_veteran(vet, 3)
	vet.hp = vet.max_hp * 0.2
	green.hp = green.max_hp * 0.2
	_think(w, ai)
	assert_eq(vet.order, SimUnit.Order.RETREAT, "the hurt veteran runs home")
	assert_ne(green.order, SimUnit.Order.RETREAT, "a hurt recruit is not worth the trip at this level")
	assert_true(ai._resting.has(vet.id))
	# It rests at the capital until it is fit: slowly, through rest_heal.
	_run(w, 40.0, [ai])
	assert_true(vet.pos.distance_to(home.center) < 500.0, "home")
	var hp := vet.hp
	_run(w, 30.0, [ai])
	assert_gt(vet.hp, hp, "mending at the capital")
	assert_true(ai._resting.has(vet.id), "still resting: the capital heals slowly")
	vet.hp = vet.max_hp * 0.95
	_think(w, ai)
	assert_false(ai._resting.has(vet.id), "fit again: back in the army")


func test_protect_rank_follows_the_level() -> void:
	for level in ["easy", "normal"]:
		var r := _war_only(level)
		var w: SimWorld = r[0]
		var ai: EconomyAi = r[1]
		var away := w.economy.hall_of(0).center.lerp(w.economy.hall_of(1).center, 0.5)
		var vet: SimUnit = _soldiers(w, "lancer", 1, away, 1)[0]
		w.set_veteran(vet, 3)
		vet.hp = vet.max_hp * 0.2
		_think(w, ai)
		assert_ne(vet.order, SimUnit.Order.RETREAT, "%s leaves a rank-3 unit where it is" % level)


func test_a_losing_wave_falls_back() -> void:
	var r := _war_only("hard")
	var w: SimWorld = r[0]
	var ai: EconomyAi = r[1]
	var eco := w.economy
	var mid := eco.hall_of(0).center.lerp(eco.hall_of(1).center, 0.5)
	var wave := _soldiers(w, "pike_militia", 1, mid, 4)
	_soldiers(w, "lancer", 0, mid + Vector2(-120, 0), 12)
	var ids: Array = []
	for u: SimUnit in wave:
		ids.append(u.id)
	w.command_attack_move(ids, eco.hall_of(0).center)
	ai._wave_target = eco.hall_of(0).id
	ai.expand = 0
	_think(w, ai)
	for u: SimUnit in wave:
		assert_eq(u.order, SimUnit.Order.RETREAT, "four pikes do not take on twelve lancers")
	assert_eq(ai._wave_target, -1)
	assert_gt(float(ai._calm_until), float(w.tick), "and the next wave waits a while")


func test_no_wave_into_a_stronger_garrison() -> void:
	var r := _war_only("very_hard")
	var w: SimWorld = r[0]
	var ai: EconomyAi = r[1]
	var eco := w.economy
	var home := eco.hall_of(1)
	var army := _soldiers(w, "pike_militia", 1, home.center + Vector2(0, 150), 12)
	ai.army_to_attack = 12
	ai.expand = 0
	# Every settlement not ours gets a garrison far stronger than twelve pikes.
	for s in eco.sectors:
		if s.owner != 1:
			_soldiers(w, "lancer", 0, s.center, 14)
	_think(w, ai)
	for u: SimUnit in army:
		assert_ne(u.order, SimUnit.Order.ATTACK_MOVE, "it waits rather than feed the enemy")
	assert_eq(ai._wave_target, -1)


func test_rest_heal_is_slow_and_only_at_home() -> void:
	var w := SkirmishScenario.build_skirmish(11, ["concord", "hollow"])
	var home := w.economy.hall_of(0)
	for u in w.units:
		if u.owner == Economy.NEUTRAL:
			u.alive = false  # no militia to pick a fight with the unit out in the field
	var resting: SimUnit = _soldiers(w, "pike_militia", 0, home.center + Vector2(0, 160), 1)[0]
	var away: SimUnit = _soldiers(w, "pike_militia", 0, home.center.lerp(w.economy.hall_of(1).center, 0.5), 1)[0]
	var struck: SimUnit = _soldiers(w, "pike_militia", 0, home.center + Vector2(160, 0), 1)[0]
	for u: SimUnit in [resting, away, struck]:
		u.hp = u.max_hp * 0.5
	for i in 10 * w.tick_rate:
		struck.since_hit = 0.0  # in a fight: no rest
		w.step()
	var rate := float(UnitCatalog.get_default().rules["rest_heal"]["per_second"])
	assert_between(resting.hp_ratio(), 0.5 + rate * 8.0, 0.5 + rate * 12.0, "about per_second x 10 s")
	assert_lt(rate, 0.01, "very slowly: the healing buildings are the fast way")
	assert_between(away.hp_ratio(), 0.499, 0.501, "nothing away from the capital")
	assert_between(struck.hp_ratio(), 0.499, 0.501, "nothing while being hit")


func test_brutal_income_bonus_pays_more() -> void:
	var w := SkirmishScenario.build_skirmish(11, ["concord", "concord"])
	var ai := EconomyAi.new(1, "brutal")
	ai.update(w)
	assert_eq(w.economy.player(1).income_bonus, ai.income_bonus)
	assert_eq(w.economy.player(0).income_bonus, 0.0)
	_run(w, 120.0)
	var a: Dictionary = w.economy.player(0).gathered
	var b: Dictionary = w.economy.player(1).gathered
	assert_gt(float(b.get("gold", 0)), float(a.get("gold", 0)) * 1.15, "more gold")
	assert_gt(float(b.get("wood", 0)), float(a.get("wood", 0)) * 1.1, "more timber")

