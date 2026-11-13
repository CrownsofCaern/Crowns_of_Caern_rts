extends "res://tests/test_case.gd"

var st: StoryTrees = StoryTrees.get_default()
var hc: HeroCatalog = HeroCatalog.get_default()


func _world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 40)
	return w


func _step(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


## The tree's nodes in a row, in data order.
func _row(tree_id: String, row: int) -> Array:
	var out: Array = []
	for n: Dictionary in st.trees[tree_id]["nodes"]:
		if int(n["row"]) == row:
			out.append(n)
	return out


func test_tree_data_is_valid() -> void:
	var errors := st.validate(hc)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_every_class_has_three_trees() -> void:
	for id in hc.classes:
		assert_eq(st.class_trees(hc, id).size(), 3, id)


func test_tree_skills_have_real_effects() -> void:
	for nid in st.nodes:
		var n: Dictionary = st.nodes[nid]
		if n["kind"] == "active":
			assert_false((hc.skill(n["skill"])["effects"] as Array).is_empty(), nid)


func test_levelling_to_forty() -> void:
	var s := StoryHero.new("knight")
	assert_eq(s.points, 1)
	s.add_xp(10000000)
	assert_eq(s.level, 40)
	assert_eq(s.points, 40, "1 to start and 1 per level")
	var total := 0
	for l in range(1, 40):
		total += st.xp_to_next(l)
	assert_gt(total, 60000, "a slow, persistent climb")


func test_rows_open_with_points_in_the_tree() -> void:
	var s := StoryHero.new("knight")
	s.add_xp(100000)
	var bulwark := "bulwark"
	var r0: Array = _row(bulwark, 0)
	var r1: Array = _row(bulwark, 1)
	assert_eq(s.learn_problem(r1[0]["id"]), "row locked")
	assert_true(s.learn(r0[0]["id"]))
	assert_true(s.learn(r0[0]["id"]))
	assert_eq(s.learn_problem(r1[0]["id"]), "", "2 points open row 2")
	assert_eq(s.learn_problem("cleave"), "not your tree", "a knight has no warrior tree")


func test_ultimate_needs_level_ten() -> void:
	var s := StoryHero.new("warlock")
	s.points = 30
	for n: Dictionary in st.trees["ruin"]["nodes"]:
		if n["kind"] == "passive":
			for i in 3:
				s.learn(n["id"])
	assert_eq(s.learn_problem("cataclysm"), "level")
	s.add_xp(20000)
	assert_true(s.level >= 10)
	assert_true(s.learn("cataclysm"))
	assert_eq(s.slots[3], "cataclysm", "the ultimate goes into R")


func test_learned_skills_fill_slots_and_can_be_moved() -> void:
	var s := StoryHero.new("ranger")
	s.points = 20
	assert_eq(s.slots[0], "pinning_shafts", "the signature starts in Q")
	for n: Dictionary in _row("marksman", 0):
		s.learn(n["id"])
		s.learn(n["id"])
	assert_true(s.learn("power_shot"))
	assert_eq(s.slots[1], "power_shot")
	assert_false(s.set_slot(3, "power_shot"), "R is for ultimates")
	assert_true(s.set_slot(2, "power_shot"))
	assert_eq(s.slots[1], "", "a skill sits in one slot only")
	assert_false(s.set_slot(0, "volley"), "not learned")


func test_signature_ranks_up() -> void:
	var s := StoryHero.new("oracle")
	s.points = 5
	assert_true(s.learn(StoryHero.SIGNATURE))
	assert_true(s.learn(StoryHero.SIGNATURE))
	assert_false(s.learn(StoryHero.SIGNATURE), "3 ranks in all")
	assert_eq(s.known_skills()["lantern_of_mending"], 3)


func test_passives_and_respec() -> void:
	var s := StoryHero.new("templar")
	s.add_xp(100000)
	var n: Dictionary = _row("slaughter", 0)[0]
	for i in 3:
		assert_true(s.learn(n["id"]))
	var tal := s.talents()
	assert_eq(float(tal[n["talent"]["type"]]), float(n["talent"]["value"][2]), "the talent at rank 3")
	# An army aura node adds its stat per rank (the Oath tree's banner).
	for m: Dictionary in _row("oath", 0):
		s.learn(m["id"])
		s.learn(m["id"])
	assert_true(s.learn("banner_bearer"))
	assert_eq(float(s.passive_mods()["aura_might"]), 0.03)
	var before := s.points
	var cost := s.respec()
	assert_eq(s.points, before + 8)
	assert_eq(cost, 25 * s.level)
	assert_true(s.passive_mods().is_empty())
	assert_true(s.talents().is_empty())


func test_save_round_trip() -> void:
	var s := StoryHero.new("necromancer")
	s.add_xp(5000)
	s.learn(_row("legions", 0)[0]["id"])
	var t := StoryHero.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(t.to_dict(), s.to_dict())
	assert_eq(t.passive_mods(), s.passive_mods())


func test_story_hero_fights_with_its_build() -> void:
	var s := StoryHero.new("templar")
	s.add_xp(100000)
	for n: Dictionary in _row("slaughter", 0):
		s.learn(n["id"])
		s.learn(n["id"])
	s.learn("cleave")
	var w := _world()
	var worn := {"weapon": ItemCatalog.get_default().make_unique("headsmans_maul")}
	var u := w.heroes.spawn_story_hero(0, s, Vector2(400, 400), worn)
	var h := u.hero
	assert_eq(h.level, s.level)
	assert_eq(h.kit, ["judgement", "cleave", "", ""])
	assert_eq(h.ranks[1], 1)
	assert_eq(h.points, 0)
	var plain := hc.make_def("templar", s.level, w.catalog)
	assert_gt(float(u.def["damage"]), float(plain["damage"]), "the maul adds damage")
	assert_eq(h.talents.size(), 2, "both row 1 talents came along")
	assert_eq(w.heroes.cast_problem(h, 2), "not learned", "an empty slot")
	var t := w.spawn("pike_militia", 1, Vector2(420, 400))
	w.command_hold([t.id])
	w.step()  # the area lookup sees units placed since the last tick
	assert_true(w.heroes.command_cast(0, 1))
	assert_lt(t.hp, t.max_hp, "Cleave hit")
	var xp0 := h.xp
	w.heroes.add_xp(h, 500)
	assert_eq(h.level, s.level, "story levels are not raised in battle")
	assert_eq(h.xp, xp0 + 500, "the XP is banked for the campaign")
	_step(w, 1.0)
