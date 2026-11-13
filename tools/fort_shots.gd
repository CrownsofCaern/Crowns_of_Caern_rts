extends SceneTree
## Stills of walls, a gate, a tower with archers and the hall's arrows:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/fort_shots.gd -- /tmp/forts

var _scene: Node2D
var _out := "/tmp/warbound_forts"


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
	for u in w.units.duplicate():
		if u.owner == 1 and not u.is_worker():
			w.retire(u)
	_scene.pick_hero(String(_scene.hero_classes()[0]))
	var pl := w.economy.player(0)
	for r in pl.res:
		pl.res[r] = 5000
	var home: Sector = w.economy.hall_of(0)
	# The camera looks north, so an east-west wall shows its face: the foes come from the north.
	var toward := Vector2(0, -1)
	var side := Vector2(1, 0)
	var east := signf(w.economy.hall_of(1).center.x - home.center.x)
	var mid := home.center + Vector2(east * 750.0, 0.0)
	# A wall across the way out, with a gate in the middle and a tower beside it.
	var a := mid - side * 220.0
	var b := mid + side * 220.0
	var made := w.forts.command_build_wall([], 0, a, b)
	print("wall: %d pieces (%s)" % [made.size(), w.forts.plan(0, a, b)["problem"]])
	for p in made:
		p.progress = 1.0
	_advance(0.2)
	if made.size() >= 3:
		var m := made.size() / 2
		w.forts.command_upgrade(0, made[m].id, "gate")
		w.forts.command_upgrade(0, made[m + 1].id, "tower")
		_advance(30.0)
		var bows: Array = []
		for i in 2:
			bows.append(w.spawn("longbowman", 0, made[m + 1].pos - toward * 90.0 + side * (i * 30.0)).id)
		w.forts.command_garrison(bows, made[m + 1].id)
		_advance(6.0)
	_scene.cam.position = mid
	_scene.cam.zoom = Vector2(0.6, 0.6)
	_scene.selection.clear()
	await _shot("01_wall_gate_tower")
	# The Hollow come for it.
	var foes: Array = []
	for i in 10:
		var t := "shambler" if i < 7 else "marrow_archer"
		foes.append(w.spawn(t, 1, mid + toward * 420.0 + side * ((i % 5) - 2) * 34.0 + toward * (i / 5) * 34.0).id)
	w.command_attack_move(foes, mid - toward * 300.0)
	_advance(6.0)
	await _shot("02_assault")
	_advance(10.0)
	await _shot("03_hammering_the_wall")
	_scene.cam.zoom = Vector2(1.1, 1.1)
	await _shot("04_close_tower")
	_scene.cam.zoom = Vector2(0.6, 0.6)
	_advance(25.0)
	await _shot("05_later")
	# Hall arrows: a raid on the hall itself.
	var raid: Array = []
	for i in 6:
		raid.append(w.spawn("shambler", 1, home.center + Vector2(east * 330.0, 0.0) + side.orthogonal() * (i - 3) * 30.0).id)
	w.command_attack_move(raid, home.center)
	_scene.cam.position = home.center
	_advance(4.0)
	await _shot("06_hall_arrows")
	_advance(0.4)
	await _shot("07_hall_arrows_b")
	quit()
