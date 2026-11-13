extends "res://tests/test_case.gd"
## Workers gather on their own; the player sets how they share out over the resources.


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _share(w: SimWorld, owner: int, resource: String) -> float:
	var on := 0
	var all := 0
	for u in w.economy.workers_of(owner):
		if u.order == SimUnit.Order.GATHER:
			all += 1
			if w.economy.node(u.job).resource == resource:
				on += 1
	return float(on) / maxf(1.0, float(all))


func test_workers_start_gathering_by_themselves() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	_run(w, 5.0)
	var gathering := 0
	for u in w.economy.workers_of(0):
		if u.order == SimUnit.Order.GATHER:
			gathering += 1
	assert_gt(gathering, 2, "workers find piles without orders")


func test_weights_split_the_gatherers() -> void:
	# Example from playtests: 3x wood, 1x ore, everything else 0x.
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	_run(w, 5.0)
	for r in eco.gather_resources(0):
		eco.set_gather_weight(0, r, 0)
	eco.set_gather_weight(0, "wood", 3)
	eco.set_gather_weight(0, "ore", 1)
	assert_eq(eco.gather_weight(0, "wood"), 3)
	var c := eco.gather_counts(0)
	var all := 0
	for r in c:
		all += int(c[r])
	var t := eco.gather_targets(0, all)
	assert_eq(int(t["wood"]) + int(t["ore"]), all, "only wood and ore get workers")
	assert_eq(c, t, "the gatherers move at once to match: %s" % str(c))
	assert_true(absi(int(c["wood"]) - 3 * int(c["ore"])) <= 2, "about three on wood for each on ore: %s" % str(c))
	# A new worker joins the resource furthest below its share.
	var u := eco._spawn_worker(0, eco.hall_of(0), eco.hall_of(0).center)
	assert_true(eco.node(u.job).resource in ["wood", "ore"])
	# Bounds, and resources the faction does not use, are ignored.
	eco.set_gather_weight(0, "wood", 99)
	assert_eq(eco.gather_weight(0, "wood"), int(eco.e["gather_weights"]["max"]))
	eco.set_gather_weight(0, "sulfur", 5)  # Concord does not gather sulfur
	assert_false(eco.player(0).gather_weights.has("sulfur"))


func test_targets_share_by_largest_remainder() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	for r in eco.gather_resources(0):
		eco.player(0).gather_weights[r] = 0
	eco.player(0).gather_weights["wood"] = 2
	eco.player(0).gather_weights["ore"] = 1
	var t := eco.gather_targets(0, 7)
	assert_eq(int(t["wood"]), 5, str(t))
	assert_eq(int(t["ore"]), 2, str(t))
	for r in eco.gather_resources(0):
		eco.player(0).gather_weights[r] = 0
	var even := eco.gather_targets(0, 4)
	var sum := 0
	for r in even:
		sum += int(even[r])
	assert_eq(sum, 4, "all at 0x counts as all equal: nobody stands about")


func test_building_takes_the_worker_the_mix_can_spare() -> void:
	# Five gatherers, 3x wood and 1x ore wanted, four on wood and one on ore: the builder
	# comes off wood, even when an ore worker stands closer.
	var w := SkirmishScenario.build_skirmish(7, ["concord", "hollow"])
	var eco := w.economy
	for u in eco.workers_of(0):
		u.alive = false
	w.step()
	for r in eco.gather_resources(0):
		eco.player(0).gather_weights[r] = 0
	eco.player(0).gather_weights["wood"] = 3
	eco.player(0).gather_weights["ore"] = 1
	var home := eco.hall_of(0)
	var wood_node: ResNode = null
	var ore_node: ResNode = null
	for n in eco.nodes:
		if eco.sectors[n.sector].owner == 0:
			if n.resource == "wood" and wood_node == null:
				wood_node = n
			if n.resource == "ore" and ore_node == null:
				ore_node = n
	var wt := w.catalog.worker_type("concord")
	var ore_man := w.spawn(wt, 0, home.center + Vector2(40, 0))
	eco._set_job(ore_man, SimUnit.Order.GATHER, ore_node.id)
	for i in 4:
		var u := w.spawn(wt, 0, home.center + Vector2(200 + i * 20, 0))
		eco._set_job(u, SimUnit.Order.GATHER, wood_node.id)
	var pick := eco.spare_worker(0, home.center + Vector2(30, 0))
	assert_true(pick != null and pick.id != ore_man.id and eco.node(pick.job).resource == "wood",
		"the builder comes off wood")
	ore_man.order = SimUnit.Order.IDLE
	assert_eq(eco.spare_worker(0, home.center).id, ore_man.id, "an idle worker goes first")


func test_marching_soldiers_engage_enemies_on_the_way() -> void:
	var w := SimWorld.new(3)
	w.setup_map(60, 20)
	var a := w.spawn("pike_militia", 0, Vector2(200, 300))
	var e := w.spawn("pike_militia", 1, Vector2(600, 300))
	w.command_hold([e.id])
	w.command_attack_move([a.id], Vector2(1500, 300))
	var fought := false
	for i in int(20 * w.tick_rate):
		w.step()
		for ev in w.events:
			fought = fought or (ev["type"] == "attack" and ev["unit"] == a.id)
		if fought:
			break
	assert_true(fought, "an attack-moving unit fights what it meets")


func test_fog_of_war_tracks_sight_and_memory() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["darkelf", "concord"])
	for i in 10:
		w.step()
	var v := w.vision
	var home0 := w.economy.hall_of(0).center
	var home1 := w.economy.hall_of(1).center
	assert_true(v.is_visible(0, home0), "a player sees its own home")
	assert_false(v.is_explored(0, home1), "and not the enemy's at the start")
	# A scout reveals the enemy home; once it leaves, the land stays explored but dims.
	var scout := w.spawn("de_gloam_spear", 0, home1 + Vector2(0, 120))
	for i in Vision.UPDATE_TICKS + 1:
		w.step()
	assert_true(v.is_visible(0, home1), "the scout sees the enemy home")
	scout.alive = false
	for i in Vision.UPDATE_TICKS * 2 + 2:
		w.step()
	assert_false(v.is_visible(0, home1 + Vector2(0, 120)))
	assert_true(v.is_explored(0, home1 + Vector2(0, 120)), "explored land is remembered")


func test_whisper_web_sees_farther() -> void:
	var w := SkirmishScenario.build_skirmish(7, ["darkelf", "concord"])
	for u in w.units:
		u.alive = false
	w.step()
	var mid := w.nav.world_size() * 0.5
	var a := w.spawn("de_gloam_spear", 0, mid)
	var b := w.spawn("pike_militia", 1, mid)
	for i in Vision.UPDATE_TICKS + 1:
		w.step()
	var scale := float(w.catalog.rules.get("vision_scale", 1.0))
	var far := mid + Vector2(float(b.def["sight"]) * scale * 1.15, 0)
	assert_true(w.vision.is_visible(0, far), "Dark Elves see past normal sight")
	assert_false(w.vision.is_visible(1, far), "Concord does not")
	var near := mid + Vector2(float(b.def["sight"]) * (scale - 0.1), 0)
	assert_true(w.vision.is_visible(1, near), "everyone sees a little past their fighting range (vision_scale)")
