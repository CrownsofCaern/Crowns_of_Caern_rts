extends "res://tests/test_case.gd"
## The tactical map (Tab / F3 / the map button), the skirmish's greyed-out fog and the
## minimap's always-known settlements.


func _skirmish(fog_grey: bool = true) -> Skirmish:
	var w := SkirmishScenario.build_skirmish(4, ["concord", "hollow"])
	var sk := Skirmish.new()
	sk.world = w
	sk.fog_grey = fog_grey
	return sk


func test_every_pile_is_counted_in_its_sector() -> void:
	var sk := _skirmish()
	var res := TacticalMap.sector_resources(sk.world)
	var total := 0
	for sec in sk.world.economy.sectors:
		assert_true(res.has(sec.id), "every sector has a resource row, even an empty one")
		for k: String in res[sec.id]:
			total += int(res[sec.id][k])
			var keys: Array = res[sec.id].keys()
			var sorted := keys.duplicate()
			sorted.sort()
			assert_eq(keys, sorted, "the row's order never depends on pile order")
	assert_eq(total, sk.world.economy.nodes.size())
	assert_true(total > 0)
	sk.free()


func test_never_explored_settlements_look_unclaimed() -> void:
	var sk := _skirmish()
	var enemy_home := sk.world.economy.hall_of(1)
	assert_eq(enemy_home.owner, 1)
	assert_false(sk.has_explored(enemy_home.center), "the enemy capital starts in the fog")
	assert_eq(TacticalMap.known_owner(sk, enemy_home), -1, "who holds it stays hidden")
	assert_eq(TacticalMap.known_owner(sk, sk.world.economy.hall_of(0)), 0, "your own always shows")
	sk.fog_enabled = false
	assert_eq(TacticalMap.known_owner(sk, enemy_home), 1, "without fog everything shows")
	sk.free()


func test_skirmish_fog_greys_unexplored_land_campaign_keeps_it_black() -> void:
	for grey in [true, false]:
		var sk := _skirmish(grey)
		sk.world.step()
		var img := sk.fog_texture().get_image()
		var far := sk.world.economy.hall_of(1).center
		var c := Vector2i(int(far.x / Vision.CELL), int(far.y / Vision.CELL))
		var px := img.get_pixelv(c)
		if grey:
			assert_true(px.r > 0.2 and px.a < 0.95, "skirmish: a see-through grey veil, got %s" % px)
		else:
			assert_true(px.r < 0.01 and px.a > 0.99, "campaign: black, got %s" % px)
		var home := sk.world.economy.hall_of(0).center
		var hc := Vector2i(int(home.x / Vision.CELL), int(home.y / Vision.CELL))
		assert_true(img.get_pixelv(hc).a < 0.01, "home is in sight")
		sk.free()


func test_tactical_map_opens_on_the_whole_map_and_returns_the_camera() -> void:
	var sk := _skirmish()
	sk.cam = Camera2D.new()
	sk.audio = BattleAudio.new()
	sk.audio.muted = true
	sk.layer = Node2D.new()
	sk.view3d = SkirmishView3D.new()
	sk.view3d.overlay = Control.new()
	sk.view3d.camera = Camera3D.new()
	var home := Vector2(900, 700)
	sk.cam.position = home
	sk.cam.zoom = Vector2(0.55, 0.55)
	sk.toggle_tactical()
	assert_false(sk.mode_3d)
	var ws := sk.world.nav.world_size()
	assert_eq(sk.cam.position, sk.full_map_center(), "the map opens centred")
	var view := Vector2(1280, 800 - Skirmish.MAP_INSET_TOP - Skirmish.MAP_INSET_BOTTOM) / sk.cam.zoom
	assert_true(view.x >= ws.x and view.y >= ws.y, "and shows all of it between the HUD bars (%s for %s)" % [view, ws])
	sk.toggle_tactical()
	assert_true(sk.mode_3d)
	assert_eq(sk.cam.position, home, "unmoved, the 3D camera comes back where it was")
	assert_between(sk.cam.zoom.x, 0.5499, 0.5501)
	sk.toggle_tactical()
	sk.zoom_map(1.5, Vector2(300, 200))
	assert_true(sk.cam.zoom.x > sk.full_map_zoom(), "the map zooms in")
	var looked := sk.cam.position
	sk.toggle_tactical()
	assert_eq(sk.cam.position, looked, "after looking around the map, 3D looks there")
	sk.toggle_tactical()
	assert_eq(sk.cam.position, sk.full_map_center(), "opening again resets to the whole map")
	sk.zoom_map(0.5, Vector2(300, 200))
	assert_between(sk.cam.zoom.x, sk.full_map_zoom() - 0.0001, sk.full_map_zoom() + 0.0001, "never further out than the whole map")
	for n: Node in [sk.audio, sk.layer, sk.view3d.overlay, sk.view3d.camera, sk.view3d]:
		n.free()
	sk.cam.free()
	sk.free()
