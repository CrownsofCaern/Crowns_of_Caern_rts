extends "res://tests/test_case.gd"
## The hero UI's art hooks and the hero window's item handling.

var hc: HeroCatalog = HeroCatalog.get_default()


class FakeSkirmish:
	extends Node
	var world: SimWorld


func _hero_world() -> Array:
	var w := SimWorld.new(5)
	w.setup_map(60, 40)
	w.heroes.spawn_hero(0, "knight", Vector2(600, 600))
	var sk := FakeSkirmish.new()
	sk.world = w
	var hw := HeroWindow.new()
	hw.skirmish = sk
	return [w, hw, sk]


func test_every_skill_has_an_icon() -> void:
	for sid: String in hc.skills:
		assert_true(HudArt.skill_icon(sid) != null, "no icon or stand-in for skill " + sid)


func test_every_passive_node_has_an_icon() -> void:
	var st := StoryTrees.get_default()
	for tid: String in st.trees:
		for n: Dictionary in st.trees[tid]["nodes"]:
			if n["kind"] == "passive":
				assert_true(HudArt.stat_icon(StoryTrees.node_icon(n)) != null, "no icon for passive " + String(n["id"]))


func test_every_class_has_a_portrait() -> void:
	for cid: String in hc.classes:
		assert_true(ResourceLoader.exists("res://assets/ui/heroes/%s.png" % cid), "no portrait for " + cid)


func test_every_gear_slot_has_a_symbol() -> void:
	for slot: String in ItemCatalog.SLOTS:
		assert_true(HudArt.slot_icon(slot) != null, "no empty-slot symbol for " + slot)


## The art importer cuts the skill sheets in the order of the art list: every skill exactly once.
func test_art_importer_covers_every_skill() -> void:
	var src := FileAccess.get_file_as_string("res://tools/import_ui_art.py")
	for sid: String in hc.skills:
		assert_eq(src.count("\"%s\"" % sid), 1, "import_ui_art.py lists " + sid)


func test_window_wears_and_takes_off_items() -> void:
	var r := _hero_world()
	var w: SimWorld = r[0]
	var hw: HeroWindow = r[1]
	var h := w.heroes.hero_of(0)
	var g := w.heroes.gear
	g.give(h, g.icat.make_unique("scarred_plate"))
	if h.worn.has("armor"):
		g.command_unequip(0, "armor")
	var j := h.bag.size() - 1
	assert_eq(String(h.bag[j]["slot"]), "armor")
	hw._click(h, g, {"kind": "bag", "key": j})
	assert_true(h.worn.has("armor"), "a click on a bag item wears it")
	hw._click(h, g, {"kind": "worn", "key": "armor"})
	assert_false(h.worn.has("armor"), "a click on a worn item takes it off")
	# Dragging a bag item out of the window drops it.
	var before := h.bag.size()
	hw._press = {"kind": "bag", "key": 0, "at": Vector2.ZERO}
	hw._drop(h, g, Vector2(-50, -50))
	assert_eq(h.bag.size(), before - 1, "dragged out of the window: dropped")
	r[2].free()
	hw.free()


func test_comparison_lines_show_gains_and_losses() -> void:
	var a := {"name": "A", "slot": "armor", "mods": {"defense": 4.0, "attack": 1.0}}
	var b := {"name": "B", "slot": "armor", "mods": {"defense": 3.0, "hp": 60.0}}
	var lines := HeroWindow._compare(a, b)
	assert_eq(lines[0], "~Instead of B:")
	assert_true("+1 defense" in lines, str(lines))
	assert_true("!-60 health" in lines, str(lines))
	assert_true("+1 attack" in lines, str(lines))
	assert_eq(HeroWindow._compare(a, {}).size(), 1, "an empty slot: one line")


func test_painted_frames_fit_their_openings() -> void:
	for name in ["bar_frame", "skill_slot", "portrait_frame", "node_active", "node_passive", "node_signature",
			"node_ultimate"]:
		var o := HudArt.opening(name)
		assert_true(o.position.x > 0.0 and o.position.y > 0.0 and o.end.x < 1.0 and o.end.y < 1.0,
			"opening of %s is not inside the frame: %s" % [name, o])
		# The opening of the placed frame lands exactly on the content.
		var content := Rect2(100, 50, 64, 64)
		var f := HudArt.frame_rect(name, content)
		var back := Rect2(f.position + o.position * f.size, o.size * f.size)
		assert_true(back.position.distance_to(content.position) < 0.01 and back.size.distance_to(content.size) < 0.01,
			"frame %s does not fit its content" % name)


class FakeTown:
	extends Node
	var world: SimWorld
	var factions: Array = ["concord", "hollow"]
	var selected_building: int = -1
	var selected_sector: int = -1
	var mission: StoryMission = null
	var looked: bool = false

	func select_building(id: int, look: bool = false) -> void:
		selected_building = id
		looked = look

	func select_sector(id: int, look: bool = false) -> void:
		selected_sector = id
		looked = look


func test_building_bar_selects_and_cycles() -> void:
	var sk := FakeTown.new()
	sk.world = SkirmishScenario.build_skirmish(123, ["concord", "hollow"])
	var bar := BuildingBar.new()
	bar.skirmish = sk
	var halls := bar.buildings_for("hall", 0)
	assert_eq(halls.size(), 1, "one home hall at the start")
	assert_true(bar.select_slot("hall", 0))
	assert_eq(sk.selected_sector, (halls[0] as Sector).id)
	assert_false(sk.looked, "the first click only selects")
	assert_true(bar.select_slot("hall", 0))
	assert_true(sk.looked, "a second click looks at it")
	# A tier with no building stays greyed and does nothing.
	var free_tier := 0
	for t in range(8, 0, -1):
		if bar.buildings_for("dwelling", t, false).is_empty():
			free_tier = t
			break
	assert_gt(free_tier, 0, "some tier is not built at the start")
	var before := sk.selected_building
	assert_false(bar.select_slot("dwelling", free_tier))
	assert_eq(sk.selected_building, before)
	bar.free()
	sk.free()
