extends "res://tests/test_case.gd"
## Story skill tree talents (StoryTrees.TALENTS, carried out by HeroSystem) and the skills the
## trees added: Resurrection, Raise the Fallen, Corpse Burst, Call to Arms, Challenge, Chain
## Lightning, Steam Blast, Riptide, Purify, Blood Price.

var st: StoryTrees = StoryTrees.get_default()
var hc: HeroCatalog = HeroCatalog.get_default()


func _world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 40)
	return w


func _step(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


## A hero for owner 0 that stands still (it never swings on its own), with these talents and,
## if given, `skill` at rank 3 in slot Q.
func _hero(w: SimWorld, class_id: String, talents: Dictionary = {}, skill: String = "") -> SimUnit:
	var u := w.heroes.spawn_hero(0, class_id, Vector2(400, 400))
	var h := u.hero
	h.autocast = [false, false, false, false]
	h.auto_learn = false
	h.talents = talents
	w.heroes.has_talents = true
	if skill != "":
		h.kit[0] = skill
		h.ranks[0] = 3
	h.max_mana = 500.0
	h.mana = 500.0
	u.passive = true
	return u


## Kills a unit at once and lets the heroes see the death (as a tick would).
func _kill(w: SimWorld, t: SimUnit, by: int) -> void:
	w.events.clear()
	w.deal_damage(t, 999999.0, by)
	w.heroes.step()


## Living units of a side (count_alive also counts the dead until the next tick).
func _living(w: SimWorld, owner: int) -> int:
	var n := 0
	for u: SimUnit in w.units:
		if u.alive and u.owner == owner:
			n += 1
	return n


func _held(w: SimWorld, type_id: String, owner: int, p: Vector2) -> SimUnit:
	var t := w.spawn(type_id, owner, p)
	w.command_hold([t.id])
	return t


# --- Data --------------------------------------------------------------------------

func test_no_plain_stat_passives() -> void:
	# Design decision: no more "+1 defense" nodes. A passive is a talent or an army aura.
	for nid in st.nodes:
		var n: Dictionary = st.nodes[nid]
		if n["kind"] != "passive" or n.has("talent"):
			continue
		for k in n.get("mods", {}):
			assert_true(String(k).begins_with("aura_"), "%s is a plain stat node (%s)" % [nid, k])


func test_every_talent_is_used() -> void:
	var used := {}
	for nid in st.nodes:
		if st.nodes[nid].has("talent"):
			used[st.nodes[nid]["talent"]["type"]] = true
	for type in StoryTrees.TALENTS:
		assert_true(used.has(type), "talent %s is in no tree" % type)
	for type in StoryTrees.MIN_TALENTS:
		assert_true(StoryTrees.TALENTS.has(type), type)


func test_every_tree_has_three_actives_and_a_clear_text() -> void:
	var seen := {}
	for tid in st.trees:
		var n_active := 0
		for n: Dictionary in st.trees[tid]["nodes"]:
			if n["kind"] == "active":
				n_active += 1
				assert_false(seen.has(n["skill"]), "%s is in two trees" % n["skill"])
				seen[n["skill"]] = true
		assert_eq(n_active, 3, tid)
		assert_gt(String(st.trees[tid]["text"]).length(), 20.0, tid)


func test_talent_text() -> void:
	var n: Dictionary = st.nodes["honed_edge"]
	var line := StoryTrees.talent_text(n, 2)
	assert_true(line.contains("15% / [25%] / 35%"), line)
	assert_true(line.contains("30% health"), line)
	assert_eq(StoryTrees.format_value("heavy_blow", 3.0), "3rd")
	assert_eq(StoryTrees.format_value("echo", 5.0), "5th")
	assert_eq(StoryTrees.format_value("undying", 90.0), "90 s")
	assert_eq(StoryTrees.format_value("army_regen", 1.5), "1.5")
	for nid in st.nodes:
		if st.nodes[nid].has("talent"):
			assert_false(StoryTrees.talent_text(st.nodes[nid], 1).contains("%"  + "s"), nid)


func test_talents_add_up_and_keep_the_shortest_wait() -> void:
	var s := StoryHero.new("grovewarden")  # bulwark, vigil and wild
	s.ranks = {"plated": 1, "barkskin": 2, "immovable": 2}
	var t := s.talents()
	assert_between(float(t["thorns"]), 0.319, 0.321, "0.15 + 0.17")
	assert_eq(float(t["undying"]), 70.0)
	var o := StoryHero.new("oracle")  # grace, sanctuary and oath: two soldier-saving talents
	o.ranks = {"mercy": 2, "chaplain": 1}
	assert_eq(float(o.talents()["ally_undying"]), 45.0, "the shorter wait wins")


func test_old_saves_get_their_points_back() -> void:
	var d := {"class_id": "templar", "level": 20, "xp": 0, "points": 0,
		"ranks": {"butcher": 3, "honed_edge": 3, "cleave": 2}, "slots": ["judgement", "cleave", "ghost_skill", ""]}
	var s := StoryHero.from_dict(d)
	assert_eq(s.points, 3, "Butcher is gone: its 3 points come back")
	assert_false(s.ranks.has("butcher"))
	assert_eq(s.rank("honed_edge"), 3)
	assert_eq(s.slots, ["judgement", "cleave", "", ""])
	var n := StoryHero.from_dict({"class_id": "necromancer", "level": 20, "xp": 0, "points": 1,
		"ranks": {"dominion": 3}, "slots": ["", "", "", ""]})
	assert_eq(n.rank("dominion"), 2, "Dominion has 2 ranks now")
	assert_eq(n.points, 2)


func test_story_hero_brings_its_talents_into_battle() -> void:
	var s := StoryHero.new("templar")
	s.add_xp(100000)
	for n: Dictionary in st.trees["slaughter"]["nodes"]:
		if int(n["row"]) == 0:
			s.learn(n["id"])
	var w := _world()
	var u := w.heroes.spawn_story_hero(0, s, Vector2(400, 400))
	assert_true(u.hero.talents.has("execute"))
	assert_true(u.hero.talents.has("lifesteal"))
	assert_true(w.heroes.has_talents)


# --- Blows and wounds --------------------------------------------------------------

func test_damage_bonuses() -> void:
	var w := _world()
	var u := _hero(w, "templar", {"execute": 0.3, "first_strike": 0.5, "berserk": 0.2})
	var t := w.spawn("pike_militia", 1, Vector2(430, 400))
	assert_between(w.heroes.damage_factor(u, t), 1.49, 1.51, "an unhurt target")
	t.hp = t.max_hp * 0.2
	assert_between(w.heroes.damage_factor(u, t), 1.29, 1.31, "a target below 30%")
	u.hp = u.max_hp * 0.3
	assert_between(w.heroes.damage_factor(u, t), 1.49, 1.51, "and a hurt hero")


func test_lifesteal_heals_the_hero() -> void:
	var hp := []
	for steal in [0.0, 0.5]:
		var w := _world()
		var u := _hero(w, "templar", {"lifesteal": steal} if steal > 0.0 else {})
		u.hp = u.max_hp * 0.5
		var t := w.spawn("pike_militia", 1, Vector2(430, 400))
		for i in 3:
			w._damage(t, 20.0, false, u.id)
		hp.append(u.hp)
	assert_gt(hp[1], hp[0] + 5.0, "blows heal")


func test_every_nth_blow_stuns_and_crits() -> void:
	var w := _world()
	var u := _hero(w, "templar", {"heavy_blow": 2, "crit_every": 2})
	var t := _held(w, "scorchhound", 1, Vector2(430, 400))
	w._damage(t, 10.0, false, u.id)
	assert_false(t.stunned())
	w._damage(t, 10.0, false, u.id)
	assert_true(t.stunned(), "the 2nd blow stuns")
	w.deal_damage(t, 10.0, u.id)
	assert_true(t.stunned(), "skills do not count as blows")
	assert_between(w.heroes.blow_factor(u, t), 0.99, 1.01)
	assert_between(w.heroes.blow_factor(u, t), 1.99, 2.01, "the 2nd swing hits twice as hard")


func test_struck_hero_talents() -> void:
	var w := _world()
	var u := _hero(w, "knight", {"thorns": 0.5, "evade_every": 2, "ranged_ward": 0.4, "attacker_weak": 0.2})
	var t := w.spawn("pike_militia", 1, Vector2(430, 400))
	var hp := u.hp
	w._damage(u, 40.0, false, t.id)
	assert_lt(u.hp, hp, "the 1st blow lands")
	assert_lt(t.hp, t.max_hp, "thorns hurt the attacker")
	assert_gt(t.status_value("weak"), 0.1, "Hex Ward weakens it")
	hp = u.hp
	w._damage(u, 40.0, false, t.id)
	assert_eq(u.hp, hp, "the 2nd blow misses")
	assert_between(w.heroes.hero_taken(u, t, 100.0, true, false), 59.0, 61.0, "arrows hurt less")
	assert_between(w.heroes.hero_taken(u, t, 100.0, false, true), 99.0, 101.0, "skills are not blows")


func test_unyielding_saves_the_hero_once() -> void:
	var w := _world()
	var u := _hero(w, "knight", {"undying": 60.0})
	var t := w.spawn("pike_militia", 1, Vector2(430, 400))
	w.deal_damage(u, 999999.0, t.id)
	assert_true(u.alive)
	assert_eq(u.hp, 1.0)
	assert_gt(u.status_value("ward"), 0.4)
	u.status.clear()
	w.deal_damage(u, 999999.0, t.id)
	assert_false(u.alive, "not twice within the wait")


func test_chaplain_saves_a_soldier_near_the_hero() -> void:
	var w := _world()
	_hero(w, "knight", {"ally_undying": 30.0})
	var near := w.spawn("pike_militia", 0, Vector2(450, 400))
	var far := w.spawn("pike_militia", 0, Vector2(1500, 400))
	var foe := w.spawn("pike_militia", 1, Vector2(480, 400))
	w.deal_damage(far, 999999.0, foe.id)
	assert_false(far.alive, "too far from the hero")
	w.deal_damage(near, 999999.0, foe.id)
	assert_true(near.alive)
	assert_between(near.hp / near.max_hp, 0.29, 0.31)


func test_shoulder_to_shoulder_and_pack_hunter_count_soldiers() -> void:
	var w := _world()
	var u := _hero(w, "knight", {"phalanx": 0.04, "pack": 0.03})
	var t := w.spawn("pike_militia", 1, Vector2(700, 400))
	for i in 10:
		w.spawn("pike_militia", 0, Vector2(380 + 4 * i, 420))
	w.step()
	assert_between(w.heroes.hero_taken(u, t, 100.0, false, false), 67.0, 69.0, "8 soldiers at most: 32% less")
	assert_between(w.heroes.damage_factor(u, t), 1.23, 1.25, "1 + 8 x 3%")


# --- Kills and deaths --------------------------------------------------------------

func test_kill_talents() -> void:
	var w := _world()
	var u := _hero(w, "warlord", {"kill_mana": 20.0, "kill_heal": 0.1, "kill_cooldown": 2.0, "kill_rally": 0.2})
	var h := u.hero
	h.mana = 100.0
	h.cooldowns[0] = 5.0
	u.hp = u.max_hp * 0.5
	var friend := w.spawn("cinderling", 0, Vector2(450, 400))
	var t := w.spawn("pike_militia", 1, Vector2(430, 400))
	w.step()
	_kill(w, t, u.id)
	assert_gt(h.mana, 119.0)
	assert_gt(u.hp, u.max_hp * 0.55)
	assert_lt(h.cooldowns[0], 3.1)
	assert_gt(friend.status_value("might"), 0.15, "For the Crown!")


func test_last_rites_and_sworn_vengeance() -> void:
	var w := _world()
	var u := _hero(w, "knight", {"last_rites": 10.0, "avenge": 0.2})
	u.hero.mana = 100.0
	var a := w.spawn("pike_militia", 0, Vector2(450, 400))
	var b := w.spawn("pike_militia", 0, Vector2(460, 420))
	var foe := w.spawn("pike_militia", 1, Vector2(700, 400))
	w.step()
	_kill(w, a, foe.id)
	assert_gt(u.hero.mana, 109.0)
	assert_gt(b.status_value("might"), 0.15)


func test_harvest_of_the_fallen_raises_every_nth_enemy() -> void:
	var w := _world()
	_hero(w, "necromancer", {"fallen_rise": 2})
	var before := w.count_alive(0)
	for i in 2:
		_kill(w, w.spawn("pike_militia", 1, Vector2(450 + 20 * i, 400)), -1)
	assert_eq(w.count_alive(0), before + 1, "the 2nd body gets up")
	var risen: SimUnit = w.units[w.units.size() - 1]
	assert_eq(risen.type_id, "pike_militia")
	assert_eq(risen.owner, 0)
	assert_gt(risen.expires, 0.0, "for a while only")


func test_contagion_spreads_hexes() -> void:
	var w := _world()
	_hero(w, "warlock", {"contagion": 120.0})
	var a := w.spawn("pike_militia", 1, Vector2(450, 400))
	var b := w.spawn("pike_militia", 1, Vector2(500, 400))
	w.step()
	a.add_status("exposed", 5.0, 0.3)
	_kill(w, a, -1)
	assert_between(b.status_value("exposed"), 0.29, 0.31)


# --- Army talents ------------------------------------------------------------------

func test_army_regen_and_steady_ranks() -> void:
	var w := _world()
	_hero(w, "knight", {"army_regen": 4.0, "cleanse_pulse": 1.0})
	var s := w.spawn("pike_militia", 0, Vector2(450, 400))
	w.command_hold([s.id])
	s.hp = 50.0
	s.add_status("slow", 30.0, 0.5)
	_step(w, 2.0)
	assert_gt(s.hp, 55.0)
	assert_false(s.status.has("slow"), "Steady Ranks lifted the slow")


func test_summon_talents() -> void:
	var w := _world()
	var u := _hero(w, "knight", {"summon_count": 1.0, "summon_might": 0.5, "summon_time": 1.0}, "call_to_arms")
	var before := w.count_alive(0)
	assert_true(w.heroes.command_cast(0, 0))
	assert_eq(w.count_alive(0), before + 4, "3 soldiers at rank 3, and 1 more")
	var m: SimUnit = w.units[w.units.size() - 1]
	var plain := w.catalog.get_unit(m.type_id)
	assert_eq(int(plain["tier"]), 2)
	assert_eq(m.max_hp, float(plain["hp"]) * 1.5)
	assert_eq(m.expires, 90.0)
	assert_eq(float(m.def["damage"]), float(plain["damage"]) * 1.5)
	assert_eq(float(w.catalog.get_unit(m.type_id)["damage"]), 9.0, "the catalogue is untouched")
	assert_gt(u.hero.cooldowns[0], 0.0)


func test_echo_makes_every_nth_cast_free() -> void:
	var w := _world()
	var u := _hero(w, "warlock", {"echo": 2}, "sunder")
	var h := u.hero
	w.heroes.command_cast(0, 0)
	var m1 := h.mana
	assert_lt(m1, 500.0)
	h.cooldowns[0] = 0.0
	w.heroes.command_cast(0, 0)
	assert_eq(h.mana, m1, "the 2nd cast is free")


# --- New skills --------------------------------------------------------------------

func test_resurrection_brings_soldiers_back_for_good() -> void:
	var w := _world()
	_hero(w, "oracle", {}, "resurrection")
	var foe := w.spawn("pike_militia", 1, Vector2(1500, 400))
	var mine := []
	for i in 4:
		mine.append(w.spawn("longbowman" if i == 0 else "pike_militia", 0, Vector2(440 + 20 * i, 420)))
	w.step()
	var alive := _living(w, 0)
	for m in mine:
		_kill(w, m, foe.id)
	_kill(w, w.spawn("pike_militia", 1, Vector2(450, 380)), -1)  # an enemy body: not ours to call back
	assert_eq(_living(w, 0), alive - 4)
	assert_true(w.heroes.command_cast(0, 0))
	assert_eq(_living(w, 0), alive - 1, "3 at rank 3")
	var back: Array = []
	for u: SimUnit in w.units:
		if u.alive and u.owner == 0 and not u.is_hero():
			back.append(u)
	assert_eq(back.size(), 3)
	assert_eq((back[0] as SimUnit).type_id, "longbowman", "the strongest comes back first")
	for b: SimUnit in back:
		assert_eq(b.expires, 0.0, "for good")
		assert_between(b.hp / b.max_hp, 0.59, 0.61)
	w.heroes.hero_of(0).cooldowns[0] = 0.0
	assert_eq(w.heroes._bodies(back[0], Vector2(400, 400), 220.0, true).size(), 1, "one body is left")


func test_raise_the_fallen_takes_any_side() -> void:
	var w := _world()
	_hero(w, "necromancer", {}, "raise_dead")
	for i in 3:
		_kill(w, w.spawn("scorchhound", 1, Vector2(440 + 20 * i, 420)), -1)
	w.heroes.fallen[0]["time"] = -100.0  # one fell long ago
	var before := w.count_alive(0)
	assert_true(w.heroes.command_cast(0, 0))
	assert_eq(w.count_alive(0), before + 2, "only the recent bodies")
	var m: SimUnit = w.units[w.units.size() - 1]
	assert_eq(m.owner, 0)
	assert_eq(m.type_id, "scorchhound")
	assert_gt(m.expires, 0.0)


func test_corpse_burst() -> void:
	var w := _world()
	var u := _hero(w, "blightcaller", {}, "bone_burst")
	_kill(w, w.spawn("pike_militia", 1, Vector2(500, 400)), -1)
	var t := _held(w, "scorchhound", 1, Vector2(520, 400))
	var far := _held(w, "scorchhound", 1, Vector2(800, 400))
	w.step()
	assert_true(w.heroes.command_cast(0, 0))
	assert_lt(t.hp, t.max_hp, "the body burst next to it")
	assert_eq(far.hp, far.max_hp)
	assert_eq(w.heroes._bodies(u, u.pos, 500.0, false).size(), 0, "the body is used up")


func test_challenge_draws_the_enemy() -> void:
	var w := _world()
	var u := _hero(w, "knight", {}, "challenge")
	var friend := w.spawn("pike_militia", 0, Vector2(520, 400))
	var foe := w.spawn("pike_militia", 1, Vector2(480, 400))
	w.command_attack([foe.id], friend.id)
	w.step()
	assert_true(w.heroes.command_cast(0, 0))
	assert_eq(foe.target_id, u.id)
	assert_gt(u.status_value("ward"), 0.2, "the hero braces")
	assert_eq(friend.status_value("ward"), 0.0, "only the hero")


func test_chain_lightning_leaps() -> void:
	var w := _world()
	_hero(w, "warlock", {}, "chain_lightning")
	var a := _held(w, "scorchhound", 1, Vector2(600, 400))
	var b := _held(w, "scorchhound", 1, Vector2(700, 400))
	var c := _held(w, "scorchhound", 1, Vector2(800, 400))
	var d := _held(w, "scorchhound", 1, Vector2(1300, 400))
	w.step()
	assert_true(w.heroes.command_cast(0, 0, a.id))
	_step(w, 0.05)
	for t: SimUnit in [a, b, c]:
		assert_lt(t.hp, t.max_hp)
	assert_eq(d.hp, d.max_hp, "too far to leap to")
	assert_gt(c.hp, a.hp, "weaker with each leap")


func test_steam_blast_and_riptide_move_enemies() -> void:
	var w := _world()
	_hero(w, "anvilbreaker", {}, "steam_blast")
	var t := _held(w, "scorchhound", 1, Vector2(450, 400))
	w.step()
	var d0 := t.pos.distance_to(Vector2(400, 400))
	assert_true(w.heroes.command_cast(0, 0))
	assert_gt(t.pos.distance_to(Vector2(400, 400)), d0 + 60.0, "thrown back")
	var w2 := _world()
	_hero(w2, "tidemarshal", {}, "riptide")
	var a := _held(w2, "scorchhound", 1, Vector2(600, 300))
	var b := _held(w2, "scorchhound", 1, Vector2(600, 500))
	w2.step()
	var gap := a.pos.distance_to(b.pos)
	assert_true(w2.heroes.command_cast(0, 0, -1, Vector2(600, 400)))
	assert_lt(a.pos.distance_to(b.pos), gap - 100.0, "dragged together")
	assert_true(a.stunned())


func test_purify_and_blood_price() -> void:
	var w := _world()
	var u := _hero(w, "oracle", {}, "purify")
	var s := w.spawn("pike_militia", 0, Vector2(450, 400))
	w.step()
	s.add_status("stun", 5.0, 1.0)
	s.add_status("weak", 5.0, 0.3)
	s.poison_left = 3.0
	s.poison_dps = 5.0
	assert_true(w.heroes.command_cast(0, 0))
	assert_false(s.stunned())
	assert_false(s.status.has("weak"))
	assert_eq(s.poison_left, 0.0)
	var w2 := _world()
	var v := _hero(w2, "warlord", {}, "blood_price")
	v.hero.mana = 100.0
	var hp := v.hp
	assert_true(w2.heroes.command_cast(0, 0))
	assert_between(v.hp, hp - v.max_hp * 0.16, hp - v.max_hp * 0.14)
	assert_eq(v.hero.mana, 160.0)
	assert_gt(v.status_value("might"), 0.25)
	assert_true(u.alive)


func test_new_skills_autocast_when_it_makes_sense() -> void:
	var w := _world()
	var u := _hero(w, "oracle", {}, "resurrection")
	var s := hc.skill("resurrection")
	assert_true(w.heroes._autocast_target(u, s).is_empty(), "nobody to call back")
	_kill(w, w.spawn("pike_militia", 0, Vector2(450, 400)), -1)
	assert_false(w.heroes._autocast_target(u, s).is_empty())
	var bp := hc.skill("blood_price")
	var foes := []
	for i in 3:
		foes.append(_held(w, "pike_militia", 1, Vector2(500 + 10 * i, 400)))
	w.step()
	assert_false(w.heroes._autocast_target(u, bp).is_empty())
	u.hp = u.max_hp * 0.3
	assert_true(w.heroes._autocast_target(u, bp).is_empty(), "a dying hero does not pay in blood")
