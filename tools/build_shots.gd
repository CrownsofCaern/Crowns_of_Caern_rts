extends SceneTree
## Stills of B with nothing selected: the build menu, then the nearest worker off to build.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/build_shots.gd -- /tmp/build

var _scene: Node2D
var _out := "/tmp/warbound_build"


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
	for i in 4:
		await process_frame
	_scene.hud_center.visible = false
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	_scene.factions = ["concord", "hollow"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	_scene.fog_enabled = false
	var w: SimWorld = _scene.world
	_scene.pick_hero(String(_scene.hero_classes()[0]))
	_advance(3.0)
	var home: Sector = w.economy.hall_of(0)
	var east := signf(w.economy.hall_of(1).center.x - home.center.x)
	var mid := home.center + Vector2(east * 420.0, 0.0)
	_scene.cam.position = home.center.lerp(mid, 0.5)
	_scene.cam.zoom = Vector2(0.75, 0.75)
	# Nothing selected, press B.
	_scene.selection.clear()
	_scene.selected_building = -1
	_scene.selected_sector = -1
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	_scene._unhandled_input(ev)
	_scene.paused = true
	await _shot("08_b_with_nothing_selected")
	# Pick Wall and lay it with two clicks: the nearest free worker walks out to build it.
	_scene._start_placing("wall", 0)
	var wall_at := home.center + Vector2(east * 640.0, 0.0)
	_scene._place(wall_at + Vector2(0, -150), false)
	_scene._place(wall_at + Vector2(0, 150), false)
	_scene.cam.position = home.center.lerp(wall_at, 0.6)
	_scene.paused = false
	_advance(9.0)
	_scene.paused = true
	await _shot("09_nearest_worker_builds")
	quit()
