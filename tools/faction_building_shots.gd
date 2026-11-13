extends SceneTree
## Stills of the faction buildings (two per house, economy.json faction_buildings):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/faction_building_shots.gd -- /tmp/faction_buildings [faction,...]

var _scene: Node2D
var _out := "/tmp/warbound_faction_buildings"
var _factions: Array = ["concord", "darkelf", "frostmarch", "ashen"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_factions = Array(args[1].split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(seconds * w.tick_rate):
		w.step()
		_scene._collect_events()


func _shot(name: String) -> void:
	_scene.paused = true
	for i in 8:
		await process_frame
	_scene.hud_center.visible = false
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)
	_scene.paused = false


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	var n := 0
	for f: String in _factions:
		n += 1
		if _scene != null:
			_scene.queue_free()
			await process_frame
		_scene = load("res://scenes/skirmish.tscn").instantiate()
		root.add_child(_scene)
		await process_frame
		_scene.factions = [f, "hollow" if f != "hollow" else "concord"]
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
		pl.hall_level = 2
		var home: Sector = eco.hall_of(0)
		var made: Array = []
		for d: Dictionary in eco.special_defs(f):
			var spot := EconomyAi.find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
			var b := eco.command_build([], 0, "special", 0, spot, d["id"])
			if b != null:
				b.progress = 1.0
				made.append(b)
		_advance(1.0)
		if n == 1:
			_scene.cam.position = home.center + Vector2(0, 120)
			_scene.cam.zoom = Vector2(0.75, 0.75)
			_scene._build_menu_open = true
			_scene._menu_selection = _scene.selection.duplicate()
			await _shot("%02d_%s_build_menu" % [n, f])
			_scene._build_menu_open = false
		for b: Building in made:
			_scene.selected_building = b.id
			_scene.cam.position = b.pos + Vector2(0, 140)
			_scene.cam.zoom = Vector2(0.9, 0.9)
			await _shot("%02d_%s_%s" % [n, f, b.special])
		_scene.selected_building = -1
	quit()
