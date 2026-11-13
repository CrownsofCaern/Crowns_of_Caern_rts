extends SceneTree
## Review shots of the hero UI in a campaign chapter: the HUD, the skill trees with points spent
## and a tooltip, and the hero window.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/ui_shots.gd -- /tmp/ui [w h]
## The skirmish hero HUD and window: tools/hero_shots.gd.

var _out := "/tmp/warbound_ui"
var _scene: Node
var _size := Vector2i(1440, 900)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 2:
		_size = Vector2i(int(args[1]), int(args[2]))
	DirAccess.make_dir_recursive_absolute(_out)
	var cc := CampaignCatalog.get_default()
	CampaignSetup.current = CampaignSetup.make(cc.start("last_light"), "ll_harvest")
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	root.size = _size
	await process_frame
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.paused = true
	_scene.campaign_hud.card.hide()
	_scene.hud_help.visible = false
	var m: StoryMission = _scene.mission
	_scene.cam.position = m.pos_of("hero") + Vector2(120, -40)
	m._act({"xp": 6000}, "")
	var st := m.progress.story
	var trees: Array = st.trees()
	# Spend some points: a few in the first tree, one in the second.
	for nid in ["signature"]:
		m.command_learn(nid)
	var t0: Dictionary = StoryTrees.get_default().trees[trees[0]]
	for n: Dictionary in t0["nodes"]:
		if int(n["row"]) <= 1:
			m.command_learn(n["id"])
			m.command_learn(n["id"])
	var t1: Dictionary = StoryTrees.get_default().trees[trees[1]]
	m.command_learn(t1["nodes"][0]["id"])
	_scene.paused = false
	await _shot("10_campaign_hud")
	_scene.campaign_hud.toggle_trees()
	await _shot("11_skill_trees")
	var panel: SkillTreePanel = _scene.campaign_hud.trees
	var nd: Dictionary = panel._nodes[3]
	root.get_viewport().warp_mouse(panel.position + (nd["rect"] as Rect2).get_center())
	await _shot("12_skill_tree_tip")
	panel.hide()
	_scene.toggle_hero_window()
	await _shot("13_hero_window")
	quit()
