class_name CampaignScreen
extends Control
## The campaign screen, laid out like the main game's (CampaignJourneyScreen): a bar with Back,
## the campaign picker and Hero motion; the campaign's journey painting with a numbered stop per
## chapter (JourneyMap, the campaign's hero walking there as its 3D model); and a side panel with
## the selected chapter's picture, story and Play / Start over. The pictures are the main game's
## (tools/campaign/sync_campaign_art.py). Starting a chapter emits chapter_requested with a
## CampaignSetup for the battle scene.

signal back_requested
signal chapter_requested(setup: CampaignSetup)

const ART_DIR := "res://assets/campaign_art/"
const JOURNEYS := "res://data/campaigns/journeys.json"

var ids: Array = []
var picker: OptionButton
var motion: CheckButton
var journey: JourneyMap
var details: PanelContainer
var content: BoxContainer
var art: TextureRect
var title: Label
var state_label: Label
var description: Label
var hero_label: Label
var saved_label: Label
var play_button: Button
var restart: Button
var confirm_restart: ConfirmationDialog
var progress: CampaignProgress  ## the open campaign's saved progress (null: not started)
var campaign_id: String = ""

static var _journeys: Dictionary = {}


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("101116")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	column.add_child(bar)
	var back := Button.new()
	back.name = "Back"
	back.text = "‹ Back"
	back.custom_minimum_size = Vector2(90, 44)
	back.pressed.connect(func() -> void: back_requested.emit())
	bar.add_child(back)
	picker = OptionButton.new()
	picker.name = "CampaignPicker"
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 44
	var cc := CampaignCatalog.get_default()
	ids = cc.campaigns.keys()
	# Campaigns with a playable chapter first, then the rest in the order of the data.
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _has_playable(cc, a) and not _has_playable(cc, b))
	for id: String in ids:
		var c: Dictionary = cc.campaigns[id]
		var label := "%s · %s" % [c["name"], WbStyle.faction_name(String(c["faction"]))]
		picker.add_icon_item(WbStyle.small_icon(WbStyle.emblem_path(String(c["faction"]))), label)
	picker.item_selected.connect(func(i: int) -> void: open_campaign(ids[i]))
	bar.add_child(picker)
	motion = CheckButton.new()
	motion.text = "Hero motion"
	motion.button_pressed = true
	motion.tooltip_text = "Animate the hero walking to the next chapter"
	bar.add_child(motion)
	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	journey = JourneyMap.new()
	journey.name = "JourneyMap"
	journey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journey.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journey.custom_minimum_size = Vector2(220, 220)
	journey.stop_selected.connect(_show_stop)
	content.add_child(journey)
	motion.toggled.connect(func(on: bool) -> void: journey.animate_travel = on)
	details = PanelContainer.new()
	details.custom_minimum_size.x = 360
	details.add_theme_stylebox_override("panel", WbStyle.frame_panel("ashen", 4))
	content.add_child(details)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(inset)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 12)
	inset.add_child(info)
	art = TextureRect.new()
	art.name = "ChapterArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(0, 200)
	info.add_child(art)
	title = _text(info, 23, WbStyle.BRASS)
	title.add_theme_font_override("font", WbStyle.DISPLAY_FONT)
	state_label = _text(info, 15, WbStyle.BRASS)
	description = _text(info, 16, WbStyle.TEXT)
	hero_label = _text(info, 13, WbStyle.TEXT_DIM)
	saved_label = _text(info, 13, WbStyle.GOOD)
	play_button = Button.new()
	play_button.name = "Play"
	play_button.custom_minimum_size.y = 48
	play_button.pressed.connect(_play)
	info.add_child(play_button)
	restart = Button.new()
	restart.name = "StartOver"
	restart.text = "Start over"
	restart.custom_minimum_size.y = 44
	restart.pressed.connect(func() -> void: confirm_restart.popup_centered())
	info.add_child(restart)
	var legend := _text(info, 12, WbStyle.TEXT_DIM)
	legend.text = "Green: won · Gold: next · Grey: locked\nOdd chapters are hero chapters, even ones war chapters.\nSelect a stop to read its story."
	confirm_restart = ConfirmationDialog.new()
	confirm_restart.title = "Start over?"
	confirm_restart.dialog_text = "Erase this campaign's saved progress and begin at chapter 1?"
	confirm_restart.confirmed.connect(start_over)
	add_child(confirm_restart)
	resized.connect(_responsive_layout)
	visibility_changed.connect(func() -> void:
		if visible:
			open_campaign(campaign_id if campaign_id != "" else String(ids[0])))
	_responsive_layout()


func _text(parent: Node, font_size: int, color: Color) -> Label:
	var l := WbStyle.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _responsive_layout() -> void:
	if content == null:
		return
	var narrow := size.x > 0 and size.x < 900
	content.vertical = narrow
	details.custom_minimum_size = Vector2(0, 260) if narrow else Vector2(360, 0)


static func _has_playable(cc: CampaignCatalog, id: String) -> bool:
	for c: Dictionary in cc.chapters(id):
		if cc.playable(c):
			return true
	return false


## The journey stops and lead hero class of a campaign (from the main game).
static func journey_info(id: String) -> Dictionary:
	if _journeys.is_empty() and FileAccess.file_exists(JOURNEYS):
		_journeys = JSON.parse_string(FileAccess.get_file_as_string(JOURNEYS)).get("campaigns", {})
	return _journeys.get(id, {})


## The main game's picture for a chapter (or, with chapter "", the campaign's journey
## painting), or null.
static func picture(campaign: String, chapter: String = "") -> Texture2D:
	var path := ART_DIR + ("journeys/%s.webp" % campaign if chapter == "" else "%s/%s.webp" % [campaign, chapter])
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The hero class that walks the journey map: the campaign's own hero, else the main game's
## lead hero for it.
static func hero_class_of(id: String) -> String:
	var hero: Dictionary = CampaignCatalog.get_default().campaigns[id].get("hero", {})
	return String(hero.get("class", journey_info(id).get("lead_class", "")))


## Shows one campaign's journey with its saved progress.
func open_campaign(id: String) -> void:
	campaign_id = id
	if picker.selected != ids.find(id):
		picker.select(ids.find(id))
	progress = CampaignProgress.load_saved(id)
	var cc := CampaignCatalog.get_default()
	var chapters := cc.chapters(id)
	var stops: Array = journey_info(id).get("nodes", [])
	if stops.size() != chapters.size():
		stops = []
		for i in chapters.size():
			stops.append({"chapter": chapters[i]["id"], "layer": "surface",
				"at": [0.15 + 0.7 * i / maxf(1.0, chapters.size() - 1), 0.5]})
	var at := 0
	var states: Array = []
	for i in chapters.size():
		var won: bool = progress != null and progress.done.has(chapters[i]["id"])
		states.append("done" if won else "locked")
		if won:
			at = mini(i + 1, chapters.size() - 1)
	if at < states.size() and states[at] != "done":
		states[at] = "current"
	var c: Dictionary = cc.campaigns[id]
	journey.configure(picture(id), stops, states, at, hero_class_of(id),
		WbStyle.accent(String(c["faction"])).lightened(0.25))
	restart.visible = progress != null
	var hero: Dictionary = c.get("hero", {})
	hero_label.text = ("Your hero: %s, %s" % [hero["name"], HeroCatalog.get_default().classes[hero["class"]]["name"]]) \
			if not hero.is_empty() else ""
	hero_label.visible = hero_label.text != ""
	saved_label.text = ""
	if progress != null:
		saved_label.text = "Saved: level %d, %d %s, %d chapter%s won" % [progress.story.level, progress.marks,
			String(HeroCatalog.get_default().rules["coin"]["name"]), progress.done.size(), "" if progress.done.size() == 1 else "s"]
	saved_label.visible = saved_label.text != ""
	_show_stop(journey.selected)


func _show_stop(index: int) -> void:
	var cc := CampaignCatalog.get_default()
	var chapters := cc.chapters(campaign_id)
	if index < 0 or index >= chapters.size():
		return
	var ch: Dictionary = chapters[index]
	var state: String = journey.states[index]
	art.texture = picture(campaign_id, String(ch["id"]))
	art.visible = art.texture != null
	title.text = String(ch["title"])
	var kind := "Hero chapter" if ch["kind"] == "hero" else "War chapter"
	var status: String = {"done": "Won", "current": "Next", "locked": "Locked: win the chapters before it"}[state]
	if not cc.playable(ch):
		status += " · being written"
	state_label.text = "Chapter %d of %d · %s\n%s" % [index + 1, chapters.size(), kind, status]
	description.text = String(ch.get("text", ""))
	var finished := progress != null and progress.done.size() >= chapters.size()
	play_button.disabled = state != "current" or not cc.playable(ch) or finished
	play_button.tooltip_text = ""
	if finished:
		play_button.text = "Campaign complete"
	elif state == "done":
		play_button.text = "Chapter won"
	elif state == "locked":
		play_button.text = "Locked"
	elif not cc.playable(ch):
		play_button.text = "Being written"
		play_button.tooltip_text = "This chapter is still being written."
	elif progress == null:
		play_button.text = "Begin campaign"
	else:
		play_button.text = "Play chapter %d" % (index + 1)


func start_over() -> void:
	CampaignProgress.erase_saved(campaign_id)
	open_campaign(campaign_id)


func _play() -> void:
	var cc := CampaignCatalog.get_default()
	var p := progress if progress != null else cc.start(campaign_id)
	var nxt := cc.next_chapter(p)
	if nxt.is_empty():
		return
	chapter_requested.emit(CampaignSetup.make(p, String(nxt["id"])))
