extends "res://tests/test_case.gd"
## Combat effects of the 3D view (CombatFx3D, data/combat_fx.json) and the shot data
## the sim hands it.


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_every_unit_has_its_effects() -> void:
	var units: Dictionary = _json("res://data/units.json")["units"]
	var fx: Dictionary = CombatFx3D.table()["units"]
	for id in units:
		assert_true(fx.has(id), "%s is in combat_fx.json" % id)
		if not fx.has(id):
			continue
		var e: Dictionary = fx[id]
		var el := String(e["element"])
		assert_true(el == "" or el in CombatFx3D.ELEMENTS, "%s element %s" % [id, el])
		assert_true(String(e["gore"]) in CombatFx3D.GORES, "%s gore %s" % [id, e["gore"]])
		var ranged: bool = "ranged" in units[id]["abilities"]
		var missile := String(e["missile"])
		if ranged:
			assert_true(missile in CombatFx3D.MISSILES, "%s shoots a known missile (%s)" % [id, missile])
		else:
			assert_eq(missile, "", "%s fights hand to hand" % id)


func test_casters_shoot_glowing_bolts_and_archers_arrows() -> void:
	assert_eq(CombatFx3D.missile_of("longbowman", true), "arrow")
	assert_eq(CombatFx3D.missile_of("rivet_crossbowman", true), "bolt")
	assert_eq(CombatFx3D.missile_of("thunder_bombard", true), "shell")
	assert_eq(CombatFx3D.missile_of("frost_shaman", true), "orb")
	assert_eq(String(CombatFx3D.type_fx("frost_shaman")["element"]), "frost")
	assert_eq(String(CombatFx3D.type_fx("ash_witch")["element"]), "fire")
	assert_eq(CombatFx3D.missile_of("pike_militia", false), "")


func test_gore_follows_what_a_unit_is_made_of() -> void:
	assert_eq(String(CombatFx3D.type_fx("pike_militia")["gore"]), "blood")
	assert_eq(String(CombatFx3D.type_fx("shambler")["gore"]), "bone")
	assert_eq(String(CombatFx3D.type_fx("slag_golem")["gore"]), "sparks")
	assert_eq(String(CombatFx3D.type_fx("cinderling")["gore"]), "ember")
	assert_eq(String(CombatFx3D.type_fx("fm_brine_spear")["gore"]), "ichor")
	assert_eq(String(CombatFx3D.type_fx("wailing_shade")["gore"]), "wisp")
	assert_eq(String(CombatFx3D.type_fx("worker_hollow")["gore"]), "bone")


func test_every_hero_class_and_skill_has_an_effect() -> void:
	var heroes := _json("res://data/heroes.json")
	var t := CombatFx3D.table()
	for cls in heroes["classes"]:
		assert_true(t["classes"].has(cls), "class %s is listed" % cls)
		var c: Dictionary = t["classes"].get(cls, {})
		var el := String(c.get("element", ""))
		assert_true(el == "" or el in CombatFx3D.ELEMENTS, "%s element %s" % [cls, el])
		var ranged: bool = heroes["archetypes"][heroes["classes"][cls]["archetype"]]["abilities"].has("ranged")
		var m := CombatFx3D.missile_of("hero_" + cls, ranged)
		assert_true(m in CombatFx3D.MISSILES if ranged else true, "%s shoots %s" % [cls, m])
	for sid in heroes["skills"]:
		assert_true(t["skills"].has(sid), "skill %s is listed" % sid)
		var fx := CombatFx3D.skill_fx(sid, "warlock", heroes["skills"][sid], true)
		assert_true(String(fx["element"]) in CombatFx3D.ELEMENTS, "%s element %s" % [sid, fx["element"]])
		assert_true(String(fx["shape"]) in CombatFx3D.SHAPES, "%s shape %s" % [sid, fx["shape"]])


func test_skill_shapes_follow_their_targets() -> void:
	var skills: Dictionary = _json("res://data/heroes.json")["skills"]
	assert_eq(CombatFx3D.shape_from(skills["arcane_bolt"], true), "bolt")
	assert_eq(CombatFx3D.shape_from(skills["shield_bash"], false), "strike")
	assert_eq(CombatFx3D.shape_from(skills["cataclysm"], true), "area")
	assert_eq(CombatFx3D.shape_from(skills["cleave"], false), "nova")
	assert_eq(CombatFx3D.shape_from(skills["rallying_oath"], false), "aura")
	assert_eq(CombatFx3D.shape_from(skills["leap"], false), "leap")
	assert_eq(CombatFx3D.shape_from(skills["legion"], true), "summon")
	assert_eq(String(CombatFx3D.skill_fx("volley", "ranger", skills["volley"], true)["shape"]), "rain")
	# A generic skill takes its caster's colour: a frost mystic's bolt is frost.
	assert_eq(String(CombatFx3D.skill_fx("arcane_bolt", "frostcaller", skills["arcane_bolt"], true)["element"]), "frost")


func test_hero_skills_glow_in_their_class_colour() -> void:
	var skills: Dictionary = _json("res://data/heroes.json")["skills"]
	# A ranger's plain shot skill still glows: holy gold for the Concord ranger.
	assert_eq(String(CombatFx3D.skill_fx("power_shot", "ranger", skills["power_shot"], true)["element"]), "holy")
	assert_eq(String(CombatFx3D.skill_fx("volley", "reaver", skills["volley"], true)["element"]), "frost")
	for cls in CombatFx3D.table()["classes"]:
		var el := String(CombatFx3D.table()["classes"][cls].get("skill_element", ""))
		assert_true(el in CombatFx3D.ELEMENTS, "%s skills glow (%s)" % [cls, el])
	var plain := CombatFx3D.missile("arrow", "holy")
	var charged := CombatFx3D.missile("arrow", "holy", true)
	assert_gt(float(charged.get_child_count()), float(plain.get_child_count()), "a skill arrow carries a glow and trail")
	assert_gt(charged.scale.x, 1.0, "a skill arrow is bigger")
	plain.free()
	charged.free()


func test_every_missile_builds() -> void:
	for kind in CombatFx3D.MISSILES:
		var m := CombatFx3D.missile(kind, "fire")
		assert_gt(m.get_child_count(), 0, "%s has a body" % kind)
		m.free()


func test_pool_textures_are_ragged_blobs() -> void:
	var tex := CombatFx3D.pool_texture(2)
	var img := tex.get_image()
	assert_eq(img.get_width(), 32)
	var filled := 0
	for y in 32:
		for x in 32:
			if img.get_pixel(x, y).a > 0.5:
				filled += 1
	assert_between(float(filled), 32.0 * 32.0 * 0.15, 32.0 * 32.0 * 0.7, "a blob, not a square")
	assert_true(img.get_pixel(16, 16).a > 0.5, "solid in the middle")
	assert_true(img.get_pixel(0, 0).a < 0.5, "clear in the corner")


func test_shots_carry_an_id_and_their_last_position() -> void:
	var w := SimWorld.new(7)
	w.setup_map(50, 30)
	var archers: Array = []
	for i in 3:
		archers.append(w.spawn("longbowman", 0, Vector2(300, 280 + i * 30)).id)
	var foe := w.spawn("shieldwarden", 1, Vector2(500, 300))
	w.command_attack_move(archers, foe.pos)
	var ids := {}
	var moved := false
	for i in 20 * 6:
		w.step()
		for p in w.projectiles:
			assert_true(int(p["id"]) > 0, "shot has an id")
			ids[int(p["id"])] = true
			if (p["prev"] as Vector2) != (p["pos"] as Vector2):
				moved = true
				assert_lt((p["pos"] as Vector2).distance_to(p["prev"]), 60.0, "prev is one tick back")
	assert_gt(float(ids.size()), 2.0, "several shots, each with its own id")
	assert_true(moved, "shots fly from prev to pos")
