class_name HeroWindow
extends Control
## The hero window (I, or the bag button on the HUD; hidden by default): the painted portrait with
## level, class and faction, health, mana and experience, the attributes and combat stats, the 7
## worn slots around the hero, the bag, the potions and the skills.
## Click a bag item to wear it, click a worn item to take it off, right click a bag item to drop it,
## or drag items between the bag and the slots (drag out of the window to drop). Hover any item for
## its stats and what wearing it would change. The battle does not wait while it is open.
## Reads SimWorld state; changes it only through WorldCommands (the skirmish's act()).

signal closed

const W := 980.0
const H := 650.0
const CELL := 66.0
const DRAG_PX := 6.0
## Where each worn slot sits on the paper doll (centre, as a share of the doll area).
const DOLL := {"helm": Vector2(0.5, 0.13), "banner": Vector2(0.16, 0.13), "charm": Vector2(0.84, 0.13),
	"weapon": Vector2(0.16, 0.47), "armor": Vector2(0.5, 0.47), "shield": Vector2(0.84, 0.47),
	"boots": Vector2(0.5, 0.82)}

var skirmish: Node
var faction := "concord"
var _font: Font
var _title: Font
var _frame: StyleBox
var _worn_cells: Dictionary = {}  ## slot -> Rect2
var _bag_cells: Array[Rect2] = []
var _bag_area := Rect2()
var _potions: Dictionary = {}
var _skill_rows: Array[Rect2] = []
var _plus: Array[Rect2] = []
var _auto: Array[Rect2] = []
var _close := Rect2()
var _tree_button := Rect2()
var _press: Dictionary = {}  ## {kind: "bag"/"worn", key, at} while the left button is down on an item
var _dragging := false
var _hint := ""
var _hint_time := 0.0


func _ready() -> void:
	_font = WbStyle.BODY_FONT
	_title = WbStyle.DISPLAY_FONT
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	visible = false


func open() -> void:
	_frame = WbStyle.frame_panel(faction, 0)
	visible = true
	_hint = ""
	if get_parent() is Control or get_viewport() != null:
		position = ((get_viewport_rect().size - size) * 0.5).floor()


func close() -> void:
	visible = false
	_press = {}
	_dragging = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _process(delta: float) -> void:
	if not visible:
		return
	if _hint_time > 0.0:
		_hint_time -= delta
	position = ((get_viewport_rect().size - size) * 0.5).floor()
	queue_redraw()


func _world() -> SimWorld:
	return skirmish.world if skirmish != null else null


## A command for your own hero, through the skirmish (online it reaches every computer).
func _send(c: Dictionary) -> bool:
	var h := _hero()
	return h != null and OnlineGame.send_command(skirmish, _world(), h.owner, c)


func _hero() -> HeroState:
	var w := _world()
	return w.heroes.hero_of(Skirmish.PLAYER) if w != null else null


func _story() -> StoryHero:
	var m: StoryMission = skirmish.mission if skirmish != null and "mission" in skirmish else null
	return m.progress.story if m != null else null


# --- Drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	var w := _world()
	var h := _hero()
	if w == null or h == null:
		return
	var all := Rect2(Vector2.ZERO, size)
	draw_rect(all.grow(10.0), Color(0, 0, 0, 0.35))
	if _frame != null:
		draw_style_box(_frame, all)
	else:
		draw_rect(all, Color("#1d1813"))
		draw_rect(all, HudArt.BRASS, false, 2.0)
	var inner := all.grow(-22.0)
	draw_rect(inner, Color(0.04, 0.03, 0.025, 0.55))
	var hc := w.heroes.cat
	var c: Dictionary = hc.classes[h.class_id]
	var u := w.heroes.hero_unit(h.owner)
	var st := _story()
	_draw_header(h, c, u, st)
	_draw_left(w, h, u, st)
	_draw_doll(w, h)
	_draw_right(w, h, st)
	if _hint_time > 0.0 and _hint != "":
		HudArt.text(self, _font, Vector2(40, H - 32), _hint, 13, HudArt.BAD)
	else:
		HudArt.text(self, _font, Vector2(40, H - 32),
			"Click: wear or take off  ·  Right click: drop  ·  Drag between bag and slots", 12, HudArt.TEXT_DIM)
	_draw_drag(w)
	_draw_tips(w, h)


func _draw_header(h: HeroState, c: Dictionary, u: SimUnit, st: StoryHero) -> void:
	var hname := String(c["name"])
	if u != null and u.label != "":
		hname = u.label
	elif st != null and "mission" in skirmish and skirmish.mission.progress.hero_name != "":
		hname = skirmish.mission.progress.hero_name
	var level := st.level if st != null else h.level
	HudArt.text(self, _title, Vector2(36, 54), hname, 28, Color("#e8c873"))
	var fac := WbStyle.faction_name(String(c["faction"]))
	HudArt.text(self, _font, Vector2(36, 76), "Level %d %s  ·  %s  ·  %s" % [level, c["name"], fac,
		String(c["archetype"]).capitalize()], 15, HudArt.TEXT_DIM)
	var crest := WbStyle.emblem(String(c["faction"]))
	if crest != null:
		draw_texture_rect(crest, Rect2(Vector2(W - 120, 24), Vector2(64, 64)), false)
	_close = Rect2(Vector2(W - 52, 30), Vector2(26, 26))
	var hot := _close.has_point(get_local_mouse_position())
	HudArt.bevel(self, _close, HudArt.BRASS if hot else HudArt.BRASS_DIM, Color("#2a1a14") if hot else Color("#17120e"))
	var cc := _close.get_center()
	draw_line(cc + Vector2(-6, -6), cc + Vector2(6, 6), Color("#eadfc4"), 2.0)
	draw_line(cc + Vector2(6, -6), cc + Vector2(-6, 6), Color("#eadfc4"), 2.0)
	# A brass rule under the header.
	var div := HudArt.tex("res://assets/ui/divider.png")
	if div != null:
		draw_texture_rect(div, Rect2(Vector2(32, 86), Vector2(W - 64, 10)), false)
	else:
		draw_line(Vector2(32, 91), Vector2(W - 32, 91), HudArt.BRASS_DIM, 1.0)


func _draw_left(w: SimWorld, h: HeroState, u: SimUnit, st: StoryHero) -> void:
	var x := 36.0
	var pr := Rect2(Vector2(x + 34, 118), Vector2(186, 186))
	HudArt.framed_portrait(self, pr, h.class_id, u == null, HudArt.BRASS)
	HudArt.badge(self, _title, pr.end - Vector2(6, 6), str(st.level if st != null else h.level), 17.0)
	if u == null:
		HudArt.text(self, _title, Vector2(pr.position.x, pr.get_center().y), "Fallen", 26, Color("#e8a090"),
			HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		HudArt.text(self, _font, Vector2(pr.position.x, pr.get_center().y + 24), "back in %d s" % ceili(h.respawn), 15,
			Color("#e8c0b0"), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
	var bw := 250.0
	var y := pr.end.y + 22.0
	var d := w.heroes.hero_def(h)
	var hp := u.hp if u != null else 0.0
	var max_hp := u.max_hp if u != null else float(d["hp"])
	HudArt.bar(self, Rect2(Vector2(x, y), Vector2(bw, 16)), hp / maxf(max_hp, 1.0), "health",
		"Health %d / %d" % [int(hp), int(max_hp)], _font, 11)
	HudArt.bar(self, Rect2(Vector2(x, y + 32), Vector2(bw, 16)), h.mana / maxf(h.max_mana, 1.0), "mana",
		"Mana %d / %d" % [int(h.mana), int(h.max_mana)], _font, 11)
	var hc := w.heroes.cat
	var xp := h.xp
	var next := hc.xp_to_next(h.level) if h.level < int(hc.rules["max_level"]) else 0
	if st != null:
		var trees := StoryTrees.get_default()
		xp = st.xp
		next = trees.xp_to_next(st.level) if st.level < int(trees.rules["max_level"]) else 0
	HudArt.bar(self, Rect2(Vector2(x, y + 62), Vector2(bw, 12)), float(xp) / float(next) if next > 0 else 1.0, "xp",
		("Experience %d / %d" % [xp, next]) if next > 0 else "Highest level", _font, 10)
	# Attributes (with the main game's icons) and the combat stats.
	y += 90.0
	var a: Dictionary = h.attributes
	var rows := [
		["attack", "Attack", "%d" % roundi(float(a.get("attack", 0))), "Raises the hero's damage."],
		["defense", "Defense", "%d" % roundi(float(a.get("defense", 0))), "Raises armour and health."],
		["power", "Power", "%d" % roundi(float(a.get("power", 0))), "Skills hit and heal %d%% harder." % roundi((h.power_factor - 1.0) * 100.0)],
		["knowledge", "Knowledge", "%d" % roundi(float(a.get("knowledge", 0))), "More mana and faster mana."],
		["damage", "Damage", "%d" % roundi(float(d["damage"])), "Every %.1f s, range %s." % [float(d["attack_interval"]), "melee" if float(d["range"]) < 50.0 else str(int(d["range"]))]],
		["armor", "Armour", "%d%%" % roundi(float(d["armor_pct"]) * 100.0), "Share of damage the hero shrugs off."],
		["move", "Speed", "%d" % roundi(float(d["speed"])), "Walking speed."],
		["mana_regen", "Mana / s", "%.1f" % h.mana_regen, "Mana regained each second."],
		["marks", String(hc.rules["coin"]["name"]), "%d" % h.marks, "The hero's own coin, for merchants."],
		["skill_pct", "Skills", "+%d%%" % roundi((h.power_factor - 1.0) * 100.0), "Skill strength from Power and gear."],
	]
	var mouse := get_local_mouse_position()
	for i in rows.size():
		var col := i % 2
		var row := i / 2
		var r := Rect2(Vector2(x + col * 128.0, y + row * 30.0), Vector2(122, 26))
		var row_data: Array = rows[i]
		draw_rect(r, Color(1, 1, 1, 0.035) if not r.has_point(mouse) else Color(1, 0.9, 0.6, 0.08))
		var icon := HudArt.ui_icon(row_data[0])
		if icon == null:
			icon = HudArt.stat_icon(row_data[0])
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position + Vector2(2, 1), Vector2(24, 24)), false)
		draw_string(_font, r.position + Vector2(30, 18), row_data[1], HORIZONTAL_ALIGNMENT_LEFT, 66, 12, HudArt.TEXT_DIM)
		HudArt.text(self, _title, r.position + Vector2(30, 18), row_data[2], 14, Color("#f0e2c0"),
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 34)
		if r.has_point(mouse):
			set_meta("stat_tip", [r, [row_data[1], row_data[3]]])


func _doll_area() -> Rect2:
	return Rect2(Vector2(318, 128), Vector2(330, 388))


func _draw_doll(w: SimWorld, h: HeroState) -> void:
	var area := _doll_area()
	HudArt.text(self, _title, area.position + Vector2(0, -8), "Equipment", 16, Color("#d8b866"))
	var bg := HudArt.piece("paper_doll")
	HudArt.bevel(self, area, HudArt.BRASS_DIM, Color("#0d0a08"))
	if bg != null:
		draw_texture_rect(bg, area.grow(-2.0), false)
	else:
		# Stand-in: a dim niche, the faction crest faint behind the slots, and slot-to-slot lines.
		draw_texture_rect(HudArt._radial(Color(0.22, 0.16, 0.1, 0.9), Color(0.03, 0.025, 0.02, 1.0)),
			area.grow(-2.0), false)
		var crest := WbStyle.emblem(faction)
		if crest != null:
			var s := area.size.x * 0.78
			draw_texture_rect(crest, Rect2(area.get_center() - Vector2(s, s) * 0.5 + Vector2(0, 10), Vector2(s, s)), false,
				Color(1, 1, 1, 0.1))
	var g := w.heroes.gear
	var mouse := get_local_mouse_position()
	_worn_cells.clear()
	for slot: String in ItemCatalog.SLOTS:
		var p := area.position + area.size * (DOLL[slot] as Vector2)
		var r := Rect2(p - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL))
		_worn_cells[slot] = r
	if bg == null:
		var links := [["helm", "armor"], ["armor", "boots"], ["weapon", "armor"], ["armor", "shield"],
			["banner", "weapon"], ["charm", "shield"]]
		for l: Array in links:
			draw_line((_worn_cells[l[0]] as Rect2).get_center(), (_worn_cells[l[1]] as Rect2).get_center(),
				Color(0.5, 0.4, 0.25, 0.25), 2.0)
	var dragged := _dragged_item(h)
	for slot: String in ItemCatalog.SLOTS:
		var r: Rect2 = _worn_cells[slot]
		var it: Dictionary = h.worn.get(slot, {})
		if _dragging and _press.get("kind", "") == "worn" and _press.get("key", "") == slot:
			it = {}
		HudArt.item_cell(self, r, it, g.icat, slot, r.has_point(mouse))
		if _dragging and not dragged.is_empty() and dragged.get("slot", "") == slot:
			draw_rect(r.grow(3.0), Color(0.6, 1.0, 0.5, 0.6 + 0.3 * sin(Time.get_ticks_msec() * 0.01)), false, 2.0)
		draw_string(_font, Vector2(r.position.x - 10, r.end.y + 14), slot.capitalize(), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x + 20, 11, HudArt.TEXT_DIM)
	# What the gear adds, under the doll.
	var parts: Array[String] = []
	var keys: Array = h.gear.keys()
	keys.sort_custom(func(a, b): return ItemCatalog.STATS.find(a) < ItemCatalog.STATS.find(b))
	for k in keys:
		if float(h.gear[k]) != 0.0 and k in ItemCatalog.STATS:
			parts.append(ItemCatalog.stat_line(k, float(h.gear[k])))
	var text := "Gear and skills add: " + (", ".join(parts) if not parts.is_empty() else "nothing yet")
	var lines := _wrap(text, area.size.x, 12)
	for i in mini(lines.size(), 3):
		draw_string(_font, Vector2(area.position.x, area.end.y + 20 + i * 15), lines[i], HORIZONTAL_ALIGNMENT_LEFT,
			area.size.x, 12, Color("#b9d9a0") if i > 0 or not parts.is_empty() else HudArt.TEXT_DIM)


func _draw_right(w: SimWorld, h: HeroState, st: StoryHero) -> void:
	var g := w.heroes.gear
	var x := 676.0
	var mouse := get_local_mouse_position()
	var n := int(g.ir["bag_size"])
	HudArt.text(self, _title, Vector2(x, 120), "Bag  %d / %d" % [h.bag.size(), n], 16, Color("#d8b866"))
	_bag_cells.clear()
	var cols := 4
	for j in n:
		var r := Rect2(Vector2(x + (j % cols) * (CELL + 4.0), 128 + (j / cols) * (CELL + 4.0)), Vector2(CELL, CELL))
		_bag_cells.append(r)
		var it: Dictionary = h.bag[j] if j < h.bag.size() else {}
		if _dragging and _press.get("kind", "") == "bag" and int(_press.get("key", -1)) == j:
			it = {}
		var usable := it.is_empty() or g.icat.can_wear(g.archetype(h), it)
		HudArt.item_cell(self, r, it, g.icat, "", r.has_point(mouse), usable)
	var rows := ceili(float(n) / cols)
	_bag_area = Rect2(Vector2(x - 4, 124), Vector2(cols * (CELL + 4.0) + 4.0, rows * (CELL + 4.0) + 4.0))
	if _dragging and _press.get("kind", "") == "worn" and _bag_area.has_point(mouse):
		draw_rect(_bag_area, Color(0.6, 1.0, 0.5, 0.5), false, 2.0)
	# Potions.
	var py := 128.0 + rows * (CELL + 4.0) + 10.0
	_potions.clear()
	var i := 0
	for kind in ["health", "mana"]:
		var r := Rect2(Vector2(x + i * 140.0, py), Vector2(46, 54))
		_potions[kind] = r
		var cnt := int(h.potions.get(kind, 0))
		HudArt.slot(self, r, HudArt.BRASS_DIM, Color(0.05, 0.04, 0.035))
		HudArt.potion(self, r.grow(-3.0), kind, cnt > 0)
		HudArt.badge(self, _title, r.end - Vector2(5, 5), str(cnt), 9.0, Color("#6b5a3a"))
		draw_string(_font, Vector2(r.end.x + 6, r.position.y + 24), "%s" % String(kind).capitalize(),
			HORIZONTAL_ALIGNMENT_LEFT, 80, 13, Color("#e0d4b8"))
		draw_string(_font, Vector2(r.end.x + 6, r.position.y + 40), "%d / %d" % [cnt, int(g.ir["potion_max"])],
			HORIZONTAL_ALIGNMENT_LEFT, 80, 12, HudArt.TEXT_DIM)
		i += 1
	# Skills.
	var sy := py + 88.0
	HudArt.text(self, _title, Vector2(x, sy), "Skills", 16, Color("#d8b866"))
	var hc := w.heroes.cat
	_skill_rows.clear()
	_plus.clear()
	_auto.clear()
	for k in 4:
		var r := Rect2(Vector2(x, sy + 10 + k * 50.0), Vector2(272, 46))
		_skill_rows.append(r)
		_plus.append(Rect2())
		_auto.append(Rect2())
		var sid: String = h.kit[k]
		draw_rect(r, Color(1, 1, 1, 0.035) if not r.has_point(mouse) else Color(1, 0.9, 0.6, 0.07))
		var ir := Rect2(r.position + Vector2(2, 2), Vector2(42, 42))
		if sid == "":
			HudArt.slot(self, ir, Color(0.3, 0.26, 0.2), Color(0.05, 0.04, 0.035))
			draw_string(_font, r.position + Vector2(54, 28), "%s  (empty)" % HudArt.KEYS[k], HORIZONTAL_ALIGNMENT_LEFT, -1,
				13, HudArt.TEXT_DIM)
			continue
		var s := hc.skill(sid)
		HudArt.skill_tile(self, ir, sid, "ready" if h.ranks[k] > 0 else "locked")
		HudArt.text(self, _title, ir.position + Vector2(3, 13), HudArt.KEYS[k], 11, Color("#f0e2c0"))
		draw_string(_title, r.position + Vector2(52, 19), String(s["name"]), HORIZONTAL_ALIGNMENT_LEFT, 170, 14,
			Color("#efe0bc") if h.ranks[k] > 0 else HudArt.TEXT_DIM)
		var maxr := hc.max_rank(sid)
		for p in maxr:
			var pr := Rect2(r.position + Vector2(53 + p * 12, 28), Vector2(9, 9))
			draw_rect(pr.grow(1.0), Color(0, 0, 0, 0.8))
			draw_rect(pr, Color("#f0c050") if p < h.ranks[k] else Color(0.25, 0.22, 0.18))
		if s.has("autocast") and h.ranks[k] > 0:
			var ar := Rect2(r.position + Vector2(170, 25), Vector2(14, 14))
			_auto[k] = ar.grow_individual(0, 0, 70, 0)
			HudArt.bevel(self, ar, HudArt.BRASS_DIM, Color(0.05, 0.04, 0.035), 1.0)
			if h.autocast[k]:
				draw_rect(ar.grow(-3.0), Color("#f0c050"))
			draw_string(_font, ar.position + Vector2(18, 12), "Autocast", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudArt.TEXT_DIM)
		if st == null and w.heroes.can_learn(h, k):
			_plus[k] = Rect2(Vector2(r.end.x - 24, r.position.y + 12), Vector2(20, 20))
			HudArt.plus_button(self, _font, _plus[k], _plus[k].has_point(mouse))
	_tree_button = Rect2()
	if st != null:
		_tree_button = Rect2(Vector2(x, sy + 220), Vector2(272, 32))
		var hot := _tree_button.has_point(mouse)
		HudArt.slot(self, _tree_button, HudArt.BRASS if hot or st.points > 0 else HudArt.BRASS_DIM,
			Color("#2a2016") if hot else Color("#1a140f"))
		var tree_icon := HudArt.piece("skill_tree")
		if tree_icon != null:
			draw_texture_rect(tree_icon, Rect2(_tree_button.position + Vector2(8, 1), Vector2(30, 30)), false)
		HudArt.text(self, _title, Vector2(_tree_button.position.x, _tree_button.position.y + 21),
			"Skill trees (K)" + ("   %d point%s" % [st.points, "" if st.points == 1 else "s"] if st.points > 0 else ""), 14,
			Color("#f0dfb4"), HORIZONTAL_ALIGNMENT_CENTER, _tree_button.size.x)
	elif h.points > 0:
		HudArt.text(self, _font, Vector2(x, sy + 232), "%d skill point%s to spend: click +" % [h.points,
			"" if h.points == 1 else "s"], 13, Color(0.65, 0.92, 0.5))


func _dragged_item(h: HeroState) -> Dictionary:
	if _press.is_empty():
		return {}
	if _press["kind"] == "bag":
		var j := int(_press["key"])
		return h.bag[j] if j < h.bag.size() else {}
	return h.worn.get(_press["key"], {})


func _draw_drag(w: SimWorld) -> void:
	if not _dragging:
		return
	var it := _dragged_item(_hero())
	if it.is_empty():
		return
	var icon := LootMarks.icon(it)
	var p := get_local_mouse_position() - Vector2(CELL, CELL) * 0.5
	if icon != null:
		draw_texture_rect(icon, Rect2(p, Vector2(CELL, CELL)), false, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(p, Vector2(CELL, CELL)), w.heroes.gear.icat.color(it), false, 2.0)


func _draw_tips(w: SimWorld, h: HeroState) -> void:
	if _dragging:
		return
	var mouse := get_local_mouse_position()
	var bounds := Rect2(Vector2.ZERO, size)
	var g := w.heroes.gear
	for slot: String in _worn_cells:
		if (_worn_cells[slot] as Rect2).has_point(mouse):
			var it: Dictionary = h.worn.get(slot, {})
			if it.is_empty():
				HudArt.tooltip(self, _font, mouse + Vector2(18, 12), bounds, [slot.capitalize() + " slot",
					"~Empty. Click a bag item, or drag one here."], Color("#e0d4b8"), null, 240.0)
			else:
				var lines: Array = g.icat.describe(it)
				lines.append("~Click to take it off.")
				HudArt.tooltip(self, _font, mouse + Vector2(18, 12), bounds, lines, g.icat.color(it), LootMarks.icon(it))
			return
	for j in _bag_cells.size():
		if _bag_cells[j].has_point(mouse) and j < h.bag.size():
			var it: Dictionary = h.bag[j]
			var lines: Array = g.icat.describe(it)
			if not g.icat.can_wear(g.archetype(h), it):
				lines.append("!Your hero can't use this.")
			else:
				lines.append_array(_compare(it, h.worn.get(it["slot"], {})))
				lines.append("~Click to wear it, right click to drop it.")
			HudArt.tooltip(self, _font, mouse + Vector2(18, 12), bounds, lines, g.icat.color(it), LootMarks.icon(it))
			return
	for k in _skill_rows.size():
		if _skill_rows[k].has_point(mouse) and h.kit[k] != "":
			HudArt.tooltip(self, _font, mouse + Vector2(-330, 12), bounds, HeroBar.skill_lines(w.heroes.cat, h.kit[k],
				h.ranks[k]), Color("#f0dfb4"), HudArt.skill_icon(h.kit[k]), 280.0)
			return
	if has_meta("stat_tip"):
		var tip: Array = get_meta("stat_tip")
		if (tip[0] as Rect2).has_point(mouse):
			HudArt.tooltip(self, _font, mouse + Vector2(18, 12), bounds, tip[1], Color("#f0dfb4"), null, 240.0)
		remove_meta("stat_tip")


## What wearing an item instead of the worn one changes, as tooltip lines.
static func _compare(item: Dictionary, worn: Dictionary) -> Array:
	var out: Array = []
	if worn.is_empty():
		out.append("+Fills an empty %s slot." % String(item["slot"]))
		return out
	out.append("~Instead of %s:" % String(worn["name"]))
	var keys: Array = []
	for k in item["mods"]:
		keys.append(k)
	for k in worn["mods"]:
		if not k in keys:
			keys.append(k)
	keys.sort_custom(func(a, b): return ItemCatalog.STATS.find(a) < ItemCatalog.STATS.find(b))
	for k in keys:
		var dv := float(item["mods"].get(k, 0.0)) - float(worn["mods"].get(k, 0.0))
		if absf(dv) < 0.0001:
			continue
		var line := ItemCatalog.stat_line(k, absf(dv))
		out.append(line if dv > 0.0 else "!-" + line.substr(1))
	return out


func _wrap(text: String, width: float, fs: int) -> Array:
	var out: Array = []
	var line := ""
	for wd in text.split(" "):
		var t := wd if line == "" else line + " " + wd
		if _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and line != "":
			out.append(line)
			line = wd
		else:
			line = t
	if line != "":
		out.append(line)
	return out


# --- Input --------------------------------------------------------------------------------------

func _item_at(p: Vector2) -> Dictionary:
	var h := _hero()
	for slot: String in _worn_cells:
		if (_worn_cells[slot] as Rect2).has_point(p) and h.worn.has(slot):
			return {"kind": "worn", "key": slot, "at": p}
	for j in _bag_cells.size():
		if _bag_cells[j].has_point(p) and j < h.bag.size():
			return {"kind": "bag", "key": j, "at": p}
	return {}


func _fail(why: String) -> void:
	_hint = why
	_hint_time = 3.0


func _gui_input(event: InputEvent) -> void:
	var w := _world()
	var h := _hero()
	if w == null or h == null:
		return
	if event is InputEventMouseMotion:
		if not _press.is_empty() and not _dragging and (event.position - (_press["at"] as Vector2)).length() > DRAG_PX:
			_dragging = true
		accept_event()
		return
	if not event is InputEventMouseButton:
		return
	var e := event as InputEventMouseButton
	accept_event()
	var g := w.heroes.gear
	if e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		if _dragging:
			_drop(h, g, e.position)
		elif not _press.is_empty():
			_click(h, g, _press)
		_press = {}
		_dragging = false
		return
	if not e.pressed:
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		var at := _item_at(e.position)
		if not at.is_empty() and at["kind"] == "bag":
			_send({"t": "drop", "index": int(at["key"])})
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if _close.has_point(e.position):
		close()
		return
	if _tree_button.has_point(e.position) and "campaign_hud" in skirmish:
		skirmish.campaign_hud.toggle_trees()
		return
	for k in _plus.size():
		if _plus[k].has_point(e.position) and w.heroes.can_learn(h, k):
			_send({"t": "learn", "slot": k})
			return
	for k in _auto.size():
		if _auto[k].has_point(e.position):
			_send({"t": "autocast", "slot": k, "on": not h.autocast[k]})
			return
	for kind in _potions:
		if (_potions[kind] as Rect2).has_point(e.position):
			_send({"t": "drink", "kind": kind})
			return
	_press = _item_at(e.position)


func _click(h: HeroState, g: HeroGear, at: Dictionary) -> void:
	if at["kind"] == "bag":
		_equip(h, g, int(at["key"]))
	elif not _send({"t": "unequip", "slot": String(at["key"])}):
		_fail("The bag is full.")


func _equip(h: HeroState, g: HeroGear, j: int) -> void:
	if j >= h.bag.size():
		return
	if not g.icat.can_wear(g.archetype(h), h.bag[j]):
		_fail("Your hero can't use this.")
	elif not _send({"t": "equip", "index": j}):
		_fail("No room in the bag for what it replaces.")


func _drop(h: HeroState, g: HeroGear, p: Vector2) -> void:
	var kind: String = _press["kind"]
	if kind == "bag":
		var j := int(_press["key"])
		for slot: String in _worn_cells:
			if (_worn_cells[slot] as Rect2).has_point(p):
				_equip(h, g, j)
				return
		if not Rect2(Vector2.ZERO, size).has_point(p):
			_send({"t": "drop", "index": j})
		return
	if _bag_area.has_point(p) or not Rect2(Vector2.ZERO, size).has_point(p):
		if not _send({"t": "unequip", "slot": String(_press["key"])}):
			_fail("The bag is full.")
