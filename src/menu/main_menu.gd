class_name WbMainMenu
extends Control
## Warbound's title screen, ported from the main game's MainMenu: the painted
## backdrop with an ember glow, the Crowns of Caern wordmark over "Warbound",
## and Skirmish / Campaign / Settings / Quit. Each choice swaps in its own
## framed screen and backdrop. Begin hands a SkirmishSetup to the skirmish scene.

const SKIRMISH_SCENE := "res://scenes/skirmish.tscn"

var audio: MenuAudio
var backdrop: TextureRect
var brand: VBoxContainer
var home: VBoxContainer
var setup_screen: SkirmishSetupScreen
var campaign_screen: CampaignScreen
var settings_screen: SettingsScreen
var online_screen: OnlineScreen
var screen: String = "title"
## Tests set this to stop Begin from switching scenes.
var launch_scene: bool = true
var launched_setup: SkirmishSetup = null
var footer: Label


func _ready() -> void:
	WbSettings.ensure_loaded()
	WbSettings.apply()
	build()
	audio.play_music()
	if CampaignSetup.returning:
		CampaignSetup.returning = false
		CampaignSetup.current = null
		show_campaigns()


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = WbStyle.menu_theme()
	audio = MenuAudio.new()
	add_child(audio)
	var bg := ColorRect.new()
	bg.color = Color("#0b0a09")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	backdrop = WbStyle.backdrop("title")
	add_child(backdrop)
	add_child(WbStyle.ember_glow())
	if is_inside_tree():
		get_window().title = "%s: %s" % [WbStyle.TITLE, WbStyle.SUBTITLE]

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	brand = WbStyle.brand()
	brand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(brand)
	col.add_child(WbStyle.spacer(10))
	home = VBoxContainer.new()
	home.name = "Home"
	home.add_theme_constant_override("separation", 10)
	home.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(home)
	home.add_child(WbStyle.menu_button("Skirmish", show_setup))
	home.add_child(WbStyle.menu_button("Online", show_online))
	home.add_child(WbStyle.menu_button("Campaign", show_campaigns))
	home.add_child(WbStyle.menu_button("Settings", show_settings))
	if OS.get_name() not in ["iOS", "Web"]:
		home.add_child(WbStyle.menu_button("Quit", func() -> void: get_tree().quit()))

	setup_screen = SkirmishSetupScreen.new()
	setup_screen.build(SkirmishSetup.from_dict(WbSettings.last_setup) if not WbSettings.last_setup.is_empty() else null)
	setup_screen.back_requested.connect(show_title)
	setup_screen.begin_requested.connect(begin)
	col.add_child(setup_screen)
	campaign_screen = CampaignScreen.new()
	campaign_screen.build()
	campaign_screen.back_requested.connect(show_title)
	campaign_screen.chapter_requested.connect(begin_chapter)
	# Full screen, like the main game's journey map.
	add_child(campaign_screen)
	settings_screen = SettingsScreen.new()
	settings_screen.build()
	settings_screen.back_requested.connect(show_title)
	col.add_child(settings_screen)
	online_screen = OnlineScreen.new()
	online_screen.build()
	online_screen.back_requested.connect(show_title)
	online_screen.start_requested.connect(begin_online)
	col.add_child(online_screen)

	footer = WbStyle.label("Skirmish demo · real-time spinoff of %s" % WbStyle.TITLE, 12, Color("#a89a7cc0"))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_right = -14
	footer.offset_bottom = -10
	add_child(footer)
	audio.wire_clicks(self)
	show_title()


func _set_screen(id: String) -> void:
	screen = id
	home.visible = id == "title"
	setup_screen.visible = id == "setup"
	campaign_screen.visible = id == "campaign"
	settings_screen.visible = id == "settings"
	online_screen.visible = id == "online"
	if id != "online" and OnlineGame.current == null:
		online_screen.leave()
	# The brand shrinks above the forms, as in the main game.
	brand.visible = id in ["title", "settings"]
	footer.visible = id == "title"
	var art: String = {"title": "title", "setup": "setup", "campaign": "campaign", "settings": "title", "online": "setup"}[id]
	backdrop.texture = WbStyle.backdrop_texture(art)


func show_title() -> void:
	if screen != "title" and audio != null:
		audio.play("close")
	_set_screen("title")


func show_setup() -> void:
	_set_screen("setup")


func show_online() -> void:
	_set_screen("online")


## The online lobby started the match (SkirmishSetup.current, OnlineGame.current are set).
func begin_online() -> void:
	launched_setup = SkirmishSetup.current
	if launch_scene:
		audio.stop_music()
		get_tree().change_scene_to_file(SKIRMISH_SCENE)


func show_campaigns() -> void:
	_set_screen("campaign")


func show_settings() -> void:
	_set_screen("settings")


## Starts the skirmish: remember the choices, hand them over, switch scenes.
func begin(setup: SkirmishSetup) -> void:
	WbSettings.last_setup = setup.to_dict()
	# A fresh map next time unless the player typed a seed.
	if setup_screen.seed_edit.text.strip_edges() == "":
		WbSettings.last_setup["seed"] = 0
	WbSettings.save_settings()
	SkirmishSetup.current = setup.resolved(int(Time.get_ticks_usec() % 2147483647))
	launched_setup = SkirmishSetup.current
	if launch_scene:
		audio.stop_music()
		get_tree().change_scene_to_file(SKIRMISH_SCENE)


## Starts a campaign chapter in the battle scene.
func begin_chapter(setup: CampaignSetup) -> void:
	CampaignSetup.current = setup
	SkirmishSetup.current = null
	if launch_scene:
		audio.stop_music()
		get_tree().change_scene_to_file(SKIRMISH_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and screen != "title":
		if screen == "settings":
			WbSettings.save_settings()
		if screen == "online":
			online_screen.leave()
		show_title()
		get_viewport().set_input_as_handled()
