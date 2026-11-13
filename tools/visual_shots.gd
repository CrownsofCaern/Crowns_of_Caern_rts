extends SceneTree
## Stills and clip frames of the view's finishing touches: the home with the ink outlines
## and living land off and on, frames of the living land, of a building going up, and of
## a fight close up. Run with a fixed frame rate so clips play at the right speed:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 12 --script res://tools/visual_shots.gd -- <out dir> [frames]
## Make a clip: ffmpeg -framerate 12 -i <dir>/living/%03d.png -vf scale=800:-1 living.gif

var _scene: Node2D
var _out := "/tmp/visual_shots"
var _frames := 48
var _p0_ai: EconomyAi


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_frames = int(args[1])
	for d in ["", "/living", "/build", "/fight"]:
		DirAccess.make_dir_recursive_absolute(_out + d)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(round(seconds * w.tick_rate)):
		for a in _scene.ais:
			a.update(w)
		_p0_ai.update(w)
		w.step()
		_scene._collect_events()


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + path + ".png")


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _look(on: bool) -> void:
	var look: LookFx3D = _scene.view3d.look
	look.ink = on
	look.ambience = on


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 900)
	_scene.factions = ["concord", "hollow"]
	_scene._start(101)
	_p0_ai = EconomyAi.new(0)
	_scene.hud_help.visible = false
	_scene.hud_center.visible = false
	var hc := HeroCatalog.get_default()
	for c in hc.classes:
		if hc.classes[c]["faction"] == "concord":
			_scene.pick_hero(c)
			break
	var atmo: Atmosphere3D = _scene.view3d.scene.atmosphere
	atmo.weather_enabled = false
	var eco: Economy = _scene.world.economy
	var home: Sector = eco.hall_of(0)
	_advance(150.0)
	_scene.paused = true
	_scene.cam.position = home.center + Vector2(60, 60)
	_look(false)
	await _settle(4)
	_save("home_before")
	_look(true)
	await _settle(4)
	_save("home_after")
	print("saved home stills")
	# The living land: the same view over a few seconds.
	for i in _frames:
		await process_frame
		_save("living/%03d" % i)
	print("saved living frames")
	# A building going up, close, with the game running (the builders work).
	var site: Building = null
	var spot := EconomyAi.find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
	var ws := _p0_ai._nearest_workers(eco, spot, 3) if spot != Vector2.INF else []
	for r in ["gold", "wood", "stone"]:
		eco.player(0).res[r] = eco.player(0).amount(r) + 500
	for t in range(1, eco.max_tier(0) + 1):
		if site == null and not ws.is_empty():
			site = eco.command_build(ws, 0, "dwelling", t, spot)
	if site == null and not ws.is_empty():
		site = eco.command_build(ws, 0, "storehouse", 1, spot)
	print("build site: spot %s, %d workers, %s" % [spot, ws.size(), site])
	for i in 60:
		if site == null or site.progress > 0.3:
			break
		_advance(1.0)
	if site != null:
		_scene.cam.position = site.pos + Vector2(0, 30)
		_scene.cam.zoom = Vector2(1.1, 1.1)
		_scene.paused = false
		for i in _frames:
			await process_frame
			_save("build/%03d" % i)
		_scene.paused = true
		print("saved build frames (%s at %.0f%%)" % [site.key, site.progress * 100.0])
	# A fight close up: two small bands meet in the open by the home.
	_scene.fog_enabled = false
	var w: SimWorld = _scene.world
	var at := spot + Vector2(160, 0)
	for i in 5:
		w.spawn("pike_militia", 0, at + Vector2(-70, (i - 2) * 22))
		w.spawn("shambler" if i % 2 == 0 else "charnel_hulk", 1, at + Vector2(70, (i - 2) * 22))
	_scene.paused = true
	_advance(2.5)
	_scene.cam.position = at + Vector2(0, 30)
	_scene.cam.zoom = Vector2(1.6, 1.6)
	_scene.paused = false
	for i in _frames:
		await process_frame
		_save("fight/%03d" % i)
	print("saved fight frames")
	quit()
