extends "res://tests/test_case.gd"
## Dark Elves (Whisper Web) and Frostmarch (Feast of Victory), and the abilities they brought:
## poison, brace and relentless.

## Whole AI games and sweeps over every faction or template; run with ./run_tests.sh --slow.
const SLOW := ["test_new_factions_are_playable"]


func _first_hit(w: SimWorld, attacker: int) -> float:
	for i in 80:
		w.step()
		for e in w.events:
			if e["type"] == "hit" and e["attacker"] == attacker:
				return float(e["damage"])
	return 0.0


func test_poison_keeps_hurting_after_the_blow() -> void:
	var w := SimWorld.new(5)
	w.setup_map(40, 20)
	var s := w.spawn("de_silk_stalker", 0, Vector2(300, 300))
	var t := w.spawn("bastion_colossus", 1, Vector2(330, 300))
	w.command_hold([t.id])
	w.command_attack([s.id], t.id)
	var hit := _first_hit(w, s.id)
	assert_gt(hit, 0.0, "the stalker struck")
	assert_gt(t.poison_left, 0.0, "the target is poisoned")
	s.alive = false  # no more blows: only the venom works now
	var hp := t.hp
	for i in int(w.tick_rate * 5):
		w.step()
	var pr: Dictionary = w.catalog.rules["poison"]
	var want := hit * float(pr["fraction"])
	assert_between(hp - t.hp, want * 0.9, want * 1.1, "venom deals its share over time")
	assert_eq(t.poison_left, 0.0)


func test_poison_kill_counts_as_a_death() -> void:
	var w := SimWorld.new(5)
	w.setup_map(40, 20)
	var t := w.spawn("pike_militia", 1, Vector2(330, 300))
	t.hp = 1.0
	t.poison_left = 2.0
	t.poison_dps = 10.0
	var died := false
	for i in 40:
		w.step()
		for e in w.events:
			died = died or (e["type"] == "death" and e["unit"] == t.id)
	assert_true(died and not t.alive, "venom kills")


func test_brace_blunts_a_charge() -> void:
	var dmg := []
	for target in ["clan_raider", "de_gloam_spear"]:
		var w := SimWorld.new(9)
		w.setup_map(60, 20)
		var r := w.spawn("tusk_rider", 0, Vector2(200, 300))
		var t := w.spawn(target, 1, Vector2(450, 300))
		w.command_hold([t.id])
		w.command_attack([r.id], t.id)
		dmg.append(_first_hit(w, r.id) / (1.0 - t.defense("melee")))
	var r := SimWorld.new(1).catalog.rules
	var m := float(r["charge"]["multiplier"])
	var braced := 1.0 + (m - 1.0) * float(r["brace"]["charge_bonus_factor"])
	assert_gt(dmg[0] / dmg[1], m / braced * 0.85, "a braced target takes a smaller charge")


func test_relentless_staggers() -> void:
	var w := SimWorld.new(4)
	w.setup_map(40, 20)
	var a := w.spawn("oathless_berserker", 0, Vector2(300, 300))
	var t := w.spawn("pike_militia", 1, Vector2(325, 300))
	w.command_hold([t.id])
	w.command_attack([a.id], t.id)
	_first_hit(w, a.id)
	var st := float(w.catalog.rules["relentless"]["stagger_seconds"])
	assert_gt(t.cooldown, st - 0.06, "a relentless blow staggers the target")


func test_dark_elves_see_farther_and_strike_first() -> void:
	var w := SkirmishScenario.build_skirmish(4, ["darkelf", "concord"])
	for u in w.units:
		u.alive = false
	var de := w.spawn("de_gloam_spear", 0, Vector2(400, 400))
	var co := w.spawn("pike_militia", 1, Vector2(800, 400))
	assert_between(w._sight(de), float(de.def["sight"]) * 1.29, float(de.def["sight"]) * 1.31, "Whisper Web sight")
	assert_eq(w._sight(co), float(co.def["sight"]))
	# The first blow on an unhurt enemy is an ambush; the next one is not.
	co.pos = Vector2(415, 400)
	w.command_hold([co.id])
	w.command_attack([de.id], co.id)
	var first := _first_hit(w, de.id)
	var second := 0.0
	for i in 80:
		w.step()
		for e in w.events:
			if e["type"] == "hit" and e["attacker"] == de.id and second == 0.0:
				second = float(e["damage"])
		if second > 0.0:
			break
	assert_gt(first, second * 1.25, "ambush blow is stronger")


func test_frostmarch_feasts_on_a_kill() -> void:
	var gain := []
	for pair in [["frostmarch", "concord"], ["concord", "frostmarch"]]:
		var w := SkirmishScenario.build_skirmish(4, pair)
		for u in w.units:
			u.alive = false
		var k := w.spawn("clan_raider", 0, Vector2(400, 400))
		var v := w.spawn("pike_militia", 1, Vector2(420, 400))
		k.hp = k.max_hp * 0.4
		v.hp = 1.0
		w.command_hold([v.id])
		w.command_attack([k.id], v.id)
		for i in 60:
			w.step()
			if not v.alive:
				break
		assert_false(v.alive, "the victim fell")
		gain.append(k.hp - k.max_hp * 0.4)
	assert_gt(gain[0], gain[1] + 20.0, "a Frostmarch killer heals, others do not")


func test_new_factions_are_playable() -> void:
	var pf := SkirmishSetup.playable_factions()
	assert_true("darkelf" in pf and "frostmarch" in pf)
	assert_eq(Biomes.for_faction("darkelf"), "gloomcrag")
	var w := SkirmishScenario.build_skirmish(4, ["darkelf", "frostmarch"])
	var ais := [EconomyAi.new(0, "normal"), EconomyAi.new(1, "normal")]
	for i in int(240 * w.tick_rate):
		for a in ais:
			a.update(w)
		w.step()
	for o in 2:
		var trained := 0
		for u in w.units:
			if u.owner == o and u.role() != "worker" and int(u.def["tier"]) > 0:
				trained += 1
		assert_gt(trained, 3, "player %d trains an army" % o)
