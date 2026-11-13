extends "res://tests/test_case.gd"
## Workers run themselves: the player can't select them (clicks, boxes, double clicks and
## control groups pass them by).


func test_workers_cannot_be_selected() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var mine := w.economy.workers_of(0)
	var theirs := w.economy.workers_of(1)
	assert_gt(mine.size(), 0, "the player has workers")
	var soldier := w.spawn("pike_militia", 0, mine[0].pos)
	var foe := w.spawn("pike_militia", 1, mine[0].pos)
	for u in mine:
		assert_false(Skirmish.can_select(u, 0), "%s can't be selected" % u.type_id)
	assert_true(Skirmish.can_select(soldier, 0), "a soldier can")
	assert_false(Skirmish.can_select(foe, 0), "an enemy soldier can't")
	assert_false(Skirmish.can_select(theirs[0], 0), "an enemy worker can't")
	assert_false(Skirmish.can_select(null, 0))
	# A box or a control group over workers and soldiers keeps only the soldiers.
	var ids: Array = [mine[0].id, soldier.id, mine[1].id, foe.id]
	assert_eq(Skirmish.selectable(w, ids, 0), [soldier.id])

