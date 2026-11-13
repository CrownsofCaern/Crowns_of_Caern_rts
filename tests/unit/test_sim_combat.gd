extends "res://tests/test_case.gd"


func _duel(a_type: String, a_n: int, b_type: String, b_n: int, seed_value: int) -> int:
	## Returns the winning side (0 or 1), or -1 when nobody won in time.
	var w := SimWorld.new(seed_value)
	w.setup_map(50, 30)
	var ids_a: Array = []
	for i in a_n:
		ids_a.append(w.spawn(a_type, 0, Vector2(300, 300 + (i - a_n / 2) * 28)).id)
	var ids_b: Array = []
	for i in b_n:
		ids_b.append(w.spawn(b_type, 1, Vector2(1100, 300 + (i - b_n / 2) * 28)).id)
	w.command_attack_move(ids_a, Vector2(1100, 400))
	w.command_attack_move(ids_b, Vector2(300, 400))
	for i in 20 * 120:
		w.step()
		if w.count_alive(0) == 0 or w.count_alive(1) == 0:
			break
	if w.count_alive(1) == 0 and w.count_alive(0) > 0:
		return 0
	if w.count_alive(0) == 0 and w.count_alive(1) > 0:
		return 1
	return -1


## Value of a unit: its gold plus the drafted worker it costs (PERSON_VALUE gold).
const PERSON_VALUE := 15.0


func _value(type_id: String) -> float:
	return float(catalog.get_unit(type_id)["cost"]["gold"]) + PERSON_VALUE


## Equal value on both sides; the counter should win most seeds.
func _counter_wins(winner: String, loser: String, n_win: int) -> void:
	var n_lose := int(round(n_win * _value(winner) / _value(loser)))
	var wins := 0
	for s in [11, 22, 33, 44, 55]:
		if _duel(winner, n_win, loser, n_lose, s) == 0:
			wins += 1
	assert_gt(wins, 3, "%d %s should beat %d %s (won %d of 5)" % [n_win, winner, n_lose, loser, wins])


func test_pikes_beat_cavalry() -> void:
	_counter_wins("pike_militia", "lancer", 16)


func test_cavalry_beats_archers() -> void:
	_counter_wins("lancer", "longbowman", 4)


func test_archers_beat_infantry() -> void:
	_counter_wins("marrow_archer", "shambler", 10)


func test_same_seed_same_battle() -> void:
	var a := SkirmishScenario.build(5, ["concord", "hollow"], 0.3)
	var b := SkirmishScenario.build(5, ["concord", "hollow"], 0.3)
	for w in [a, b]:
		var ids0: Array = []
		var ids1: Array = []
		for u in w.units:
			(ids0 if u.owner == 0 else ids1).append(u.id)
		w.command_attack_move(ids0, Vector2(3000, 1100))
		w.command_attack_move(ids1, Vector2(800, 1100))
		for i in 600:
			w.step()
	assert_eq(a.checksum(), b.checksum())
	assert_lt(a.units.size(), 90, "the battle actually happened")


func test_healer_heals_hurt_ally() -> void:
	var w := SimWorld.new(3)
	w.setup_map(30, 20)
	var h := w.spawn("lightbearer", 0, Vector2(200, 200))
	var a := w.spawn("pike_militia", 0, Vector2(260, 200))
	a.hp = a.max_hp * 0.5
	for i in 40:
		w.step()
	assert_gt(a.hp, a.max_hp * 0.5)
	assert_eq(h.order, SimUnit.Order.IDLE)


func test_charge_doubles_first_hit() -> void:
	var w := SimWorld.new(3)
	w.setup_map(40, 20)
	var l := w.spawn("lancer", 0, Vector2(100, 300))
	var t := w.spawn("bastion_colossus", 1, Vector2(600, 300))
	w.command_attack([l.id], t.id)
	var first := 0.0
	for i in 200:
		w.step()
		for e in w.events:
			if e["type"] == "hit" and e["attacker"] == l.id and first == 0.0:
				first = e["damage"]
	var plain := float(l.def["damage"]) * (1.0 - t.defense("melee"))
	assert_gt(first, plain * 1.6, "charged hit")


func test_curse_weakens_the_target() -> void:
	var w := SimWorld.new(3)
	w.setup_map(40, 20)
	var witch := w.spawn("ash_witch", 0, Vector2(200, 300))
	var t := w.spawn("bastion_colossus", 1, Vector2(330, 300))
	w.command_hold([t.id])
	w.command_attack([witch.id], t.id)
	for i in 60:
		w.step()
		if t.cursed > 0.0:
			break
	assert_gt(t.cursed, 0.0, "the witch's hit curses")
	assert_gt(float(witch.def["range"]), 100.0, "the witch casts from range")
	# A cursed attacker deals curse.damage_factor of its damage.
	var f := float(w.catalog.rules["curse"]["damage_factor"])
	var a := w.spawn("pike_militia", 0, Vector2(600, 300))
	var b := w.spawn("pike_militia", 1, Vector2(620, 300))
	a.cursed = 5.0
	w.command_attack([a.id], b.id)
	var hit := 0.0
	for i in 40:
		w.step()
		for e in w.events:
			if e["type"] == "hit" and e["attacker"] == a.id and hit == 0.0:
				hit = e["damage"]
	var plain := float(a.def["damage"]) * (1.0 - b.defense("melee"))
	assert_lt(hit, plain * f * 1.15, "cursed hit is weaker")
	assert_gt(hit, plain * f * 0.85)
