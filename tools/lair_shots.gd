extends SceneTree
## Close stills of the monster lairs in the game's own view (fog off), one per tier and biome:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/lair_shots.gd -- <out dir> [faction,faction] [seed]

var _out := "/tmp/lair_shots"
var _factions: Array = ["frostmarch", "hollow"]
var _seed := 101


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_factions = Array(args[1].split(","))
	if args.size() > 2:
		_seed = int(args[2])
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var scene: Node2D = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.factions = _factions
	scene._start(_seed)
	scene.fog_enabled = false
	scene.hud_help.visible = false
	scene.hud_center.visible = false
	var hc := HeroCatalog.get_default()
	for c in hc.classes:
		if hc.classes[c]["faction"] == _factions[0]:
			scene.pick_hero(c)
			break
	var atmo: Atmosphere3D = scene.view3d.scene.atmosphere
	if atmo != null:
		atmo.weather_enabled = false
	var w: SimWorld = scene.world
	var taken := {}
	for st in w.sites.all:
		if st["kind"] != "lair":
			continue
		var biome: String = scene.view3d.field.biome_at(TerrainField.to_world(st["pos"]))
		var key := "%s_t%d" % [biome, int(st["tier"])]
		if taken.has(key):
			continue
		taken[key] = true
		scene.cam.position = st["pos"]
		scene.cam.zoom = Vector2(1.1, 1.1)
		for i in 3:
			await process_frame
		if atmo != null:
			atmo.step(8.0)
		for i in 3:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/lair_%s.png" % [_out, key])
		print("saved ", key)
	quit()
