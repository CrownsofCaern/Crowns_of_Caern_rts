extends SceneTree
## Review shots of the hero UI: the class picker, then a levelled hero in a fight.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/hero_shots.gd -- /tmp/hero_shots [class]

var _scene: Node2D
var _out := "/tmp/hero_shots"
var _class := "knight"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_class = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _advance(seconds: float) -> void:
	var w: SimWorld = _scene.world
	for i in int(seconds * w.tick_rate):
		w.step()
		_scene._collect_events()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	var hc := HeroCatalog.get_default()
	_scene.factions = [hc.classes[_class]["faction"], "hollow" if hc.classes[_class]["faction"] != "hollow" else "concord"]
	_scene._start(_scene.seed_value)
	_scene.hud_help.visible = false
	await _shot("01_pick")
	_scene.pick_hero(_class)
	var w: SimWorld = _scene.world
	var u: SimUnit = w.heroes.hero_unit(0)
	w.heroes.add_xp(u.hero, 2400)
	for slot in [0, 1, 0, 2, 0, 3]:
		w.heroes.command_learn(0, slot)
	# A fight in the open next to home.
	var p := u.pos + Vector2(260, 0)
	var foes: Array = []
	for i in 6:
		foes.append(w.spawn(w.catalog.faction_units(_scene.factions[1])[0], 1, p + Vector2(60, (i - 3) * 26)).id)
	var mine: Array = [u.id]
	for i in 5:
		mine.append(w.spawn(w.catalog.faction_units(_scene.factions[0])[0], 0, u.pos + Vector2(0, (i - 2) * 26)).id)
	w.command_attack_move(mine, p + Vector2(200, 0))
	w.command_attack_move(foes, u.pos)
	_scene.cam.position = p
	_scene.selection = [u.id]
	_advance(4.0)
	await _shot("02_fight")
	_scene._casting = 2
	_advance(3.0)
	await _shot("03_more")
	# Gear: a few worn items, a full-ish bag, potions, and loot on the ground.
	var g := w.heroes.gear
	var rng := GameRng.new(5)
	for id in ["warhost_oriflamme", "scarred_plate", "gravewatch_visor"]:
		g.give(u.hero, g.icat.make_unique(id))
	for r in ["rare", "magic", "common"]:
		g.give(u.hero, g.icat.roll(rng, r, 5))
	u.hero.potions = {"health": 3, "mana": 1}
	_scene._casting = -1
	for i in 4:
		g.drop_item(g.icat.roll_drop(rng, "capture", 6), u.pos + Vector2(-120 + i * 40, -90))
	g._put({"potion": "health"}, u.pos + Vector2(60, -90))
	_scene.cam.position = u.pos
	_advance(0.1)
	await _shot("04_loot")
	# Hover the first skill for the hero bar's tooltip (the bar is drawn at 80%).
	var hb: HeroBar = _scene.hero_bar
	root.get_viewport().warp_mouse(hb.get_global_transform_with_canvas() * hb._slots[0].get_center())
	await _shot("04b_skill_tip")
	_scene.toggle_help()
	await _shot("04c_help")
	_scene.toggle_help()
	# Hover a dwelling emblem over the minimap.
	var bb: BuildingBar = _scene.building_bar
	root.get_viewport().warp_mouse(bb.get_global_rect().position + (bb._cells[1]["rect"] as Rect2).get_center())
	await _shot("04d_buildings")
	root.get_viewport().warp_mouse(Vector2(640, 300))
	_scene.toggle_hero_window()
	await _shot("05_hero_window")
	var hw: HeroWindow = _scene.hero_window
	# Hover a bag item for the tooltip with the comparison.
	var cell: Rect2 = hw._bag_cells[0]
	root.get_viewport().warp_mouse(hw.position + cell.get_center())
	await _shot("06_hero_window_tip")
	quit()
