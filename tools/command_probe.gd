extends SceneTree
## Checks the view's order handling on a real skirmish: what the cursor shows over each kind
## of target, right click to capture, shift-queued waypoints and queued building sites.
##   godot --headless --path . --script res://tools/command_probe.gd
## Optional stills (queue lines in 2D and 3D):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/command_probe.gd -- /tmp/cmd

var _scene: Node2D
var _out := ""
var _fails := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
		DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(seconds * w.tick_rate):
		w.step()
		_scene._collect_events()


func _shot(name: String) -> void:
	if _out == "":
		return
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


## The intent and cursor for a world point, in the 2D view (the mouse is not used there:
## _unit_at and friends take the point).
func _at(wp: Vector2) -> Array:
	var it: Dictionary = _scene.click_intent(wp)
	return [String(it["kind"]), it]


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	_scene.factions = ["concord", "hollow"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	_scene.fog_enabled = false
	_scene.mode_3d = false
	_scene._apply_mode()
	var w: SimWorld = _scene.world
	var eco := w.economy
	var home: Sector = eco.hall_of(0)
	var town: Sector = null
	for s in eco.sectors:
		if s.owner == -1 and s.size != "waystone" and (town == null or s.center.distance_to(home.center) < town.center.distance_to(home.center)):
			town = s
	# Troops next to home.
	var ids: Array = []
	for i in 12:
		ids.append(w.spawn("pike_militia", 0, w.nav.nearest_free(home.center + Vector2(200 + (i % 4) * 22, 120 + (i / 4) * 22))).id)
	_scene.selection = ids.duplicate()
	var foe := w.spawn("shambler", 1, w.nav.nearest_free(home.center + Vector2(-260, 160)))
	var ground: Vector2 = w.nav.nearest_free(home.center + Vector2(320, -260))
	var a := _at(ground)
	_check(a[0] == "move", "ground under soldiers: move (%s)" % a[0])
	a = _at(foe.pos + Vector2(0, -foe.radius() * 1.2))
	_check(a[0] == "attack", "enemy: attack (%s)" % a[0])
	a = _at(town.center)
	_check(a[0] == "capture", "neutral settlement: capture (%s)" % a[0])
	a = _at(home.center)
	_check(a[0] != "capture", "own settlement is no capture target (%s)" % a[0])
	# Workers over a pile: gather; over the wrong kind: the cursor says no.
	var worker: SimUnit = eco.workers_of(0)[0]
	_scene.selection = [worker.id]
	var pile: ResNode = null
	for n in eco.nodes:
		if eco.uses(0, n.resource) and (pile == null or n.pos.distance_to(home.center) < pile.pos.distance_to(home.center)):
			pile = n
	a = _at(pile.pos)
	_check(a[0] == "gather", "worker over a pile: gather (%s)" % a[0])
	# Cursor actions (headless: works out the action, sets no image).
	_scene.selection = ids.duplicate()
	var ca: String = _scene.cursor_action()
	_check(ca in CommandCursor.ACTIONS, "cursor_action gives a known action (%s)" % ca)
	for act in CommandCursor.ACTIONS:
		_check(ResourceLoader.exists(CommandCursor.texture_path(act)), "cursor art for " + act)
	# Shift + right clicks: two waypoints, then a capture.
	_scene._right_click(ground, false, true)
	var via: Vector2 = w.nav.nearest_free(town.center.lerp(home.center, 0.5))
	_scene._right_click(via, false, true)
	_scene._right_click(town.center, false, true)
	var u := w.get_unit(ids[0])
	_check(u.plan_id >= 0, "shift queues the orders")
	_check(w.plan_points(u).size() == 3, "three queued points (%d)" % w.plan_points(u).size())
	_check(_scene.queued_paths().size() == 1, "one queue line for the selection")
	_scene.cam.position = home.center.lerp(town.center, 0.4)
	_scene.cam.zoom = Vector2(0.45, 0.45)
	await _shot("01_queue_2d")
	_scene.mode_3d = true
	_scene._apply_mode()
	await _shot("02_queue_3d")
	_scene.mode_3d = false
	_scene._apply_mode()
	_advance(eco.capture_seconds(town) + 60.0)
	_check(town.owner == 0, "the queued capture took the settlement (owner %d)" % town.owner)
	# A right click without shift drops a queue.
	_scene._right_click(ground, false, true)
	_scene._right_click(home.center + Vector2(0, 300), false, true)
	_scene._right_click(ground, false, false)
	_check(u == null or w.get_unit(ids[0]) == null or w.get_unit(ids[0]).plan_id == -1, "a plain right click drops the queue")
	# Shift + place: one worker builds two sites in turn.
	var pl := eco.player(0)
	for r in pl.res:
		pl.res[r] = 5000
	_scene.selection = [worker.id]
	_scene._start_placing("storehouse", 0)
	var spot1: Vector2 = Vector2.ZERO
	var spot2: Vector2 = Vector2.ZERO
	for k in 40:
		var p: Vector2 = home.center + Vector2(cos(k * 0.6), sin(k * 0.6)) * (420.0 + k * 6.0)
		if eco.can_place(0, p, _scene.placing_radius()):
			if spot1 == Vector2.ZERO:
				spot1 = p
			elif p.distance_to(spot1) > 200.0:
				spot2 = p
				break
	_scene._place(spot1, true)
	_scene._start_placing("storehouse", 0)
	_scene._place(spot2, true)
	_check(worker.plan_id >= 0 and w.plan_points(worker).size() == 2, "two sites queued for the worker (%d)" % w.plan_points(worker).size())
	var sites: Array = []
	for b in eco.buildings:
		if b.owner == 0 and not b.done():
			sites.append(b)
	_advance(150.0)
	var built := sites.filter(func(b: Building) -> bool: return b.done()).size()
	_check(built == sites.size() and built >= 2, "both queued sites built (%d of %d)" % [built, sites.size()])
	print("command probe: %d failed" % _fails)
	quit(1 if _fails > 0 else 0)
