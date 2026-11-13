extends SceneTree
## Stills of the compact unit-building panel (units, queue, upgrades) above the building emblems:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/panel_shots.gd -- /tmp/panel

var _scene: Node2D
var _out := "/tmp/warbound_panel"


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
	var ids: Array = []
	for u in eco.workers_of(0):
		ids.append(u.id)
	for t in [1, 3]:
		var spot := EconomyAi.find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
		var b := eco.command_build(ids, 0, "dwelling", t, spot)
		if b != null:
			b.progress = 1.0
	_advance(0.5)
	var dw: Building = null
	for b in eco.buildings:
		if b.owner == 0 and b.kind == "dwelling" and b.trains(1):
			dw = b
	_scene.selected_building = dw.id
	_scene.cam.position = dw.pos + Vector2(0, 160)
	_scene.cam.zoom = Vector2(0.75, 0.75)
	await _shot("01_units_and_upgrades")
	for i in 3:
		eco.command_train(0, dw.id, 1)
	eco.command_train(0, dw.id, 2)
	_advance(4.0)
	await _shot("02_queue_training")
	_advance(60.0)
	eco.command_upgrade_dwelling(0, dw.id, 1)
	_advance(eco.dwelling_upgrade_seconds(1) * 0.4)
	await _shot("03_upgrading")
	quit()

