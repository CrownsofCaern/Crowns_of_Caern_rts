extends "res://tests/test_case.gd"
## Hero bodies (assets/heroes3d/<class>.glb), their weapons in hand, and the
## faction worker bodies (assets/units3d/worker_<faction>.glb).

const HEROES3D := "res://assets/heroes3d/"


func _classes() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes.json"))
	return data["classes"]


func test_every_hero_class_has_a_body() -> void:
	for cls in _classes():
		assert_true(LiveUnit.exists(cls, HEROES3D), "%s has a hero body" % cls)


func test_hero_bodies_stand_and_hold_their_weapons() -> void:
	var classes := _classes()
	for cls in ["knight", "ranger", "warlock", "anvilbreaker", "tidemarshal"]:
		var unit := LiveUnit.spawn(cls, HEROES3D)
		assert_true(unit != null, "%s spawns" % cls)
		if unit == null:
			continue
		assert_between(unit.height, 1.3, 2.2, "%s is hero-sized" % cls)
		for clip in ["idle", "move", "attack", "death"]:
			assert_true(unit.has_clip(clip), "%s has %s" % [cls, clip])
		var weapons: Array = classes[cls]["weapons"]
		var held := HeroGear3D.equip(unit, weapons)
		assert_eq(held.size(), weapons.size(), "%s holds all its weapons" % cls)
		for node in held:
			var socket := node.get_parent() as BoneAttachment3D
			assert_true(socket != null and socket.bone_name.begins_with("mixamorig_"), "%s rides a hand bone" % node.name)
		unit.free()


func test_every_faction_has_a_worker_body() -> void:
	for faction in ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]:
		var id: String = "worker_" + faction
		assert_true(LiveUnit.exists(id), "%s exists" % id)
		var unit := LiveUnit.spawn(id)
		if unit == null:
			continue
		assert_lt(unit.height, 1.6, "%s is smaller than a soldier" % id)
		assert_true(unit.has_clip("attack"), "%s has a gather swing" % id)
		unit.free()
