extends SceneTree
## Screenshots of the menus for review:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/menu_shots.gd -- /tmp/menus [with_battle]
## Title, skirmish setup, campaign shell, settings; with "battle" also the pause
## menu and the victory card over a running skirmish (slow on software GL).

var _out := "/tmp/warbound_menus"
var _battle := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_battle = args.size() > 1 and args[1] == "battle"
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var menu: WbMainMenu = load("res://scenes/main_menu.tscn").instantiate()
	menu.launch_scene = false
	root.add_child(menu)
	await _shot("01_title")
	menu.show_setup()
	var hp: OptionButton = menu.setup_screen.rows[0]["hero"]
	if hp.item_count > 1:
		hp.select(1)
		hp.item_selected.emit(1)
	await _shot("02_skirmish_setup")
	menu.setup_screen.players_pick.select(2)
	menu.setup_screen.players_pick.item_selected.emit(2)
	await _shot("02b_skirmish_setup_4p")
	menu.show_campaigns()
	await _shot("03_campaign")
	menu.show_settings()
	await _shot("04_settings")
	menu.queue_free()
	if _battle:
		var s := SkirmishSetup.new()
		s.player_faction = "concord"
		s.enemy_faction = "hollow"
		s.seed_value = 7
		SkirmishSetup.current = s
		var sk: Skirmish = load("res://scenes/skirmish.tscn").instantiate()
		root.add_child(sk)
		await process_frame
		sk.hud_help.visible = false
		sk.open_pause_menu()
		await _shot("05_pause")
		sk.close_pause_menu()
		sk._winner = 0
		sk._show_outcome()
		await _shot("06_victory")
		sk.pause_menu.close()
		sk._winner = -1
		for u in sk.world.economy.workers_of(0):
			sk.selection.append(u.id)
		sk._build_menu_open = true
		await _shot("07_hud")
	quit()
