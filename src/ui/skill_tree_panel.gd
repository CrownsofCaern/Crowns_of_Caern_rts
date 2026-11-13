class_name SkillTreePanel
extends Control
## The campaign hero's skill trees (K), drawn as real trees: the class signature at the root, three
## trunks (two archetype trees and the faction tree), each with 4 tiers of framed nodes branching
## off it. A tier opens once enough points are spent in its tree (the gate on the trunk lights up).
## Active skills sit in square frames, the ultimate in a crowned frame, passives in round ones.
## Below: the Q W E R bar. Click a node to spend a point; drag a learned skill onto a bar slot (or
## click a slot to cycle through the known skills).
## Changes go through StoryMission.command_learn / command_slot. The painted frames, icons and
## backdrop come from HudArt; stand-ins are drawn until they exist.

signal closed

const W := 1100.0
const H := 744.0
const COL_W := 330.0
const ROW_Y := [300.0, 390.0, 480.0, 570.0]
const NODE_DX := 96.0
const ACTIVE := 54.0
const PASSIVE_R := 24.0

var mission: StoryMission
var _font: Font
var _title: Font
var _frame: StyleBox
var _nodes: Array = []  ## {id, rect, kind, skill, tree}
var _slots: Array[Rect2] = []
var _close := Rect2()
var _press: Dictionary = {}  ## {skill, at} while dragging a learned active from a node
var _dragging := false
var _t := 0.0
var _flash: Dictionary = {}  ## node id -> seconds of the learn flash left


func build() -> void:
	_font = WbStyle.BODY_FONT
	_title = WbStyle.DISPLAY_FONT
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)


func open(m: StoryMission) -> void:
	mission = m
	var heroes := HeroCatalog.get_default()
	var faction := String(heroes.classes[m.progress.story.class_id]["faction"]) if m != null else "concord"
	_frame = WbStyle.frame_panel(faction, 0)
	refresh()
	show()


## Kept for callers: the panel redraws itself every frame.
func refresh() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for k in _flash.keys():
		_flash[k] = float(_flash[k]) - delta
		if float(_flash[k]) <= 0.0:
			_flash.erase(k)
	queue_redraw()


# --- Drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	if mission == null:
		return
	var st := mission.progress.story
	var heroes := HeroCatalog.get_default()
	var trees := StoryTrees.get_default()
	var all := Rect2(Vector2.ZERO, size)
	draw_rect(all.grow(10.0), Color(0, 0, 0, 0.4))
	if _frame != null:
		draw_style_box(_frame, all)
	var inner := all.grow(-22.0)
	var bd := HudArt.piece("tree_backdrop")
	if bd != null:
		draw_texture_rect(bd, inner, false)
	else:
		draw_texture_rect(HudArt._radial(Color(0.13, 0.09, 0.06, 1.0), Color(0.025, 0.02, 0.016, 1.0)), inner, false)
	_nodes.clear()
	var mouse := get_local_mouse_position()
	# Header.
	var cls: Dictionary = heroes.classes[st.class_id]
	var hname: String = mission.progress.hero_name if mission.progress.hero_name != "" else String(cls["name"])
	HudArt.framed_portrait(self, Rect2(Vector2(38, 34), Vector2(64, 64)), st.class_id)
	HudArt.text(self, _title, Vector2(116, 62), hname, 26, Color("#e8c873"))
	HudArt.text(self, _font, Vector2(116, 86), "Level %d %s  ·  Skill trees" % [st.level, cls["name"]], 15,
		HudArt.TEXT_DIM)
	var pts_col := Color("#8fd070") if st.points > 0 else HudArt.TEXT_DIM
	HudArt.text(self, _title, Vector2(W - 380, 70), "Skill points", 16, pts_col, HORIZONTAL_ALIGNMENT_RIGHT, 220)
	HudArt.badge(self, _title, Vector2(W - 130, 64), str(st.points), 19.0, Color("#4f8a32") if st.points > 0 else Color("#5a4d36"))
	_close = Rect2(Vector2(W - 62, 36), Vector2(28, 28))
	var hot := _close.has_point(mouse)
	HudArt.bevel(self, _close, HudArt.BRASS if hot else HudArt.BRASS_DIM, Color("#2a1a14") if hot else Color("#17120e"))
	var cc := _close.get_center()
	draw_line(cc + Vector2(-6, -6), cc + Vector2(6, 6), HudArt.TEXT, 2.0)
	draw_line(cc + Vector2(6, -6), cc + Vector2(-6, 6), HudArt.TEXT, 2.0)
	# The root: the signature skill, joined to the three trunks.
	var tids: Array = st.trees()
	var root := Vector2(W * 0.5, 150)
	var cols: Array[float] = []
	for i in tids.size():
		cols.append(W * 0.5 + (i - (tids.size() - 1) * 0.5) * (COL_W + 18.0))
	for i in tids.size():
		var top := Vector2(cols[i], 196)
		var mid_y := 178.0
		_connector([root, Vector2(root.x, mid_y), Vector2(top.x, mid_y), top], true)
	var sig := st.signature()
	var sig_r := Rect2(root - Vector2(34, 34), Vector2(68, 68))
	var sig_problem := st.learn_problem(StoryHero.SIGNATURE)
	_node_frame(sig_r, "signature", sig, "", st.rank(StoryHero.SIGNATURE) + 1, heroes.max_rank(sig), true,
		sig_problem == "", sig_r.has_point(mouse), StoryHero.SIGNATURE)
	_nodes.append({"id": StoryHero.SIGNATURE, "rect": sig_r, "kind": "signature", "skill": sig, "tree": ""})
	# The trees.
	for i in tids.size():
		_draw_tree(String(tids[i]), cols[i], st, heroes, trees, mouse)
	_draw_bar(st, heroes, mouse)
	_draw_drag()
	_draw_tip(st, heroes, trees, mouse)


func _draw_tree(tid: String, cx: float, st: StoryHero, heroes: HeroCatalog, trees: StoryTrees, mouse: Vector2) -> void:
	var t: Dictionary = trees.trees[tid]
	var spent := st.spent_in(tid)
	var panel := Rect2(Vector2(cx - COL_W * 0.5, 196), Vector2(COL_W, 436))
	draw_rect(panel, Color(0, 0, 0, 0.35))
	draw_rect(panel, Color(0.5, 0.4, 0.25, 0.35), false, 1.0)
	# Tree title plaque.
	var plaque := Rect2(Vector2(panel.position.x + 10, panel.position.y + 8), Vector2(COL_W - 20, 54))
	HudArt.bevel(self, plaque, HudArt.BRASS_DIM, Color("#1b1510"))
	HudArt.text(self, _title, Vector2(plaque.position.x + 12, plaque.position.y + 22), String(t["name"]), 17,
		Color("#e8c873"))
	var kind := "Faction tree" if t.has("faction") else String(t.get("archetype", "")).capitalize() + " tree"
	draw_string(_font, Vector2(plaque.position.x + 12, plaque.position.y + 42), kind, HORIZONTAL_ALIGNMENT_LEFT, 180, 12,
		HudArt.TEXT_DIM)
	HudArt.text(self, _font, Vector2(plaque.end.x - 110, plaque.position.y + 33), "%d spent" % spent, 13,
		Color("#d8c08a"), HORIZONTAL_ALIGNMENT_RIGHT, 98)
	# First the chains (trunk and branches), then the gates on the trunk, then the nodes on top.
	var gates: Array = trees.rules["row_points"]
	var trunk_top := plaque.end.y
	for row in 4:
		var y: float = ROW_Y[row]
		_connector([Vector2(cx, trunk_top), Vector2(cx, y)], spent >= int(gates[row]))
		_connector([Vector2(cx - NODE_DX, y), Vector2(cx + NODE_DX, y)], spent >= int(gates[row]))
		trunk_top = y
	for row in 4:
		var y: float = ROW_Y[row]
		var open := spent >= int(gates[row])
		if int(gates[row]) > 0:
			# The gate: a small plaque on the trunk with the points the tier needs.
			var g := Rect2(Vector2(cx - 13, y - 13), Vector2(26, 26))
			draw_rect(g.grow(2.0), Color(0, 0, 0, 0.9))
			draw_rect(g, Color("#3b2e1c") if open else Color("#1a1612"))
			draw_rect(g, Color("#e0b450") if open else Color("#5a4d36"), false, 1.5)
			HudArt.text(self, _title, Vector2(g.position.x, g.position.y + 18), str(int(gates[row])), 13,
				Color("#fff0c0") if open else Color("#7d725e"), HORIZONTAL_ALIGNMENT_CENTER, g.size.x)
		else:
			draw_circle(Vector2(cx, y), 6.0, Color(0, 0, 0, 0.9))
			draw_circle(Vector2(cx, y), 4.0, Color("#e0b450"))
	# The nodes: two per tier, left and right of the trunk, the name underneath.
	var side := {}
	for n: Dictionary in t["nodes"]:
		var row := int(n["row"])
		var k := int(side.get(row, 0))
		side[row] = k + 1
		var nx := cx + (-1.0 if k == 0 else 1.0) * NODE_DX
		var ny: float = ROW_Y[row]
		var open := spent >= int(gates[row])
		var nid := String(n["id"])
		var is_active: bool = n["kind"] == "active"
		var sid := String(n.get("skill", ""))
		var ult := is_active and bool(heroes.skills[sid].get("ultimate", false))
		var sz := (ACTIVE + (8.0 if ult else 0.0)) if is_active else PASSIVE_R * 2.0
		var r := Rect2(Vector2(nx, ny) - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
		var kind_s := ("ultimate" if ult else "active") if is_active else "passive"
		var rank := st.rank(nid)
		var problem := st.learn_problem(nid)
		_node_frame(r, kind_s, sid, "" if is_active else StoryTrees.node_icon(n), rank, trees.max_rank(heroes, nid), open,
			problem == "", r.has_point(mouse), nid)
		_nodes.append({"id": nid, "rect": r, "kind": kind_s, "skill": sid, "tree": tid})
		var label := String(heroes.skills[sid]["name"]) if is_active else String(n.get("name", ""))
		HudArt.text(self, _font, Vector2(nx - 70.0, r.end.y + (31.0 if ult else 23.0)), label, 12,
			Color("#ecdcb6") if rank > 0 else (Color("#b0a385") if open else Color("#6e6656")),
			HORIZONTAL_ALIGNMENT_CENTER, 140.0)


## A node: its icon in the right frame, dimmed while locked, a rank tag, and a pulsing rim when a
## point can go into it now.
func _node_frame(r: Rect2, kind: String, skill_id: String, passive_icon: String, rank: int, max_rank: int, open: bool,
		learnable: bool, hover: bool, nid: String) -> void:
	var round := kind in ["passive", "signature"]
	var learned := rank > 0
	var rim := Color("#e0b450") if learned else (HudArt.BRASS_DIM if open else Color("#4a4030"))
	if learnable:
		rim = Color("#7fd060").lerp(Color("#d8ffb0"), 0.5 + 0.5 * sin(_t * 4.0))
	var icon: Texture2D = HudArt.skill_icon(skill_id) if skill_id != "" else HudArt.stat_icon(passive_icon)
	var mod := Color.WHITE if learned else (Color(0.62, 0.6, 0.56) if open else Color(0.25, 0.24, 0.22))
	var c := r.get_center()
	var rad := r.size.x * 0.5
	if learnable or _flash.has(nid):
		var glow := 0.25 + 0.2 * sin(_t * 4.0)
		if _flash.has(nid):
			glow = float(_flash[nid])
		draw_circle(c, rad + 10.0, Color(0.6, 1.0, 0.4, glow * 0.35))
	var painted := HudArt.piece("node_" + kind)
	if round:
		draw_circle(c, rad + 3.0, Color(0, 0, 0, 0.9))
		draw_circle(c, rad, Color("#120e0b"))
		if icon != null:
			# A round crop: the icon drawn into a circle polygon with UVs.
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 32:
				var a := TAU * i / 32.0
				var d := Vector2(cos(a), sin(a))
				pts.append(c + d * (rad - 2.0))
				uvs.append(Vector2(0.5, 0.5) + d * 0.5)
			var cols := PackedColorArray()
			cols.resize(32)
			cols.fill(mod)
			draw_polygon(pts, cols, uvs, icon)
		if painted == null:
			draw_arc(c, rad, 0, TAU, 40, rim, 3.0 if kind == "signature" else 2.0)
			draw_arc(c, rad + 3.5, 0, TAU, 40, Color(0, 0, 0, 0.8), 1.5)
			if kind == "signature":
				# A laurel of small leaves round the signature.
				for i in 14:
					var a := PI * 0.62 + i * (PI * 1.76 / 13.0)
					var p := c + Vector2(cos(a), sin(a)) * (rad + 8.0)
					draw_circle(p, 3.2, Color(0, 0, 0, 0.8))
					draw_circle(p, 2.4, rim.darkened(0.15))
	else:
		var tile := r
		HudArt.bevel(self, tile, rim, Color("#120e0b"), 2.5 if kind == "ultimate" else 2.0)
		if icon != null:
			if not HudArt.has_painted_skill(skill_id):
				draw_texture_rect(HudArt._radial(Color(0.45, 0.25, 0.12, 0.9), Color(0.05, 0.04, 0.03, 1.0)),
					tile.grow(-3.0), false, mod)
			draw_texture_rect(icon, tile.grow(-5.0), false, mod)
		if kind == "ultimate" and painted == null:
			for dx in [0.2, 0.5, 0.8]:
				var tip := Vector2(tile.position.x + tile.size.x * dx, tile.position.y - (9.0 if dx == 0.5 else 6.0))
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, 9), tip + Vector2(5, 9)]), rim)
			draw_circle(Vector2(c.x, tile.end.y), 5.0, Color(0, 0, 0, 0.9))
			draw_circle(Vector2(c.x, tile.end.y), 3.5, Color("#c0302a") if learned else Color("#4a1a16"))
	if painted != null:
		draw_texture_rect(painted, HudArt.frame_rect("node_" + kind, r), false,
			Color.WHITE if open else Color(0.55, 0.55, 0.55))
		if learnable:
			draw_rect(r.grow(2.0), rim, false, 1.5)
	if hover:
		draw_rect(r.grow(1.0), Color(1, 0.95, 0.75, 0.12))
	if not open:
		# A small padlock.
		var lp := Vector2(r.end.x - 6, r.position.y + 6)
		draw_arc(lp + Vector2(0, -2), 3.5, PI, TAU, 8, Color("#a89a7c"), 1.5)
		draw_rect(Rect2(lp + Vector2(-5, -1), Vector2(10, 8)), Color(0, 0, 0, 0.9))
		draw_rect(Rect2(lp + Vector2(-4, 0), Vector2(8, 6)), Color("#8a7a5a"))
	# Rank tag.
	var tag := "%d/%d" % [rank, max_rank]
	var tr := Rect2(Vector2(c.x - 17, r.end.y - 6), Vector2(34, 15))
	draw_rect(tr.grow(1.0), Color(0, 0, 0, 0.9))
	draw_rect(tr, Color("#2a2016") if learned else Color("#14100c"))
	draw_string(_font, Vector2(tr.position.x, tr.position.y + 12), tag, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 11,
		Color("#f0d080") if learned else Color("#8a806c"))


## A connector between points: an iron chain look (dark bed, a lit or dull core), or the painted strip.
func _connector(pts: Array, lit: bool) -> void:
	var strip := HudArt.piece("tree_connector")
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if a.distance_to(b) < 0.5:
			continue
		draw_line(a, b, Color(0, 0, 0, 0.85), 7.0)
		if strip != null:
			var len := a.distance_to(b)
			var ang := (b - a).angle()
			draw_set_transform(a, ang)
			# Links keep their painted proportions and repeat along the line.
			var th := 12.0
			var region := Rect2(0, 0, len * strip.get_height() / th, strip.get_height())
			draw_texture_rect_region(strip, Rect2(Vector2(0, -th * 0.5), Vector2(len, th)), region,
				Color.WHITE if lit else Color(0.4, 0.38, 0.35))
			draw_set_transform(Vector2.ZERO)
		else:
			draw_line(a, b, Color("#d9a840") if lit else Color("#3e3528"), 3.0)
			if lit:
				draw_line(a, b, Color(1.0, 0.85, 0.45, 0.18 + 0.08 * sin(_t * 2.0)), 7.0)


func _draw_bar(st: StoryHero, heroes: HeroCatalog, mouse: Vector2) -> void:
	var y := 646.0
	var x0 := W * 0.5 - 2.0 * 74.0
	HudArt.text(self, _title, Vector2(60, y + 26), "Skill bar", 16, Color("#d8b866"))
	draw_string(_font, Vector2(60, y + 46), "Drag a learned skill onto a slot,", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		HudArt.TEXT_DIM)
	draw_string(_font, Vector2(60, y + 61), "or click a slot to cycle.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudArt.TEXT_DIM)
	_slots.clear()
	var known := st.known_skills()
	for i in 4:
		var r := Rect2(Vector2(x0 + i * 74.0, y), Vector2(60, 60))
		_slots.append(r)
		var sid: String = st.slots[i]
		var rim := HudArt.BRASS_DIM
		if _dragging and _press.has("skill"):
			var ult := bool(heroes.skills[_press["skill"]].get("ultimate", false))
			if ult == (i == 3):
				rim = Color("#7fd060").lerp(Color("#d8ffb0"), 0.5 + 0.5 * sin(_t * 5.0))
		if sid == "":
			HudArt.slot(self, r, rim, Color(0.05, 0.04, 0.035))
		else:
			HudArt.skill_tile(self, r, sid, "ready", 0.0, rim)
			var rk := int(known.get(sid, 0))
			draw_string(_font, Vector2(r.position.x - 12.0, r.end.y + 14), String(heroes.skills[sid]["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 24.0, 10, HudArt.TEXT_DIM)
			if rk > 0:
				HudArt.badge(self, _title, r.end - Vector2(4, 4), str(rk), 9.0, Color("#6b5a3a"))
		if r.has_point(mouse):
			draw_rect(r.grow(-2.0), Color(1, 0.95, 0.75, 0.1))
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(15, 15)), Color(0, 0, 0, 0.7))
		HudArt.text(self, _title, r.position + Vector2(4, 14), HudArt.KEYS[i], 12, Color("#f0e2c0"))
	HudArt.text(self, _font, Vector2(W - 300, y + 36), "Ultimate (R) opens at level %d" % int(StoryTrees.get_default().rules["ultimate_level"]),
		12, HudArt.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 240)


func _draw_drag() -> void:
	if not _dragging or not _press.has("skill"):
		return
	var icon := HudArt.skill_icon(_press["skill"])
	var p := get_local_mouse_position() - Vector2(28, 28)
	if icon != null:
		draw_texture_rect(icon, Rect2(p, Vector2(56, 56)), false, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(p, Vector2(56, 56)), Color("#e0b450"), false, 2.0)


func _draw_tip(st: StoryHero, heroes: HeroCatalog, trees: StoryTrees, mouse: Vector2) -> void:
	if _dragging:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	for nd: Dictionary in _nodes:
		if not (nd["rect"] as Rect2).has_point(mouse):
			continue
		var nid := String(nd["id"])
		var lines: Array = []
		var icon: Texture2D = null
		var max_r := heroes.max_rank(nd["skill"]) if nid == StoryHero.SIGNATURE else trees.max_rank(heroes, nid)
		var rank := st.rank(nid) + (1 if nid == StoryHero.SIGNATURE else 0)
		if nd["skill"] != "":
			lines = HeroBar.skill_lines(heroes, nd["skill"], rank)
			lines[lines.size() - 1] = "~Rank %d / %d" % [rank, max_r]
			icon = HudArt.skill_icon(nd["skill"])
			if nid == StoryHero.SIGNATURE:
				lines.insert(1, "~Signature skill of the class")
		else:
			var n: Dictionary = trees.nodes[nid]
			lines = [String(n.get("name", nid)), "~Passive, rank %d / %d" % [rank, max_r]]
			if n.has("talent"):
				lines.append(StoryTrees.talent_text(n, rank))
			for k in n.get("mods", {}):
				lines.append("+" + ItemCatalog.stat_line(k, float(n["mods"][k])).substr(1) + " per rank")
			icon = HudArt.stat_icon(StoryTrees.node_icon(n))
		var problem := st.learn_problem(nid)
		match problem:
			"":
				lines.append("+Click to spend a point.")
			"no points":
				lines.append("~No skill points to spend.")
			"row locked":
				var n: Dictionary = trees.nodes[nid]
				lines.append("!Opens with %d points in %s." % [int(trees.rules["row_points"][int(n["row"])]),
					trees.trees[n["tree"]]["name"]])
			"max rank":
				lines.append("~Fully learned.")
			"level":
				lines.append("!Needs level %d." % int(trees.rules["ultimate_level"]))
		if rank > 0 and nd["kind"] in ["active", "ultimate", "signature"]:
			lines.append("~Drag it onto the skill bar.")
		var r: Rect2 = nd["rect"]
		HudArt.tooltip(self, _font, Vector2(r.end.x + 14, r.position.y - 10), bounds, lines, Color("#f0dfb4"), icon, 290.0)
		return
	for i in _slots.size():
		if _slots[i].has_point(mouse):
			var sid: String = st.slots[i]
			var lines: Array = ["%s slot" % HudArt.KEYS[i] + (" (ultimate)" if i == 3 else "")]
			if sid != "":
				lines = HeroBar.skill_lines(heroes, sid, int(st.known_skills().get(sid, 0)))
			lines.append("~Click to cycle through the skills you know.")
			HudArt.tooltip(self, _font, Vector2(_slots[i].position.x, _slots[i].position.y - 150), bounds, lines,
				Color("#f0dfb4"), HudArt.skill_icon(sid) if sid != "" else null, 280.0)
			return


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

func _node_at(p: Vector2) -> Dictionary:
	for nd: Dictionary in _nodes:
		if (nd["rect"] as Rect2).has_point(p):
			return nd
	return {}


func _gui_input(event: InputEvent) -> void:
	if mission == null:
		return
	if event is InputEventMouseMotion:
		if not _press.is_empty() and not _dragging and (event.position - (_press["at"] as Vector2)).length() > 6.0:
			_dragging = _press.has("skill")
		accept_event()
		return
	if not event is InputEventMouseButton:
		return
	var e := event as InputEventMouseButton
	accept_event()
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		if _close.has_point(e.position):
			hide()
			closed.emit()
			return
		for i in _slots.size():
			if _slots[i].has_point(e.position):
				_cycle_slot(i)
				return
		var nd := _node_at(e.position)
		if nd.is_empty():
			return
		_press = {"node": nd["id"], "at": e.position}
		var st := mission.progress.story
		if nd["skill"] != "" and st.known_skills().has(nd["skill"]):
			_press["skill"] = nd["skill"]
		return
	# Release: a drop on a slot, or a click on the node pressed.
	if _dragging:
		for i in _slots.size():
			if _slots[i].grow(6.0).has_point(e.position):
				mission.command_slot(i, _press["skill"])
	elif not _press.is_empty():
		var nid := String(_press["node"])
		if mission.command_learn(nid):
			_flash[nid] = 0.8
			_play("ui_click")
		else:
			_play("ui_error")
	_press = {}
	_dragging = false


func _play(id: String) -> void:
	var p := "res://assets/audio/sfx/%s.ogg" % id
	if not ResourceLoader.exists(p):
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(p)
	a.volume_db = -8.0
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


## The next known skill (of the slot's kind) goes into the slot; past the last, it empties.
func _cycle_slot(slot: int) -> void:
	var st := mission.progress.story
	var heroes := HeroCatalog.get_default()
	var options: Array = [""]
	var known := st.known_skills().keys()
	known.sort()
	for sid: String in known:
		if bool(heroes.skills[sid].get("ultimate", false)) == (slot == 3):
			options.append(sid)
	var i := options.find(st.slots[slot])
	var next: String = options[(i + 1) % options.size()]
	mission.command_slot(slot, next)
