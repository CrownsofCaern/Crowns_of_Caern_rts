class_name SkirmishSetupScreen
extends PanelContainer
## The skirmish setup, laid out like the main game's New Game panel: the map
## (preview, player count, victory, seed) on top, then one row per player
## (control, house, hero, computer level), and a card for your hero with its
## portrait and skills. Begin emits the finished SkirmishSetup.

signal begin_requested(setup: SkirmishSetup)
signal back_requested

var setup := SkirmishSetup.new()
var players_pick: OptionButton
var map_pick: OptionButton
var victory_pick: OptionButton
var seed_edit: LineEdit
var preview: MapPreview
var map_info: Label
var slots_grid: GridContainer
var hero_card: HBoxContainer
## The form between the heading and the buttons; it scrolls when the window is too short
## for it (four players on a laptop screen), so Begin and Back always stay in view.
var scroll: ScrollContainer
## Space kept free above and below the panel, in px.
const SCREEN_MARGIN := 24.0
var rows: Array = []  ## per slot: {type, faction, hero, difficulty} OptionButtons (type null for you)
var _factions: Array = []
var _preview_timer: Timer
var _preview_seed: int = 1
## The computer player takes a difficulty (EconomyAi.new(owner, difficulty)).
var difficulty_supported: bool = true


func build(initial: SkirmishSetup = null) -> void:
	if initial != null:
		setup = initial.copy()
	setup.set_player_count(clampi(setup.slots.size(), 2, SkirmishSetup.max_players()))
	_factions = SkirmishSetup.playable_factions()
	add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 22))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 9)
	add_child(outer)
	outer.add_child(WbStyle.heading("Skirmish", 28))
	scroll = ScrollContainer.new()
	scroll.name = "FormScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 9)
	root.custom_minimum_size.x = 1020
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.minimum_size_changed.connect(fit_to_screen, CONNECT_DEFERRED)
	scroll.add_child(root)

	# --- Map -------------------------------------------------------------
	root.add_child(WbStyle.section("Battlefield"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	root.add_child(top)
	var frame := PanelContainer.new()
	var inset := WbStyle.flat_box(Color("#0f0c0a"), Color("#826c45"), 1)
	inset.set_content_margin_all(4)
	inset.shadow_size = 0
	frame.add_theme_stylebox_override("panel", inset)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(frame)
	preview = MapPreview.new()
	preview.custom_minimum_size = Vector2(270, 180)
	frame.add_child(preview)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 8)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(form)
	form.add_child(_caption("Map"))
	map_pick = OptionButton.new()
	map_pick.name = "MapPick"
	map_pick.tooltip_text = "The map layout. Random picks one from the seed."
	map_pick.item_selected.connect(func(i: int) -> void:
		setup.map = String(map_pick.get_item_metadata(i))
		_refresh_preview())
	form.add_child(map_pick)
	_fill_maps()
	form.add_child(_caption(""))
	map_info = WbStyle.label("", 14, WbStyle.TEXT)
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.custom_minimum_size.x = 420
	form.add_child(map_info)
	form.add_child(_caption("Players"))
	players_pick = OptionButton.new()
	for n in range(2, SkirmishSetup.max_players() + 1):
		players_pick.add_item("%d players" % n)
		players_pick.set_item_metadata(players_pick.item_count - 1, n)
	players_pick.select(setup.slots.size() - 2)
	players_pick.disabled = SkirmishSetup.max_players() <= 2
	players_pick.tooltip_text = "How many houses take the field." if not players_pick.disabled \
		else "One against one for now; maps for more players are coming."
	players_pick.item_selected.connect(func(i: int) -> void:
		setup.set_player_count(int(players_pick.get_item_metadata(i)))
		_fill_maps()
		_fill_slots()
		_queue_preview())
	form.add_child(players_pick)
	form.add_child(_caption("Victory"))
	victory_pick = OptionButton.new()
	for v: String in SkirmishSetup.VICTORY:
		victory_pick.add_item(String(SkirmishSetup.VICTORY_NAMES[v]))
		victory_pick.set_item_metadata(victory_pick.item_count - 1, v)
	victory_pick.tooltip_text = "Dominion (hold the centre) comes later."
	victory_pick.item_selected.connect(func(i: int) -> void: setup.victory = String(victory_pick.get_item_metadata(i)))
	form.add_child(victory_pick)
	form.add_child(_caption("Seed"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	form.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size.x = 140
	seed_edit.text = "" if setup.seed_value == 0 else str(setup.seed_value)
	seed_edit.text_changed.connect(func(_t: String) -> void: _queue_preview())
	seed_row.add_child(seed_edit)
	var reroll := Button.new()
	reroll.text = "New map"
	reroll.tooltip_text = "Roll a new seed: a new map layout."
	reroll.pressed.connect(func() -> void:
		_preview_seed = (_preview_seed * 48271 + 104729) % 999983 + 1
		seed_edit.text = str(_preview_seed)
		_refresh_preview())
	seed_row.add_child(reroll)
	var hint := WbStyle.label("Same seed and houses, same map.", 12, WbStyle.TEXT_DIM)
	seed_row.add_child(hint)

	# --- Players ---------------------------------------------------------
	root.add_child(WbStyle.section("Players"))
	slots_grid = GridContainer.new()
	slots_grid.columns = 5
	slots_grid.add_theme_constant_override("h_separation", 12)
	slots_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(slots_grid)

	# --- Your hero -------------------------------------------------------
	root.add_child(WbStyle.section("Your hero"))
	hero_card = HBoxContainer.new()
	hero_card.add_theme_constant_override("separation", 16)
	hero_card.custom_minimum_size.y = 104
	root.add_child(hero_card)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	outer.add_child(buttons)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(130, 42)
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)
	var begin := Button.new()
	begin.name = "Begin"
	begin.text = "Begin battle"
	begin.custom_minimum_size = Vector2(190, 42)
	begin.add_theme_font_size_override("font_size", 18)
	begin.pressed.connect(func() -> void: begin_requested.emit(current_setup()))
	buttons.add_child(begin)

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.3
	_preview_timer.timeout.connect(_refresh_preview)
	add_child(_preview_timer)
	_preview_seed = setup.seed_value if setup.seed_value > 0 else 1 + int(Time.get_ticks_usec() % 999983)
	_fill_slots()
	_refresh_preview()
	fit_to_screen()


func _ready() -> void:
	get_viewport().size_changed.connect(fit_to_screen)
	fit_to_screen()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		fit_to_screen.call_deferred()


## Gives the form its full height when the window has room, otherwise as much as fits
## (the rest scrolls, with a scroll bar for the mouse wheel or a drag).
func fit_to_screen() -> void:
	if is_inside_tree():
		fit_to_height(get_viewport_rect().size.y)


## Fits the panel into a window this many px tall.
func fit_to_height(window_h: float) -> void:
	if scroll == null or scroll.get_child_count() == 0:
		return
	var form: Control = scroll.get_child(0)
	var want := form.get_combined_minimum_size().y
	var others := get_combined_minimum_size().y - scroll.custom_minimum_size.y
	var room := window_h - SCREEN_MARGIN * 2.0 - others
	scroll.custom_minimum_size = Vector2(form.get_combined_minimum_size().x + (12.0 if want > room else 0.0),
		clampf(minf(want, room), 160.0, maxf(want, 160.0)))


## Templates for the current number of players, plus Random.
func _fill_maps() -> void:
	map_pick.clear()
	map_pick.add_item("Random map")
	map_pick.set_item_metadata(0, "random")
	for pair: Array in SkirmishScenario.templates(setup.active_slots().size()):
		map_pick.add_item(String(pair[1]))
		map_pick.set_item_metadata(map_pick.item_count - 1, String(pair[0]))
		map_pick.set_item_tooltip(map_pick.item_count - 1, MapGen.template_desc(String(pair[0])))
	if not _select_meta(map_pick, setup.map):
		setup.map = "random"
		map_pick.select(0)


# --- Player rows -------------------------------------------------------------

func _fill_slots() -> void:
	for c in slots_grid.get_children():
		slots_grid.remove_child(c)
		c.queue_free()
	rows.clear()
	for h: String in ["Player", "Control", "House", "Hero", "Computer level"]:
		var l := WbStyle.label(h, 13, WbStyle.TEXT_DIM)
		slots_grid.add_child(l)
	for i in setup.slots.size():
		var slot: Dictionary = setup.slots[i]
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 8)
		who.custom_minimum_size.x = 120
		var sw := ColorRect.new()
		sw.color = SkirmishSetup.PLAYER_COLORS[i]
		sw.custom_minimum_size = Vector2(16, 16)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(sw)
		who.add_child(WbStyle.label("%s" % SkirmishSetup.PLAYER_NAMES[i], 15))
		slots_grid.add_child(who)
		var row := {}
		if i == 0:
			var you := WbStyle.label("You", 15, WbStyle.BRASS)
			you.custom_minimum_size.x = 140
			slots_grid.add_child(you)
			row["type"] = null
		else:
			var tp := OptionButton.new()
			tp.custom_minimum_size.x = 140
			for t: String in ["computer", "closed"]:
				tp.add_item(String(SkirmishSetup.TYPE_NAMES[t]))
				tp.set_item_metadata(tp.item_count - 1, t)
			tp.select(1 if slot["type"] == "closed" else 0)
			# Two players are the minimum: the first computer cannot be closed.
			tp.disabled = i == 1
			tp.item_selected.connect(_on_type.bind(i))
			slots_grid.add_child(tp)
			row["type"] = tp
		var fp := OptionButton.new()
		fp.name = "House%d" % i
		fp.custom_minimum_size.x = 250
		for f: String in _factions:
			fp.add_icon_item(WbStyle.small_icon(WbStyle.emblem_path(f)), WbStyle.faction_name(f))
			fp.set_item_metadata(fp.item_count - 1, f)
			fp.set_item_tooltip(fp.item_count - 1, String(WbStyle.faction_info(f).get("roster", "")))
		fp.add_icon_item(WbStyle.small_icon("res://assets/ui/emblem.png"), "Random house")
		fp.set_item_metadata(fp.item_count - 1, "random")
		_select_meta(fp, String(slot["faction"]))
		fp.item_selected.connect(_on_faction.bind(i))
		slots_grid.add_child(fp)
		row["faction"] = fp
		var hp := OptionButton.new()
		hp.name = "Hero%d" % i
		hp.custom_minimum_size.x = 210
		hp.item_selected.connect(_on_hero.bind(i))
		slots_grid.add_child(hp)
		row["hero"] = hp
		var dp := OptionButton.new()
		dp.custom_minimum_size.x = 130
		for d: String in SkirmishSetup.DIFFICULTIES:
			dp.add_item(String(SkirmishSetup.DIFFICULTY_NAMES[d]))
			dp.set_item_metadata(dp.item_count - 1, d)
		_select_meta(dp, String(slot["difficulty"]))
		dp.disabled = i == 0 or not difficulty_supported
		dp.tooltip_text = "How hard this computer plays." if i > 0 else ""
		dp.modulate.a = 0.0 if i == 0 else 1.0
		dp.item_selected.connect(func(k: int) -> void: setup.slots[i]["difficulty"] = String(dp.get_item_metadata(k)))
		slots_grid.add_child(dp)
		row["difficulty"] = dp
		rows.append(row)
		_fill_heroes(i)
		_dim_closed(i)
	_refresh_hero_card()


func _fill_heroes(i: int) -> void:
	var hp: OptionButton = rows[i]["hero"]
	hp.clear()
	var faction := String(setup.slots[i]["faction"])
	var cat := HeroCatalog.get_default()
	var classes := SkirmishSetup.hero_classes(faction)
	hp.add_icon_item(WbStyle.small_icon("res://assets/ui/emblem.png"), "Random hero")
	hp.set_item_metadata(0, "random")
	hp.set_item_tooltip(0, "A hero of this house picked at random.")
	for c: String in classes:
		var cls: Dictionary = cat.classes[c]
		hp.add_icon_item(WbStyle.small_icon(WbStyle.hero_portrait_path(c)), String(cls["name"]))
		hp.set_item_metadata(hp.item_count - 1, c)
		hp.set_item_tooltip(hp.item_count - 1, _hero_tooltip(c))
	if classes.is_empty() and faction != "random":
		hp.set_item_text(0, "No heroes yet")
		hp.disabled = true
	else:
		hp.disabled = false
	if not _select_meta(hp, String(setup.slots[i]["hero"])):
		hp.select(0)
		setup.slots[i]["hero"] = "random"


func _on_type(k: int, i: int) -> void:
	setup.slots[i]["type"] = String((rows[i]["type"] as OptionButton).get_item_metadata(k))
	_dim_closed(i)
	_fill_maps()
	_queue_preview()


func _on_faction(k: int, i: int) -> void:
	setup.slots[i]["faction"] = String((rows[i]["faction"] as OptionButton).get_item_metadata(k))
	setup.slots[i]["hero"] = "random"
	_fill_heroes(i)
	if i == 0:
		_refresh_hero_card()
	_queue_preview()


func _on_hero(k: int, i: int) -> void:
	setup.slots[i]["hero"] = String((rows[i]["hero"] as OptionButton).get_item_metadata(k))
	if i == 0:
		_refresh_hero_card()


func _dim_closed(i: int) -> void:
	var closed: bool = setup.slots[i]["type"] == "closed"
	for k: String in ["faction", "hero", "difficulty"]:
		var c: Control = rows[i][k]
		if i > 0:
			c.modulate.a = 0.35 if closed else 1.0
			(c as OptionButton).disabled = closed or (k == "difficulty" and not difficulty_supported) \
				or (k == "hero" and SkirmishSetup.hero_classes(String(setup.slots[i]["faction"])).is_empty()
					and setup.slots[i]["faction"] != "random")


static func _select_meta(ob: OptionButton, value: String) -> bool:
	for k in ob.item_count:
		if String(ob.get_item_metadata(k)) == value:
			ob.select(k)
			return true
	return false


# --- Hero card -----------------------------------------------------------------

func _refresh_hero_card() -> void:
	for c in hero_card.get_children():
		hero_card.remove_child(c)
		c.queue_free()
	var faction := String(setup.slots[0]["faction"])
	var hero := String(setup.slots[0]["hero"])
	var cat := HeroCatalog.get_default()
	var portrait_path := "res://assets/ui/emblem.png"
	if hero != "random" and cat.classes.has(hero):
		portrait_path = WbStyle.hero_portrait_path(hero)
	elif faction != "random":
		portrait_path = WbStyle.emblem_path(faction)
	var frame := PanelContainer.new()
	var box := WbStyle.flat_box(Color("#0f0c0a"), WbStyle.accent(faction if faction != "random" else ""), 2)
	box.set_content_margin_all(3)
	box.shadow_size = 3
	frame.add_theme_stylebox_override("panel", box)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(WbStyle.icon(WbStyle.texture(portrait_path), Vector2(96, 96)))
	hero_card.add_child(frame)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_card.add_child(info)
	if hero == "random" or not cat.classes.has(hero):
		var classes := SkirmishSetup.hero_classes(faction) if faction != "random" else []
		info.add_child(WbStyle.heading("A hero chosen by fate" if faction == "random" or not classes.is_empty() else "No hero", 20))
		var text := "Pick a hero in the table above, or let the battle choose one." \
			if faction == "random" or not classes.is_empty() else "This house has no heroes yet; your army fights alone."
		var l := WbStyle.label(text, 14, WbStyle.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(l)
		return
	var cls: Dictionary = cat.classes[hero]
	var arch := String(cls.get("archetype", ""))
	var title := WbStyle.heading(String(cls["name"]), 20)
	info.add_child(title)
	var role := String(cat.archetypes.get(arch, {}).get("role", ""))
	info.add_child(WbStyle.label("%s%s · %s" % [arch.capitalize(), (" (%s)" % role) if role != "" else "",
		WbStyle.faction_name(String(cls["faction"]))], 13, WbStyle.TEXT_DIM))
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override("separation", 14)
	info.add_child(skills)
	var keys := ["Q", "W", "E", "R"]
	var kit: Array = cat.kit(hero)
	for k in kit.size():
		var sk := cat.skill(String(kit[k]))
		var chip := VBoxContainer.new()
		chip.add_theme_constant_override("separation", 0)
		chip.custom_minimum_size.x = 170
		chip.tooltip_text = "%s\n%s" % [sk.get("name", kit[k]), sk.get("text", "")]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_l := WbStyle.label("%s  %s%s" % [keys[k] if k < keys.size() else "", sk.get("name", kit[k]),
			"  (ultimate)" if k == kit.size() - 1 else ""], 14, WbStyle.BRASS.lightened(0.15))
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(name_l)
		var t := WbStyle.label(String(sk.get("text", "")), 12, WbStyle.TEXT_DIM)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 170
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(t)
		skills.add_child(chip)


func _hero_tooltip(class_id: String) -> String:
	var cat := HeroCatalog.get_default()
	var cls: Dictionary = cat.classes[class_id]
	var names: Array = []
	for s: String in cat.kit(class_id):
		names.append(String(cat.skill(s).get("name", s)))
	return "%s (%s)\nSkills: %s" % [cls["name"], String(cls.get("archetype", "")).capitalize(), ", ".join(names)]


# --- Result and preview -------------------------------------------------------

## Kept for older callers: difficulty is per computer row now.
func set_difficulty_supported(on: bool) -> void:
	difficulty_supported = on
	if not rows.is_empty():
		_fill_slots()


## The setup as chosen; the seed is the one shown in the preview when the field
## is empty, so the battle matches the picture.
func current_setup() -> SkirmishSetup:
	var s := setup.copy()
	s.seed_value = _typed_seed()
	if s.seed_value == 0:
		s.seed_value = _preview_seed
	return s


func _typed_seed() -> int:
	var t := seed_edit.text.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return absi(t.to_int()) % 2147483647
	return absi(t.hash()) % 2147483647


func _caption(text: String) -> Label:
	var l := WbStyle.label(text, 15, WbStyle.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return l


func _queue_preview() -> void:
	if _preview_timer != null and _preview_timer.is_inside_tree():
		_preview_timer.start()
	else:
		_refresh_preview()


## The map the battle will use (random houses preview as the first house).
func _refresh_preview() -> void:
	var typed := _typed_seed()
	var seed_value := typed if typed != 0 else _preview_seed
	var fs: Array = []
	for f: String in setup.factions():
		fs.append(f if _factions.has(f) else _factions[0])
	preview.show_map(seed_value, fs, setup.map_template())
	var counts := {}
	for s: Sector in preview.world().economy.sectors:
		if s.home_of < 0:
			var n := String(preview.world().economy.settlement(s).get("name", s.size))
			counts[n] = int(counts.get(n, 0)) + 1
	var parts: Array = []
	for n: String in counts:
		parts.append("%d %s" % [counts[n], n.to_lower() + ("s" if counts[n] > 1 else "")])
	var tid := String(preview.world().map_info.get("template", ""))
	var layout := "%s%s: %s" % ["Random: " if setup.map == "random" else "", MapGen.template_name(tid),
		MapGen.template_desc(tid)]
	if fs.size() == 3:
		layout += " The spare corner is a neutral town."
	map_info.text = "%s\nA town for each house; %s in between. Seed %d" % [layout, ", ".join(parts), seed_value]
