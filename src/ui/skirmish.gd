extends Node2D
class_name Skirmish
## The skirmish battle view: classic RTS controls over the headless SimWorld.
## The view only reads world state; every change a player makes goes through act()
## as a WorldCommands command (applied at once alone, through Lockstep online).
## Units, terrain and sounds come from the main game until 3D arrives.

## The house this computer plays: 0 alone at the keyboard, the seat's owner online.
static var PLAYER: int = 0
## Indexed by owner: players 0-3 (room up to 7), then Economy.NEUTRAL (8) for the militia.
## What an upgraded unit's special does, for the dwelling panel (rules: rules.json upgrade_specials).
const SPECIAL_TEXT := {"life_drain": "life drain, heals from the damage it deals",
	"armor_pierce": "armour pierce, ignores half of the target's armour",
	"cleave": "cleave, its blows also hit up to 2 foes beside the target",
	"splash": "splash, its blows also hit up to 3 foes around the target",
	"stun": "stun, a blow may stun the target for a moment",
	"double_strike": "double strike, a second, lighter blow after each attack",
	"sunder": "sunder, the target takes 20% more damage for 5 s",
	"first_strike": "first strike, +50% damage against unhurt foes",
	"aura": "aura, allies nearby deal 10% more damage",
	"fear": "fear, the target deals 25% less damage for 3 s",
	"poison": "poison, venom keeps hurting the target",
	"brace": "brace, blunts cavalry charges",
	"regenerate": "regeneration, heals over time",
	"shield_wall": "shield wall, takes half damage from missiles",
	"curse": "curse, the target deals less damage",
	"burn": "burn, sets the target (even a building) alight for 3 s",
	"bleed": "bleed, the wound keeps bleeding for 5 s (not the bloodless)",
	"frost": "frost, the target moves 30% slower for 2 s"}
## Rings and bars of upgraded dwellings.
const UPGRADE_COLOR := Color(0.95, 0.78, 0.32)
const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(0.95, 0.3, 0.25), Color(0.4, 0.85, 0.35),
	Color(0.95, 0.8, 0.25), Color(0.75, 0.4, 0.95), Color(0.3, 0.85, 0.85), Color(0.95, 0.55, 0.2),
	Color(0.9, 0.9, 0.9), Color(0.8, 0.75, 0.55)]
const SELECT_COLOR := Color(0.45, 1.0, 0.45)
## Markers and queue lines of capture orders.
const CAPTURE_COLOR := Color(1.0, 0.82, 0.3)
const EDGE_PAN := 12.0
const PAN_SPEED := 900.0
const DOUBLE_TAP := 0.35
## Camera zoom: the default shows a whole home sector with room around it (a third
## wider than before); the wheel goes from a near map view to a close look at a fight.
## Skirmish fog over land never explored: the land shows through, greyed out.
const FOG_GREY := Color8(72, 74, 80, 150)
const DEFAULT_ZOOM := 0.55
const ZOOM_MIN := 0.32
const ZOOM_MAX := 2.5

var world: SimWorld
var ai: EconomyAi  ## owner 1's computer player (ais[0])
var ais: Array[EconomyAi] = []  ## one per computer owner 1 .. n-1
var slot_difficulty: Array = []  ## per owner, from SkirmishSetup slots ("" = ai_difficulty)
var seed_value: int = 1
var paused: bool = false
## The online match (OnlineGame.current when the scene started), or null.
var online: OnlineGame = null
var _wait_start: float = 0.0  ## online: when the lockstep last had its next turn ready
var _acc: float = 0.0

var selection: Array = []  ## unit ids, ascending
var groups: Dictionary = {}  ## 1..9 -> Array of ids
var _last_group_key: int = -1
var _last_group_time: float = -10.0
var _attack_move_armed: bool = false
var _capture_armed: bool = false  ## T pressed: the next left click picks a settlement to take
var cursor: CommandCursor
var _drag_start_screen := Vector2.ZERO
var _dragging: bool = false
var _box_active: bool = false
var _middle_drag: bool = false
var _last_click_time: float = -10.0
var _last_click_type: String = ""
var _last_alert := Vector2(-1, -1)
var _alert_time: float = -10.0
var _time: float = 0.0

var _textures: Dictionary = {}
var _grass: Texture2D = preload("res://assets/terrain/grass.png")
var _water: Texture2D = preload("res://assets/terrain/water.png")
var _boulders: Texture2D = preload("res://assets/terrain/boulders.png")
var _rocks: Array = []  ## {pos, variant, scale}: one boulder per rock cell, y-sorted with units
var _water_cells: Array = []  ## Vector2i
var _forest_cells: Array = []  ## Vector2i
var _corpses: Array = []  ## {pos, type_id, owner, facing, t}
var _ai_was_started: bool = false
var _outcome_played: bool = false
var _contact: bool = false
var _markers: Array = []  ## {pos, color, t}
var _border_lines: PackedVector2Array = PackedVector2Array()  ## pairs, between sectors
var _art: Dictionary = {}  ## path -> Texture2D
var selected_building: int = -1
var selected_sector: int = -1
var _placing: Dictionary = {}  ## {kind, tier} while placing a building
var _notice: String = ""
var _notice_time: float = -10.0
var _winner: int = -1
var _build_menu_open: bool = false
var _menu_selection: Array = []  ## the selection the build menu was opened for
## Fog of war (Vision in the sim): unexplored land is black (campaign) or greyed out
## (skirmish: the land shows, never what is on it), explored land out of sight is dimmed,
## and enemies show only within sight. F4 lifts it (for testing).
var fog_enabled: bool = true
var fog_grey: bool = true  ## skirmish: unexplored land greyed out instead of black
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_tick: int = -1

@onready var cam := Camera2D.new()
var layer: Node2D
var hud_top: Label
var hud_help: Label
var help_button: Button
var building_bar: BuildingBar
var group_bar: GroupBar
var hud_center: Label
var panel: UnitPanel
var minimap: Minimap
var audio: BattleAudio
var build_panel: BuildPanel
var view3d: SkirmishView3D
var mode_3d: bool = true  ## Tab, F3 or the map button: false shows the flat tactical map
var tactical: TacticalMap = TacticalMap.new()
var map_button: Button
var _cam_before: Dictionary = {}  ## the 3D camera {pos, zoom} when the tactical map opened
var factions: Array = ["concord", "hollow"]  ## [you, the computer]; from SkirmishSetup.current
var map_template: String = ""  ## map template id ("" = the seed picks); from SkirmishSetup.current
var ai_difficulty: String = "normal"  ## EconomyAi.DIFFICULTIES; from SkirmishSetup.current
var pause_menu: PauseMenu
var build_ring: BuildRing
var _paused_before_menu: bool = false
var hero_bar: HeroBar
var hero_window: HeroWindow
## Campaign chapters (CampaignSetup.current): the running StoryMission and its HUD layer.
var campaign: CampaignSetup
var mission: StoryMission
var campaign_hud: CampaignHud
var _notice_queue: Array = []  ## campaign notices waiting their turn
var _casting: int = -1  ## hero skill slot waiting for a target click (-1 = none)


func _ready() -> void:
	add_child(cam)
	layer = Node2D.new()
	layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	layer.draw.connect(_draw_world)
	add_child(layer)
	audio = BattleAudio.new()
	add_child(audio)
	cursor = CommandCursor.new()
	add_child(cursor)
	view3d = SkirmishView3D.new()
	add_child(view3d)
	view3d.setup(self)
	_build_hud()
	_build_pause_menu()
	online = OnlineGame.current
	PLAYER = online.me if online != null else 0
	pause_menu.online = online != null
	campaign = CampaignSetup.current if online == null else null
	var setup := SkirmishSetup.current if campaign == null else null
	if setup != null:
		factions = setup.factions()
		seed_value = setup.seed_value
		map_template = setup.map_template()
		ai_difficulty = setup.difficulty
		slot_difficulty = setup.active_slots().map(func(sl: Dictionary) -> String: return String(sl.get("difficulty", "")))
	WbSettings.ensure_loaded()
	# The controls list stays hidden until F1 or the ? button asks for it.
	hud_help.visible = false
	_start(seed_value)


func _start(s: int) -> void:
	seed_value = s
	ais.clear()
	mission = null
	_notice_queue.clear()
	if campaign != null:
		# A campaign chapter: its handcrafted map, story hero, NPCs and quests.
		mission = StoryMission.new(campaign.mission_def(), campaign.progress())
		world = mission.build()
		factions = mission.factions
		if mission.is_war():
			# War chapters: every other side is a computer player at the chapter's difficulty.
			for o in range(1, factions.size()):
				ais.append(EconomyAi.new(o, String(mission.def.get("ai", "easy"))))
			ai = ais[0]
		else:
			ai = EconomyAi.new(1, ai_difficulty)  # hero chapters have no computer player
	else:
		world = SkirmishScenario.build_skirmish(s, factions, map_template)
		for o in range(1, factions.size()):
			if online != null and int(online.seats[o]) >= 0:
				continue  # a person plays this house
			var d: String = slot_difficulty[o] if o < slot_difficulty.size() and slot_difficulty[o] != "" else ai_difficulty
			ais.append(EconomyAi.new(o, d))
		# F2 and the resource bar read `ai`; with only people playing it is a stand-in that never runs.
		ai = ais[0] if not ais.is_empty() else EconomyAi.new(1, ai_difficulty)
	_casting = -1
	if online != null:
		online.lockstep.extras.assign(ais)  # a drift repair copies the computer players too
		# Every computer makes the same heroes in the same order (unit ids must match).
		for o in factions.size():
			_spawn_ai_hero(s, o, int(online.seats[o]) < 0)
	elif mission == null:
		for o in range(1, factions.size()):
			_spawn_ai_hero(s, o)
	selection.clear()
	selected_building = -1
	selected_sector = -1
	_placing = {}
	_winner = -1
	groups.clear()
	_corpses.clear()
	_markers.clear()
	_acc = 0.0
	paused = false
	_build_ground()
	minimap.rebuild(world)
	fog_grey = mission == null
	_fog_tick = -1
	_ai_was_started = false
	_outcome_played = false
	_contact = false
	audio.music("battle", true)
	_set_cam_limits(false)
	var home := world.economy.hall_of(PLAYER)
	if home != null:
		cam.position = home.center + Vector2(120, 0)
	elif world.heroes.hero_unit(PLAYER) != null:
		cam.position = world.heroes.hero_unit(PLAYER).pos
	cam.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	_build_borders()
	tactical.rebuild(world)
	_cam_before = {}
	if not mode_3d:
		_cam_before = {"pos": cam.position, "zoom": cam.zoom}
		show_full_map()
	view3d.rebuild(world, s)
	view3d.scene.atmosphere.weather_enabled = WbSettings.weather
	view3d.scene.atmosphere.muted = audio.muted
	_apply_mode()
	HudSkin.apply(self, factions[PLAYER])
	if online != null:
		var mine := world.heroes.hero_unit(PLAYER)
		if mine != null:
			selection = [mine.id]
		return
	if mission != null:
		selection = [world.heroes.hero_unit(PLAYER).id]
		hud_help.visible = false
		campaign_hud.show_intro()
		return
	# Your hero from the skirmish setup (no setup: the hero bar asks at the start).
	if SkirmishSetup.current != null and hero_classes().has(SkirmishSetup.current.hero_for(PLAYER)):
		pick_hero(SkirmishSetup.current.hero_for(PLAYER))


## Playable factions: every faction in units.json except the neutral defenders.
func playable_factions() -> Array:
	return world.catalog.factions.filter(func(f: String) -> bool: return f != "neutral")


func _apply_mode() -> void:
	layer.visible = not mode_3d
	view3d.visible = mode_3d
	view3d.overlay.visible = mode_3d
	view3d.camera.current = mode_3d
	if map_button != null:
		map_button.button_pressed = not mode_3d


## Tab, F3 or the map button: opens the tactical map showing the whole map, or goes back
## to the 3D world. Back in 3D the camera returns where it was, unless the player moved
## the map's view: then it looks at the middle of what the map showed.
func toggle_tactical() -> void:
	mode_3d = not mode_3d
	if not mode_3d:
		_cam_before = {"pos": cam.position, "zoom": cam.zoom}
		show_full_map()
	else:
		_set_cam_limits(false)
		var fit := full_map_zoom()
		if not _cam_before.is_empty():
			var moved: bool = absf(cam.zoom.x - fit) > 0.001 or cam.position.distance_to(full_map_center()) > 1.0
			cam.zoom = _cam_before["zoom"]
			cam.position = cam.position if moved else _cam_before["pos"]
		cam.zoom = Vector2.ONE * clampf(cam.zoom.x, ZOOM_MIN, ZOOM_MAX)
		_clamp_camera()
		_cam_before = {}
	_apply_mode()
	audio.play("click", _time, 0.5)


## Screen pixels the HUD covers above (resource bar) and below (unit panel) the map.
const MAP_INSET_TOP := 48.0
const MAP_INSET_BOTTOM := 116.0


## The zoom at which the whole map fits between the HUD bars (with a small margin).
func full_map_zoom() -> float:
	var vp := _screen_size() - Vector2(0, MAP_INSET_TOP + MAP_INSET_BOTTOM)
	var ws := world.nav.world_size()
	return minf(vp.x / ws.x, vp.y / ws.y) * 0.97


## Where the camera looks to show the whole map centred between the HUD bars.
func full_map_center() -> Vector2:
	var shift := (MAP_INSET_BOTTOM - MAP_INSET_TOP) * 0.5 / full_map_zoom()
	return world.nav.world_size() * 0.5 + Vector2(0, shift)


func _screen_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1280, 800)


## The tactical map's reset: the camera looks at the whole map.
func show_full_map() -> void:
	_set_cam_limits(true)
	cam.zoom = Vector2.ONE * full_map_zoom()
	cam.position = full_map_center()


## The map view may show beyond the map's edges (a whole map on a wide screen).
func _set_cam_limits(open: bool) -> void:
	var size := world.nav.world_size()
	var m := 100000 if open else 200
	cam.limit_left = -m
	cam.limit_top = -m
	cam.limit_right = int(size.x) + m
	cam.limit_bottom = int(size.y) + m


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud_top = _label(cl, Vector2(12, 8), 18)
	panel = UnitPanel.new()
	panel.skirmish = self
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = 10
	panel.offset_top = -104
	panel.offset_right = -262
	panel.offset_bottom = -10
	cl.add_child(panel)
	minimap = Minimap.new()
	minimap.skirmish = self
	minimap.anchor_left = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -250
	minimap.offset_top = -160
	minimap.offset_right = -10
	minimap.offset_bottom = -16
	minimap.look_at.connect(func(p: Vector2) -> void:
		cam.position = p
		_clamp_camera())
	minimap.order_to.connect(func(p: Vector2) -> void: _right_click(p, true, Input.is_key_pressed(KEY_SHIFT)))
	cl.add_child(minimap)
	building_bar = BuildingBar.new()
	building_bar.name = "BuildingBar"
	building_bar.skirmish = self
	building_bar.anchor_left = 1.0
	building_bar.anchor_top = 1.0
	building_bar.anchor_right = 1.0
	building_bar.anchor_bottom = 1.0
	building_bar.offset_left = -262
	building_bar.offset_right = -10
	building_bar.offset_top = -204
	building_bar.offset_bottom = -176
	cl.add_child(building_bar)
	build_panel = BuildPanel.new()
	build_panel.skirmish = self
	build_panel.anchor_left = 1.0
	build_panel.anchor_top = 1.0
	build_panel.anchor_right = 1.0
	build_panel.anchor_bottom = 1.0
	build_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Bottom edge just above the building emblems (building_bar.offset_top = -204), so it never covers them.
	build_panel.offset_left = -160
	build_panel.offset_right = -10
	build_panel.offset_top = -210
	build_panel.offset_bottom = -210
	build_panel.visible = false
	cl.add_child(build_panel)
	hero_bar = HeroBar.new()
	hero_bar.skirmish = self
	# Top left, under the resource bar, at 80% size.
	hero_bar.scale = Vector2(HeroBar.UI_SCALE, HeroBar.UI_SCALE)
	hero_bar.offset_left = 10
	hero_bar.offset_top = HeroBar.TOP
	hero_bar.offset_right = 840
	hero_bar.offset_bottom = HeroBar.TOP + HeroBar.BAR_H
	cl.add_child(hero_bar)
	hero_window = HeroWindow.new()
	hero_window.name = "HeroWindow"
	hero_window.skirmish = self
	cl.add_child(hero_window)
	# Control group portraits: top right, left of the ? button (HudSkin moves both under the resource bar).
	group_bar = GroupBar.new()
	group_bar.name = "GroupBar"
	group_bar.skirmish = self
	group_bar.anchor_left = 1.0
	group_bar.anchor_right = 1.0
	group_bar.offset_right = -102
	group_bar.offset_left = -102
	group_bar.offset_top = 50
	group_bar.offset_bottom = 50 + GroupBar.CARD.y
	cl.add_child(group_bar)
	help_button = Button.new()
	help_button.name = "HelpButton"
	help_button.text = "?"
	help_button.tooltip_text = "Controls (F1)"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.anchor_left = 1.0
	help_button.anchor_right = 1.0
	help_button.offset_left = -50
	help_button.offset_right = -14
	help_button.offset_top = 50
	help_button.offset_bottom = 86
	help_button.add_theme_font_size_override("font_size", 20)
	help_button.pressed.connect(toggle_help)
	cl.add_child(help_button)
	map_button = Button.new()
	map_button.name = "MapButton"
	map_button.icon = map_icon()
	map_button.toggle_mode = true
	map_button.tooltip_text = "Tactical map (Tab)"
	map_button.focus_mode = Control.FOCUS_NONE
	map_button.anchor_left = 1.0
	map_button.anchor_right = 1.0
	map_button.offset_left = -94
	map_button.offset_right = -58
	map_button.offset_top = 50
	map_button.offset_bottom = 86
	map_button.expand_icon = true
	map_button.pressed.connect(func() -> void:
		if map_button.button_pressed == mode_3d:
			toggle_tactical())
	cl.add_child(map_button)
	hud_help = _label(cl, Vector2(0, 94), 14)
	hud_help.anchor_left = 1.0
	hud_help.anchor_right = 1.0
	hud_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud_help.offset_left = -12
	hud_help.offset_right = -12
	hud_help.offset_top = 94
	hud_help.offset_bottom = 94
	hud_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.04, 0.03, 0.62)
	box.set_content_margin_all(8)
	box.set_corner_radius_all(4)
	hud_help.add_theme_stylebox_override("normal", box)
	hud_help.text = "\n".join([
		"Left click / drag: select units, buildings, settlements",
		"Shift: add or remove   B: build menu",
		"Right click a pile: gather   a building site: help build",
		"Double click: all of that type on screen",
		"Right click: move, attack an enemy, or take a settlement",
		"A + click: attack-move   T + click: capture   S: stop   H: hold   F: retreat",
		"Shift + any order: queue it (waypoints), shift + place: build one after another",
		"Q W E: hero skills   R: ultimate   Shift: cast at the mouse",
		"Hero gear: walk over loot to pick it up; click bag items to wear them, right click to drop",
		"Right click a skill: autocast on/off   + over a skill: learn it",
		"Ctrl+1-9: save group   1-9: recall (twice: jump)",
		"P: pause (orders still work)   Space: last alert",
		"Arrows / screen edge / middle drag: scroll   Wheel: zoom",
		"Minimap: click to look, right click to send   M: sound on/off",
		"Capture a settlement: right click it with soldiers (or T + click); they stay until it is yours",
		"Tab (or F3, or the map button): tactical map of the whole map, again: back to 3D",
		"F2: enemy AI on/off   F4: fog of war on/off   F5: new map",
		"F6: weather   Esc / F10: menu",
		"F1 or ?: hide this list"])
	campaign_hud = CampaignHud.new()
	campaign_hud.skirmish = self
	campaign_hud.build()
	campaign_hud.quest_box.position = Vector2(12, HeroBar.TOP + HeroBar.BAR_H * HeroBar.UI_SCALE + 10.0)
	campaign_hud.visible = false
	cl.add_child(campaign_hud)
	campaign_hud.outro_closed.connect(func(_won: bool) -> void:
		CampaignSetup.returning = true
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	hud_center = _label(cl, Vector2.ZERO, 34)
	hud_center.anchor_left = 0.0
	hud_center.anchor_right = 1.0
	hud_center.offset_left = 0
	hud_center.offset_right = 0
	hud_center.offset_top = 150  # below the hero bar (top left)
	hud_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## The map button's icon: a folded map with a route on it.
static func map_icon() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var paper := [Color(0.86, 0.79, 0.6), Color(0.74, 0.67, 0.5), Color(0.86, 0.79, 0.6)]
	for x in range(2, 22):
		var panel := mini((x - 2) / 7, 2)
		var tilt := 2 if panel == 1 else 0
		for y in range(4 + tilt, 20 + tilt):
			img.set_pixel(x, y, paper[panel])
		img.set_pixel(x, 4 + tilt, Color(0.2, 0.15, 0.1))
		img.set_pixel(x, 19 + tilt, Color(0.2, 0.15, 0.1))
	for y in range(4, 22):
		for x in [2, 9, 16, 21]:
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color(0.2, 0.15, 0.1))
	for i in 12:
		img.set_pixel(5 + i, 15 - (i * 7) / 12, Color(0.75, 0.2, 0.15))
	img.set_pixel(17, 8, Color(0.75, 0.2, 0.15))
	img.set_pixel(17, 9, Color(0.75, 0.2, 0.15))
	return ImageTexture.create_from_image(img)


func _label(parent: Node, p: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = p
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Rock cells get a boulder each (variant and size from a cell hash, so the
## same map always looks the same); water cells are drawn from the water field.
func _build_ground() -> void:
	_rocks.clear()
	_water_cells.clear()
	_forest_cells.clear()
	var nav := world.nav
	for y in nav.height:
		for x in nav.width:
			var c := Vector2i(x, y)
			var h := absi((x * 73856093) ^ (y * 19349663))
			match nav.kind_at(c):
				NavGrid.Kind.ROCK:
					_rocks.append({"pos": nav.center_of(c) + Vector2(float(h % 9) - 4.0, 10.0 + float(h % 5)),
						"variant": h % 20, "scale": 0.9 + float(h % 7) * 0.06})
				NavGrid.Kind.WATER:
					_water_cells.append(c)
				NavGrid.Kind.FOREST:
					_forest_cells.append(c)


## Opens or closes the hero window (I), once the player has a hero.
## Selects one of your buildings (the emblems over the minimap); look: the camera moves to it.
func select_building(id: int, look: bool = false) -> void:
	var b := world.economy.building(id)
	if b == null:
		return
	selection.clear()
	selected_sector = -1
	selected_building = id
	if look:
		cam.position = b.pos
		_clamp_camera()


## Selects one of your settlements (the hall emblem over the minimap); look: the camera moves to it.
func select_sector(id: int, look: bool = false) -> void:
	for sec in world.economy.sectors:
		if sec.id == id:
			selection.clear()
			selected_building = -1
			selected_sector = id
			if look:
				cam.position = sec.center
				_clamp_camera()
			return


## Shows or hides the controls list (F1 or the ? button top right).
func toggle_help() -> void:
	hud_help.visible = not hud_help.visible


func toggle_hero_window() -> void:
	if world == null or world.heroes.hero_of(PLAYER) == null:
		return
	hero_window.faction = factions[PLAYER]
	hero_window.toggle()


func unit_texture(type_id: String) -> Texture2D:
	return _texture(type_id)


func _texture(type_id: String) -> Texture2D:
	if not _textures.has(type_id):
		_textures[type_id] = load(world.catalog.get_unit(type_id)["sprite"])
	return _textures[type_id]


# --- Frame loop ---------------------------------------------------------------

## Whether the world is ticking now (not paused, no dialogue, card or pick open).
func sim_running() -> bool:
	return not paused and not _game_over() and not hero_bar.picking() and not campaign_hud.blocking()


func _process(delta: float) -> void:
	_time += delta
	_pan_camera(delta)
	if online != null:
		_online_frame(delta)
	elif sim_running():
		_acc += delta
		var steps := 0
		while _acc >= world.dt and steps < 4:
			_acc -= world.dt
			steps += 1
			for a in ais:
				a.update(world)
			world.step()
			if mission != null:
				mission.step()
			_collect_events()
			if campaign_hud.blocking():
				_acc = 0.0
				break
		if steps == 4:
			_acc = 0.0  # too slow: drop time instead of spiralling
	_age_effects(delta)
	_update_hud()
	cursor.refresh(delta, cursor_action)
	if mode_3d:
		view3d.update(delta)
	else:
		layer.queue_redraw()


## Online: the match runs at the lockstep's pace (no pause, nothing stops it but the end).
func _online_frame(delta: float) -> void:
	online.pump()
	for n in online.notices:
		_notice = n
		_notice_time = _time
		audio.play("error", _time, 0.6)
	online.notices.clear()
	if online.ended == "" and not online.lockstep.failed and world.economy.winner() < 0:
		online.lockstep.advance(world, _online_tick, delta)
	if online.lockstep.can_run():
		_wait_start = _time
	online.flush()
	_game_over()


func _online_tick() -> void:
	for a in ais:
		a.update(world)
	world.step()
	_collect_events()


## The one way the view changes the world: alone it happens now, online it goes to every
## computer and happens a moment later (then the result is not known yet: true).
func act(c: Dictionary) -> bool:
	if online != null:
		online.issue(c)
		return true
	return WorldCommands.apply(world, PLAYER, c)


func _collect_events() -> void:
	if mission != null:
		for e in mission.events:
			var text := CampaignHud.notice_for(e)
			if text != "":
				_notice_queue.append(text)
			if e["type"] in ["quest_start", "quest_done", "level", "join"]:
				audio.play("horn", _time, 0.6)
		mission.events.clear()
	for n in world.economy.notices:
		if int(n["owner"]) == PLAYER:
			_notice = n["text"]
			_notice_time = _time
			audio.play("error", _time, 0.5)
	for e in world.events:
		view3d.on_event(e)
		match e["type"]:
			"attack":
				var a := world.get_unit(int(e["unit"]))
				if a != null:
					if not _contact:
						_contact = true
						audio.play("start", _time, 0.9)
					audio.play("shot" if a.is_ranged() else "hit", _time, _hear(a.pos))
			"tower_shot":
				audio.play("shot", _time, _hear(e["pos"]))
			"hall_destroyed":
				var lost := int(e["owner"])
				_notice = "Your hall has fallen" if lost == PLAYER else "An enemy hall has fallen"
				_notice_time = _time
				audio.play("error" if lost == PLAYER else "horn", _time, 1.0)
			"building_destroyed":
				var lost_b := int(e["owner"])
				if lost_b == PLAYER or int(e.get("by", -1)) == PLAYER:
					_notice = "Your %s has been destroyed" % _destroyed_name(e) if lost_b == PLAYER \
						else "You destroyed an enemy %s" % _destroyed_name(e)
					_notice_time = _time
				audio.play("error" if lost_b == PLAYER else "hit", _time, _hear(e["pos"]))
				if int(e["building"]) == selected_building:
					selected_building = -1
			"capture":
				var who := int(e["owner"])
				_notice = "%s %s" % ["You took" if who == PLAYER else "The enemy took",
					world.economy.settlement(world.economy.sectors[int(e["sector"])])["name"]]
				_notice_time = _time
				audio.play("horn" if who == PLAYER else "error", _time, 0.8)
			"built", "trained":
				if int(e["owner"]) == PLAYER:
					audio.play("click", _time, 0.5)
			"veteran":
				if int(e["owner"]) == PLAYER and (String(e["promoted"]) != "" or int(e["level"]) >= 5):
					var vu := world.get_unit(int(e["unit"]))
					if vu != null:
						var was := String(world.catalog.get_unit(String(vu.def.get("upgrade_of", vu.type_id)))["name"])
						_notice = "Your %s has become Ascendant" % vu.def["name"] if int(e["level"]) >= 5 \
							else "Your %s was promoted to %s" % [was, vu.def["name"]]
						_notice_time = _time
						audio.play("horn", _time, 0.45)
			"hero_level":
				if int(e["owner"]) == PLAYER:
					_notice = "Your hero reached level %d" % int(e["level"])
					_notice_time = _time
					audio.play("horn", _time, 0.6)
			"hero_death":
				if int(e["owner"]) == PLAYER:
					_notice = "Your hero has fallen: back in %d s" % ceili(float(e["respawn"]))
					_notice_time = _time
			"lair_cleared":
				if int(e["owner"]) == PLAYER:
					_notice = "Lair cleared: +%d %s, loot on the ground" % [int(e["marks"]), _coin_name()]
					_notice_time = _time
					audio.play("horn", _time, 0.7)
			"shrine":
				if int(e["owner"]) == PLAYER:
					_notice = "The shrine heals and blesses your hero"
					_notice_time = _time
					audio.play("horn", _time, 0.5)
			"buy":
				if int(e["owner"]) == PLAYER:
					_notice = "Bought: %s" % e["name"]
					_notice_time = _time
					audio.play("click", _time, 0.7)
			"loot_pickup":
				if int(e["owner"]) == PLAYER:
					_notice = "Your hero found: %s" % e["name"]
					_notice_time = _time
					audio.play("click", _time, 0.7)
			"skill":
				audio.play("hit", _time, _hear(e["pos"]) * 0.8)
			"retire":
				selection.erase(e["unit"])
			"death":
				_corpses.append({"pos": e["pos"], "type_id": e["type_id"], "owner": e["owner"],
					"facing": e["facing"], "t": 0.0})
				selection.erase(e["unit"])
			"hit":
				var u := world.get_unit(int(e["unit"]))
				if u != null and u.owner == PLAYER and _time - _alert_time > 3.0:
					_last_alert = u.pos
					_alert_time = _time


## 1 in the middle of the screen, fading to 0 two screens away.
func _hear(p: Vector2) -> float:
	var view := view_rect()
	var d := p.distance_to(view.get_center()) / maxf(view.size.x, 1.0)
	return clampf(1.0 - (d - 0.3) / 1.7, 0.0, 1.0) * clampf(1.4 - (1.0 / cam.zoom.x - 1.0) * 0.3, 0.4, 1.0)


func _age_effects(delta: float) -> void:
	for c in _corpses:
		c["t"] += delta
	_corpses = _corpses.filter(func(c): return c["t"] < 6.0)
	for m in _markers:
		m["t"] += delta
	_markers = _markers.filter(func(m): return m["t"] < 0.6)


## A side that holds no settlement is beaten. The game ends when one side is left,
## or when you are beaten (then _winner is a rival still standing).
func _game_over() -> bool:
	if _winner >= 0:
		return true
	if mission != null:
		if mission.outcome != "":
			_winner = PLAYER if mission.outcome == "won" else 1
		return _winner >= 0
	_winner = world.economy.winner()
	if _winner < 0 and not _holds_any(PLAYER):
		for o in factions.size():
			if o != PLAYER and _holds_any(o):
				_winner = o
				break
	return _winner >= 0


func _holds_any(owner: int) -> bool:
	for sec in world.economy.sectors:
		if sec.owner == owner:
			return true
	return false


func _pan_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var r := vp.get_visible_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, r).has_point(m) and not _dragging:
		if m.x < EDGE_PAN:
			dir.x -= 1
		elif m.x > r.x - EDGE_PAN:
			dir.x += 1
		if m.y < EDGE_PAN:
			dir.y -= 1
		elif m.y > r.y - EDGE_PAN:
			dir.y += 1
	if dir != Vector2.ZERO:
		cam.position += dir.normalized() * PAN_SPEED * delta / cam.zoom.x
		_clamp_camera()


## Tactical map zoom: from the whole map in, keeping the point under the mouse in place.
func zoom_map(f: float, mouse: Vector2) -> void:
	var fit := full_map_zoom()
	var old := cam.zoom.x
	var z := clampf(old * f, fit, ZOOM_MAX)
	var half := _screen_size() * 0.5
	var under := cam.position + (mouse - half) / old
	cam.zoom = Vector2(z, z)
	cam.position = under - (mouse - half) / z
	if z <= fit + 0.0001:
		cam.position = full_map_center()  # all the way out: the whole map, centred
		return
	_clamp_camera()


func _clamp_camera() -> void:
	var s := world.nav.world_size()
	cam.position = Vector2(clampf(cam.position.x, 0, s.x), clampf(cam.position.y, 0, s.y))


func _update_hud() -> void:
	# Resources, people, hall and sectors are on the ResourceBar (HudSkin).
	hud_top.text = "ATTACK-MOVE: click a target point" if _attack_move_armed else (
		"CAPTURE: click a settlement" if _capture_armed else (
		"TACTICAL MAP: Tab to go back" if not mode_3d else ""))
	# Notices stay out of the way of the hero window and the skill trees.
	hud_center.modulate.a = 0.0 if hero_window.visible or (mission != null and campaign_hud.trees.visible) else 1.0
	if mission != null:
		# The quest log sits where the windows open.
		campaign_hud.quest_box.modulate.a = 0.0 if hero_window.visible or campaign_hud.trees.visible else 1.0
	if _winner == PLAYER:
		hud_center.text = "Victory"
	elif _winner >= 0:
		hud_center.text = "Defeat"
	elif online != null and online.ended != "":
		hud_center.text = online.ended
	elif online != null and online.lockstep.failed:
		hud_center.text = "Out of sync: the games drifted apart and could not be repaired. Please report it."
	elif online != null and online.lockstep.repairing():
		hud_center.text = "Re-syncing with the host..."
	elif online != null and online.waiting_text() != "" and _time - _wait_start > 0.5:
		hud_center.text = online.waiting_text()
	elif paused:
		hud_center.text = "Paused (P)"
	elif _time - _notice_time < 2.5:
		hud_center.text = _notice
	elif not _notice_queue.is_empty():
		_notice = _notice_queue.pop_front()
		_notice_time = _time
		hud_center.text = _notice
	else:
		hud_center.text = ""
	if pause_menu.is_open():
		hud_center.text = ""
	if not _outcome_played and _winner >= 0:
		_outcome_played = true
		audio.music("battle_victory_concord" if _winner == PLAYER else "battle_defeat", false)
		_show_outcome()
	_update_build_panel()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if pause_menu != null and pause_menu.is_open():
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _middle_drag:
			cam.position -= event.relative * (view3d.sim_per_pixel() if mode_3d else 1.0 / cam.zoom.x)
			_clamp_camera()
		elif _dragging and event.position.distance_to(_drag_start_screen) > 6.0:
			_box_active = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(e: InputEventMouseButton) -> void:
	var wp := _mouse_world()
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				var f := 1.12 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
				if not mode_3d:
					zoom_map(f, get_viewport().get_mouse_position())
					return
				var z := clampf(cam.zoom.x * f, ZOOM_MIN, ZOOM_MAX)
				cam.zoom = Vector2(z, z)
		MOUSE_BUTTON_MIDDLE:
			_middle_drag = e.pressed
		MOUSE_BUTTON_LEFT:
			if e.pressed and _casting >= 0:
				_finish_cast(wp)
				return
			if e.pressed and not _placing.is_empty():
				_place(wp, e.shift_pressed)
				return
			if e.pressed:
				if _attack_move_armed:
					_attack_move_armed = e.shift_pressed  # shift: keep queueing attack-moves
					_order_attack_move(wp, e.shift_pressed)
					return
				if _capture_armed:
					_capture_armed = false
					_order_capture(wp, e.shift_pressed)
					return
				_dragging = true
				_box_active = false
				_drag_start_screen = e.position
			elif _dragging:
				_dragging = false
				if _box_active:
					_box_select(e.shift_pressed)
				else:
					_click_select(wp, e.shift_pressed)
				_box_active = false
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_attack_move_armed = false
				_capture_armed = false
				if _casting >= 0:
					_casting = -1
					return
				if not _placing.is_empty():
					_placing = {}
					return
				_right_click(wp, false, e.shift_pressed)


## What a right click at wp would do with the current selection. The cursor shows it and
## _right_click carries it out, so the two always agree. kind: none, rally, gather,
## help_build, talk, attack, garrison, capture or move; sel = the units it is for.
func click_intent(wp: Vector2, from_minimap: bool = false) -> Dictionary:
	var eco := world.economy
	if selection.is_empty() and selected_building >= 0:
		return {"kind": "rally", "pos": wp}
	var workers: Array = []
	var soldiers: Array = []
	for id in selection:
		var u := world.get_unit(id)
		if u != null:
			(workers if u.is_worker() else soldiers).append(id)
	if not from_minimap and not workers.is_empty():
		var n := _node_at(wp)
		if n != null:
			return {"kind": "gather", "node": n.id, "pos": n.pos, "workers": workers, "others": soldiers,
				"usable": eco.uses(PLAYER, n.resource)}
		var site := _building_at(wp)
		if site != null and site.owner == PLAYER and not site.done():
			return {"kind": "help_build", "building": site.id, "pos": site.pos, "workers": workers, "others": soldiers}
	var sel := selection
	var target: SimUnit = null if from_minimap else _unit_at(wp, true)
	if mission != null and target != null and target.passive:
		# A villager: the hero walks over and talks (the hero is picked if nothing is).
		if sel.is_empty() and world.heroes.hero_unit(PLAYER) != null:
			sel = [world.heroes.hero_unit(PLAYER).id]
		if not sel.is_empty():
			return {"kind": "talk", "npc": target.id, "pos": target.pos, "sel": sel}
	if sel.is_empty():
		return {"kind": "none"}
	var fort: Building = null if from_minimap else _building_at(wp)
	if target == null and fort != null and not fort.is_fort() and fort.owner != PLAYER and fort.structure >= 0:
		return {"kind": "attack", "target": fort.structure, "pos": fort.pos, "sel": sel}  # torn down, never taken
	if target == null and fort != null and fort.is_fort():
		if fort.owner != PLAYER:
			return {"kind": "attack", "target": fort.structure, "pos": fort.pos, "sel": sel}
		if fort.kind == "tower" and fort.done() and _any_archer(sel):
			return {"kind": "garrison", "fort": fort.id, "pos": fort.pos, "sel": sel,
				"workers": workers, "soldiers": soldiers}
	var hall: SimUnit = null if from_minimap or target != null else _enemy_hall_at(wp)
	if hall != null:
		return {"kind": "attack", "target": hall.id, "pos": hall.pos, "sel": sel}  # a capital is not taken: it is torn down
	if target != null and target.owner != PLAYER:
		return {"kind": "attack", "target": target.id, "pos": target.pos, "sel": sel}
	if target == null and not from_minimap and not soldiers.is_empty():
		var sec := sector_under(wp)
		if sec != null and eco.can_capture(PLAYER, sec):
			return {"kind": "capture", "sector": sec.id, "pos": sec.center, "sel": sel,
				"workers": workers, "soldiers": soldiers}
	var fly := not soldiers.is_empty() and workers.is_empty()
	for id in soldiers:
		var u := world.get_unit(id)
		if u != null and not u.is_flying():
			fly = false
	return {"kind": "move", "pos": wp, "sel": sel, "workers": workers, "soldiers": soldiers,
		"blocked": not fly and world.nav.is_blocked(wp)}


## The settlement drawn at this point (the same reach as clicking to select one), or null.
## Settlements never seen stay unknown.
func sector_under(wp: Vector2) -> Sector:
	var reach := 170.0 if mode_3d else maxf(70.0, 18.0 / cam.zoom.x)
	var best: Sector = null
	var best_d := reach
	for sec in world.economy.sectors:
		var d := sec.center.distance_to(wp)
		if d < best_d and (sec.owner == PLAYER or has_explored(sec.center)):
			best_d = d
			best = sec
	return best


func _any_archer(ids: Array) -> bool:
	for id in ids:
		var u := world.get_unit(id)
		if u != null and u.is_ranged() and not u.is_flying() and not u.is_hero():
			return true
	return false


## Gives an order now, or (queued, shift held) puts it at the end of the units' queue.
func _order(ids: Array, cmd: Dictionary, queued: bool) -> void:
	if ids.is_empty():
		return
	act({"t": "order", "ids": ids, "cmd": cmd, "queued": queued})


func _right_click(wp: Vector2, from_minimap: bool = false, queued: bool = false) -> void:
	var eco := world.economy
	var it := click_intent(wp, from_minimap)
	var gold := Color(0.95, 0.85, 0.4)
	match String(it["kind"]):
		"rally":
			act({"t": "rally", "building": selected_building, "point": wp})
			_markers.append({"pos": wp, "color": gold, "t": 0.0})
			return
		"none":
			audio.play("error", _time, 0.6)
			return
		"gather":
			if not it["usable"]:
				act({"t": "gather", "ids": it["workers"], "node": it["node"]})  # says why not
				_collect_notices_now()
				audio.play("error", _time, 0.6)
				return
			_order(it["workers"], {"type": "gather", "node": it["node"]}, queued)
			_order(it["others"], {"type": "move", "point": wp}, queued)
			_markers.append({"pos": it["pos"], "color": gold, "t": 0.0})
		"help_build":
			_order(it["workers"], {"type": "build", "building": it["building"]}, queued)
			_order(it["others"], {"type": "move", "point": wp}, queued)
			_markers.append({"pos": it["pos"], "color": gold, "t": 0.0})
		"talk":
			selection = it["sel"]
			world.drop_plans(selection)
			if not mission.command_talk(mission.npc_of(int(it["npc"]))):
				audio.play("error", _time, 0.5)
				return
			_markers.append({"pos": it["pos"], "color": gold, "t": 0.0})
		"attack":
			_order(it["sel"], {"type": "attack", "target": it["target"]}, queued)
			_markers.append({"pos": it["pos"], "color": Color(1, 0.3, 0.2), "t": 0.0})
		"garrison":
			if queued:
				_order(it["sel"], {"type": "garrison", "fort": it["fort"]}, true)
			else:
				act({"t": "garrison_now", "ids": it["sel"], "fort": it["fort"], "point": wp})  # no room: walk there
			_markers.append({"pos": it["pos"], "color": SELECT_COLOR, "t": 0.0})
		"capture":
			# Soldiers go to take it; workers just walk along.
			_order(it["soldiers"], {"type": "capture", "sector": it["sector"]}, queued)
			_order(it["workers"], {"type": "move", "point": wp}, queued)
			_markers.append({"pos": it["pos"], "color": CAPTURE_COLOR, "t": 0.0})
		_:
			# Soldiers march ready to fight: they engage enemies they meet on the way. Troops
			# already in a fight break off instead (a retreat), so the order wins over auto-attack.
			_order(it["sel"], {"type": "move", "point": wp}, queued)
			_markers.append({"pos": wp, "color": SELECT_COLOR, "t": 0.0})
	audio.play("click", _time, 0.7)


func _order_attack_move(wp: Vector2, queued: bool = false) -> void:
	if selection.is_empty():
		return
	_order(selection, {"type": "attack_move", "point": wp}, queued)
	_markers.append({"pos": wp, "color": Color(1, 0.55, 0.2), "t": 0.0})


## The queued orders of the selected units, as lines to draw: one point list per queue,
## starting at its members' middle (sim coordinates).
func queued_paths() -> Array:
	var out: Array = []
	var seen := {}
	for id in selection:
		var u := world.get_unit(id)
		if u == null or u.plan_id < 0 or seen.has(u.plan_id):
			continue
		seen[u.plan_id] = true
		var pts := world.plan_points(u)
		if pts.is_empty():
			continue
		var c := Vector2.ZERO
		var n := 0
		for oid in selection:
			var o := world.get_unit(oid)
			if o != null and o.plan_id == u.plan_id:
				c += _draw_pos(o)
				n += 1
		var line := PackedVector2Array([c / maxi(n, 1)])
		line.append_array(PackedVector2Array(pts))
		out.append(line)
	return out


## The cursor for where the mouse is now (CommandCursor.ACTIONS): what a click would do.
func cursor_action() -> String:
	if (pause_menu != null and pause_menu.is_open()) or _winner >= 0 or world == null:
		return "default"
	if get_viewport().gui_get_hovered_control() != null:
		return "default"
	var wp := _mouse_world()
	if _casting >= 0:
		return "attack"
	if not _placing.is_empty():
		if String(_placing["kind"]) == "wall":
			return "build" if not _placing.has("start") or String(wall_plan()["problem"]) == "" else "blocked"
		return "build" if world.economy.can_place(PLAYER, wp, placing_radius()) else "blocked"
	if _attack_move_armed:
		return "attack"
	if _capture_armed:
		var sec := sector_under(wp)
		return "capture" if sec != null and world.economy.can_capture(PLAYER, sec) else "blocked"
	var hover := _unit_at(wp)
	var own := hover != null and hover.owner == PLAYER and not hover.passive
	var it := click_intent(wp)
	match String(it["kind"]):
		"gather":
			return "pickup" if it["usable"] else "blocked"
		"help_build":
			return "build"
		"talk":
			return "encounter"
		"attack":
			return "attack"
		"garrison":
			return "select"
		"capture":
			return "capture"
		"rally":
			return "move"
		"move":
			if own:
				return "select"
			return "blocked" if it["blocked"] else "move"
	return "select" if own else "default"


## T + click: the selected troops take the settlement nearest the click.
func _order_capture(wp: Vector2, queued: bool = false) -> void:
	var sec := sector_under(wp)
	if sec == null:
		var best := 260.0
		for s in world.economy.sectors:
			if s.center.distance_to(wp) < best and (s.owner == PLAYER or has_explored(s.center)):
				best = s.center.distance_to(wp)
				sec = s
	var soldiers: Array = []
	for id in selection:
		var u := world.get_unit(id)
		if u != null and not u.is_worker():
			soldiers.append(id)
	if sec == null or soldiers.is_empty() or not world.economy.can_capture(PLAYER, sec):
		audio.play("error", _time, 0.6)
		return
	_order(soldiers, {"type": "capture", "sector": sec.id}, queued)
	_markers.append({"pos": sec.center, "color": CAPTURE_COLOR, "t": 0.0})
	audio.play("click", _time, 0.7)


func _key(e: InputEventKey) -> void:
	var k := e.keycode
	if mission != null and campaign_hud.key(k):
		return
	if mission != null and k == KEY_ESCAPE and campaign_hud.trees.visible:
		campaign_hud.trees.hide()
		return
	if k >= KEY_1 and k <= KEY_9:
		var g := int(k - KEY_0)
		if e.ctrl_pressed or e.meta_pressed:
			set_group(g)
		else:
			recall_group(g)
		return
	if hero_window.visible and k in [KEY_ESCAPE, KEY_I, KEY_C]:
		hero_window.close()
		return
	match k:
		KEY_I, KEY_C:
			toggle_hero_window()
		KEY_Q, KEY_W, KEY_E, KEY_R:
			start_cast(["Q", "W", "E", "R"].find(OS.get_keycode_string(k)), e.shift_pressed)
		KEY_B:
			_build_menu_open = not _build_menu_open
			_menu_selection = selection.duplicate()
		KEY_A:
			if not selection.is_empty():
				_attack_move_armed = true
				_capture_armed = false
		KEY_T:
			if not selection.is_empty():
				_capture_armed = true
				_attack_move_armed = false
		KEY_S:
			act({"t": "stop", "ids": selection})
		KEY_H:
			act({"t": "hold", "ids": selection})
		KEY_F:
			retreat(selection)
		KEY_P, KEY_PAUSE:
			if online == null:
				paused = not paused
		KEY_SPACE:
			if _last_alert.x >= 0:
				cam.position = _last_alert
		KEY_ESCAPE:
			if _casting >= 0:
				_casting = -1
			elif not _placing.is_empty():
				_placing = {}
			elif _attack_move_armed or _capture_armed:
				_attack_move_armed = false
				_capture_armed = false
			elif _build_menu_open and build_ring.visible:
				_build_menu_open = false
			elif not selection.is_empty() or selected_building >= 0 or selected_sector >= 0:
				selection.clear()
				selected_building = -1
				selected_sector = -1
			else:
				open_pause_menu()
		KEY_F1:
			toggle_help()
		KEY_F4:
			if online != null:
				return  # no peeking online
			fog_enabled = not fog_enabled
			_fog_tick = -1
		KEY_F3, KEY_TAB:
			toggle_tactical()
		KEY_F2:
			if online != null:
				return
			var on := not ai.enabled
			for a in ais:
				a.enabled = on
		KEY_M:
			audio.set_muted(not audio.muted)
			view3d.scene.atmosphere.muted = audio.muted
		KEY_F6:
			view3d.scene.atmosphere.next_weather()
		KEY_F5:
			if online == null:
				_start(seed_value + 1)
		KEY_F10:
			open_pause_menu()


## Retreat (F, or the foot on a unit card): these units run home to the capital, 40% faster,
## and fight nothing on the way.
func retreat(ids: Array) -> void:
	if ids.is_empty():
		return
	if act({"t": "retreat", "ids": ids.duplicate()}):
		audio.play("click", _time, 0.7)
	else:
		audio.play("error", _time, 0.6)


## Ctrl + number: the selection becomes group g; with nothing selected, group g is cleared.
func set_group(g: int) -> void:
	if selection.is_empty():
		groups.erase(g)
	else:
		groups[g] = selection.duplicate()


## Number key (or a click on the group's portrait, top right): selects group g; twice quickly, the camera looks at it.
func recall_group(g: int) -> void:
	if not groups.has(g):
		return
	var alive: Array = []
	for id in groups[g]:
		if can_select(world.get_unit(id), PLAYER):
			alive.append(id)
	if alive.is_empty():
		groups.erase(g)
		return
	groups[g] = alive
	selection = alive.duplicate()
	selected_building = -1
	selected_sector = -1
	if _last_group_key == g and _time - _last_group_time < DOUBLE_TAP and not alive.is_empty():
		var c := Vector2.ZERO
		for id in alive:
			c += world.get_unit(id).pos
		cam.position = c / alive.size()
	_last_group_key = g
	_last_group_time = _time


func _node_at(wp: Vector2) -> ResNode:
	if mode_3d and _at_mouse(wp):
		for n in world.economy.nodes:
			if not n.depleted() and view3d.billboard_hit(n.pos, 1.9, 1.9, get_viewport().get_mouse_position()):
				return n
	for n in world.economy.nodes:
		if not n.depleted() and n.pos.distance_to(wp + Vector2(0, 14)) < 34.0:
			return n
	return null


func _building_at(wp: Vector2) -> Building:
	if mode_3d and _at_mouse(wp):
		for b in world.economy.buildings:
			var w := b.radius * 2.6 * SkirmishView3D.ART_SCALE / TerrainField.PX
			if view3d.billboard_hit(b.pos, w, w * 0.9, get_viewport().get_mouse_position()):
				return b
	for b in world.economy.buildings:
		if mode_3d and b.pos.distance_to(wp + Vector2(0, b.radius * 0.4)) < b.radius * 1.2:
			return b
		var br := b.radius * sprite_k()
		if not mode_3d and (b.owner == PLAYER or has_explored(b.pos)) \
				and b.pos.distance_to(wp + Vector2(0, br * 0.4)) < br * 1.2:
			return b
	return null


## "dwelling" or "faction building", for the notice when one falls.
static func _destroyed_name(e: Dictionary) -> String:
	return "faction building" if String(e.get("kind", "")) == "special" else "dwelling"


## The hit points of an enemy capital under the cursor, or null.
func _enemy_hall_at(wp: Vector2) -> SimUnit:
	for sec in world.economy.sectors:
		var st := world.defense.hall_structure(sec)
		if st != null and st.owner != PLAYER and sec.center.distance_to(wp) < st.radius() * 2.0:
			return st
	return null


## The colour of a capital's strength bar: green for yours, red for a rival's.
static func hall_bar_color(owner: int) -> Color:
	return Color(0.35, 0.85, 0.3) if owner == PLAYER else Color(0.88, 0.25, 0.18)


## Workers run themselves (resource weights, the nearest one builds), so the player
## never selects them: clicks, boxes, double clicks and control groups pass them by.
static func can_select(u: SimUnit, owner: int) -> bool:
	return u != null and u.owner == owner and not u.is_worker()


## The ids of `ids` the player `owner` may have selected (in order).
static func selectable(w: SimWorld, ids: Array, owner: int) -> Array:
	var out: Array = []
	for id in ids:
		if can_select(w.get_unit(id), owner):
			out.append(id)
	return out


## Workers building (or walking to build) this site.
func _builders(b: Building) -> int:
	var n := 0
	for u in world.economy.workers_of(b.owner):
		if u.order == SimUnit.Order.BUILD and u.job == b.id:
			n += 1
	return n


## A site's "Send another worker": the spare worker nearest it comes to help.
func _send_builder(building_id: int) -> void:
	var b := world.economy.building(building_id)
	var near := world.economy.spare_worker(PLAYER, b.pos) if b != null and not b.done() else null
	if near == null:
		_notice = "No free worker to send"
		_notice_time = _time
		audio.play("error", _time, 0.6)
		return
	act({"t": "help_build", "ids": [near.id], "building": building_id})
	_markers.append({"pos": b.pos, "color": Color(0.95, 0.85, 0.4), "t": 0.0})
	audio.play("click", _time, 0.7)


func _place(wp: Vector2, keep: bool) -> void:
	# The nearest free worker goes.
	var near := world.economy.spare_worker(PLAYER, wp)
	if near == null:
		_notice = "No free worker to build it"
		_notice_time = _time
		audio.play("error", _time, 0.6)
		return
	var ws := [near.id]
	if _placing["kind"] == "wall":
		# Two clicks: where the wall starts, where it ends. Shift keeps on walling from there.
		if not _placing.has("start"):
			_placing["start"] = wp
			audio.play("click", _time, 0.6)
			return
		if not act({"t": "wall", "ids": ws, "a": _placing["start"], "b": wp}):
			_collect_notices_now()
			return
		audio.play("click", _time, 0.8)
		if keep:
			_placing["start"] = wp
		else:
			_placing = {}
		return
	# Shift: the workers build the sites one after another (a queue) instead of leaving the
	# last one for the next.
	if online != null and not world.economy.can_place(PLAYER, wp, placing_radius()):
		_notice = "Can't build there"
		_notice_time = _time
		audio.play("error", _time, 0.6)
		return
	if act({"t": "build", "ids": ws, "keep": keep, "kind": String(_placing["kind"]), "tier": int(_placing["tier"]),
			"point": wp, "special": String(_placing.get("special", ""))}):
		audio.play("click", _time, 0.8)
		if not keep:
			_placing = {}
	else:
		_collect_notices_now()


func _collect_notices_now() -> void:
	for n in world.economy.notices:
		if int(n["owner"]) == PLAYER:
			_notice = n["text"]
			_notice_time = _time
	world.economy.notices.clear()
	audio.play("error", _time, 0.6)


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for r in cost:
		parts.append("%d %s" % [int(cost[r]), world.economy.e["resources"][r]])
	return ", ".join(parts)


const ROMAN := ["I", "II", "III", "IV"]


func _update_build_panel() -> void:
	var eco := world.economy
	var pl := eco.player(PLAYER)
	var b := eco.building(selected_building)
	if b != null:
		build_ring.hide_ring()
		_panel_building(eco, pl, b)
		return
	if selected_sector >= 0:
		build_ring.hide_ring()
		_panel_sector(eco, pl, eco.sectors[selected_sector])
		return
	var hero := world.heroes.hero_unit(PLAYER)
	if hero != null and hero.id in selection and not world.sites.merchant_near(PLAYER).is_empty():
		_panel_merchant(pl, world.sites.merchant_near(PLAYER))
		return
	if _build_menu_open and selection != _menu_selection:
		_build_menu_open = false  # a new selection closes the menu
	# B opens the menu with anything (or nothing) selected; the nearest worker builds.
	if _build_menu_open and _placing.is_empty():
		_panel_build_menu(eco, pl)
		return
	build_ring.hide_ring()
	if _build_menu_open:
		build_panel.hide_panel()
		return
	build_panel.hide_panel()


## The hero's coin, as the HUD names it (heroes.json rules "coin").
func _coin_name() -> String:
	return String(HeroCatalog.get_default().rules["coin"]["name"]).to_lower()


func _panel_merchant(pl: PlayerState, s: Dictionary) -> void:
	var sites := world.sites
	var sid: int = s["id"]
	var lines: Array = []
	var h := world.heroes.hero_of(PLAYER)
	var key := "shop%d:%d:%d" % [sid, s["stock"].size(), h.marks if h != null else 0]
	var buy := func(what: Variant) -> void:
		if not act({"t": "buy", "site": sid, "what": what}):
			_notice = sites.buy_problem(PLAYER, sid, what)
			_notice_time = _time
			audio.play("error", _time, 0.5)
	for k in ["health", "mana"]:
		var why := sites.buy_problem(PLAYER, sid, k)
		lines.append({"text": "%s potion (%d %s)" % [k.capitalize(), sites.potion_price(k), _coin_name()], "enabled": why == "",
			"action": buy.bind(k)})
	var icat := world.heroes.gear.icat
	for i in s["stock"].size():
		var item: Dictionary = s["stock"][i]
		var desc: Array = icat.describe(item)
		var why := sites.buy_problem(PLAYER, sid, i)
		lines.append({"text": "%s (%d %s)\n%s" % [item["name"], sites.item_price(item), _coin_name(), "  ".join(desc.slice(1, 3))],
			"enabled": why == "", "action": buy.bind(i)})
	if s["stock"].is_empty():
		lines.append({"text": "Sold out: new wares in %d s" % ceili(float(s["restock_in"]))})
	build_panel.show_entries(key, "%s: your hero has %d %s" % [sites.title(s), h.marks if h != null else 0, _coin_name()], lines)


func _panel_building(eco: Economy, pl: PlayerState, b: Building) -> void:
	if b.is_fort():
		_panel_fort(eco, pl, b)
		return
	var nm := eco.building_name(b)
	if not b.done():
		var n := _builders(b)
		build_panel.show_entries("site%d:%d:%d" % [b.id, int(b.progress * 20.0), n], nm,
			[{"text": "Being built: %d%%, %d at work" % [int(b.progress * 100.0), n]},
			{"text": "Send another worker", "action": _send_builder.bind(b.id)}])
		return
	if b.kind == "special":
		_panel_special(eco, pl, b, nm)
		return
	if b.kind == "storehouse":
		_panel_storehouse(eco, pl, b, nm)
		return
	if b.kind != "dwelling":
		build_panel.show_entries("st%d" % b.id, nm, [{"text": "Workers drop resources here."}])
		return
	_panel_dwelling(eco, pl, b, nm)


## A unit-training building, kept small: a Units row (one icon per unit it trains, with its tier
## and the cost beside it), the queue, and an Upgrades row (the upgraded unit's portrait with a
## gold up-arrow, cost beside it). Every word of explanation is in the tooltips.
func _panel_dwelling(eco: Economy, pl: PlayerState, b: Building, nm: String) -> void:
	var id := b.id
	var mine := b.owner == PLAYER
	var key := "dw%d:%s:%d:%s:%d" % [b.id, ",".join(b.queue), eco.max_tier(PLAYER), b.has_recruit, int(ceil(b.refit_left))]
	var units: Array = []
	for t: int in b.tiers:
		var ud := world.catalog.get_unit(b.unit_of(t))
		var cost := eco.unit_cost(b.unit_of(t))
		var locked := t > eco.max_tier(PLAYER)
		var ok := pl.can_pay(cost) and not locked and mine and b.refit_left <= 0.0 and b.queue.size() < 5
		var tier := t
		var df: Dictionary = ud.get("defense", {})
		var tip := "Train %s (tier %d): %s\n%d health, %.0f %s damage, %.0f against buildings\nDefence %d%% melee, %d%% ranged, %d%% magic" % [
			ud["name"], t, _cost_text(cost), int(ud["hp"]), float(ud["damage"]), UnitCatalog.damage_type_of(ud),
			UnitCatalog.building_damage_of(ud), roundi(float(df.get("melee", 0.0)) * 100.0),
			roundi(float(df.get("ranged", 0.0)) * 100.0), roundi(float(df.get("magic", 0.0)) * 100.0)]
		if locked:
			tip += "\n" + eco.tier_lock_text(t)
		elif b.refit_left > 0.0:
			tip += "\nWait for the upgrade to finish."
		elif b.queue.size() >= 5:
			tip += "\nThe queue is full."
		elif not pl.can_pay(cost):
			tip += "\nNot enough resources."
		units.append({"texture": _tex_at(String(ud["sprite"])), "badge": str(t), "cost": cost, "enabled": ok, "tooltip": tip,
			"action": func() -> void:
				if act({"t": "train", "building": id, "tier": tier}):
					audio.play("click", _time, 0.7)
				else:
					_collect_notices_now()})
		key += ":%s" % ok
	var lines: Array = [{"header": "Units"}, {"icons": units, "side": true}]
	if not b.queue.is_empty():
		var q: Array = []
		for type_id in b.queue:
			var qd := world.catalog.get_unit(String(type_id))
			q.append({"texture": _tex_at(String(qd["sprite"])), "name": String(qd["name"])})
		lines.append({"queue": q, "tooltip": "Training" if b.has_recruit else "Waiting for a free worker"})
	var ups: Array = []
	if b.refit_left > 0.0:
		var ru := world.catalog.get_unit(world.catalog.upgrade_of_unit(b.unit_of(b.refit_tier)))
		ups.append({"texture": _tex_at(String(ru["sprite"])), "arrow": true, "progress": 1.0 - b.refit_left / maxf(eco.dwelling_upgrade_seconds(b.refit_tier), 0.01),
			"tooltip": "Upgrading to %s: %d s" % [ru["name"], int(ceil(b.refit_left))]})
	elif mine:
		for t: int in b.tiers:
			if not eco.can_upgrade_dwelling(b, t):
				continue
			var ud := world.catalog.get_unit(b.unit_of(t))
			var uc := eco.dwelling_upgrade_cost(PLAYER, t)
			var up := world.catalog.get_unit(world.catalog.upgrade_of_unit(b.unit_of(t)))
			var up_ok := pl.can_pay(uc) and b.queue.is_empty() and not b.has_recruit
			var up_name: String = world.catalog.building_names.get(eco.e["buildings"][pl.faction]["dwellings"][t - 1] + "_up", "Upgrade")
			var tier := t
			var tip := "%s: %s\nTrain %s instead of %s from now on.\n%s" % [up_name, _cost_text(uc), up["name"], ud["name"], _upgrade_tooltip(ud, up)]
			if not b.queue.is_empty() or b.has_recruit:
				tip += "\nNeeds an empty queue."
			elif not pl.can_pay(uc):
				tip += "\nNot enough resources."
			ups.append({"texture": _tex_at(String(up["sprite"])), "arrow": true, "cost": uc, "enabled": up_ok, "tooltip": tip,
				"action": func() -> void:
					if act({"t": "refit", "building": id, "tier": tier}):
						audio.play("click", _time, 0.7)
					else:
						_collect_notices_now()})
			key += ":u%d%s" % [t, up_ok]
	if not ups.is_empty():
		lines.append({"header": "Upgrades"})
		lines.append({"icons": ups, "side": true})
	var span := "tier %d" % b.tier if b.tiers.size() == 1 else "tiers %d-%d" % [b.tiers[0], b.tiers[-1]]
	build_panel.show_entries(key, nm, lines, "%s, %s.\nEach unit takes one of your workers, who walks here and comes out as the soldier.\nRight click the ground: rally point." % [nm, span])
	var prog: Array = []
	for i in b.queue.size():
		prog.append(1.0 - b.train_left / maxf(b.train_total, 0.01) if i == 0 and b.has_recruit else 0.0)
	build_panel.set_queue_progress(prog)


## A storehouse: workers drop loads here, and it sells the worker upgrades: one icon per resource
## the faction gathers, its next level as a badge and the cost under it; the rest in the tooltip.
func _panel_storehouse(eco: Economy, _pl: PlayerState, b: Building, nm: String) -> void:
	var id := b.id
	var mine := b.owner == PLAYER
	var top := eco.gather_levels_max()
	var icons: Array = []
	var key := "st%d" % b.id
	for r: String in eco.gather_resources(b.owner):
		var lv := eco.gather_level(b.owner, r)
		var rname := String(eco.e["resources"][r])
		var why := eco.gather_upgrade_lock(b.owner, id, r)
		var tip := "%s gathering: level %d of %d" % [rname.capitalize(), lv, top]
		if lv > 0:
			tip += ", loads worth +%d%%" % roundi(eco.gather_bonus(b.owner, r) * 100.0)
		var ic := {"texture": WbStyle.resource_icon(r), "badge": ROMAN[mini(lv, ROMAN.size() - 1)] if lv < top else "max"}
		if lv < top:
			var cost := eco.gather_upgrade_cost(b.owner, r)
			tip += ".\nLevel %d: all your workers bring in +%d%% %s, for good. %s, %d s." % [lv + 1,
				roundi(eco.gather_bonus(b.owner, r, lv + 1) * 100.0), rname, _cost_text(cost), int(eco.gather_upgrade_seconds(b.owner, r))]
			ic["cost"] = cost
			if b.study == r:
				ic["progress"] = 1.0 - b.study_left / maxf(b.study_total, 0.01)
				tip += "\nUnder way: %d s left." % ceili(b.study_left)
			elif why != "":
				tip += "\n" + why + "."
			ic["enabled"] = mine and why == ""
			ic["action"] = func() -> void:
				if act({"t": "gather_upgrade", "building": id, "res": r}):
					audio.play("click", _time, 0.7)
				else:
					_collect_notices_now()
		else:
			tip += "."
		ic["tooltip"] = tip
		icons.append(ic)
		key += ":%s%d%s" % [r, lv, why]
	key += ":%s%d" % [b.study, ceili(b.study_left)]
	var lines: Array = [{"icons": icons}]
	if b.study != "":
		lines.append({"text": "Upgrading %s: %d s" % [eco.e["resources"][b.study], ceili(b.study_left)]})
	lines.append({"text": "Workers drop loads here. Upgrades help all your workers."})
	build_panel.show_entries(key, nm, lines)


## A faction building: what it does, and its button(s) when it has any.
func _panel_special(eco: Economy, pl: PlayerState, b: Building, nm: String) -> void:
	var d := eco.def_of(b)
	var fx: Dictionary = d["effect"]
	var kind := String(fx["kind"])
	var sp := world.specials
	var id := b.id
	var lines: Array = [{"text": String(d["text"])}]
	var key := "sp%d" % b.id
	var mine := b.owner == PLAYER
	var press := func(arg: String) -> void:
		if act({"t": "special", "building": id, "arg": arg}):
			audio.play("click", _time, 0.7)
		else:
			_collect_notices_now()
	match kind:
		"trade":
			var txt := "Give %s for %s" % [_cost_text(fx["give"]) + (" and a worker" if fx.get("worker", false) else ""), _cost_text(fx["take"])]
			var why := sp.can_use(PLAYER, id)
			lines.append({"text": txt, "enabled": mine and why == "", "action": press.bind("")})
			key += ":%s" % why
		"market":
			for arg: String in sp.market_pairs(PLAYER):
				var o := sp.market_offer(PLAYER, id, arg)
				if o["give"] != "gold" and o["take"] != "gold":
					continue  # keep the list short: gold for anything, anything for gold
				var why := sp.can_use(PLAYER, id, arg)
				lines.append({"text": "%d %s for %d %s" % [o["give_n"], eco.e["resources"][o["give"]], o["take_n"], eco.e["resources"][o["take"]]],
					"enabled": mine and why == "", "action": press.bind(arg)})
				key += ":%s" % (why == "")
		"gate":
			var why := sp.can_use(PLAYER, id)
			var src := "your hall" if fx["from"] == "hall" else "your other %ss" % String(d["name"]).to_lower()
			lines.append({"text": "Call the troops standing at %s" % src + ("" if why == "" else " (%s)" % why.to_lower()),
				"enabled": mine and why == "", "action": press.bind("")})
			key += ":%s" % why
		"research":
			var why := sp.can_use(PLAYER, id)
			if pl.researched.has(b.special):
				lines.append({"text": "Researched: your troops take %d%% less damage." % roundi((1.0 - float(fx["taken_factor"])) * 100.0)})
			elif b.timer > 0.0:
				lines.append({"text": "Researching: %d s" % ceili(b.timer)})
			else:
				lines.append({"text": "Research (%s): your troops take %d%% less damage, for good" % [_cost_text(fx["cost"]),
					roundi((1.0 - float(fx["taken_factor"])) * 100.0)], "enabled": mine and why == "", "action": press.bind("")})
			key += ":%s:%d" % [why, ceili(b.timer)]
		"feast":
			var why := sp.can_use(PLAYER, id)
			lines.append({"text": "Hold a feast (%s): all your troops +%d%% %s for %d s" % [_cost_text(fx["cost"]),
				roundi(float(fx["value"]) * 100.0), fx["status"], int(fx["seconds"])] + ("" if why == "" else " (%s)" % why.to_lower()),
				"enabled": mine and why == "", "action": press.bind("")})
			key += ":%s" % why
		"spawn", "raise":
			lines.append({"text": "%d of %d standing" % [b.spawned.size(), int(fx["max"])]})
			key += ":%d" % b.spawned.size()
	if kind == "spawn" or kind == "gate":
		lines.append({"text": "Right click the ground: rally point."})
	build_panel.show_entries(key, nm, lines)


## What a dwelling upgrade brings: the stat gains and the new specials, on one line.
func _upgrade_tooltip(base: Dictionary, up: Dictionary) -> String:
	var t := "+%d health, +%.0f damage" % [int(up["hp"]) - int(base["hp"]), float(up["damage"]) - float(base["damage"])]
	for a in up["abilities"]:
		if not a in base["abilities"]:
			t += "; " + String(SPECIAL_TEXT.get(a, String(a).replace("_", " ")))
	return t + ". Permanent."


func _panel_fort(_eco: Economy, pl: PlayerState, b: Building) -> void:
	var forts := world.forts
	var st := world.get_unit(b.structure)
	var nm: String = {"wall": "Wall", "gate": "Gate", "tower": "Tower"}[b.kind]
	var hp := "%d / %d" % [int(st.hp), int(st.max_hp)] if st != null else ""
	var lines: Array = [{"text": "Strength %s" % hp}]
	var key := "fort%d:%s:%s" % [b.id, b.kind, hp]
	if not b.done():
		var n := _builders(b)
		lines.append({"text": "Being built: %d%%, %d at work" % [int(b.progress * 100.0), n]})
		lines.append({"text": "Send another worker", "action": _send_builder.bind(b.id)})
		key += ":b%d:%d" % [int(b.progress * 20.0), n]
	elif b.upgrade_left > 0.0:
		lines.append({"text": "Becoming a %s: %d s" % [b.upgrade_to, int(ceil(b.upgrade_left))]})
		key += ":u%d" % int(ceil(b.upgrade_left))
	elif b.owner == PLAYER and b.kind == "wall":
		var id := b.id
		for kind in ["gate", "tower"]:
			var c := forts.upgrade_cost(kind)
			var what := "Make a gate: opens for your people, shut to the enemy" if kind == "gate" \
				else "Raise a tower: up to %d archers stand on it" % int(forts.conf()["tower"]["garrison"])
			lines.append({"text": "%s (%s)" % [what, _cost_text(c)], "enabled": pl.can_pay(c),
				"action": func() -> void:
					if not act({"t": "fort_upgrade", "building": id, "kind": kind}):
						_collect_notices_now()})
			key += ":%s" % pl.can_pay(c)
	elif b.kind == "gate":
		lines.append({"text": "Opens when your units come close. Mind: an enemy at hand can slip through then."})
	elif b.kind == "tower":
		var cap := int(forts.conf()["tower"]["garrison"])
		lines.append({"text": "Archers %d / %d. Select ranged units and right click the tower to send them up.\nUp there they shoot farther; only ranged and flying foes can hurt them." % [b.garrison.size(), cap]})
		key += ":g%d" % b.garrison.size()
		if b.owner == PLAYER and not b.garrison.is_empty():
			var id := b.id
			lines.append({"text": "Bring them down", "action": func() -> void: act({"t": "fort_release", "building": id})})
	build_panel.show_entries(key, nm, lines)


func _panel_sector(eco: Economy, pl: PlayerState, sec: Sector) -> void:
	var st := eco.settlement(sec)
	var lines: Array = []
	var who := "Yours" if sec.owner == PLAYER else ("Enemy" if sec.owner >= 0 else "Neutral")
	lines.append({"text": "%s. Up to %d workers, %d gold a minute." % [who, int(st["workers"]), int(st["gold_per_min"])]})
	var held: Dictionary = world.map_info.get("garrisons", {}).get(sec.id, {})
	if sec.owner < 0 and not held.is_empty() and has_explored(sec.center):
		var parts: PackedStringArray = []
		for e: Array in held["units"]:
			parts.append("%d %s" % [int(e[1]), String(world.catalog.get_unit(String(e[0])).get("name", e[0]))])
		lines.append({"text": "Held by %s: %s." % [held["name"], ", ".join(parts)]})
	var key := "sec%d:%d:%s" % [sec.id, sec.owner, sec.size]
	if sec.owner == PLAYER and int(st["workers"]) > 0:
		var n := 0
		for u in world.units:
			if u.owner == PLAYER and u.is_worker() and u.home_sector == sec.id:
				n += 1
		var wl := "Workers %d/%d" % [n, int(st["workers"])]
		if n < int(st["workers"]):
			wl += ", next in %d s" % ceili(float(st["spawn_every"]) - sec.spawn_timer)
		lines.append({"text": wl + "\n(each soldier you train takes one)"})
		key += ":" + wl
	if sec.unsettled > 0.0:
		lines.append({"text": "Unsettled: %d s" % int(ceil(sec.unsettled))})
		key += ":u%d" % int(ceil(sec.unsettled))
	var hall_st := world.defense.hall_structure(sec)
	if hall_st != null:
		lines.append({"text": "Hall strength %d / %d" % [ceili(hall_st.hp), int(hall_st.max_hp)]})
		lines.append({"text": "A capital cannot be taken. If it falls, %s lost." % ("you have" if sec.owner == PLAYER else "they have")})
		key += ":hp%d" % ceili(hall_st.hp / 50.0)
	if sec.capture > 0.0 and sec.capturer >= 0:
		lines.append({"text": "Being taken: %d%%" % int(sec.capture * 100.0)})
		key += ":c%d" % int(sec.capture * 20.0)
	if sec.owner == PLAYER:
		if sec.growing > 0.0:
			lines.append({"text": "Growing: %d s" % int(ceil(sec.growing))})
			key += ":g%d" % int(ceil(sec.growing))
		elif st["next"] != "" and sec.size != "waystone":
			var cost := eco.settlement_upgrade_cost(sec)
			var sid := sec.id
			lines.append({"text": "Grow into %s (%s)" % [eco.e["settlements"][st["next"]]["name"], _cost_text(cost)],
				"enabled": pl.can_pay(cost), "action": func() -> void:
					if not act({"t": "grow", "sector": sid}):
						_collect_notices_now()})
			key += ":n%s" % pl.can_pay(cost)
		if sec.home_of == PLAYER:
			if pl.hall_upgrading > 0.0:
				lines.append({"text": "Hall rising: %d s" % int(ceil(pl.hall_upgrading))})
				key += ":h%d" % int(ceil(pl.hall_upgrading))
			elif pl.hall_level < eco.e["hall_levels"].size():
				var hc := eco.hall_upgrade_cost(PLAYER)
				var next_tier := int(eco.e["hall_levels"][pl.hall_level]["max_tier"])
				var limit := " (this chapter's limit)" if eco.capped(next_tier) else ""
				if eco.tier_cap > 0:
					next_tier = mini(next_tier, eco.tier_cap)
				lines.append({"text": "Raise hall to %s, tiers up to %d%s (%s)" % [ROMAN[pl.hall_level],
					next_tier, limit, _cost_text(hc)],
					"enabled": pl.can_pay(hc), "action": func() -> void:
						if not act({"t": "hall"}):
							_collect_notices_now()})
				key += ":hc%s" % pl.can_pay(hc)
	build_panel.show_entries(key, st["name"], lines)


## Picking a building closes the build menu; B opens it again for the next one.
func _start_placing(kind: String, tier: int, special: String = "") -> void:
	_placing = {"kind": kind, "tier": tier, "special": special}
	_build_menu_open = false


## The build menu as a ring of building sprites (BuildRing, src/menu).
func _panel_build_menu(eco: Economy, pl: PlayerState) -> void:
	build_panel.hide_panel()
	var units := world.catalog.faction_units(pl.faction)
	var keys: Dictionary = eco.e["buildings"][pl.faction]
	var names: Dictionary = world.catalog.building_names
	var options: Array = []
	var key := "ring%d:%s" % [pl.hall_level, pl.faction]
	for t: int in eco.slot_heads():
		var has := eco.dwelling_of(PLAYER, t) != null
		var slot := eco.slot_tiers(t)
		var cost := eco.dwelling_cost(t)
		var locked := t > eco.max_tier(PLAYER)
		var ok := not has and not locked and pl.can_pay(cost)
		var tier := t
		var ud: Dictionary = world.catalog.get_unit(units[t - 1])
		var bkey: String = keys["dwellings"][t - 1]
		var status := "Built" if has else ("Locked in this chapter" if eco.capped(t) \
				else ("Needs hall %s" % ROMAN[(t - 1) / 2] if locked else ""))
		options.append({"id": bkey, "sprite": "res://assets/buildings/%s.png" % bkey,
			"name": String(names.get(bkey, "%s dwelling" % ud["name"])), "cost": cost,
			"enabled": ok, "status": status,
			"tooltip": "%s (%s)\nTrains %s. Each unit drafts one worker.\nCost: %s%s" % [
				names.get(bkey, bkey), ("tier %d" % t) if slot.size() == 1 else "tiers %d-%d" % [slot[0], slot[-1]],
				" and ".join(slot.map(func(x: int) -> String: return "%s (%s)" % [world.catalog.get_unit(units[x - 1])["name"],
					String(world.catalog.get_unit(units[x - 1]).get("role", ""))])), _cost_text(cost),
				"\nThis chapter allows tiers up to %d." % eco.tier_cap if eco.capped(t) else ""],
			"action": func() -> void: _start_placing("dwelling", tier)})
		key += ":%s%s" % [ok, has]
	for d: Dictionary in eco.special_defs(pl.faction):
		var sid: String = d["id"]
		var why := eco.special_lock_text(PLAYER, sid)
		var dc: Dictionary = d["cost"]
		var sok := why == "" and pl.can_pay(dc)
		options.append({"id": sid, "sprite": "res://assets/buildings/%s.png" % d["key"],
			"name": String(d["name"]), "cost": dc, "enabled": sok, "status": why,
			"tooltip": "%s (house building)\n%s\nNeeds hall %s; up to %d.\nCost: %s" % [d["name"], d["text"],
				ROMAN[int(d["hall"]) - 1], int(d["limit"]), _cost_text(dc)],
			"action": func() -> void: _start_placing("special", 0, sid)})
		key += ":%s%s" % [sok, why]
	var sc: Dictionary = eco.e["storehouse"]["cost"]
	var skey: String = keys["storehouse"]
	options.append({"id": skey, "sprite": "res://assets/buildings/%s.png" % skey,
		"name": String(names.get(skey, "Storehouse")), "cost": sc, "enabled": pl.can_pay(sc), "status": "",
		"tooltip": "%s (storehouse)\nWorkers drop gathered resources here: build it near far piles.\nSells worker upgrades: each resource gathered faster.\nCost: %s" % [
			names.get(skey, "Storehouse"), _cost_text(sc)],
		"action": func() -> void: _start_placing("storehouse", 0)})
	key += ":%s" % pl.can_pay(sc)
	var fc := world.forts.wall_cost(1)
	options.append({"id": "fort_wall", "sprite": "res://assets/ui/wall_icon.png", "name": "Wall", "cost": fc,
		"enabled": pl.can_pay(fc), "status": "",
		"tooltip": "Wall\nClick where it starts, then where it ends (Shift: keep going). Its ends reach rock, water or\nanother wall close by, so it can shut a pass or a bridge. Flyers cross it; ground foes must break it.\nA finished piece can become a gate or a tower.\nCost: %s per %d m" % [_cost_text(fc), int(world.forts.conf()["piece_cells"])],
		"action": func() -> void: _start_placing("wall", 0)})
	key += ":%s" % pl.can_pay(fc)
	build_ring.show_options(key, options, eco.e["resources"])


## The wall the player is laying out (from its first click to the mouse), or {}.
func wall_plan() -> Dictionary:
	if _placing.is_empty() or _placing["kind"] != "wall":
		return {}
	var m := _mouse_world()
	return world.forts.plan(PLAYER, _placing.get("start", m), m)


## True when wp is the ground point under the mouse (not a minimap click).
func _at_mouse(wp: Vector2) -> bool:
	return wp.distance_to(_mouse_world()) < 2.0


func _mouse_world() -> Vector2:
	if mode_3d:
		return view3d.screen_to_sim(get_viewport().get_mouse_position())
	return get_global_mouse_position()


## True when the human player may see this unit now.
func can_see(u: SimUnit) -> bool:
	return not fog_enabled or u.owner == PLAYER or world.vision.is_visible(PLAYER, u.pos)


## True when the player has ever seen this spot (enemy buildings stay shown there).
func has_explored(p: Vector2) -> bool:
	return not fog_enabled or world.vision.is_explored(PLAYER, p)


## The player's fog as a texture over the whole map (one texel per vision cell):
## black where unexplored (a grey veil in skirmish), half dark where explored, clear in sight.
func fog_texture() -> ImageTexture:
	var v := world.vision
	if v.width == 0:
		return null
	if _fog_img == null or _fog_img.get_width() != v.width or _fog_img.get_height() != v.height:
		_fog_img = Image.create(v.width, v.height, false, Image.FORMAT_RGBA8)
		_fog_tex = null
		_fog_tick = -1
	if _fog_tick != world.tick:
		_fog_tick = world.tick
		var cells := v.cells(PLAYER)
		var data := PackedByteArray()
		data.resize(cells.size() * 4)
		for i in cells.size():
			var a := 0 if not fog_enabled or cells[i] == Vision.VISIBLE else (140 if cells[i] == Vision.EXPLORED else 255)
			if a == 255 and fog_grey:
				# Never explored, in a skirmish: a grey veil (the 3D fog reads the red as "grey this").
				data[i * 4] = FOG_GREY.r8
				data[i * 4 + 1] = FOG_GREY.g8
				data[i * 4 + 2] = FOG_GREY.b8
				a = FOG_GREY.a8
			data[i * 4 + 3] = a
		_fog_img.set_data(v.width, v.height, false, Image.FORMAT_RGBA8, data)
		if _fog_tex == null:
			_fog_tex = ImageTexture.create_from_image(_fog_img)
		else:
			_fog_tex.update(_fog_img)
	return _fog_tex


## The unit drawn at wp. skip_workers: the player's own workers are not there (they
## can't be selected), so a click falls through to what is behind or under them.
func _unit_at(wp: Vector2, skip_workers: bool = false) -> SimUnit:
	if mode_3d and _at_mouse(wp):
		return view3d.unit_at_screen(get_viewport().get_mouse_position(), PLAYER if skip_workers else -1)
	var best: SimUnit = null
	var best_d := INF
	for u in world.units:
		if not can_see(u) or (skip_workers and u.owner == PLAYER and u.is_worker()):
			continue
		var p := _draw_pos(u)
		# The tactical map draws units as dots of a few screen pixels on their position.
		var k := 1.0 if mode_3d else sprite_k()
		var hit_r := maxf(u.radius() * 1.4 * k, 12.0)
		var center := p + Vector2(0, -u.radius() * 1.2 * k)
		var d := center.distance_to(wp)
		if d < hit_r and d < best_d:
			best_d = d
			best = u
	return best


func _click_select(wp: Vector2, shift: bool) -> void:
	var u := _unit_at(wp, true)
	if u == null or u.owner != PLAYER:
		if not shift:
			selection.clear()
			selected_building = -1
			selected_sector = -1
			var b := _building_at(wp)
			if b != null:
				selected_building = b.id
			else:
				for sec in world.economy.sectors:
					if sec.center.distance_to(wp) < (170.0 if mode_3d else maxf(70.0, 18.0 / cam.zoom.x)):
						selected_sector = sec.id
		return
	selected_building = -1
	selected_sector = -1
	var double := _time - _last_click_time < DOUBLE_TAP and _last_click_type == u.type_id
	_last_click_time = _time
	_last_click_type = u.type_id
	if double:
		var view := view_rect()
		if not shift:
			selection.clear()
		for o in world.units:
			if can_select(o, PLAYER) and o.type_id == u.type_id and view.has_point(o.pos) and not o.id in selection:
				selection.append(o.id)
	elif shift:
		if u.id in selection:
			selection.erase(u.id)
		else:
			selection.append(u.id)
	else:
		selection = [u.id]
	selection.sort()


## From the unit panel: keep only this type, or (shift) drop it.
func select_type(type_id: String, drop: bool) -> void:
	var keep: Array = []
	for id in selection:
		var u := world.get_unit(id)
		if u != null and ((u.type_id == type_id) != drop):
			keep.append(id)
	selection = keep
	audio.play("click", _time, 0.6)


func _box_select(shift: bool) -> void:
	if mode_3d:
		var sr := Rect2(_drag_start_screen, Vector2.ZERO).expand(get_viewport().get_mouse_position()).grow(6.0)
		if not shift:
			selection.clear()
		selected_building = -1
		selected_sector = -1
		for u in world.units:
			if can_select(u, PLAYER) and not u.id in selection and view3d.on_screen(u.pos) \
					and sr.has_point(view3d.sim_to_screen(u.pos, 0.8)):
				selection.append(u.id)
		selection.sort()
		return
	var a := _screen_to_world(_drag_start_screen)
	var b := _mouse_world()
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	if not shift:
		selection.clear()
	selected_building = -1
	selected_sector = -1
	for u in world.units:
		if can_select(u, PLAYER) and rect.grow(u.radius()).has_point(_draw_pos(u)) and not u.id in selection:
			selection.append(u.id)
	selection.sort()


func _screen_to_world(p: Vector2) -> Vector2:
	if mode_3d:
		return view3d.screen_to_sim(p)
	return get_canvas_transform().affine_inverse() * p


func view_rect() -> Rect2:
	if mode_3d:
		return view3d.view_rect()
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size)


# --- Drawing -------------------------------------------------------------------

func _alpha() -> float:
	return clampf(_acc / world.dt, 0.0, 1.0)


## How much larger the tactical map draws sprites: 1 up close, up to 2.4x when zoomed out
## to the whole map, so units, dwellings and towns stay readable.
func sprite_k() -> float:
	return clampf(0.45 / cam.zoom.x, 1.0, 2.4)


func _draw_pos(u: SimUnit) -> Vector2:
	return u.prev_pos.lerp(u.pos, _alpha())


## The flat view (the tactical map): the 2D sprites of the old F3 map, drawn larger when
## zoomed out so they stay readable, with TacticalMap's borders and resource rows on top.
func _draw_world() -> void:
	var size := world.nav.world_size()
	var view := view_rect().grow(96.0)
	layer.draw_texture_rect(_grass, Rect2(Vector2.ZERO, size), true)
	var cell := float(NavGrid.CELL)
	for c in _water_cells:
		var r := Rect2(Vector2(c) * cell, Vector2(cell, cell))
		if view.intersects(r):
			layer.draw_texture_rect_region(_water, r, Rect2(fposmod(r.position.x, 480.0), fposmod(r.position.y, 480.0), cell, cell))
	for c in _water_cells:
		_draw_shore(c)
	for c in _forest_cells:
		var fr := Rect2(Vector2(c) * cell, Vector2(cell, cell))
		if view.intersects(fr):
			layer.draw_rect(fr, Color(0.05, 0.1, 0.04, 0.85))
			layer.draw_circle(fr.get_center() + Vector2(float(c.x * 7 % 9) - 4.0, float(c.y * 5 % 9) - 4.0), cell * 0.55,
				Color(0.1, 0.17, 0.07))
	layer.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 4.0)
	_draw_sectors(view)
	for c in _corpses:
		if view.has_point(c["pos"]):
			_draw_corpse(c)
	LootMarks.draw_all(layer, world, func(q: Vector2) -> Variant: return q if view.has_point(q) else null, _time)
	SiteMarks.draw_all(layer, world, func(q: Vector2) -> Variant: return q if view.has_point(q) else null,
		has_explored, 1.0, _time)
	# Rocks and units share one depth order, so units walk behind boulders.
	var items: Array = []
	for r in _rocks:
		if view.has_point(r["pos"]):
			items.append([r["pos"].y, r])
	for u in world.units:
		if view.has_point(u.pos) and can_see(u):
			items.append([u.pos.y + (1000.0 if u.is_flying() else 0.0), u])
	for b in world.economy.buildings:
		if view.grow(120.0).has_point(b.pos) and (b.owner == PLAYER or has_explored(b.pos)):
			items.append([b.pos.y, b])
	for sec in world.economy.sectors:
		if view.grow(160.0).has_point(sec.center):
			items.append([sec.center.y, sec])
	for n in world.economy.nodes:
		if view.has_point(n.pos) and not n.depleted():
			items.append([n.pos.y, n])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if it[1] is SimUnit:
			_draw_unit(it[1])
		elif it[1] is Building:
			_draw_building(it[1])
		elif it[1] is Sector:
			_draw_settlement(it[1])
		elif it[1] is ResNode:
			_draw_node(it[1])
		else:
			_draw_rock(it[1])
	var fog := fog_texture()
	if fog != null and fog_enabled:
		layer.draw_texture_rect(fog, Rect2(Vector2.ZERO, world.nav.world_size()), false)
	tactical.draw_overlay(self, layer)  # sector borders and each sector's resources, over the fog
	if not _placing.is_empty():
		_draw_ghost()
	for p in world.projectiles:
		var t := world.get_unit(int(p["target"]))
		var to: Vector2 = (t.pos - p["pos"]).normalized() if t != null else Vector2.RIGHT
		var tip: Vector2 = p["pos"] + Vector2(0, -14)
		layer.draw_line(tip - to * 9.0, tip, Color(0.95, 0.9, 0.75), 1.5)
	for m in _markers:
		var k: float = m["t"] / 0.6
		layer.draw_arc(m["pos"], 6.0 + 14.0 * k, 0, TAU, 20, Color(m["color"], 1.0 - k), 2.0)
	for line: PackedVector2Array in queued_paths():
		for i in range(1, line.size()):
			layer.draw_dashed_line(line[i - 1], line[i], Color(SELECT_COLOR, 0.55), 1.5, 8.0)
			layer.draw_circle(line[i], 4.0, Color(SELECT_COLOR, 0.8))
	if _box_active:
		var a := _screen_to_world(_drag_start_screen)
		var rect := Rect2(a, Vector2.ZERO).expand(_mouse_world())
		layer.draw_rect(rect, Color(SELECT_COLOR, 0.12), true)
		layer.draw_rect(rect, SELECT_COLOR, false, 1.5 / cam.zoom.x)


func _tex_at(path: String) -> Texture2D:
	if not _art.has(path):
		_art[path] = load(path) if ResourceLoader.exists(path) else null
	return _art[path]


## Sector borders: edges between nav cells that belong to different sectors.
func _build_borders() -> void:
	_border_lines = PackedVector2Array()
	var nav := world.nav
	var eco := world.economy
	var owner_of := {}
	for y in nav.height:
		for x in nav.width:
			owner_of[Vector2i(x, y)] = eco.sector_at(nav.center_of(Vector2i(x, y))).id
	var cell := float(NavGrid.CELL)
	for y in nav.height:
		for x in nav.width:
			var c := Vector2i(x, y)
			if x + 1 < nav.width and owner_of[c] != owner_of[c + Vector2i.RIGHT]:
				_border_lines.append(Vector2(x + 1, y) * cell)
				_border_lines.append(Vector2(x + 1, y + 1) * cell)
			if y + 1 < nav.height and owner_of[c] != owner_of[c + Vector2i.DOWN]:
				_border_lines.append(Vector2(x, y + 1) * cell)
				_border_lines.append(Vector2(x + 1, y + 1) * cell)


func _draw_sectors(_view: Rect2) -> void:
	if _border_lines.size() > 1:
		layer.draw_multiline(_border_lines, Color(0.05, 0.03, 0.02, 0.55), 3.0 / cam.zoom.x)
	var eco := world.economy
	var cr := float(eco.e["capture_radius"])
	for sec in eco.sectors:
		var o := TacticalMap.known_owner(self, sec)
		var col := Color(0.8, 0.75, 0.55, 0.35) if o < 0 else Color(TEAM_COLORS[o], 0.55)
		_draw_ellipse(sec.center, cr, cr * 0.62, Color(col, col.a * 0.25), true)
		_draw_ellipse(sec.center, cr, cr * 0.62, col, false, 2.0 / cam.zoom.x)


## A settlement's sprite (its kind, or the faction's hall for a known capital) and its bars;
## the name and resources are TacticalMap's overlay, readable at any zoom.
func _draw_settlement(sec: Sector) -> void:
	var tex := _tex_at("res://assets/settlements/%s.png" % sec.size)
	var o := TacticalMap.known_owner(self, sec)
	if sec.home_of >= 0 and o >= 0 and o == sec.home_of:  # the capital shows the faction's main hall
		var hall := String(world.economy.e["buildings"][world.economy.player(o).faction]["hall"])
		tex = _tex_at("res://assets/buildings/%s.png" % hall)
	var p := sec.center
	var k := sprite_k()
	if tex != null:
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		layer.draw_texture_rect(tex, Rect2(p - Vector2(sz.x * 0.5, sz.y * 0.8), sz), false)
	var eco := world.economy
	if o < 0 and sec.owner != PLAYER and not has_explored(sec.center):
		return  # nothing is known about it yet
	var bk := 1.0 / cam.zoom.x  # bars stay a few screen pixels tall
	# Capture and growth bars.
	var bw := 50.0 * bk
	var bar := Rect2(p + Vector2(-bw * 0.5, -6.0 * bk), Vector2(bw, 4.0 * bk))
	var hall_st := world.defense.hall_structure(sec)
	if hall_st != null and (hall_st.hp < hall_st.max_hp or sec.id == selected_sector):
		layer.draw_rect(bar.grow(bk), Color(0, 0, 0, 0.85))
		layer.draw_rect(Rect2(bar.position, Vector2(bw * hall_st.hp_ratio(), bar.size.y)), hall_bar_color(sec.owner))
	elif sec.capture > 0.0 and sec.capturer >= 0:
		layer.draw_rect(bar, Color(0, 0, 0, 0.7))
		layer.draw_rect(Rect2(bar.position, Vector2(bw * sec.capture, bar.size.y)), TEAM_COLORS[sec.capturer])
	elif sec.unsettled > 0.0:
		var f := sec.unsettled / float(eco.e["unsettled_seconds"])
		layer.draw_rect(bar, Color(0, 0, 0, 0.7))
		layer.draw_rect(Rect2(bar.position, Vector2(bw * (1.0 - f), bar.size.y)), Color(0.85, 0.75, 0.4))
	elif sec.growing > 0.0:
		var f := sec.growing / float(eco.e["settlement_upgrade"]["seconds"])
		layer.draw_rect(bar, Color(0, 0, 0, 0.7))
		layer.draw_rect(Rect2(bar.position, Vector2(bw * (1.0 - f), bar.size.y)), Color(0.5, 0.85, 0.4))


func _draw_node(n: ResNode) -> void:
	var tex := _tex_at("res://assets/resources/%s.png" % n.resource)
	var usable := world.economy.uses(PLAYER, n.resource)
	var k := sprite_k()
	_draw_ellipse(n.pos, 24.0 * k, 9.0 * k, Color(0, 0, 0, 0.35), true)
	if tex != null:
		var s := 0.62 * k
		var mod := Color.WHITE if usable else Color(0.45, 0.45, 0.45, 0.75)
		layer.draw_texture_rect(tex, Rect2(n.pos - Vector2(48, 78) * s, Vector2(96, 96) * s), false, mod)
	_draw_pile_bar(n)


## A thin bar under a pile that has been worked: what is left of it.
func _draw_pile_bar(n: ResNode) -> void:
	if n.endless() or n.amount >= n.full or not has_explored(n.pos):
		return
	var bar := Rect2(n.pos + Vector2(-20, 14), Vector2(40, 4))
	layer.draw_rect(bar, Color(0, 0, 0, 0.7))
	var k := n.fraction()
	layer.draw_rect(Rect2(bar.position, Vector2(40 * k, 4)), Color(0.85, 0.75, 0.4) if k > 0.25 else Color(0.9, 0.4, 0.3))


func _draw_building(b: Building) -> void:
	if b.is_fort():
		var col := Color(0.32, 0.3, 0.28, 0.35 + 0.65 * b.progress)
		if b.kind == "gate":
			col = Color(0.35, 0.24, 0.14, 0.4 if b.gate_open else 1.0)
		for c: Vector2i in b.cells:
			layer.draw_rect(Rect2(Vector2(c) * NavGrid.CELL, Vector2(NavGrid.CELL, NavGrid.CELL)), col)
		var edge := SELECT_COLOR if b.id == selected_building else Color(TEAM_COLORS[b.owner], 0.9)
		if b.kind == "tower":
			layer.draw_circle(b.pos, 20.0, Color(0.25, 0.24, 0.23))
		layer.draw_arc(b.pos, b.radius, 0, TAU, 24, edge, 1.5)
		return
	var tex := _tex_at("res://assets/buildings/%s.png" % b.key)
	var p := b.pos
	var br := b.radius * sprite_k()
	_draw_ellipse(p, br * 1.1, br * 0.5, Color(0, 0, 0, 0.35), true)
	var sel := b.id == selected_building
	_draw_ellipse(p, br * 1.15, br * 0.55, SELECT_COLOR if sel else Color(TEAM_COLORS[b.owner], 0.8),
		false, (2.0 if sel else 1.5) / cam.zoom.x)
	if tex != null:
		var w := br * 2.6
		var s := w / float(tex.get_width())
		var h := tex.get_height() * s
		var mod := Color.WHITE if b.done() else Color(0.8, 0.75, 0.6, 0.35 + 0.5 * b.progress)
		layer.draw_texture_rect(tex, Rect2(p - Vector2(w * 0.5, h * 0.82), Vector2(w, h)), false, mod)
	if b.upgraded:
		_draw_ellipse(p, br * 1.3, br * 0.64, UPGRADE_COLOR, false, 2.0 / cam.zoom.x)  # a paid upgrade
	var bst := world.defense.building_structure(b)
	if bst != null and b.done() and (bst.hp < bst.max_hp or sel):
		var hb := Rect2(p + Vector2(-30, 4), Vector2(60, 5))  # its strength: it can be torn down
		layer.draw_rect(hb.grow(1.0), Color(0, 0, 0, 0.85))
		layer.draw_rect(Rect2(hb.position, Vector2(60 * bst.hp_ratio(), 5)), hall_bar_color(b.owner))
	if not b.done():
		var bar := Rect2(p + Vector2(-30, 12), Vector2(60, 5))
		layer.draw_rect(bar, Color(0, 0, 0, 0.7))
		layer.draw_rect(Rect2(bar.position, Vector2(60 * b.progress, 5)), Color(0.9, 0.75, 0.35))
	elif b.refit_left > 0.0:
		var bar := Rect2(p + Vector2(-30, 12), Vector2(60, 5))
		var k := 1.0 - b.refit_left / world.economy.dwelling_upgrade_seconds(b.refit_tier)
		layer.draw_rect(bar, Color(0, 0, 0, 0.7))
		layer.draw_rect(Rect2(bar.position, Vector2(60 * k, 5)), UPGRADE_COLOR)
	elif not b.queue.is_empty():
		var font := ThemeDB.fallback_font
		layer.draw_string(font, p + Vector2(-8, 18), "x%d" % b.queue.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 0.95, 0.8))
	if sel and (b.kind == "dwelling" or b.kind == "special"):
		layer.draw_dashed_line(p, b.rally, Color(0.95, 0.85, 0.4, 0.7), 2.0, 8.0)
		layer.draw_circle(b.rally, 4.0, Color(0.95, 0.85, 0.4))


func _draw_ghost() -> void:
	var eco := world.economy
	var wp := _mouse_world()
	var kind: String = _placing["kind"]
	if kind == "wall":
		var plan := wall_plan()
		var wcol := Color(0.4, 1.0, 0.4, 0.5) if plan["problem"] == "" else Color(1.0, 0.3, 0.25, 0.5)
		for c: Vector2i in plan["cells"]:
			layer.draw_rect(Rect2(Vector2(c) * NavGrid.CELL, Vector2(NavGrid.CELL, NavGrid.CELL)), wcol)
		return
	var radius := placing_radius()
	var ok := eco.can_place(PLAYER, wp, radius)
	var col := Color(0.4, 1.0, 0.4, 0.6) if ok else Color(1.0, 0.3, 0.25, 0.6)
	var key := placing_key()
	var tex := _tex_at("res://assets/buildings/%s.png" % key)
	if tex != null:
		var w := radius * 2.6
		var h := tex.get_height() * w / float(tex.get_width())
		layer.draw_texture_rect(tex, Rect2(wp - Vector2(w * 0.5, h * 0.82), Vector2(w, h)), false, Color(col, 0.55))
	_draw_ellipse(wp, radius * 1.15, radius * 0.55, col, false, 2.0)


## The art key of the building being placed.
func placing_key() -> String:
	var eco := world.economy
	var keys: Dictionary = eco.e["buildings"][eco.player(PLAYER).faction]
	match String(_placing.get("kind", "")):
		"dwelling":
			return keys["dwellings"][int(_placing["tier"]) - 1]
		"special":
			return String(eco.special_def(eco.player(PLAYER).faction, _placing["special"])["key"])
	return keys["storehouse"]


func placing_radius() -> float:
	var eco := world.economy
	return float(eco.e["storehouse"]["radius"]) if _placing.get("kind", "") == "storehouse" else float(eco.e["dwelling"]["radius"])


## Dark muddy edge where water meets land.
func _draw_shore(c: Vector2i) -> void:
	var cell := float(NavGrid.CELL)
	var o := Vector2(c) * cell
	var col := Color(0.12, 0.1, 0.06, 0.85)
	if world.nav.kind_at(c + Vector2i.UP) != NavGrid.Kind.WATER:
		layer.draw_rect(Rect2(o, Vector2(cell, 3)), col)
	if world.nav.kind_at(c + Vector2i.DOWN) != NavGrid.Kind.WATER:
		layer.draw_rect(Rect2(o + Vector2(0, cell - 3), Vector2(cell, 3)), col)
	if world.nav.kind_at(c + Vector2i.LEFT) != NavGrid.Kind.WATER:
		layer.draw_rect(Rect2(o, Vector2(3, cell)), col)
	if world.nav.kind_at(c + Vector2i.RIGHT) != NavGrid.Kind.WATER:
		layer.draw_rect(Rect2(o + Vector2(cell - 3, 0), Vector2(3, cell)), col)


func _draw_rock(r: Dictionary) -> void:
	var p: Vector2 = r["pos"]
	var sc: float = r["scale"]
	_draw_ellipse(p + Vector2(0, -2), 22.0 * sc, 9.0 * sc, Color(0.06, 0.05, 0.03, 0.45), true)
	layer.draw_set_transform(p, 0.0, Vector2(sc, sc))
	layer.draw_texture_rect_region(_boulders, Rect2(-24, -60, 48, 64), Rect2(int(r["variant"]) * 48, 0, 48, 64))
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color, filled: bool, width: float = 1.5) -> void:
	layer.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	if filled:
		layer.draw_circle(Vector2.ZERO, rx, col)
	else:
		layer.draw_arc(Vector2.ZERO, rx, 0, TAU, 24, col, width)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_unit(u: SimUnit) -> void:
	var p := _draw_pos(u)
	var r := u.radius() * sprite_k()
	var selected := u.id in selection
	_draw_ellipse(p, r * 1.1, r * 0.5, Color(0, 0, 0, 0.35), true)
	_draw_ellipse(p, r * 1.15, r * 0.55, SELECT_COLOR if selected else Color(TEAM_COLORS[u.owner], 0.85),
		false, (2.0 if selected else 1.5) / cam.zoom.x)
	var tex := _texture(u.type_id)
	var h := r * 3.6
	var s := h / 128.0
	var lift := 18.0 + sin(_time * 3.0 + u.id) * 2.0 if u.is_flying() else 0.0
	var lunge := u.facing * 4.0 if u.since_attack < 0.12 else 0.0
	var mod := Color.WHITE
	if u.since_hit < 0.1:
		mod = Color(1.6, 1.0, 1.0)
	layer.draw_set_transform(p + Vector2(lunge, -lift), 0.0, Vector2(s * u.facing, s))
	layer.draw_texture(tex, Vector2(-64, -127), mod)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if u.carry_amount > 0:
		var cc := {"wood": Color(0.55, 0.38, 0.2), "ore": Color(0.6, 0.6, 0.65), "gems": Color(0.4, 0.9, 0.6),
			"crystal": Color(0.75, 0.85, 1.0), "mercury": Color(0.85, 0.85, 0.9), "sulfur": Color(0.95, 0.85, 0.3)}
		layer.draw_circle(p + Vector2(r * 0.8, -h * 0.55), 4.0, cc.get(u.carry_type, Color.WHITE))
	if selected or u.hp < u.max_hp:
		var w := maxf(16.0, r * 2.0)
		var top := p + Vector2(-w * 0.5, -h - lift - 6.0)
		layer.draw_rect(Rect2(top, Vector2(w, 3)), Color(0, 0, 0, 0.7))
		var hc := Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - u.hp_ratio())
		layer.draw_rect(Rect2(top, Vector2(w * u.hp_ratio(), 3)), hc)


func _draw_corpse(c: Dictionary) -> void:
	var tex := _texture(c["type_id"])
	var r := float(world.catalog.get_unit(c["type_id"])["radius"]) * sprite_k()
	var s := r * 3.6 / 128.0
	var t: float = c["t"]
	var a := 1.0 if t < 4.0 else 1.0 - (t - 4.0) / 2.0
	var fall := minf(1.0, t / 0.3)
	var f: float = c["facing"]
	layer.draw_set_transform(c["pos"], -f * fall * PI * 0.5, Vector2(s * f, s))
	layer.draw_texture(tex, Vector2(-64, -127), Color(0.35, 0.3, 0.3, 0.8 * a))
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Menu (src/menu, owned by the menus thread) ------------------------------

func _build_pause_menu() -> void:
	build_ring = BuildRing.new()
	hud_top.get_parent().add_child(build_ring)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_requested.connect(close_pause_menu)
	pause_menu.restart_requested.connect(func() -> void:
		pause_menu.close()
		_start(seed_value))
	pause_menu.new_map_requested.connect(func() -> void:
		pause_menu.close()
		_start(seed_value + 1))
	pause_menu.main_menu_requested.connect(func() -> void:
		if online != null:
			online.leave()
			online = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))


## Esc / F10: pauses the battle under the menu; closing restores the pause state.
func open_pause_menu() -> void:
	if pause_menu.is_open():
		return
	_paused_before_menu = paused
	paused = online == null  # online the match goes on under the menu
	var rivals: Array = []
	for o in factions.size():
		if o != PLAYER:
			rivals.append(WbStyle.faction_name(factions[o]))
	pause_menu.open("pause", "%s against %s" % [WbStyle.faction_name(factions[PLAYER]), ", ".join(rivals)])


func close_pause_menu() -> void:
	pause_menu.close()
	paused = _paused_before_menu if _winner < 0 else paused


func _show_outcome() -> void:
	_paused_before_menu = paused
	if mission != null:
		var won_chapter := _winner == PLAYER
		if won_chapter:
			mission.harvest()
			mission.progress.save()
		campaign_hud.show_outro(won_chapter)
		return
	var won := _winner == PLAYER
	var detail := "Every enemy settlement is yours." if won else "Your last settlement has fallen."
	pause_menu.open("victory" if won else "defeat", detail)



# --- Hero ----------------------------------------------------------------------------

## Classes the player can pick for their faction (empty: this faction has no heroes yet).
func hero_classes() -> Array:
	return HeroCatalog.get_default().faction_classes(factions[PLAYER])


func pick_hero(class_id: String) -> void:
	if online != null:
		return  # online every hero is made at the start, the same on every computer
	var home := world.economy.hall_of(PLAYER)
	var u := world.heroes.spawn_hero(PLAYER, class_id, home.center + HeroSystem.HALL_SPAWN)
	selection = [u.id]
	audio.play("horn", _time, 0.7)


## A computer player's hero: a class of its faction, picked from the map seed.
func _spawn_ai_hero(s: int, owner: int = 1, computer: bool = true) -> void:
	var ids := HeroCatalog.get_default().faction_classes(factions[owner])
	if ids.is_empty():
		return
	var pick: String = ids[GameRng.new(s * 31 + 7 * owner).next_int(0, ids.size() - 1)]
	# The hero chosen in the skirmish setup, when there is one.
	if SkirmishSetup.current != null and ids.has(SkirmishSetup.current.hero_for(owner)):
		pick = SkirmishSetup.current.hero_for(owner)
	world.heroes.spawn_hero(owner, pick, world.economy.hall_of(owner).center + HeroSystem.HALL_SPAWN, computer)


func select_hero(jump: bool) -> void:
	var u := world.heroes.hero_unit(PLAYER)
	if u == null:
		return
	selection = [u.id]
	if jump:
		cam.position = u.pos
		_clamp_camera()


func casting_slot() -> int:
	return _casting


## Q W E R or a click on a skill: self skills fire at once; the others wait for a target
## click (quick: cast at the mouse right away).
func start_cast(slot: int, quick: bool) -> void:
	var h := world.heroes.hero_of(PLAYER)
	if h == null or slot < 0 or world.heroes.hero_unit(PLAYER) == null:
		return
	var problem := world.heroes.cast_problem(h, slot)
	if problem != "":
		_notice = {"not learned": "Learn that skill first (+)", "passive": "That skill is an aura: always on",
			"cooldown": "Not ready yet", "mana": "Not enough mana"}.get(problem, problem)
		_notice_time = _time
		audio.play("error", _time, 0.5)
		return
	var s := world.heroes.cat.skill(h.kit[slot])
	if s["target"] == "self":
		act({"t": "cast", "slot": slot, "target": -1, "point": Vector2.ZERO})
		return
	_casting = slot
	if quick:
		_finish_cast(_mouse_world())


func _finish_cast(wp: Vector2) -> void:
	var slot := _casting
	_casting = -1
	var h := world.heroes.hero_of(PLAYER)
	if h == null:
		return
	var s := world.heroes.cat.skill(h.kit[slot])
	var ok := false
	if s["target"] == "point":
		ok = act({"t": "cast", "slot": slot, "target": -1, "point": wp})
	else:
		var t := _unit_at(wp)
		ok = t != null and act({"t": "cast", "slot": slot, "target": t.id, "point": Vector2.ZERO})
	if ok:
		_markers.append({"pos": wp, "color": Color(0.6, 0.5, 1.0), "t": 0.0})
	else:
		audio.play("error", _time, 0.5)
