class_name HeroBar
extends Control
## The player's hero on the HUD, kept small: the framed portrait with its level, health, mana and
## experience bars, the 4 skills (Q W E, R = ultimate), the two potions and the bag button that
## opens the hero window (I), plus the skill tree button (K) for a campaign hero.
## Left click a skill to cast, right click to toggle autocast, click the "+" over it to spend a
## point. Click the portrait to select the hero (twice: jump to it). Click a potion to drink.
## At the start of a match it offers the faction's classes.
## Reads SimWorld state; changes it only through WorldCommands (the skirmish's act()).

const SLOT := 58.0
const KEYS := ["Q", "W", "E", "R"]
const BAR_H := 112.0
const UI_SCALE := 0.8  ## drawn at 80% in the top-left corner
const TOP := 48.0  ## just under the resource bar
const PICK_H := 262.0

var skirmish: Node
var frame: StyleBox  ## optional faction frame, as on UnitPanel
var _font: Font
var _title: Font
var _slots: Array[Rect2] = []
var _plus: Array[Rect2] = []
var _portrait := Rect2()
var _choices: Array = []  ## {rect, class_id} while picking a class
var _last_portrait_click: float = -10.0
var _potions: Dictionary = {}  ## kind -> Rect2
var _bag_button := Rect2()
var _tree_button := Rect2()
var _bag_seen: int = 0  ## items in the bag when the window was last opened (new loot glints)
var _t: float = 0.0


func _ready() -> void:
	_font = WbStyle.BODY_FONT
	_title = WbStyle.DISPLAY_FONT
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	if skirmish != null and skirmish.world != null:
		# The hero picker at the start keeps full size; the bar itself is drawn at 80%.
		var k := 1.0 if picking() else UI_SCALE
		scale = Vector2(k, k)
		offset_bottom = offset_top + (PICK_H if picking() else BAR_H)
		var h := _hero()
		if h != null and _window_open():
			_bag_seen = h.bag.size()
		if h != null and h.bag.size() < _bag_seen:
			_bag_seen = h.bag.size()
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


func _window_open() -> bool:
	return "hero_window" in skirmish and skirmish.hero_window != null and skirmish.hero_window.visible


func picking() -> bool:
	return _hero() == null and not skirmish.hero_classes().is_empty()


## The width the bar needs, so the skirmish can place what sits beside it.
func content_width() -> float:
	return 12.0 + 92.0 + 12.0 + 210.0 + 18.0 + 4.0 * (SLOT + 10.0) + 8.0 + 2.0 * 50.0 + 10.0 + 2.0 * 56.0 + 10.0


func _draw() -> void:
	var w := _world()
	if w == null:
		return
	if picking():
		_draw_picker()
		return
	var h := _hero()
	if h == null:
		visible = false
		return
	var area := Rect2(Vector2.ZERO, Vector2(minf(size.x, content_width()), size.y))
	if frame != null:
		draw_style_box(frame, area)
	else:
		draw_rect(area, Color(0.06, 0.05, 0.04, 0.9))
		draw_rect(area, HudArt.BRASS_DIM, false, 2.0)
	var hc := w.heroes.cat
	var c: Dictionary = hc.classes[h.class_id]
	var u := w.heroes.hero_unit(h.owner)
	var selected: bool = u != null and u.id in skirmish.selection
	# Portrait with the level badge.
	_portrait = Rect2(Vector2(14, 12), Vector2(88, 88))
	HudArt.framed_portrait(self, _portrait, h.class_id, u == null, HudArt.BRASS if selected else HudArt.BRASS_DIM)
	if selected:
		draw_rect(_portrait.grow(4.0), Color(1.0, 0.85, 0.45, 0.35 + 0.15 * sin(_t * 4.0)), false, 2.0)
	var level := h.level
	var m: StoryMission = skirmish.mission if "mission" in skirmish else null
	if m != null:
		level = m.progress.story.level
	HudArt.badge(self, _title, _portrait.end - Vector2(4, 4), str(level), 13.0)
	if u == null:
		var wait := "%d" % ceili(h.respawn)
		HudArt.text(self, _title, Vector2(_portrait.position.x, _portrait.get_center().y + 10), wait, 28,
			Color("#e8a090"), HORIZONTAL_ALIGNMENT_CENTER, _portrait.size.x)
	# Name, bars.
	var x0 := _portrait.end.x + 14.0
	var bar_w := 210.0
	var hname := String(c["name"])
	if u != null and u.label != "":
		hname = u.label
	if u != null:
		HudArt.bar(self, Rect2(Vector2(x0, 35), Vector2(bar_w, 17)), u.hp_ratio(), "health",
			"%d / %d" % [int(u.hp), int(u.max_hp)], _font, 12)
	else:
		var why := "Fallen: wakes at the shrine" if w.heroes.respawn_at.has(h.owner) else \
			"Fallen: back in %d s (%d gold)" % [ceili(h.respawn), int(w.heroes.revive_cost(h)["gold"])]
		HudArt.bar(self, Rect2(Vector2(x0, 35), Vector2(bar_w, 17)), 0.0, "health", why, _font, 11)
	HudArt.bar(self, Rect2(Vector2(x0, 58), Vector2(bar_w, 13)), h.mana / maxf(h.max_mana, 1.0), "mana",
		"%d / %d" % [int(h.mana), int(h.max_mana)], _font, 11)
	var xp := _xp(h)
	HudArt.bar(self, Rect2(Vector2(x0, 77), Vector2(bar_w, 7)), xp[0], "xp")
	# The name goes on top, so the bar frames' end caps never cover it.
	HudArt.text(self, _title, Vector2(x0 + 4.0, 24), hname, 16, Color("#f0dfb4"))
	var xp_text: String = xp[1]
	HudArt.text(self, _font, Vector2(x0, 100), xp_text, 11, HudArt.TEXT_DIM)
	HudArt.text(self, _font, Vector2(x0, 100), "%d %s" % [h.marks, String(hc.rules["coin"]["name"])], 11,
		Color("#d8c08a"), HORIZONTAL_ALIGNMENT_RIGHT, bar_w)
	# Skills.
	var sx := x0 + bar_w + 18.0
	_draw_skills(w, h, sx)
	# Potions, bag and tree buttons.
	var px := sx + 4.0 * (SLOT + 10.0) + 8.0
	_draw_potions(h, px)
	_draw_buttons(h, m, px + 2.0 * 50.0 + 10.0)
	_draw_hover_tips(w, h)


## [share of the level done, the text under the bars].
func _xp(h: HeroState) -> Array:
	var hc := _world().heroes.cat
	var next := hc.xp_to_next(h.level) if h.level < int(hc.rules["max_level"]) else 0
	var xp := h.xp
	var tail := ""
	var m: StoryMission = skirmish.mission if "mission" in skirmish else null
	if m != null:
		var st := m.progress.story
		xp = st.xp
		var trees := StoryTrees.get_default()
		next = trees.xp_to_next(st.level) if st.level < int(trees.rules["max_level"]) else 0
	var text := ("XP %d / %d" % [xp, next] if next > 0 else "Max level") + tail
	return [float(xp) / float(next) if next > 0 else 1.0, text]


func _draw_skills(w: SimWorld, h: HeroState, sx: float) -> void:
	var hc := w.heroes.cat
	_slots.clear()
	_plus.clear()
	var k: Array = h.kit
	var mouse := get_local_mouse_position()
	for i in 4:
		var r := Rect2(Vector2(sx + i * (SLOT + 10.0), 30), Vector2(SLOT, SLOT))
		_slots.append(r)
		_plus.append(Rect2())
		if k[i] == "":
			HudArt.slot(self, r, Color(0.3, 0.26, 0.2), Color(0.05, 0.04, 0.035))
			HudArt.text(self, _title, r.position + Vector2(4, 15), KEYS[i], 12, Color(0.5, 0.46, 0.4))
			continue
		var s := hc.skill(k[i])
		var learned := h.ranks[i] > 0
		var problem := w.heroes.cast_problem(h, i)
		var state := "ready"
		var cd := 0.0
		if not learned:
			state = "locked"
		elif problem == "cooldown":
			state = "cooldown"
			cd = clampf(h.cooldowns[i] / maxf(HeroCatalog.at_rank(s["cooldown"], h.ranks[i]), 0.01), 0.0, 1.0)
		elif problem == "mana":
			state = "mana"
		var rim := HudArt.BRASS_DIM
		if s["target"] == "aura":
			rim = Color("#7fa860")
		elif learned and h.autocast[i] and s.has("autocast"):
			rim = Color(0.95, 0.78, 0.3).lerp(Color(1, 0.95, 0.7), 0.5 + 0.5 * sin(_t * 3.0))
		if skirmish.casting_slot() == i:
			rim = Color(0.45, 1.0, 0.45)
		if s.get("ultimate", false):
			# The ultimate's slot: a heavier rim with small spikes.
			for dx in [0.25, 0.5, 0.75]:
				var tip := Vector2(r.position.x + r.size.x * dx, r.position.y - 6)
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 7), tip + Vector2(4, 7)]), rim)
		HudArt.skill_tile(self, r, k[i], state, cd, rim)
		if r.has_point(mouse):
			draw_rect(r.grow(-2.0), Color(1, 0.95, 0.75, 0.1))
		if state == "cooldown":
			HudArt.text(self, _title, Vector2(r.position.x, r.get_center().y + 8), "%d" % ceili(h.cooldowns[i]), 22,
				Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		# Key letter.
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(15, 15)), Color(0, 0, 0, 0.7))
		HudArt.text(self, _title, r.position + Vector2(4, 14), KEYS[i], 12, Color("#f0e2c0"))
		# Rank pips under the slot.
		var maxr := hc.max_rank(k[i])
		var pw := 9.0
		var px := r.get_center().x - (maxr * pw) * 0.5
		for p in maxr:
			var pr := Rect2(Vector2(px + p * pw + 1, r.end.y + 4), Vector2(pw - 3, 4))
			draw_rect(pr.grow(1.0), Color(0, 0, 0, 0.8))
			draw_rect(pr, Color("#f0c050") if p < h.ranks[i] else Color(0.25, 0.22, 0.18))
		var plus := Rect2(r.position + Vector2(r.size.x - 17, -9), Vector2(18, 18))
		_plus[i] = plus
		if w.heroes.can_learn(h, i):
			HudArt.plus_button(self, _font, plus, plus.has_point(mouse))
	if h.points > 0:
		HudArt.text(self, _font, Vector2(sx, 18), "%d skill point%s: click +  (auto in %d s)" % [h.points,
			"" if h.points == 1 else "s", maxi(0, ceili(float(w.heroes.cat.rules["auto_learn_delay"]) - h.unspent_time))],
			11, Color(0.65, 0.92, 0.5))


func _draw_potions(h: HeroState, x: float) -> void:
	_potions.clear()
	var mouse := get_local_mouse_position()
	var i := 0
	for kind in ["health", "mana"]:
		var r := Rect2(Vector2(x + i * 50.0, 30), Vector2(44, SLOT))
		_potions[kind] = r
		var n := int(h.potions.get(kind, 0))
		HudArt.slot(self, r, HudArt.BRASS_DIM, Color(0.05, 0.04, 0.035))
		if r.has_point(mouse) and n > 0:
			draw_rect(r.grow(-2.0), Color(1, 0.95, 0.75, 0.1))
		HudArt.potion(self, r.grow(-3.0), kind, n > 0)
		if h.potion_cd > 0.0 and n > 0:
			var f := clampf(h.potion_cd / maxf(float(_world().heroes.gear.ir["potion_cooldown"]), 0.01), 0.0, 1.0)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * f)), Color(0, 0, 0, 0.55))
		HudArt.badge(self, _title, r.end - Vector2(5, 5), str(n), 9.0, Color("#6b5a3a"))
		i += 1


func _draw_buttons(h: HeroState, m: StoryMission, x: float) -> void:
	var mouse := get_local_mouse_position()
	_bag_button = Rect2(Vector2(x, 30), Vector2(50, SLOT))
	HudArt.slot(self, _bag_button, HudArt.BRASS if _window_open() else HudArt.BRASS_DIM, Color("#1e1812"))
	var icon := HudArt.piece("bag")
	if icon != null:
		draw_texture_rect(icon, Rect2(_bag_button.position + Vector2(3, 2), Vector2(44, 44)), false)
	else:
		icon = HudArt.ui_icon("pack")
		if icon != null:
			draw_texture_rect(icon, Rect2(_bag_button.position + Vector2(5, 4), Vector2(40, 40)), false)
	if _bag_button.has_point(mouse):
		draw_rect(_bag_button.grow(-2.0), Color(1, 0.95, 0.75, 0.1))
	HudArt.text(self, _font, Vector2(_bag_button.position.x, _bag_button.end.y - 4), "%d/%d" % [h.bag.size(),
		int(_world().heroes.gear.ir["bag_size"])], 10, HudArt.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, _bag_button.size.x)
	HudArt.text(self, _title, _bag_button.position + Vector2(4, 14), "I", 12, Color("#f0e2c0"))
	if h.bag.size() > _bag_seen:
		# New loot: a glint on the bag until the window is opened.
		var a := 0.5 + 0.5 * sin(_t * 5.0)
		draw_rect(_bag_button.grow(2.0), Color(1.0, 0.8, 0.35, 0.4 + 0.5 * a), false, 2.0)
		HudArt.badge(self, _title, _bag_button.position + Vector2(_bag_button.size.x - 4, 4), "!", 8.0, Color("#c0602a"))
	_tree_button = Rect2()
	if m != null:
		_tree_button = Rect2(Vector2(x + 56.0, 30), Vector2(50, SLOT))
		var pts := m.progress.story.points
		HudArt.slot(self, _tree_button, HudArt.BRASS if pts > 0 else HudArt.BRASS_DIM, Color("#1e1812"))
		var tree_icon := HudArt.piece("skill_tree")
		if tree_icon != null:
			draw_texture_rect(tree_icon, Rect2(_tree_button.position + Vector2(3, 5), Vector2(44, 44)), false,
				Color.WHITE if pts > 0 else Color(0.8, 0.78, 0.74))
		else:
			_draw_tree_glyph(_tree_button.grow(-9.0), pts > 0)
		HudArt.text(self, _title, _tree_button.position + Vector2(4, 14), "K", 12, Color("#f0e2c0"))
		if _tree_button.has_point(mouse):
			draw_rect(_tree_button.grow(-2.0), Color(1, 0.95, 0.75, 0.1))
		if pts > 0:
			HudArt.badge(self, _title, _tree_button.position + Vector2(_tree_button.size.x - 4, 4), str(pts), 9.0,
				Color("#4f8a32"))


## Three nodes joined by lines: the skill tree button's glyph.
func _draw_tree_glyph(r: Rect2, lit: bool) -> void:
	var col := Color("#f0c050") if lit else Color("#a89a7c")
	var top := Vector2(r.get_center().x, r.position.y + 8)
	var bl := Vector2(r.position.x + 6, r.end.y - 6)
	var br := Vector2(r.end.x - 6, r.end.y - 6)
	draw_line(top, bl, col.darkened(0.3), 2.0)
	draw_line(top, br, col.darkened(0.3), 2.0)
	for p in [top, bl, br]:
		draw_circle(p, 5.5, Color(0, 0, 0, 0.9))
		draw_circle(p, 4.0, col)


func _draw_hover_tips(w: SimWorld, h: HeroState) -> void:
	var mouse := get_local_mouse_position()
	var bounds := _tip_bounds()
	var below := size.y + 10.0
	var hover := _slot_at(mouse)
	if hover >= 0 and h.kit[hover] != "":
		var lines := skill_lines(w.heroes.cat, h.kit[hover], h.ranks[hover])
		_tip(Vector2(_slots[hover].position.x, below), bounds, lines,
			Color("#f0dfb4"), HudArt.skill_icon(h.kit[hover]), 300.0)
		return
	for kind in _potions:
		if (_potions[kind] as Rect2).has_point(mouse):
			var ir: Dictionary = w.heroes.gear.ir
			var what := "Restores %d%% of the hero's health." % roundi(float(ir["potion_heal_pct"]) * 100.0) \
				if kind == "health" else "Restores %d%% of the hero's mana." % roundi(float(ir["potion_mana_pct"]) * 100.0)
			_tip(Vector2((_potions[kind] as Rect2).position.x, below), bounds,
				["%s draught (%d)" % [String(kind).capitalize(), int(h.potions.get(kind, 0))], what,
				"~Click to drink. Holds up to %d." % int(ir["potion_max"])], Color("#f0dfb4"), null, 260.0)
			return
	if _bag_button.has_point(mouse):
		_tip(Vector2(_bag_button.position.x - 100, below), bounds,
			["Hero (I)", "Equipment, bag, stats and skills."], Color("#f0dfb4"), null, 240.0)
	elif _tree_button.has_point(mouse):
		_tip(Vector2(_tree_button.position.x - 120, below), bounds,
			["Skill trees (K)", "Spend skill points and choose the skill bar."], Color("#f0dfb4"), null, 260.0)


## Tooltip lines for a skill at a rank (0 = not learned yet).
static func skill_lines(hc: HeroCatalog, sid: String, rank: int) -> Array:
	var s := hc.skill(sid)
	var lines: Array = [String(s["name"]) + ("  (ultimate)" if s.get("ultimate", false) else ""), String(s["text"])]
	if s["target"] != "aura":
		var rr := maxi(rank, 1)
		lines.append("~Mana %d   Cooldown %d s" % [int(HeroCatalog.at_rank(s["mana"], rr)),
			int(HeroCatalog.at_rank(s["cooldown"], rr))])
	lines.append("~Rank %d / %d" % [rank, hc.max_rank(sid)] + ("   Right click: autocast" if s.has("autocast") else ""))
	return lines


func _draw_picker() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if frame != null:
		draw_style_box(frame, area)
	else:
		draw_rect(area, Color(0.06, 0.05, 0.04, 0.94))
		draw_rect(area, HudArt.BRASS, false, 2.0)
	HudArt.text(self, _title, Vector2(26, 32), "Choose your hero", 18, Color("#f0dfb4"))
	var hc := HeroCatalog.get_default()
	_choices.clear()
	var ids: Array = skirmish.hero_classes()
	var cw := minf(260.0, (size.x - 28.0 - 10.0 * (ids.size() - 1)) / maxf(ids.size(), 1))
	var mouse := get_local_mouse_position()
	for i in ids.size():
		var c: Dictionary = hc.classes[ids[i]]
		var r := Rect2(Vector2(14 + i * (cw + 10.0), 42), Vector2(cw, size.y - 56))
		_choices.append({"rect": r, "class_id": ids[i]})
		var hot := r.has_point(mouse)
		HudArt.bevel(self, r, HudArt.BRASS if hot else HudArt.BRASS_DIM, Color("#211a13") if hot else Color("#17120e"))
		var pr := Rect2(r.position + Vector2(8, 8), Vector2(88, 88))
		HudArt.framed_portrait(self, pr, ids[i], false, HudArt.BRASS if hot else HudArt.BRASS_DIM)
		var tx := pr.end.x + 10.0
		var tw := r.end.x - tx - 6.0
		HudArt.text(self, _title, Vector2(tx, r.position.y + 24), c["name"], 15, Color("#f0dfb4"), HORIZONTAL_ALIGNMENT_LEFT, tw)
		HudArt.text(self, _font, Vector2(tx, r.position.y + 42), String(c["archetype"]).capitalize(), 12, HudArt.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, tw)
		var k: Array = c["kit"]
		var ics := minf(40.0, (r.size.x - 16.0 - 18.0) / 4.0)
		for j in 4:
			var sr := Rect2(Vector2(r.position.x + 8 + j * (ics + 6.0), pr.end.y + 8), Vector2(ics, ics))
			HudArt.skill_tile(self, sr, k[j])
			if sr.has_point(mouse):
				set_meta("pick_tip", [sr, k[j]])
		var lines := _wrap(String(c.get("text", "")), r.size.x - 16.0, 12)
		for j in mini(lines.size(), 3):
			draw_string(_font, Vector2(r.position.x + 8, pr.end.y + ics + 26 + j * 15), lines[j], HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x - 16.0, 12, Color("#cfc4ac"))
	_pick_tip()


func _pick_tip() -> void:
	if not has_meta("pick_tip"):
		return
	var tip: Array = get_meta("pick_tip")
	remove_meta("pick_tip")
	var r: Rect2 = tip[0]
	var lines := skill_lines(HeroCatalog.get_default(), tip[1], 0)
	lines.pop_back()
	_tip(Vector2(r.position.x, size.y + 10.0), _tip_bounds(), lines, Color("#f0dfb4"),
		HudArt.skill_icon(tip[1]), 280.0)


## A tooltip at full size even though the bar is drawn smaller: at is in the bar's coordinates.
func _tip(at: Vector2, bounds: Rect2, lines: Array, title_col: Color, icon: Texture2D = null,
		width: float = 300.0) -> void:
	var k := scale.x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / k)
	HudArt.tooltip(self, _font, at * k, Rect2(bounds.position * k, bounds.size * k), lines, title_col, icon, width)
	draw_set_transform(Vector2.ZERO)


## The screen in this bar's own (scaled) coordinates, so tooltips stay on it.
func _tip_bounds() -> Rect2:
	var inv := get_global_transform_with_canvas().affine_inverse()
	var vp := get_viewport_rect()
	var a := inv * vp.position
	var b := inv * vp.end
	return Rect2(a, b - a)


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


func _slot_at(p: Vector2) -> int:
	for i in _slots.size():
		if _slots[i].has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var e := event as InputEventMouseButton
	var w := _world()
	if picking():
		for c in _choices:
			if (c["rect"] as Rect2).has_point(e.position) and e.button_index == MOUSE_BUTTON_LEFT:
				skirmish.pick_hero(c["class_id"])
		accept_event()
		return
	var h := _hero()
	if h == null:
		return
	for i in _plus.size():
		if _plus[i].has_point(e.position) and w.heroes.can_learn(h, i):
			_send({"t": "learn", "slot": i})
			accept_event()
			return
	for kind in _potions:
		if (_potions[kind] as Rect2).has_point(e.position):
			_send({"t": "drink", "kind": kind})
			accept_event()
			return
	if _bag_button.has_point(e.position):
		skirmish.toggle_hero_window()
		accept_event()
		return
	if _tree_button.has_point(e.position) and "campaign_hud" in skirmish:
		skirmish.campaign_hud.toggle_trees()
		accept_event()
		return
	if _portrait.has_point(e.position) and e.button_index == MOUSE_BUTTON_LEFT:
		skirmish.select_hero(skirmish._time - _last_portrait_click < 0.35)
		_last_portrait_click = skirmish._time
		accept_event()
		return
	var i := _slot_at(e.position)
	if i < 0:
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		_send({"t": "autocast", "slot": i, "on": not h.autocast[i]})
	elif e.button_index == MOUSE_BUTTON_LEFT:
		skirmish.start_cast(i, false)
	accept_event()
