extends "res://tests/test_case.gd"
## The compact unit-building panel: icon buttons with the cost beside them, an up-arrow on upgrades.


func _find(n: Node, cls: String) -> Array:
	var out: Array = []
	if (cls == "UpArrow" and n is BuildPanel.UpArrow) or (cls != "UpArrow" and n.get_class() == cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out


func test_side_icons_put_the_cost_next_to_the_icon() -> void:
	var bp := BuildPanel.new()
	var row := bp._icon_row([{"texture": null, "badge": "1", "cost": {"gold": 15, "wood": 6}, "tooltip": "Train"}], true)
	var cell: Node = row.get_child(0)
	assert_true(cell is HBoxContainer, "side layout: icon and cost in one row")
	assert_true(cell.get_child(0) is Button, "the icon comes first")
	assert_true(cell.get_child(1) is VBoxContainer, "the cost column sits beside it")
	assert_eq(cell.get_child(1).get_child_count(), 2, "one line per resource")
	assert_eq(_find(row, "UpArrow").size(), 0, "no arrow without arrow: true")
	row.free()
	bp.free()


func test_upgrade_icons_carry_an_up_arrow() -> void:
	var bp := BuildPanel.new()
	var row := bp._icon_row([{"texture": null, "arrow": true, "cost": {"gold": 250}}], true)
	assert_eq(_find(row, "UpArrow").size(), 1)
	row.free()
	bp.free()


func test_every_upgraded_unit_has_a_portrait() -> void:
	var cat := UnitCatalog.get_default()
	for id: String in cat.units:
		var up := cat.upgrade_of_unit(id)
		if up != "":
			assert_true(ResourceLoader.exists(String(cat.get_unit(up)["sprite"])), "no sprite for upgraded unit " + up)
