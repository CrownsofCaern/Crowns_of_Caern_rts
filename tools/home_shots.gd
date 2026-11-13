extends SceneTree
## One still per faction of its grown home on its own ground (building contrast check):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/home_shots.gd -- <out dir> [faction,...] [seconds]

var _scene: Node2D
var _out := "/tmp/home_shots"
var _factions: Array = ["concord", "ashen", "hollow", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]
var _grow := 150.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1] != "all":
		_factions = Array(args[1].split(","))
	if args.size() > 2:
		_grow = float(args[2])
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	for f: String in _factions:
		if _scene != null:
			_scene.queue_free()
			await process_frame
		_scene = load("res://scenes/skirmish.tscn").instantiate()
		root.add_child(_scene)
		await process_frame
		_scene.factions = [f, "concord" if f != "concord" else "hollow"]
		_scene._start(101)
		_scene.hud_help.visible = false
		_scene.hud_center.visible = false
		var hc := HeroCatalog.get_default()
		for c in hc.classes:
			if hc.classes[c]["faction"] == f:
				_scene.pick_hero(c)
				break
		var w: SimWorld = _scene.world
		var mine := EconomyAi.new(0)
		for i in int(_grow * w.tick_rate):
			for a in _scene.ais:
				a.update(w)
			mine.update(w)
			w.step()
			_scene._collect_events()
		var home: Sector = w.economy.hall_of(0)
		_scene.cam.position = home.center + Vector2(40, 40)
		var atmo: Atmosphere3D = _scene.view3d.scene.atmosphere
		if atmo != null:
			atmo.weather_enabled = false
		for i in 2:
			await process_frame
		if atmo != null:
			atmo.step(8.0)
		for i in 4:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, f])
		print("saved ", f)
	quit()
