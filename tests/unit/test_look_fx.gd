extends "res://tests/test_case.gd"
## The 3D view's finishing touches: ink outlines and living land (LookFx3D), building
## sites (ConstructionFx3D), and the melee arcs and hit flash of the fight effects.


func _scene() -> MapScene3D:
	var f := TerrainField.new()
	f.build_battlefield(40, 30, 5)
	return MapScene3D.create(f, 5)


func test_settings_keep_outlines_and_ambience() -> void:
	var path := "user://test_look_settings.cfg"
	var old := [WbSettings.outlines, WbSettings.ambience]
	assert_true(WbSettings.outlines and WbSettings.ambience, "both are on by default")
	WbSettings.outlines = false
	WbSettings.ambience = false
	WbSettings.save_settings(path)
	WbSettings.outlines = true
	WbSettings.ambience = true
	WbSettings.load_settings(path)
	assert_false(WbSettings.outlines)
	assert_false(WbSettings.ambience)
	WbSettings.outlines = old[0]
	WbSettings.ambience = old[1]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_look_passes_draw_before_the_fog_of_war_and_toggle() -> void:
	var m := _scene()
	var look := LookFx3D.create(m.atmosphere, true, true)
	for p: MeshInstance3D in [look.ink_pass, look.cloud_pass, look.mist_pass]:
		var mat := p.material_override as ShaderMaterial
		assert_true(mat.shader != null, p.name + " has its shader")
		assert_lt(mat.render_priority, Material.RENDER_PRIORITY_MAX, p.name + " draws before the fog of war")
		assert_true(p.visible, p.name + " shows")
	assert_true(look.motes.emitting, "motes in the air")
	assert_eq(m.environment.adjustment_color_correction, LookFx3D.ink_lut(), "the ink look's grade")
	assert_true(SpriteUnit.ink, "sprites are outlined")
	look.ink = false
	assert_false(look.ink_pass.visible)
	assert_false(SpriteUnit.ink, "sprite outlines off with the lines")
	assert_eq(m.environment.adjustment_color_correction, ColorGrade.texture(), "back to the plain grade")
	look.ambience = false
	assert_false(look.cloud_pass.visible)
	assert_false(look.mist_pass.visible)
	assert_false(look.motes.emitting)
	look.ink = true
	assert_true(SpriteUnit.ink)
	look.free()
	m.free()


func test_ink_boosts_the_light_once_per_frame() -> void:
	var m := _scene()
	var look := LookFx3D.create(m.atmosphere, true, false)
	m.atmosphere.step(0.1)
	var base := m.sun.light_energy
	var sat := m.environment.adjustment_saturation
	look._process(0.1)
	assert_almost_eq(m.sun.light_energy, base * LookFx3D.INK_SUN_BOOST, 0.001, "the sun is a little brighter")
	look._process(0.1)
	assert_almost_eq(m.sun.light_energy, base * LookFx3D.INK_SUN_BOOST, 0.001, "and not again each frame")
	assert_gt(m.environment.adjustment_saturation, sat, "richer colour")
	assert_true(m.environment.adjustment_saturation <= 1.0)
	m.atmosphere.step(0.1)  # the atmosphere re-lights the frame...
	look._process(0.1)  # ...and the boost goes on once more
	assert_almost_eq(m.sun.light_energy, m.atmosphere.sun.light_energy, 0.0001)
	assert_between(m.sun.light_energy / base, 1.05, 1.15)
	look.free()
	m.free()


func test_ink_grade_adds_contrast_and_keeps_order() -> void:
	var last := -1.0
	for i in 11:
		var v := float(i) / 10.0
		var c := LookFx3D.grade(Color(v, v, v), LookFx3D.INK_CONTRAST, LookFx3D.INK_SATURATION, LookFx3D.INK_SPLIT)
		var lum := c.get_luminance()
		assert_gt(lum, last, "greys stay in order (%.1f)" % v)
		last = lum
	var dark := LookFx3D.grade(Color(0.2, 0.2, 0.2), LookFx3D.INK_CONTRAST, 1.0, 1.0).get_luminance()
	var light := LookFx3D.grade(Color(0.8, 0.8, 0.8), LookFx3D.INK_CONTRAST, 1.0, 1.0).get_luminance()
	assert_lt(dark, ColorGrade.grade(Color(0.2, 0.2, 0.2)).get_luminance(), "darker darks than the plain grade")
	assert_gt(light, ColorGrade.grade(Color(0.8, 0.8, 0.8)).get_luminance(), "brighter lights")
	var red := LookFx3D.grade(Color(0.6, 0.3, 0.3), 0.0, LookFx3D.INK_SATURATION, 0.0)
	assert_gt(red.r - red.g, 0.3, "richer colour")


func test_motes_follow_the_biome() -> void:
	var m := _scene()
	var look := LookFx3D.create(m.atmosphere, false, true)
	assert_eq(look.mote_biome, "meadow")
	look.set_mote_biome("ashland")
	assert_eq(look.mote_biome, "ashland")
	assert_gt(look.motes.gravity.y, 0.2, "embers rise over the ash lands")
	look.set_mote_biome("swamp")
	assert_gt(look._mote_mat.albedo_color.g, look._mote_mat.albedo_color.r, "green fireflies in the fens")
	look.set_mote_biome("no_such_place")
	assert_eq(look.mote_biome, "meadow")
	look.free()
	m.free()


func test_every_biome_has_its_motes() -> void:
	for b in LookFx3D.MOTE_KINDS:
		assert_true(Atmosphere3D.MOODS.has(b), b + " is a biome with a mood")
	for b in Atmosphere3D.MOODS:
		assert_true(LookFx3D.MOTE_KINDS.has(b), "motes for " + b)


func test_building_site_rises_with_the_work() -> void:
	assert_almost_eq(ConstructionFx3D.rise(0.0, 6.0), -6.0 * ConstructionFx3D.SUNK, 0.001, "mostly underground at first")
	assert_almost_eq(ConstructionFx3D.rise(1.0, 6.0), 0.0, 0.001, "standing when finished")
	assert_lt(ConstructionFx3D.rise(0.3, 6.0), ConstructionFx3D.rise(0.6, 6.0), "rising with the progress")
	var site := ConstructionFx3D.site(5.0, 6.0, 3)
	for n in ["Scaffold", "Dust", "Chips", "Rope"]:
		assert_true(site.has_node(n), "the site has its " + n)
	assert_gt(site.get_node("Scaffold").get_child_count(), 8, "poles, planks and a brace")
	var dust: CPUParticles3D = site.get_node("Dust")
	var chips: CPUParticles3D = site.get_node("Chips")
	assert_false(dust.emitting, "quiet until the builders work")
	ConstructionFx3D.sync_site(site, 0.4, true, 1.0)
	assert_true(dust.emitting and chips.emitting, "dust and chips while they work")
	ConstructionFx3D.sync_site(site, 0.4, false, 1.2)
	assert_false(dust.emitting or chips.emitting, "and none while nobody does")
	site.free()


func test_struck_figures_flash_white_then_flush_red() -> void:
	var hot := SkirmishView3D.hit_tint(0.0)
	assert_gt(hot.r, 1.5, "a white-hot flash")
	assert_gt(hot.b, 1.5)
	var flush := SkirmishView3D.hit_tint(0.15)
	assert_gt(flush.r, 1.0, "then a red flush")
	assert_lt(flush.g, 1.0)
	assert_eq(SkirmishView3D.hit_tint(SkirmishView3D.HIT_FADE_S + 0.01), Color.WHITE, "then nothing")
	assert_eq(SkirmishView3D.hit_tint(99.0), Color.WHITE)


func test_melee_arcs_come_in_several_swings() -> void:
	var seen := {}
	for v in CombatFx3D.SLASH_VARIANTS:
		var mesh := CombatFx3D.slash_mesh(v)
		assert_gt(mesh.get_surface_count(), 0, "swing %d builds" % v)
		var box := mesh.get_aabb()
		assert_between(maxf(box.size.x, box.size.y), 0.4, 1.4, "about a metre across")
		seen[str(box)] = true
		assert_eq(CombatFx3D.slash_mesh(v), mesh, "built once")
	assert_gt(seen.size(), 1, "the swings differ")


func assert_almost_eq(got: float, expected: float, eps: float, msg: String = "") -> void:
	assert_between(got, expected - eps, expected + eps, msg)
