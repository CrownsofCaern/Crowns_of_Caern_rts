extends "res://tests/test_case.gd"
## Menus: setup data, the setup screen, the main menu screens, the pause menu,
## settings round trip and the copied UI assets.


func test_ui_data_has_playable_factions_and_art() -> void:
	var d := WbStyle.data()
	assert_false(d.is_empty(), "data/ui.json loads")
	for f: String in SkirmishSetup.playable_factions():
		assert_true(d["factions"].has(f), "ui.json has " + f)
		assert_ne(WbStyle.faction_name(f), f.capitalize(), "real name for " + f)
		assert_true(WbStyle.emblem(f) != null, "crest for " + f)
	assert_true(WbStyle.backdrop_texture("title") != null, "title backdrop")
	assert_true(WbStyle.backdrop_texture("setup") != null, "setup backdrop")
	assert_true(WbStyle.backdrop_texture("campaign") != null, "campaign backdrop")
	assert_true(WbStyle.frame_panel("hollow") is StyleBoxTexture, "framed panel art")
	assert_true(WbStyle.frame_panel("no_such_house") is StyleBoxTexture, "falls back to Concord frame")


func test_playable_factions_skip_neutral() -> void:
	var all := SkirmishSetup.playable_factions()
	assert_false(all.has("neutral"))
	assert_true(all.has("concord") and all.has("hollow"))


func test_setup_round_trip() -> void:
	var s := SkirmishSetup.new()
	s.player_faction = "hollow"
	s.enemy_faction = "random"
	s.difficulty = "hard"
	s.seed_value = 4242
	var back := SkirmishSetup.from_dict(s.to_dict())
	assert_eq(back.to_dict(), s.to_dict())
	assert_eq(back.factions(), ["hollow", "random"])


func test_resolve_random_is_deterministic_and_valid() -> void:
	var s := SkirmishSetup.new()
	s.player_faction = "random"
	s.enemy_faction = "random"
	s.seed_value = 0
	s.difficulty = "bogus"
	var a := s.resolved(77)
	var b := s.resolved(77)
	assert_eq(a.to_dict(), b.to_dict(), "same roll, same result")
	var all := SkirmishSetup.playable_factions()
	assert_true(all.has(a.player_faction))
	assert_true(all.has(a.enemy_faction))
	assert_gt(a.seed_value, 0)
	assert_eq(a.difficulty, "normal")
	assert_eq(s.player_faction, "random", "resolved() leaves the original alone")
	var fixed := SkirmishSetup.new()
	fixed.seed_value = 99
	assert_eq(fixed.resolved(5).seed_value, 99, "a chosen seed is kept")


func test_setup_screen_builds_setup_matching_preview() -> void:
	var start := SkirmishSetup.new()
	start.player_faction = "hollow"
	start.enemy_faction = "concord"
	start.seed_value = 123
	var screen := SkirmishSetupScreen.new()
	screen.build(start)
	assert_eq(screen.rows.size(), 2, "one row per player")
	var house0: OptionButton = screen.rows[0]["faction"]
	assert_eq(String(house0.get_item_metadata(house0.selected)), "hollow")
	assert_eq(String(house0.get_item_metadata(house0.item_count - 1)), "random", "random house offered")
	var level1: OptionButton = screen.rows[1]["difficulty"]
	assert_false(level1.disabled, "computer level can be picked")
	level1.select(2)
	level1.item_selected.emit(2)
	assert_eq(screen.current_setup().difficulty, "hard")
	var got := screen.current_setup()
	assert_eq(got.seed_value, 123)
	assert_eq(got.factions(), ["hollow", "concord"])
	# The preview is the same map the battle builds.
	var w := SkirmishScenario.build_skirmish(123, ["hollow", "concord"])
	assert_eq(screen.preview.world().economy.sectors.size(), w.economy.sectors.size())
	assert_eq(screen.preview.world().nav.width, w.nav.width)
	house0.select(0)
	house0.item_selected.emit(0)
	assert_eq(screen.current_setup().player_faction, String(house0.get_item_metadata(0)))
	screen.seed_edit.text = ""
	assert_gt(screen.current_setup().seed_value, 0, "empty seed uses the previewed one")
	# Four players: four rows, the preview builds the corner map.
	screen.players_pick.select(2)
	screen.players_pick.item_selected.emit(2)
	assert_eq(screen.rows.size(), 4)
	assert_eq(screen.current_setup().factions().size(), 4)
	var homes := 0
	for sec: Sector in screen.preview.world().economy.sectors:
		if sec.home_of >= 0:
			homes += 1
	assert_eq(homes, 4, "four homes on the preview")
	screen.free()


func test_setup_screen_hero_choice() -> void:
	var start := SkirmishSetup.new()
	start.player_faction = "concord"
	var screen := SkirmishSetupScreen.new()
	screen.build(start)
	var hero0: OptionButton = screen.rows[0]["hero"]
	var classes := SkirmishSetup.hero_classes("concord")
	assert_eq(hero0.item_count, classes.size() + 1, "random plus every Concord class")
	assert_false(hero0.disabled)
	hero0.select(1)
	hero0.item_selected.emit(1)
	assert_eq(screen.current_setup().hero_for(0), classes[0])
	assert_true(screen.hero_card.get_child_count() >= 2, "hero card shows portrait and details")
	# Changing house resets the hero to random and lists that house's classes.
	var house0: OptionButton = screen.rows[0]["faction"]
	for k in house0.item_count:
		if house0.get_item_metadata(k) == "hollow":
			house0.select(k)
			house0.item_selected.emit(k)
	assert_eq(screen.current_setup().hero_for(0), "random")
	assert_eq(hero0.item_count, SkirmishSetup.hero_classes("hollow").size() + 1)
	screen.free()


func test_setup_slots_resolve_heroes_and_players() -> void:
	var s := SkirmishSetup.new()
	s.slots[0]["hero"] = "knight"
	s.slots[1]["faction"] = "concord"
	var r := s.resolved(3)
	assert_eq(r.hero_for(0), "knight", "a chosen hero is kept")
	assert_true(SkirmishSetup.hero_classes("concord").has(r.hero_for(1)), "random hero fits the house")
	s.set_player_count(4)
	assert_eq(s.slots.size(), 4)
	s.slots[3]["type"] = "closed"
	assert_eq(s.factions().size(), 3, "closed slots stay out of the battle")
	var old := SkirmishSetup.from_dict({"player_faction": "hollow", "enemy_faction": "ashen", "difficulty": "hard", "seed": 5})
	assert_eq(old.factions(), ["hollow", "ashen"], "settings from before slots still load")
	assert_eq(old.difficulty, "hard")
	assert_gte_players()


func assert_gte_players() -> void:
	assert_eq(SkirmishSetup.max_players(), SkirmishScenario.MAX_PLAYERS)
	for i in SkirmishSetup.PLAYER_COLORS.size():
		assert_eq(SkirmishSetup.PLAYER_COLORS[i], Skirmish.TEAM_COLORS[i], "setup colour %d matches the battle ring" % i)


func test_main_menu_screens_and_begin() -> void:
	var menu := WbMainMenu.new()
	menu.launch_scene = false
	menu.build()
	assert_true(menu.home.visible)
	assert_false(menu.setup_screen.visible)
	assert_true(menu.home.get_node("Skirmish") is Button)
	assert_true(menu.home.get_node("Campaign") is Button)
	assert_true(menu.home.get_node("Settings") is Button)
	menu.show_setup()
	assert_true(menu.setup_screen.visible)
	assert_false(menu.home.visible)
	menu.show_campaigns()
	assert_true(menu.campaign_screen.visible)
	assert_false(menu.setup_screen.visible)
	menu.show_settings()
	assert_true(menu.settings_screen.visible)
	menu.show_title()
	assert_true(menu.home.visible)
	var s := SkirmishSetup.new()
	s.player_faction = "random"
	s.enemy_faction = "hollow"
	s.seed_value = 555
	var saved_setup := WbSettings.last_setup
	WbSettings.path = "user://test_menu_settings.cfg"
	menu.setup_screen.seed_edit.text = "555"
	menu.begin(s)
	assert_true(SkirmishSetup.current != null)
	assert_eq(SkirmishSetup.current.seed_value, 555)
	assert_ne(SkirmishSetup.current.player_faction, "random", "random resolved before the battle")
	assert_eq(SkirmishSetup.current.enemy_faction, "hollow")
	SkirmishSetup.current = null
	WbSettings.last_setup = saved_setup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WbSettings.path))
	WbSettings.path = WbSettings.PATH
	menu.free()


func test_campaign_screen_opens_the_concord_campaign() -> void:
	var c := CampaignScreen.new()
	c.build()
	var cc := CampaignCatalog.get_default()
	assert_eq(c.picker.item_count, cc.campaigns.size(), "one picker entry per campaign")
	assert_eq(c.ids[0], "last_light", "the playable campaign comes first")
	var saved := CampaignProgress.load_saved("last_light")
	CampaignProgress.erase_saved("last_light")
	var got: Array = []
	c.chapter_requested.connect(func(s: CampaignSetup) -> void: got.append(s))
	c.open_campaign("last_light")
	assert_eq(c.journey.nodes.size(), 10, "a stop per chapter")
	assert_eq(c.journey.states[0], "current")
	assert_eq(c.journey.states[1], "locked")
	assert_eq(c.play_button.text, "Begin campaign")
	assert_false(c.play_button.disabled)
	c.play_button.pressed.emit()
	assert_eq(got.size(), 1)
	var setup: CampaignSetup = got[0]
	assert_eq(setup.chapter, "ll_harvest")
	assert_eq(setup.progress().story.class_id, "knight")
	assert_eq(setup.mission_def()["title"], "Greyhold Harvest")
	# A won first chapter: the hero walks on to chapter 2.
	var p := cc.start("last_light")
	p.done.append("ll_harvest")
	p.save()
	c.open_campaign("last_light")
	assert_eq(c.journey.current, 1)
	assert_eq(c.journey.states[0], "done")
	assert_false(c.play_button.disabled, "chapter 2 is playable")
	assert_eq(c.play_button.text, "Play chapter 2")
	# Every chapter won: the campaign is complete.
	for ch: Dictionary in cc.chapters("last_light"):
		if not p.done.has(String(ch["id"])):
			p.done.append(String(ch["id"]))
	p.save()
	c.open_campaign("last_light")
	assert_eq(c.journey.current, 9)
	assert_true(c.play_button.disabled)
	assert_eq(c.play_button.text, "Campaign complete")
	assert_true(c.restart.visible)
	c.start_over()
	assert_eq(c.journey.current, 0, "start over erases the save")
	c.open_campaign("six_eyes")
	assert_true(c.play_button.disabled, "other campaigns are being written")
	CampaignProgress.erase_saved("last_light")
	if saved != null:
		saved.save()
	c.free()


func test_every_campaign_has_its_journey_art_and_walking_hero() -> void:
	var cc := CampaignCatalog.get_default()
	for id: String in cc.campaigns:
		assert_true(CampaignScreen.picture(id) != null, id + ": journey painting")
		assert_eq(CampaignScreen.journey_info(id).get("nodes", []).size(), cc.chapters(id).size(), id + ": a stop per chapter")
		var cls := CampaignScreen.hero_class_of(id)
		assert_true(LiveUnit.exists(cls, SkirmishView3D.HEROES3D), id + ": 3D hero " + cls)
		for ch: Dictionary in cc.chapters(id):
			assert_true(CampaignScreen.picture(id, String(ch["id"])) != null, id + "/" + String(ch["id"]) + ": chapter picture")


func test_pause_menu_modes() -> void:
	var p := PauseMenu.new()
	p.build()
	assert_false(p.is_open())
	p.open("pause")
	assert_true(p.is_open())
	var names: Array = []
	for b in p.buttons.get_children():
		names.append(b.text)
	assert_true(names.has("Resume") and names.has("Main menu") and names.has("Settings"), str(names))
	var resumed := [false]
	p.resume_requested.connect(func() -> void: resumed[0] = true)
	(p.buttons.get_child(0) as Button).pressed.emit()
	assert_true(resumed[0], "Resume emits resume_requested")
	p.open("defeat", "Your last settlement has fallen.")
	assert_eq(p.title.text, "Defeat")
	names.clear()
	for b in p.buttons.get_children():
		names.append(b.text)
	assert_true(names.has("Try again") and names.has("Main menu"), str(names))
	assert_false(names.has("Settings"))
	p.close()
	assert_false(p.is_open())
	p.free()


func test_settings_round_trip() -> void:
	var path := "user://test_warbound_settings.cfg"
	var old := [WbSettings.volume, WbSettings.music_on, WbSettings.fullscreen, WbSettings.last_setup]
	WbSettings.volume = 0.35
	WbSettings.music_on = false
	WbSettings.fullscreen = true
	WbSettings.weather = false
	WbSettings.last_setup = {"player_faction": "hollow", "seed": 7}
	WbSettings.save_settings(path)
	WbSettings.volume = 1.0
	WbSettings.music_on = true
	WbSettings.fullscreen = false
	WbSettings.weather = true
	WbSettings.last_setup = {}
	WbSettings.load_settings(path)
	assert_false(WbSettings.weather)
	WbSettings.weather = true
	assert_true(absf(WbSettings.volume - 0.35) < 0.001)
	assert_false(WbSettings.music_on)
	assert_true(WbSettings.fullscreen)
	assert_eq(String(WbSettings.last_setup.get("player_faction", "")), "hollow")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	WbSettings.volume = old[0]
	WbSettings.music_on = old[1]
	WbSettings.fullscreen = old[2]
	WbSettings.last_setup = old[3]


func test_build_ring_items_and_tooltips() -> void:
	var ring := BuildRing.new()
	var calls := [0]
	var opts: Array = [
		{"id": "c_dw1", "sprite": "res://assets/buildings/c_dw1.png", "name": "Militia Muster", "cost": {"gold": 50},
			"enabled": true, "status": "", "tooltip": "Trains militia", "action": func() -> void: calls[0] += 1},
		{"id": "c_dw8", "sprite": "res://assets/buildings/c_dw8.png", "name": "Margrave's Hall", "cost": {"gold": 900},
			"enabled": false, "status": "Needs hall IV", "tooltip": "Top tier"},
	]
	ring.show_options("k1", opts)
	assert_true(ring.visible)
	assert_eq(ring.item_count(), 2)
	assert_eq(ring.item(0).tooltip_text, "Trains militia")
	assert_true(ring.item(1).disabled, "locked building is greyed out")
	ring.item(0).pressed.emit()
	assert_eq(calls[0], 1, "clicking starts placing")
	var first := ring.item(0)
	ring.show_options("k1", opts)
	assert_eq(ring.item(0), first, "same key keeps the items")
	ring.hide_ring()
	assert_false(ring.visible)
	ring.free()


func test_faction_crests_are_the_detailed_art() -> void:
	for f: String in ["concord", "hollow", "ashen", "thornwood", "forge", "frostmarch", "darkelf", "fishmen"]:
		var t := WbStyle.emblem(f)
		assert_true(t != null, f)
		if t != null:
			assert_eq(t.get_width(), 256, f + " crest is the 256 px detailed cell")


func test_setup_screen_scrolls_when_the_window_is_short() -> void:
	# Four players on a short window: the form scrolls and Begin stays on screen.
	var screen := SkirmishSetupScreen.new()
	var s := SkirmishSetup.new()
	s.set_player_count(4)
	screen.build(s)
	screen.fit_to_height(600.0)
	var form: Control = screen.scroll.get_child(0)
	assert_lt(screen.scroll.custom_minimum_size.y, form.get_combined_minimum_size().y, "the form scrolls")
	assert_lt(screen.get_combined_minimum_size().y, 600.0 - SkirmishSetupScreen.SCREEN_MARGIN * 2.0 + 1.0, "the panel fits")
	var begin := screen.find_child("Begin", true, false)
	assert_true(begin != null and not screen.scroll.is_ancestor_of(begin), "Begin sits outside the scrolling part")
	screen.fit_to_height(2000.0)
	assert_eq(screen.scroll.custom_minimum_size.y, form.get_combined_minimum_size().y, "a tall window shows it all")
	screen.free()
