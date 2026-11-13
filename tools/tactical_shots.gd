extends SceneTree
## Stills of the tactical map and the skirmish's greyed-out fog:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/tactical_shots.gd -- <out dir> [seconds] [template]
## Player 0 is played by a computer player for <seconds> (default 240) so there is something to see.

var _scene: Node2D
var _out := "/tmp/tactical"
var _seconds := 240.0
var _p0: EconomyAi


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_seconds = float(args[1])
	if args.size() > 2:
		var setup := SkirmishSetup.new()
		setup.map = args[2]
		SkirmishSetup.current = setup
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _shot(name: String) -> void:
	_scene.paused = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 900)
	_scene.hud_help.visible = false
	_p0 = EconomyAi.new(0)
	var w: SimWorld = _scene.world
	for i in int(_seconds * w.tick_rate):
		for a in _scene.ais:
			a.update(w)
		_p0.update(w)
		w.step()
		_scene._collect_events()
	_scene.pick_hero(_scene.hero_classes()[0])
	var home: Sector = w.economy.hall_of(0)
	_scene.cam.position = home.center + Vector2(900, 300)
	_scene.cam.zoom = Vector2(0.35, 0.35)
	await _shot("01_3d_greyed_fog")
	_scene.toggle_tactical()
	await _shot("02_tactical_full_map")
	_scene.zoom_map(2.2, Vector2(root.size) * 0.5 + (home.center - _scene.cam.position) * _scene.cam.zoom.x)
	await _shot("03_tactical_zoomed")
	# Close looks at the sprites: the home base, then the biggest group of soldiers.
	_scene.cam.zoom = Vector2(0.75, 0.75)
	_scene.cam.position = home.center + Vector2(120, 60)
	await _shot("05_tactical_home_close")
	var best := home.center
	var best_n := 0
	for u in w.units:
		if u.is_worker() or not _scene.can_see(u):
			continue
		var n := 0
		for o in w.units:
			if not o.is_worker() and o.pos.distance_to(u.pos) < 260.0:
				n += 1
		if n > best_n:
			best_n = n
			best = u.pos
	_scene.cam.zoom = Vector2(1.0, 1.0)
	_scene.cam.position = best
	await _shot("06_tactical_army_close")
	_scene.toggle_tactical()
	_scene.fog_grey = false
	_scene._fog_tick = -1
	await _shot("04_3d_campaign_black_fog")
	quit()
