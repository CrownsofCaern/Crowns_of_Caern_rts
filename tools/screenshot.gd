extends SceneTree
## Renders review screenshots of the battle scene:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- /tmp/shots [you,enemy]
## Advances the simulation by fixed steps (not real time) so shots are repeatable.

var _scene: Node2D
var _out := "/tmp/warbound_shots"
var _factions: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_factions = Array(args[1].split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


var _p0_ai: EconomyAi


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
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


## Player 0 is played by a second AI so the shots show a running economy.
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	await _shot("00_menu")
	if not _factions.is_empty():
		_scene.factions = _factions
	_scene._start(_scene.seed_value)
	_p0_ai = EconomyAi.new(0)
	_scene.hud_help.visible = false
	var eco: Economy = _scene.world.economy
	var home: Sector = eco.hall_of(0)
	_scene.cam.zoom = Vector2(0.8, 0.8)
	_scene.cam.position = home.center + Vector2(120, 0)
	for u in eco.workers_of(0):
		_scene.selection.append(u.id)
	_scene._build_menu_open = true
	await _shot("01_home_start")
	_scene.selection.clear()
	_advance(150.0)
	_scene.cam.position = home.center + Vector2(150, 0)
	_scene.selected_sector = home.id
	await _shot("02_home_150s")
	_scene.selected_sector = -1
	_advance(150.0)
	_scene.cam.zoom = Vector2(0.27, 0.27)
	_scene.cam.position = _scene.world.nav.world_size() * 0.5
	await _shot("03_map_300s")
	# Find a fight or a capture to look at.
	var best := Vector2.ZERO
	for i in 60:
		_advance(5.0)
		var found := false
		for u in _scene.world.units:
			if u.since_attack < 0.5 and not u.is_worker():
				best = u.pos
				found = true
				break
		if found:
			break
	if best != Vector2.ZERO:
		_scene.cam.zoom = Vector2(1.3, 1.3)
		_scene.cam.position = best
		await _shot("04_fight")
	quit()
