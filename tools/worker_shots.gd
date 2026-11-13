extends SceneTree
## A still of the gather weights in the top bar (3x wood, 1x ore, the rest 0x) after the
## workers have spread themselves to match:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/worker_shots.gd -- /tmp/workers

var _scene: Node2D
var _out := "/tmp/warbound_workers"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	_scene.factions = ["concord", "hollow"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	_scene.fog_enabled = false
	var w: SimWorld = _scene.world
	_scene.pick_hero(String(_scene.hero_classes()[0]))
	var eco := w.economy
	for r in eco.gather_resources(0):
		eco.set_gather_weight(0, r, 0)
	eco.set_gather_weight(0, "wood", 3)
	eco.set_gather_weight(0, "ore", 1)
	for i in int(20.0 * w.tick_rate):
		w.step()
		_scene._collect_events()
	print("gatherers: ", eco.gather_counts(0))
	_scene.cam.position = eco.hall_of(0).center
	_scene.cam.zoom = Vector2(0.6, 0.6)
	_scene.paused = true
	for i in 4:
		await process_frame
	_scene.hud_center.visible = false
	root.get_viewport().get_texture().get_image().save_png(_out + "/10_gather_weights.png")
	print("saved")
	quit()
