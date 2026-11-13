extends "res://tests/test_case.gd"
## The 3D world layer: terrain data from a skirmish map, the battlefield preset and
## the scene built from them (decoration placement is seeded and repeatable).


func test_skirmish_field_follows_the_map() -> void:
	var w := SkirmishScenario.build_skirmish(101)
	var f := TerrainField.new()
	SimTerrain.build(f, w, 101)
	assert_eq(f.heights.size(), f.sw * f.sh)
	assert_eq(f.tree_d.size(), f.sw * f.sh)
	# Settlements sit on level ground (on a hill or plateau as much as in a valley).
	for sec in w.economy.sectors:
		var m := TerrainField.to_world(sec.center)
		var h0 := f.height_at(m.x, m.y)
		for d: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			assert_lt(absf(f.height_at(m.x + d.x, m.y + d.y) - h0), 0.2, "settlement %d is level" % sec.id)
	# The open land is not a table top: it rises and falls.
	var lo := INF
	var hi := -INF
	for k in 200:
		var x := f.play_w * (0.1 + 0.8 * float(k % 20) / 19.0)
		var z := f.play_h * (0.1 + 0.8 * float(k / 20) / 9.0)
		var hh := f.height_at(x, z)
		if hh > f.water_level + 0.3 and hh < 4.0:
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
	assert_gt(hi - lo, 1.0, "hills and hollows")
	var water := 0
	var forest := 0
	var wooded := 0
	for y in w.nav.height:
		for x in w.nav.width:
			var kind := w.nav.kind_at(Vector2i(x, y))
			var c := Vector2(x + 0.5, y + 0.5)
			if kind == NavGrid.Kind.WATER:
				water += 1
				assert_lt(f.height_at(c.x, c.y), f.water_level, "water cell %s is under water" % c)
			elif kind == NavGrid.Kind.FOREST:
				var k := int(c.y * TerrainField.RES - f.origin.y * TerrainField.RES) * f.sw \
					+ int(c.x * TerrainField.RES - f.origin.x * TerrainField.RES)
				forest += 1
				if f.tree_d[k] > 0.0:
					wooded += 1
	assert_gt(water, 0)
	assert_gt(forest, 0)
	assert_gt(float(wooded) / forest, 0.9, "forest cells get trees")
	# Mountains rise outside the play area.
	assert_gt(f.height_at(-30.0, f.play_h * 0.5), 6.0)


func test_battlefield_is_flat_where_armies_stand() -> void:
	var f := TerrainField.new()
	f.build_battlefield(80, 50, 3)
	for p in [Vector2(0, 0), Vector2(-24, -10), Vector2(24, 10), Vector2(-24, 10)]:
		assert_lt(absf(f.height_at(p.x, p.y)), 0.01, "flat at %s" % p)
	for j in f.sh:
		for i in f.sw:
			var z := f.origin.y + float(j) / TerrainField.RES
			if z > 12.0:
				var k := j * f.sw + i
				assert_eq(f.tree_d[k], 0.0, "no trees on the camera side")
				assert_eq(f.rock_d[k], 0.0, "no rocks on the camera side")
	assert_gt(f.height_at(0.0, -50.0), 3.0, "hills or ridge behind the field")


func test_map_scene_builds_and_repeats() -> void:
	var f := TerrainField.new()
	f.build_battlefield(40, 30, 5)
	var a := MapScene3D.create(f, 5, false)
	var b := MapScene3D.create(f, 5, false)
	var total := 0
	for k in a.stats:
		total += int(a.stats[k])
	assert_gt(total, 50, "decoration placed")
	assert_eq(a.stats, b.stats, "same seed, same decoration")
	assert_true(a.get_node_or_null("Terrain") != null)
	assert_gt(a.get_node("Terrain").get_child_count(), 1, "terrain is split into chunks")
	a.free()
	b.free()


func test_biomes_data_is_valid_and_homes_take_faction_biomes() -> void:
	assert_eq(Biomes.validate(), [] as Array[String])
	assert_eq(Biomes.for_faction("hollow"), "swamp")
	assert_eq(Biomes.for_faction("ashen"), "ashland")
	assert_eq(Biomes.for_faction("nobody"), Biomes.data()["base"])
	var f := TerrainField.new()
	f.build_battlefield(40, 30, 5, Vector2(30, 13), 12.0, "ashland")
	assert_eq(f.biome_names[0], "ashland")
	assert_eq(f.biome_value(f.sw / 2, f.sh / 2, "lava"), 1.0, "a lava biome everywhere")
	var w := SkirmishScenario.build_skirmish(101, ["frostmarch", "hollow"], "classic")
	var s := TerrainField.new()
	SimTerrain.build(s, w, 101, "meadow")
	# Each home's region takes its house's biome.
	for sec: Sector in w.economy.sectors:
		if sec.home_of < 0:
			continue
		var want := Biomes.for_faction(["frostmarch", "hollow"][sec.home_of])
		var m := TerrainField.to_world(sec.center)
		var px := Vector2i((Vector2(m.x, m.y) - s.origin) * TerrainField.RES)
		var wts := s.biome_weights(px.x, px.y)
		var got := 0.0
		for k in TerrainField.SLOTS:
			if s.biome_names[k] == want:
				got += wts[k]
		assert_gt(got, 0.99, "home %d stands in %s" % [sec.home_of, want])


func test_shared_terrain_kinds_match_the_sim() -> void:
	# TerrainField is shared with the main game, so it keeps its own copy of these numbers.
	assert_eq(TerrainField.CELL_PX, NavGrid.CELL)
	assert_eq(TerrainField.KIND_GROUND, NavGrid.Kind.GROUND)
	assert_eq(TerrainField.KIND_ROCK, NavGrid.Kind.ROCK)
	assert_eq(TerrainField.KIND_WATER, NavGrid.Kind.WATER)
	assert_eq(TerrainField.KIND_FOREST, NavGrid.Kind.FOREST)
	for f in ["res://src/world3d/terrain_field.gd", "res://src/world3d/map_scene_3d.gd", "res://src/world3d/biomes.gd",
			"res://src/world3d/atmosphere_3d.gd"]:
		var code := FileAccess.get_file_as_string(f)
		for t in ["SimWorld", "NavGrid", "Economy", "SkirmishScenario", "SimUnit", "WbSettings", "GameRng"]:
			for line in code.split("\n"):
				if not line.strip_edges().begins_with("#"):
					assert_false(t in line, "%s uses Warbound-only %s" % [f, t])


func test_scene_gets_a_dark_mood_and_weather() -> void:
	var f := TerrainField.new()
	f.build_battlefield(40, 30, 5)
	var m := MapScene3D.create(f, 5)
	assert_true(m.atmosphere != null, "the scene has an atmosphere")
	assert_eq(m.environment, m.atmosphere.environment)
	assert_eq(m.sun, m.atmosphere.sun)
	# Lit like the main game's battlefield paintings: a warm sun against cool shadows.
	assert_gt(m.sun.light_color.r - m.sun.light_color.b, 0.2, "the sun is warm")
	var amb := m.environment.ambient_light_color
	assert_gt(amb.b, amb.r, "the shadows are cool")
	assert_between(m.sun.light_energy, 0.9, 1.4, "a gentle sun")
	assert_lt(m.environment.ambient_light_energy, 1.0, "the dark stays dark")
	assert_true(m.environment.fog_enabled)
	assert_true(m.environment.adjustment_color_correction != null, "a final colour grade")
	assert_true(m.atmosphere.weather in ["clear", "overcast"], "a match starts dry")
	m.free()


func test_storms_bring_rain_lightning_and_clear_up() -> void:
	var a := Atmosphere3D.create(9, "meadow")
	assert_eq(a.kind, "rain")
	var sun_clear := a.sun.light_energy
	a.set_weather("storm", 300.0)
	for i in 1200:  # 60 s at 20 steps a second
		a.step(0.05)
	assert_gt(a.rain, 0.9, "heavy rain after a minute of storm")
	assert_gt(a.cloud, 0.9)
	assert_gt(a.strikes, 2, "lightning strikes now and then")
	assert_lt(a.strikes, 15, "but not constantly")
	assert_gt(a.environment.fog_density, 0.005, "thicker fog")
	if a.flash == 0.0:
		assert_lt(a.sun.light_energy, sun_clear * 0.6, "the sun dims under the clouds")
	assert_gt(a.get_node("Precipitation").multimesh.visible_instance_count, Atmosphere3D.DROPS_MOBILE / 2)
	a.weather_enabled = false
	for i in 1200:
		a.step(0.05)
	assert_eq(a.weather, "clear", "weather off keeps the sky clear")
	assert_lt(a.rain, 0.01, "the rain stops")
	assert_false(a.get_node("Precipitation").visible, "no drops drawn on a dry day")
	a.free()


func test_weather_comes_and_goes_and_repeats_by_seed() -> void:
	var runs := []
	for n in 2:
		var a := Atmosphere3D.create(21, "")
		var seen := {}
		var wet := 0.0
		for i in 3600:  # 30 minutes at 2 steps a second
			a.step(0.5)
			seen[a.weather] = true
			if a.rain > 0.3:
				wet += 0.5
		runs.append([seen.keys(), a.strikes, wet])
		a.free()
	assert_eq(runs[0], runs[1], "same seed, same weather")
	assert_true("storm" in runs[0][0] or "rain" in runs[0][0], "it rains at some point in half an hour")
	assert_gt(runs[0][2], 60.0, "wet for more than a minute")
	assert_lt(runs[0][2], 1200.0, "but dry most of the time")


func test_snow_and_ash_lands_get_their_own_weather() -> void:
	var s := Atmosphere3D.create(3, "snowfield")
	assert_eq(s.kind, "snow")
	s.set_weather("storm", 100.0)
	for i in 600:
		s.step(0.05)
	assert_eq(s.strikes, 0, "no lightning in a snowstorm")
	assert_gt(s.rain, 0.8, "a blizzard falls")
	s.free()
	var a := Atmosphere3D.create(3, "ashland")
	assert_eq(a.kind, "ash")
	a.free()


func test_models_lose_their_plastic_shine() -> void:
	var glossy := StandardMaterial3D.new()
	glossy.metallic = 1.0
	glossy.roughness = 0.2
	glossy.roughness_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	var m := MatteMaterials.matte(glossy) as StandardMaterial3D
	assert_true(m != glossy, "a matte copy, the source stays as it is")
	assert_eq(m.metallic, 0.0)
	assert_gt(m.roughness, 0.85)
	assert_true(m.roughness_texture == null, "the gloss map is dropped")
	assert_lt(m.metallic_specular, 0.2)
	assert_eq(MatteMaterials.matte(glossy), m, "one copy per source material")
	assert_eq(MatteMaterials.matte(m), m, "matte stays matte")
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert_eq(MatteMaterials.matte(flat), flat, "unshaded rings and markers are left alone")
	var box := BoxMesh.new()
	box.material = glossy
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var holder := Node3D.new()
	holder.add_child(mi)
	MatteMaterials.apply(holder)
	assert_eq(mi.get_surface_override_material(0), m, "models under a node are made matte")
	holder.free()


func test_biomes_bring_their_own_ground_rock_and_mood() -> void:
	var seen := {}
	for b in Biomes.data()["biomes"]:
		var d: Dictionary = Biomes.get_biome(b)
		seen[str(d["ground_tex"])] = true
		assert_true(Atmosphere3D.MOODS.has(b), "%s has a sky mood" % b)
	assert_gt(seen.size(), 4, "most biomes have their own ground texture")
	var f := TerrainField.new()
	f.build_battlefield(40, 30, 5, Vector2(30, 13), 12.0, "ashland")
	var m := MapScene3D.create(f, 5, false)
	var arr := m.terrain_material.get_shader_parameter("ground_alb") as Texture2DArray
	assert_true(arr != null and arr.get_layers() >= 1, "ground textures go in as an array")
	assert_eq((m.terrain_material.get_shader_parameter("b_embers") as PackedFloat32Array)[0], 1.0, "ash land glows")
	m.free()


## Linear brightness of a biome's open ground (texture average times its tint).
func _ground_lum(biome: String, key: String) -> float:
	var d: Dictionary = Biomes.get_biome(biome)
	var tex := "dirt" if key == "dirt" else str(d["ground_tex"])
	var file := "rock023_alb_ht" if tex == "dirt" else tex + "_alb_ht"
	var img := Image.load_from_file(ProjectSettings.globalize_path(Biomes.TEXTURES % file))
	img.convert(Image.FORMAT_RGB8)
	# The mip chain is a box-filtered average; read the 16 x 16 level.
	img.generate_mipmaps()
	var level := int(round(log(img.get_width() / 16.0) / log(2.0)))
	var off := img.get_mipmap_offset(level)
	img = Image.create_from_data(16, 16, false, Image.FORMAT_RGB8, img.get_data().slice(off, off + 16 * 16 * 3))
	var sum := Vector3.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(c.r, c.g, c.b)
	var avg := sum / float(img.get_width() * img.get_height())
	var t := Biomes.color(d, key)
	return avg.x * t.r * 0.2126 + avg.y * t.g * 0.7152 + avg.z * t.b * 0.0722


func test_every_home_ground_leaves_contrast_for_buildings() -> void:
	# Dark homes swallowed their own buildings (Ashen on near-black ash): every
	# biome's open ground and yards stay within reach of the meadow's brightness.
	var meadow := _ground_lum("meadow", "grass")
	var meadow_dirt := _ground_lum("meadow", "dirt")
	for b in Biomes.data()["biomes"]:
		assert_gt(_ground_lum(b, "grass"), meadow * 0.55, "%s ground is not too dark" % b)
		assert_gt(_ground_lum(b, "dirt"), meadow_dirt * 0.75, "%s yards and roads are not too dark" % b)
	var ash: Color = Atmosphere3D.MOODS["ashland"][1]
	assert_lt(ash.r - ash.b, 0.08, "the ash lands' shade is near neutral, not red")


func test_colour_grade_warms_lights_cools_darks_and_keeps_order() -> void:
	var dark := ColorGrade.grade(Color(0.15, 0.15, 0.15))
	var light := ColorGrade.grade(Color(0.85, 0.85, 0.85))
	assert_gt(dark.b, dark.r, "grey shadows turn cool")
	assert_gt(light.r, light.b, "grey highlights turn warm")
	assert_gt(ColorGrade.grade(Color.BLACK).r, 0.0, "blacks are lifted")
	var prev := -1.0
	for i in 11:
		var g := ColorGrade.grade(Color(i / 10.0, i / 10.0, i / 10.0))
		var lum := g.r * 0.2126 + g.g * 0.7152 + g.b * 0.0722
		assert_gt(lum, prev, "the grade never inverts brightness")
		prev = lum
	var tex := ColorGrade.texture()
	assert_eq(tex.get_width(), ColorGrade.SIZE)
	assert_eq(tex.get_depth(), ColorGrade.SIZE)


func test_light_follows_the_biome_under_the_camera() -> void:
	var a := Atmosphere3D.create(4, "meadow")
	a.set_weather("clear", 500.0)
	a.step(0.1)
	var meadow_sun := a.sun.light_color
	a.set_biome("snowfield")
	assert_eq(a.mood_biome, "snowfield")
	for i in 40:
		a.step(0.25)
	assert_gt(a.sun.light_color.b, meadow_sun.b, "frost light is bluer")
	assert_lt(a.sun.light_energy, 1.1, "fresh snow gets a softer sun")
	a.set_biome("no_such_biome")
	assert_eq(a.mood_biome, "snowfield", "unknown biomes are ignored")
	a.free()


func test_field_names_the_biome_at_a_point() -> void:
	var w := SkirmishScenario.build_skirmish(101)
	var f := TerrainField.new()
	SimTerrain.build(f, w, 101)
	var home := w.economy.hall_of(0)
	var fac: String = w.economy.player(0).faction
	assert_eq(f.biome_at(TerrainField.to_world(home.center)), Biomes.data()["factions"][fac])
	assert_true(f.biome_at(Vector2(-9999, -9999)) in f.biome_names, "off the map: the nearest edge")


func test_camera_tilts_flatter_as_it_zooms_in() -> void:
	assert_lt(Skirmish.ZOOM_MIN, Skirmish.DEFAULT_ZOOM)
	assert_lt(Skirmish.DEFAULT_ZOOM, 0.7, "the default view is wide")
	var far := SkirmishView3D.pitch_for(Skirmish.ZOOM_MIN)
	var mid := SkirmishView3D.pitch_for(Skirmish.DEFAULT_ZOOM)
	var near := SkirmishView3D.pitch_for(Skirmish.ZOOM_MAX)
	assert_gt(far, mid)
	assert_gt(mid, near)
	assert_between(mid, 50.0, 58.0, "about the old 55 degrees at the default zoom")


func test_each_biome_dresses_its_land_in_its_own_scenery() -> void:
	# Snow lands grow snowy pines, fens grow willows: each biome's "scenery" lists replace
	# the shared trees and rocks, and every listed model has a size and a file.
	assert_eq(Biomes.validate(), [] as Array[String])
	var counts := {}
	for biome in ["meadow", "snowfield", "swamp"]:
		var f := TerrainField.new()
		f.build_battlefield(40, 30, 5, Vector2(30, 13), 12.0, biome)
		var m := MapScene3D.create(f, 5, false)
		counts[biome] = m.stats.duplicate()
		m.free()
	var has := func(stats: Dictionary, prefix: String) -> int:
		var n := 0
		for k: String in stats:
			if k.begins_with(prefix):
				n += int(stats[k])
		return n
	assert_gt(has.call(counts["snowfield"], "sn_"), 0, "snowy trees and rocks in the snow")
	assert_eq(has.call(counts["snowfield"], "pine_tree_"), 0, "no bare green pines in the snow")
	assert_gt(has.call(counts["swamp"], "fn_") + has.call(counts["swamp"], "mo_"), 0, "willows and moss in the fens")
	assert_eq(has.call(counts["meadow"], "sn_") + has.call(counts["meadow"], "fn_"), 0, "the meadow keeps its own")
	for k: String in counts["snowfield"]:
		if k != "grass" and k != "props":
			assert_false(MapScene3D.size_of(k).is_empty(), "%s has a size" % k)
