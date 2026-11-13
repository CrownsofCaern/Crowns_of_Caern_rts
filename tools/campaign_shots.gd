extends SceneTree
## Review screenshots of a campaign chapter (the pilot by default):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/campaign_shots.gd -- /tmp/camp [chapter]
## Shows the campaign screen, the intro card, the hero at the start, an NPC with a quest mark,
## a conversation, the quest log after a few steps, the skill trees and the outro card.

var _out := "/tmp/warbound_campaign"
var _scene: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var chapter := args[1] if args.size() > 1 else "ll_harvest"
	DirAccess.make_dir_recursive_absolute(_out)
	var cc := CampaignCatalog.get_default()
	CampaignSetup.current = CampaignSetup.make(cc.start("last_light"), chapter)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _advance(seconds: float) -> void:
	var m: StoryMission = _scene.mission
	for i in int(seconds * m.world.tick_rate):
		if not m.dialogue.is_empty():
			return
		m.world.step()
		m.step()
		_scene._collect_events()


func _look_at(p: Vector2) -> void:
	_scene.cam.position = p
	_scene._clamp_camera()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	await process_frame
	# The campaign screen.
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	menu.launch_scene = false
	root.add_child(menu)
	await process_frame
	var saved := CampaignProgress.load_saved("last_light")
	CampaignProgress.erase_saved("last_light")
	menu.show_campaigns()
	menu.campaign_screen.open_campaign("last_light")
	await _shot("00_campaign_screen")
	# Chapter 1 won: the hero walks on to chapter 2.
	var won := CampaignCatalog.get_default().start("last_light")
	won.done.append("ll_harvest")
	won.save()
	menu.campaign_screen.open_campaign("last_light")
	for i in 70:
		await process_frame
	await _shot("00b_campaign_walking")
	menu.campaign_screen.journey.elapsed = 99.0
	menu.campaign_screen.journey.select_stop(4)
	await _shot("00c_campaign_stop")
	menu.campaign_screen.open_campaign("briar_oath")
	await _shot("00d_campaign_other")
	CampaignProgress.erase_saved("last_light")
	if saved != null:
		saved.save()
	menu.queue_free()
	await process_frame
	_scene = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.paused = true
	await _shot("01_intro")
	_scene.campaign_hud.card.hide()
	_scene.hud_help.visible = false
	var m: StoryMission = _scene.mission
	_look_at(m.pos_of("hero") + Vector2(160, -40))
	await _shot("02_start")
	# Walk to the reeve.
	m.command_talk("reeve")
	_advance(60.0)
	_look_at(m.pos_of("reeve"))
	await _shot("03_reeve_talk")
	m.command_choose(-1)
	m.command_choose(-1)
	m.command_choose(0)
	_scene.world.command_attack_move([m.hero_unit().id], m.pos_of("rats"))
	_advance(30.0)
	_look_at(m.pos_of("hero"))
	await _shot("04_rats_fight")
	_advance(40.0)
	_look_at(m.pos_of("marta"))
	await _shot("05_village_marks")
	m._act({"xp": 900}, "")
	_scene.campaign_hud.toggle_trees()
	await _shot("06_skill_trees")
	_scene.campaign_hud.trees.hide()
	# The barrow fields and Sexton Grue.
	var hu := m.hero_unit()
	hu.pos = m.world.nav.nearest_free(m.pos_of("grue") + Vector2(-160, 0))
	hu.prev_pos = hu.pos
	m.world.command_move([hu.id], m.pos_of("grue"))
	_advance(20.0)
	for i in 3:
		m.world.vision.update(m.world)
	_scene._fog_tick = -1
	_look_at(m.pos_of("grue"))
	await _shot("07_grue")
	m.dialogue = {}
	m._act({"win": true}, "")
	_scene._game_over()
	_scene._update_hud()
	await _shot("08_outro")
	quit()
