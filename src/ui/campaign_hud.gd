class_name CampaignHud
extends Control
## The campaign layer of the battle screen: the quest log (top left), the dialogue panel
## (bottom centre; 1-4 pick an answer), the chapter's intro and outro cards, and the skill
## tree screen (K). It reads the StoryMission and changes it only through its command_*
## methods. While a card, a conversation or the trees are open the battle waits (blocking()).

signal outro_closed(won: bool)

var skirmish: Node
var quest_box: PanelContainer
var quest_list: VBoxContainer
var dialogue_box: PanelContainer
var speaker: Label
var line: Label
var answers: VBoxContainer
var card: PanelContainer
var card_title: Label
var card_text: VBoxContainer
var card_art: TextureRect
var card_buttons: HBoxContainer
var trees: SkillTreePanel
var card_kind: String = ""  ## "intro", "outro" or "" when no card is open
var _quest_key: String = ""
var _dialogue_key: String = ""


func mission() -> StoryMission:
	return skirmish.mission if skirmish != null else null


func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Quest log.
	quest_box = PanelContainer.new()
	quest_box.name = "QuestLog"
	var qb := WbStyle.flat_box(Color(0.06, 0.05, 0.04, 0.72), WbStyle.BRASS.darkened(0.4), 1)
	qb.set_content_margin_all(10)
	quest_box.add_theme_stylebox_override("panel", qb)
	quest_box.position = Vector2(12, 44)
	quest_box.custom_minimum_size = Vector2(330, 0)
	quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quest_box)
	quest_list = VBoxContainer.new()
	quest_list.add_theme_constant_override("separation", 3)
	quest_box.add_child(quest_list)
	# Dialogue.
	dialogue_box = PanelContainer.new()
	dialogue_box.name = "Dialogue"
	dialogue_box.add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 16))
	dialogue_box.anchor_left = 0.5
	dialogue_box.anchor_right = 0.5
	dialogue_box.anchor_top = 1.0
	dialogue_box.anchor_bottom = 1.0
	dialogue_box.offset_left = -390
	dialogue_box.offset_right = 390
	dialogue_box.offset_bottom = -252
	dialogue_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_box.visible = false
	add_child(dialogue_box)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dialogue_box.add_child(dv)
	speaker = WbStyle.heading("", 20)
	dv.add_child(speaker)
	line = WbStyle.label("", 16)
	line.add_theme_font_override("font", WbStyle.BODY_FONT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 740
	dv.add_child(line)
	answers = VBoxContainer.new()
	answers.add_theme_constant_override("separation", 4)
	dv.add_child(answers)
	# Intro / outro card.
	card = PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 26))
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.visible = false
	add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	card.add_child(cv)
	card_title = WbStyle.heading("", 30)
	cv.add_child(card_title)
	# The chapter's picture (the main game's briefing art) beside the text, as in the main game.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	cv.add_child(row)
	card_art = TextureRect.new()
	card_art.name = "ChapterArt"
	card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_art.custom_minimum_size = Vector2(450, 300)
	card_art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_art.visible = false
	row.add_child(card_art)
	card_text = VBoxContainer.new()
	card_text.add_theme_constant_override("separation", 10)
	row.add_child(card_text)
	card_buttons = HBoxContainer.new()
	card_buttons.alignment = BoxContainer.ALIGNMENT_END
	card_buttons.add_theme_constant_override("separation", 10)
	cv.add_child(card_buttons)
	# Skill trees.
	trees = SkillTreePanel.new()
	trees.name = "SkillTrees"
	trees.build()
	trees.set_anchors_preset(Control.PRESET_CENTER)
	trees.grow_horizontal = Control.GROW_DIRECTION_BOTH
	trees.grow_vertical = Control.GROW_DIRECTION_BOTH
	trees.visible = false
	add_child(trees)


## True while the battle should wait for the player.
func blocking() -> bool:
	var m := mission()
	return card.visible or trees.visible or (m != null and not m.dialogue.is_empty())


func _process(_delta: float) -> void:
	var m := mission()
	visible = m != null
	if m == null:
		return
	# Cards and the trees stay centred whatever their size.
	for c: Control in [card, trees]:
		if c.visible:
			c.position = ((size - c.size) * 0.5).floor()
	_sync_quests(m)
	_sync_dialogue(m)


# --- Quest log -------------------------------------------------------------------------------

func _sync_quests(m: StoryMission) -> void:
	var key := ""
	for q in m.quest_order:
		key += "%s:%s:%d;" % [q, m.quests[q]["state"], int(m.quests[q]["step"])]
	if key == _quest_key:
		return
	_quest_key = key
	for c in quest_list.get_children():
		quest_list.remove_child(c)
		c.queue_free()
	quest_list.add_child(WbStyle.heading("Quests", 17))
	var shown := 0
	for main_first in [true, false]:
		for q: String in m.quest_order:
			var qd: Dictionary = m.def["quests"][q]
			var st: Dictionary = m.quests[q]
			if (qd["kind"] == "main") != main_first or st["state"] != "active":
				continue
			var t := WbStyle.label(String(qd["title"]) + ("" if main_first else "  (side)"), 15,
				WbStyle.BRASS if main_first else WbStyle.TEXT)
			quest_list.add_child(t)
			var s := WbStyle.label("•  " + String(qd["steps"][int(st["step"])]["text"]), 13, WbStyle.TEXT_DIM)
			s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			s.custom_minimum_size.x = 310
			quest_list.add_child(s)
			shown += 1
	var finished := m.quest_order.filter(func(q: String) -> bool: return m.quests[q]["state"] in ["done", "failed"])
	if not finished.is_empty():
		quest_list.add_child(WbStyle.label("Done: " + ", ".join(finished.map(func(q: String) -> String:
			return String(m.def["quests"][q]["title"]) + (" (failed)" if m.quests[q]["state"] == "failed" else ""))), 12,
			WbStyle.TEXT_DIM.darkened(0.2)))
	quest_box.visible = shown > 0 or not finished.is_empty()
	quest_box.reset_size()


# --- Dialogue -------------------------------------------------------------------------------

func _sync_dialogue(m: StoryMission) -> void:
	var open := not m.dialogue.is_empty()
	dialogue_box.visible = open and not card.visible
	if not open:
		_dialogue_key = ""
		return
	var key := "%s/%s" % [m.dialogue["id"], m.dialogue["node"]]
	if key == _dialogue_key:
		return
	_dialogue_key = key
	speaker.text = m.speaker()
	line.text = String(m.current_node()["text"])
	for c in answers.get_children():
		answers.remove_child(c)
		c.queue_free()
	var n := 1
	for c: Dictionary in m.choices():
		var b := Button.new()
		b.name = "Answer%d" % n
		b.text = "%d.  %s" % [n, c["text"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", WbStyle.BODY_FONT)
		b.add_theme_font_size_override("font_size", 15)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(choose.bind(int(c["index"])))
		answers.add_child(b)
		n += 1
	dialogue_box.reset_size()


func choose(index: int) -> void:
	var m := mission()
	if m != null and m.command_choose(index):
		_dialogue_key = ""
		if skirmish != null:
			skirmish.audio.play("click", skirmish._time, 0.6)


## Keys 1-4 (and Space / Enter for a single answer) while a conversation is open.
func key(k: int) -> bool:
	var m := mission()
	if m == null:
		return false
	if k == KEY_K and not card.visible and m.dialogue.is_empty():
		toggle_trees()
		return true
	if card.visible:
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and card_buttons.get_child_count() > 0:
			(card_buttons.get_child(card_buttons.get_child_count() - 1) as Button).pressed.emit()
			return true
		return false
	if m.dialogue.is_empty():
		return false
	var cs := m.choices()
	var i := -1
	if k >= KEY_1 and k <= KEY_9:
		i = int(k - KEY_1)
	elif k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and cs.size() == 1:
		i = 0
	if i >= 0 and i < cs.size():
		choose(int(cs[i]["index"]))
		return true
	return k >= KEY_1 and k <= KEY_9  # keep the number keys away from unit groups while talking


func toggle_trees() -> void:
	if trees.visible:
		trees.hide()
	else:
		trees.open(mission())


# --- Cards ----------------------------------------------------------------------------------

func show_intro() -> void:
	var m := mission()
	var ch: Dictionary = CampaignSetup.current.chapter_def() if CampaignSetup.current != null else {}
	var kind := "Hero chapter" if m.def.get("kind", "hero") == "hero" else "War chapter"
	_open_card("intro", String(m.def["title"]), [kind] + Array(m.def.get("intro", [])), [["Begin", func() -> void:
		card.hide()
		card_kind = ""]])
	if not ch.is_empty():
		card_title.text = "%s" % ch.get("title", m.def["title"])


func show_outro(won: bool) -> void:
	var m := mission()
	if won:
		_open_card("outro", "Chapter won", m.outro(), [["Continue", func() -> void: outro_closed.emit(true)]])
	else:
		_open_card("outro", "Chapter lost", [m.lose_text if m.lose_text != "" else "The chapter is lost."],
			[["Main menu", func() -> void: outro_closed.emit(false)], ["Try again", func() -> void:
				card.hide()
				card_kind = ""
				skirmish._start(skirmish.seed_value)]])


func _open_card(kind: String, title: String, paragraphs: Array, buttons: Array) -> void:
	card_kind = kind
	card_title.text = title
	var setup := CampaignSetup.current
	card_art.texture = CampaignScreen.picture(setup.campaign, setup.chapter) if setup != null else null
	card_art.visible = card_art.texture != null
	var text_w := 520.0 if card_art.visible else 700.0
	for c in card_text.get_children():
		card_text.remove_child(c)
		c.queue_free()
	var first := true
	for p in paragraphs:
		var l := WbStyle.label(String(p), 16 if not (first and kind == "intro") else 14,
			WbStyle.TEXT if not (first and kind == "intro") else WbStyle.TEXT_DIM)
		l.add_theme_font_override("font", WbStyle.BODY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = text_w
		card_text.add_child(l)
		first = false
	for c in card_buttons.get_children():
		card_buttons.remove_child(c)
		c.queue_free()
	for b: Array in buttons:
		card_buttons.add_child(WbStyle.menu_button(String(b[0]), b[1], 200))
	card.show()
	card.reset_size()


# --- Events -----------------------------------------------------------------------------------

## The mission's news as a notice line for the battle HUD ("" = nothing to say).
static func notice_for(e: Dictionary) -> String:
	match String(e["type"]):
		"quest_start":
			return "New quest: %s" % e["title"]
		"quest_step":
			return "%s: %s" % [e["title"], e["text"]]
		"quest_done":
			return "Quest done: %s" % e["title"]
		"quest_failed":
			return "Quest failed: %s" % e["title"]
		"say":
			return "%s: \"%s\"" % [e["who"], e["text"]]
		"tier_cap":
			return "This chapter: halls train tiers 1 to %d" % int(e["tier"])
		"level":
			return "Level %d! Skill point to spend (K)" % int(e["level"])
		"xp":
			return "+%d experience" % int(e["amount"])
		"marks":
			return "%+d %s" % [int(e["amount"]), _coin()]
		"res":
			var parts: Array = []
			for r: String in e["res"]:
				parts.append("%+d %s" % [int(e["res"][r]), r])
			return ", ".join(parts)
		"item":
			return "Reward: %s (at your feet)" % e["name"]
		"potion":
			return "+%d %s potion%s" % [int(e["n"]), e["kind"], "" if int(e["n"]) == 1 else "s"]
		"join":
			return "%s joins you" % e["name"]
		"rise":
			return "%s gets back up" % e["name"]
		"checkpoint":
			return "Checkpoint: you will wake here if you fall"
		"hero_down":
			return "You have fallen: you wake at the last shrine (-%d %s)" % [int(e["marks"]), _coin()]
	return ""


static func _coin() -> String:
	return String(HeroCatalog.get_default().rules["coin"]["name"])
