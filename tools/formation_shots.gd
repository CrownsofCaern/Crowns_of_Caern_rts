extends SceneTree
## Stills of two armies meeting in melee blocks (SimFormation), at zoom 0.6:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/formation_shots.gd -- /tmp/blocks
## The Concord cavalry is sent round the flank onto the Hollow archers by hand, to show
## that picked targets still work next to the blocks.

var _scene: Node2D
var _out := "/tmp/warbound_blocks"


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


func _army(w: SimWorld, owner: int, spec: Array, at: Vector2) -> Array:
	var ids: Array = []
	var i := 0
	for e in spec:
		for n in int(e[1]):
			var p := at + Vector2((i / 6) * 28.0 * (-1.0 if owner == 0 else 1.0), (i % 6 - 2.5) * 28.0)
			ids.append(w.spawn(String(e[0]), owner, p).id)
			i += 1
	return ids


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
	var c := _open_spot(w, 200.0, home.center + Vector2(700, 0))
	var a := _army(w, 0, [["pike_militia", 8], ["shieldwarden", 6], ["longbowman", 4]], c + Vector2(-330, 0))
	var horse := _army(w, 0, [["lancer", 3]], c + Vector2(-420, 150))
	var b := _army(w, 1, [["shambler", 10], ["gibbet_knight", 4], ["marrow_archer", 4]], c + Vector2(330, 0))
	w.command_attack_move(a, c + Vector2(300, 0))
	w.command_attack_move(b, c + Vector2(-300, 0))
	_scene.cam.position = c
	_scene.cam.zoom = Vector2(0.6, 0.6)
	_scene.selection.clear()
	_advance(0.5)
	await _shot("01_armies_form_up")
	_advance(3.5)
	await _shot("02_blocks_close_in")
	# Cavalry round the flank onto the archers at the back of the Hollow block.
	var archers: Array = []
	for id in b:
		var u := w.get_unit(id)
		if u != null and u.is_ranged():
			archers.append(u)
	if not archers.is_empty():
		w.command_move(horse, c + Vector2(150, 260))
	_advance(3.0)
	await _shot("03_contact")
	for t in archers:
		if t.alive:
			w.command_attack(horse, t.id)
			break
	_advance(5.0)
	await _shot("04_grinding")
	_advance(8.0)
	await _shot("05_ranks_close_up")
	_scene.cam.zoom = Vector2(1.2, 1.2)
	await _shot("06_close_view")
	quit()
