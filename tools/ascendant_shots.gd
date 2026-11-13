extends SceneTree
## Stills of Ascendant units (veteran level 5): their aura, and one burning away into light
## when it falls. Also the unit card with its rank star and the retreat foot.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/ascendant_shots.gd -- /tmp/asc

var _scene: Node2D
var _out := "/tmp/warbound_ascendant"


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


func _shot(name: String, frames: int = 4) -> void:
	for i in frames:
		await process_frame
	_scene.hud_center.visible = false
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


## The most open spot near `mid`: no blocked cell within `r` px.
func _open_spot(w: SimWorld, r: float, mid: Vector2) -> Vector2:
	for ring in 40:
		for k in 16:
			if ring == 0 and k > 0:
				break
			var p := mid + Vector2(ring * 48.0, 0).rotated(TAU * k / 16.0)
			var ok := true
			for dy in range(-int(r), int(r) + 1, 24):
				for dx in range(-int(r * 1.6), int(r * 1.6) + 1, 24):
					if w.nav.is_blocked(p + Vector2(dx, dy)):
						ok = false
			if ok:
				return p
	return mid


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	_scene.factions = ["concord", "hollow"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	var w: SimWorld = _scene.world
	for u in w.units.duplicate():
		if u.owner == 1 and not u.is_worker():
			w.retire(u)
	_scene.pick_hero(String(_scene.hero_classes()[0]))
	var home: Sector = w.economy.hall_of(0)
	var c := _open_spot(w, 160.0, home.center + Vector2(800, 200))
	var ids: Array = []
	var kinds := ["pike_militia", "shieldwarden", "lancer", "longbowman", "sunhawk_rider", "pike_militia"]
	for i in kinds.size():
		var u := w.spawn(kinds[i], 0, c + Vector2((i % 3) * 70.0 - 70.0, (i / 3) * 70.0 - 35.0))
		ids.append(u.id)
		if i < 5:
			w.set_veteran(u, 5)  # promoted on the way, then Ascendant
	_scene.cam.position = c
	_scene.cam.zoom = Vector2(1.6, 1.6)
	_scene.selection = [ids[2]]
	_advance(0.1)
	await _shot("01_ascendant_aura", 30)
	_scene.selection = ids.duplicate()
	w.command_retreat([ids[5]])
	await _shot("02_cards_rank_and_retreat_foot", 6)
	_scene.selection = []
	_scene.cam.zoom = Vector2(2.2, 2.2)
	var victim := w.get_unit(ids[0])
	_scene.cam.position = victim.pos
	await _shot("03_before", 6)
	# Headless rendering runs at a frame or two a second: slow time down so the fade shows.
	Engine.time_scale = 0.06
	# Killed inside a tick (a tick clears the events of the one before).
	victim.hp = 0.5
	victim.poison_left = 1.0
	victim.poison_dps = 1000.0
	_advance(0.05)
	for k in [["04_fading_a", 3], ["05_fading_b", 4], ["06_fading_c", 5], ["07_gone", 25]]:
		await _shot(String(k[0]), int(k[1]))
	Engine.time_scale = 1.0
	quit()
