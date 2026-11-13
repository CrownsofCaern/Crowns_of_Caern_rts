extends "res://tests/test_case.gd"
## Control groups: Ctrl + number stores or clears a group, the number (or its portrait) selects it,
## and the portrait shows the group's strongest unit.


func _setup() -> Array:
	var w := SimWorld.new(3)
	w.setup_map(60, 40)
	var types: Array = w.catalog.faction_units("concord")
	var low := w.spawn(types[0], 0, Vector2(400, 400))
	var mid := w.spawn(types[3], 0, Vector2(430, 400))
	var top := w.spawn(types[6], 0, Vector2(460, 400))
	var sk := Skirmish.new()
	sk.world = w
	return [sk, low, mid, top]


func test_ctrl_number_stores_the_selection() -> void:
	var s := _setup()
	var sk: Skirmish = s[0]
	sk.selection = [s[1].id, s[2].id]
	sk.set_group(1)
	assert_eq(sk.groups[1], [s[1].id, s[2].id])
	sk.selection = []
	sk.recall_group(1)
	assert_eq(sk.selection, [s[1].id, s[2].id], "the number key selects the whole group")
	sk.free()


func test_ctrl_number_with_nothing_selected_clears_the_group() -> void:
	var s := _setup()
	var sk: Skirmish = s[0]
	sk.selection = [s[1].id]
	sk.set_group(2)
	sk.selection = []
	sk.set_group(2)
	assert_false(sk.groups.has(2), "Ctrl + 2 with nothing selected deletes group 2")
	sk.recall_group(2)
	assert_true(sk.selection.is_empty())
	sk.free()


func test_recall_drops_the_dead_and_forgets_wiped_groups() -> void:
	var s := _setup()
	var sk: Skirmish = s[0]
	sk.selection = [s[1].id, s[3].id]
	sk.set_group(3)
	(s[3] as SimUnit).alive = false
	sk.selection = []
	sk.recall_group(3)
	assert_eq(sk.selection, [s[1].id])
	(s[1] as SimUnit).alive = false
	sk.selection = [s[2].id]
	sk.recall_group(3)
	assert_false(sk.groups.has(3), "a group whose units all fell is gone")
	assert_eq(sk.selection, [s[2].id], "and pressing its key leaves the selection alone")
	sk.free()


func test_portrait_is_the_strongest_unit() -> void:
	var s := _setup()
	var sk: Skirmish = s[0]
	var units := GroupBar.alive_units(sk.world, [s[1].id, s[3].id, s[2].id])
	assert_eq(GroupBar.strongest(units), s[3], "highest tier wins")
	var hero := sk.world.heroes.spawn_hero(0, "knight", Vector2(500, 400))
	units.append(hero)
	assert_eq(GroupBar.strongest(units), hero, "a hero outranks any soldier")
	assert_eq(GroupBar.strongest([]), null)
	sk.free()


func test_bar_lists_only_groups_with_living_units() -> void:
	var s := _setup()
	var sk: Skirmish = s[0]
	sk.groups = {1: [s[1].id], 4: [s[2].id, s[3].id], 5: [999]}
	var bar := GroupBar.new()
	bar.skirmish = sk
	assert_eq(bar.shown_groups(), [1, 4])
	bar.free()
	sk.free()
