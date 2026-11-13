extends SceneTree
## Art-direction stills of a running skirmish at play zoom: the home at the start, the
## grown home after a few minutes, the wilds, and a fight. Same seed, same frames each run,
## so before/after comparisons line up.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/look_shots.gd -- <out dir> [zoom|default] [you,enemy] [seed] [width] [nograde]

var _scene: Node2D
var _out := "/tmp/look_shots"
var _zoom := -1.0  ## < 0: the game's default
var _factions: Array = ["concord", "hollow"]
var _seed := 101
var _width := 1600
var _p0_ai: EconomyAi
var _no_grade := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1] != "default":
		_zoom = float(args[1])
	if args.size() > 2:
		_factions = Array(args[2].split(","))
	if args.size() > 3:
		_seed = int(args[3])
	if args.size() > 4:
		_width = int(args[4])
	_no_grade = args.size() > 5 and args[5] == "nograde"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(seconds * w.tick_rate):
		for a in _scene.ais:
			a.update(w)
		_p0_ai.update(w)
		w.step()
		_scene._collect_events()


func _shot(name: String) -> void:
	_scene.paused = true
	for i in 2:
		await process_frame
	# Let the light settle into the biome under the camera.
	var atmo: Atmosphere3D = _scene.view3d.scene.atmosphere
	if atmo != null and atmo.has_method("set_biome"):
		atmo.step(8.0)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	await process_frame
	root.size = Vector2i(_width, _width * 9 / 16)
	_scene.factions = _factions
	_scene._start(_seed)
	_p0_ai = EconomyAi.new(0)
	_scene.hud_help.visible = false
	_scene.hud_center.visible = false
	var hc := HeroCatalog.get_default()
	for c in hc.classes:
		if hc.classes[c]["faction"] == _factions[0]:
			_scene.pick_hero(c)
			break
	if _zoom > 0.0:
		_scene.cam.zoom = Vector2(_zoom, _zoom)
	var eco: Economy = _scene.world.economy
	var home: Sector = eco.hall_of(0)
	_scene.cam.position = home.center + Vector2(60, 60)
	var atmo: Atmosphere3D = _scene.view3d.scene.atmosphere
	if atmo != null:
		atmo.weather_enabled = false
		if _no_grade:
			atmo.environment.adjustment_color_correction = null
	await _shot("01_home_start")
	_advance(180.0)
	_scene.cam.position = home.center + Vector2(60, 60)
	await _shot("02_home_180s")
	# The wilds between the homes (no fog of war: the look of the land itself).
	_scene.fog_enabled = false
	var foe: Sector = eco.hall_of(1)
	_scene.cam.position = home.center.lerp(foe.center, 0.5)
	await _shot("03_wilds")
	var best := Vector2.ZERO
	for i in 80:
		_advance(5.0)
		var n := 0
		var at := Vector2.ZERO
		for u in _scene.world.units:
			if u.since_attack < 0.5 and not u.is_worker():
				n += 1
				at += u.pos
		if n >= 6:
			best = at / n
			break
	if best != Vector2.ZERO:
		_scene.cam.position = best
		await _shot("04_fight")
	quit()
