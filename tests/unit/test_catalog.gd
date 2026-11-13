extends "res://tests/test_case.gd"


func test_data_is_valid() -> void:
	var errors := catalog.validate()
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_two_factions_with_eight_units() -> void:
	for f in ["concord", "hollow"]:
		var ids := catalog.faction_units(f)
		assert_eq(ids.size(), 8, f)
		for i in ids.size():
			assert_eq(int(catalog.get_unit(ids[i])["tier"]), i + 1, "%s tier order" % f)


func test_counter_circle() -> void:
	assert_gt(catalog.matchup("infantry", "cavalry"), 1.0)
	assert_gt(catalog.matchup("cavalry", "ranged"), 1.0)
	assert_gt(catalog.matchup("ranged", "infantry"), 1.0)
	assert_gt(catalog.matchup("ranged", "flyer"), 1.0)
	assert_eq(catalog.matchup("heavy", "infantry"), 1.0)


## Every unit's portrait (the unit panel and the build bar) shows a framed part of its sprite:
## data/unit_portraits.json has a square for it, and that square holds a good share of the creature.
## Wide creatures (hounds, drakes, engines) fit whole, so their portrait is not cut on both sides.
func test_every_unit_sprite_has_a_framed_portrait() -> void:
	var ids: Array = catalog.units.keys()
	ids.sort()
	for id in ids:
		var path := String(catalog.get_unit(id)["sprite"])
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_true(img != null and not img.is_empty(), "%s: %s loads" % [id, path])
		if img == null or img.is_empty():
			continue
		var r := HudArt.unit_portrait_rect(path)
		assert_ne(r, Rect2(24, 14, 80, 80), "%s: %s has a framed portrait" % [id, path])
		var used := img.get_used_rect()
		if used.size.x >= used.size.y * 0.9:
			assert_true(r.encloses(used), "%s: the whole wide creature fits its portrait" % id)
		var opaque := 0
		var y := int(maxf(r.position.y, 0.0))
		while y < mini(int(r.end.y), img.get_height()):
			var x := int(maxf(r.position.x, 0.0))
			while x < mini(int(r.end.x), img.get_width()):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
				x += 2
			y += 2
		assert_gt(opaque, 400, "%s: portrait of %s is nearly empty" % [id, path])
