extends SceneTree
## Stills of the hall's levels and dwelling upgrades:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/upgrade_shots.gd -- /tmp/upgrades

var _scene: Node2D
var _out := "/tmp/warbound_upgrades"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(seconds * w.tick_rate):
		w.step()
		_scene._collect_events()


func _shot(name: String) -> void:
	_scene.paused = true
	for i in 6:
		await process_frame
	_scene.hud_center.visible = false
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)
	_scene.paused = false


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	_scene.factions = ["concord", "hollow"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	_scene.fog_enabled = false
	var w: SimWorld = _scene.world
	var eco := w.economy
	for u in w.units.duplicate():
		if u.owner == 1 and not u.is_worker():
			w.retire(u)
	_scene.pick_hero(String(_scene.hero_classes()[0]))
	var pl := eco.player(0)
	for r in pl.res:
		pl.res[r] = 9000
	var home: Sector = eco.hall_of(0)
	_scene.selected_sector = home.id
	_scene.cam.position = home.center + Vector2(0, 120)
	_scene.cam.zoom = Vector2(0.75, 0.75)
	await _shot("01_hall_level_1")
	for lv in 3:
		eco.command_upgrade_hall(0)
		_advance(float(eco.e["hall_levels"][pl.hall_level]["seconds"]) + 0.2)
	await _shot("02_hall_level_4")
	_scene.selected_sector = -1
	var ids: Array = []
	for u in eco.workers_of(0):
		ids.append(u.id)
	var dws: Array = []
	for t in [3, 5, 6]:
		var spot := EconomyAi.find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
		var b := eco.command_build(ids, 0, "dwelling", t, spot)
		if b != null:
			b.progress = 1.0
	_advance(0.5)
	for b in eco.buildings:
		if b.owner == 0 and b.kind == "dwelling":
			dws.append(b)
	var target: Building = dws[min(1, dws.size() - 1)]
	_scene.selected_building = target.id
	_scene.cam.position = target.pos + Vector2(0, 160)
	await _shot("03_dwelling_before")
	for b in dws:
		eco.command_upgrade_dwelling(0, b.id, b.tiers[-1])
	_advance(eco.dwelling_upgrade_seconds(8) + 1.0)
	for b in dws:
		for t in b.tiers:
			eco.command_train(0, b.id, t)
			eco.command_train(0, b.id, t)
	_advance(12.0)
	await _shot("04_dwelling_after")
	# Base and upgraded unit side by side.
	_scene.selected_building = -1
	var cat := w.catalog
	var x0 := home.center + Vector2(-260, 260)
	var t := 0
	for id in cat.faction_units("concord"):
		w.spawn(id, 0, x0 + Vector2(t * 70.0, 0))
		w.spawn(cat.upgrade_of_unit(id), 0, x0 + Vector2(t * 70.0, 90))
		t += 1
	_advance(0.3)
	_scene.cam.position = x0 + Vector2(250, 40)
	_scene.cam.zoom = Vector2(1.1, 1.1)
	await _shot("05_base_vs_upgraded")
	quit()
