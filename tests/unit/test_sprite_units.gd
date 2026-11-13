extends "res://tests/test_case.gd"
## Sprite unit mode (F7): every unit's art has an animation sheet, clips play and loop,
## mirroring keeps the feet in place, and the setting is saved.


func test_every_unit_sprite_has_a_sheet() -> void:
	var cat := UnitCatalog.get_default()
	for id in cat.units:
		var sid := String(cat.get_unit(id)["sprite"]).get_file().get_basename()
		assert_true(SpriteUnit.exists(sid), "%s (%s) has an animation sheet" % [id, sid])
		var d: Dictionary = SpriteUnit.data()[sid]
		assert_true(d["actions"].has("move"), "%s walks" % sid)


func test_clips_play_loop_and_stop() -> void:
	var su := SpriteUnit.spawn("pike_militia")
	assert_true(su != null)
	assert_eq(su.action, "idle")
	assert_between(su.height, 1.4, 2.4, "a man is man-sized")
	su.walk(1.6)
	assert_eq(su.action, "move")
	for i in 40:
		su.advance(0.05)
	assert_between(su.frame_index(), 0, 7, "the walk loops")
	su.strike(1.0)
	assert_eq(su.action, "attack")
	assert_true(su.busy())
	su.advance(su.clip_seconds("attack") + 0.1)
	assert_false(su.busy(), "a blow ends")
	# A quicker blow than the clip plays the clip faster.
	su.strike(0.3)
	su.advance(0.31)
	assert_false(su.busy())
	su.die()
	assert_true(su.is_dead())
	su.play("idle")
	assert_eq(su.action, "death", "the dead stay down")
	su.free()


func test_sprites_take_the_scene_light() -> void:
	var su := SpriteUnit.spawn("shambler")
	var m := su.material_override as ShaderMaterial
	assert_true(m != null and m.shader != null, "lit by the sprite shader, not drawn unshaded")
	assert_eq(float(m.get_shader_parameter("billboard")), 1.0)
	su.lay_flat()
	assert_eq(float((su.material_override as ShaderMaterial).get_shader_parameter("billboard")), 0.0, "a corpse lies flat")
	su.free()


func test_heroes_have_their_own_sheets() -> void:
	var hc := HeroCatalog.get_default()
	for cls in hc.classes:
		assert_true(SpriteUnit.exists("hero_" + cls), "%s has a baked hero sheet" % cls)
		var d: Dictionary = SpriteUnit.data()["hero_" + cls]
		for a in ["idle", "move", "attack"]:
			assert_true(d["actions"].has(a), "%s: %s" % [cls, a])
	var su := SpriteUnit.spawn("hero_knight")
	assert_between(su.height, 1.4, 2.6, "a hero is man-sized")
	su.free()


func test_mirroring_keeps_the_feet_in_place() -> void:
	var su := SpriteUnit.spawn("pike_militia")
	var right := su.offset
	su.face(false)
	assert_true(su.flip_h)
	assert_eq(su.offset.x, -right.x)
	assert_eq(su.offset.y, right.y)
	su.free()


func test_every_worker_has_its_own_baked_sheet() -> void:
	var cat := UnitCatalog.get_default()
	for f in cat.factions:
		if f == "neutral":
			continue
		assert_true(SpriteUnit.exists(cat.worker_type(f)), "%s has its own sprite sheet" % cat.worker_type(f))


func test_every_worker_has_its_own_still_sprite() -> void:
	# The icon, training queue and 2D view show the worker's own body, not a soldier's.
	var cat := UnitCatalog.get_default()
	for f in cat.factions:
		if f == "neutral":
			continue
		var wid := cat.worker_type(f)
		var path := String(cat.get_unit(wid)["sprite"])
		assert_eq(path, "res://assets/units/%s.png" % wid, "%s has its own still sprite" % wid)
		var tex := load(path) as Texture2D
		assert_true(tex != null, "%s loads" % path)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(128, 128), "%s is a 128 px unit sprite" % wid)


func test_creatures_keep_their_sizes() -> void:
	# The battle art draws a giant as tall as a pikeman; unit_sizes.json puts it back.
	var man := SpriteUnit.spawn("pike_militia")
	var giant := SpriteUnit.spawn("cairn_giant")
	var colossus := SpriteUnit.spawn("bastion_colossus")
	var imp := SpriteUnit.spawn("cinderling")
	var rats := SpriteUnit.spawn("plague_rats")
	assert_eq(SpriteUnit.size_k("pike_militia"), 1.0, "soldiers keep the art's size")
	assert_true(giant.pixel_size > man.pixel_size * 1.6, "a giant is drawn far larger than a man")
	assert_true(colossus.pixel_size > man.pixel_size * 1.6, "a colossus too")
	assert_true(imp.pixel_size < man.pixel_size * 0.8, "a cinderling is small (#235: 0.8 m)")
	assert_true(rats.pixel_size < man.pixel_size * 0.6, "rats are small")
	assert_true(giant.height > man.height * 1.5, "health bars sit over the giant's head")
	for su in [man, giant, colossus, imp, rats]:
		su.free()


func test_size_table_covers_only_known_sheets() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SpriteUnit.SIZES))
	assert_true(parsed is Dictionary)
	for sid in (parsed as Dictionary)["units"]:
		assert_true(SpriteUnit.exists(sid), "%s has a sheet" % sid)
		assert_between(SpriteUnit.size_k(sid), 0.4, 2.7, "%s factor is sane" % sid)


func test_campaign_npcs_have_their_own_bodies() -> void:
	var cat := UnitCatalog.get_default()
	var ids := ["npc_peddler", "npc_priest", "npc_elder", "npc_woman", "npc_child", "npc_risen", "npc_noble"]
	for id in ids:
		var d := cat.get_unit(id)
		assert_false(d.is_empty(), "%s is a unit" % id)
		assert_eq(String(d["faction"]), "neutral")
		assert_true(SpriteUnit.exists(id), "%s has a sheet baked from its 3D body" % id)
		assert_true(ResourceLoader.exists("res://assets/units3d/%s.glb" % id), "%s has a 3D body" % id)
	var man := SpriteUnit.spawn("npc_elder")
	var child := SpriteUnit.spawn("npc_child")
	assert_between(man.height, 1.4, 2.4, "an elder is man-sized")
	assert_true(child.height < man.height * 0.9, "a child is smaller than a man")
	man.free()
	child.free()
	# The pilot chapter's villagers walk as their own bodies.
	var reeve := false
	var cc := CampaignCatalog.get_default()
	var ch := {}
	for c: Dictionary in cc.chapters("last_light"):
		if String(c.get("file", "")) == "ll_harvest.json":
			ch = c
	for n: Dictionary in cc.mission(ch).get("npcs", []):
		if n["id"] == "reeve":
			reeve = n["look"] == "npc_elder"
	assert_true(reeve, "Reeve Dace walks as the village elder")
