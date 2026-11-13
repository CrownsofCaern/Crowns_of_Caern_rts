class_name UnitPanel
extends Control
## Bottom panel: one card per unit type in the selection (portrait, count,
## health). Click a card to keep only that type; Shift-click drops it.
## With one unit selected it shows that unit's stats. Each card carries the best veteran rank
## in it (top right) and a small foot (bottom right of the portrait): click it to send those
## units home in retreat (F does it for the whole selection); it glows while they retreat.

const CARD := Vector2(64, 76)
const PAD := 6.0

var skirmish: Node
var _cards: Array = []  ## {rect, type_id, foot, ids}
var _font: Font
var frame: StyleBox  ## set by HudSkin (src/menu): the faction's framed panel


func _ready() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _summary() -> Array:
	var by_type := {}
	var order: Array = []
	for id in skirmish.selection:
		var u: SimUnit = skirmish.world.get_unit(id)
		if u == null:
			continue
		if not by_type.has(u.type_id):
			by_type[u.type_id] = {"n": 0, "hp": 0.0, "max": 0.0, "unit": u, "level": 0, "ids": [], "fleeing": 0}
			order.append(u.type_id)
		by_type[u.type_id]["n"] += 1
		by_type[u.type_id]["ids"].append(u.id)
		if u.order == SimUnit.Order.RETREAT:
			by_type[u.type_id]["fleeing"] += 1
		if not u.is_worker() and not u.is_hero():
			by_type[u.type_id]["level"] = maxi(int(by_type[u.type_id]["level"]), u.veteran)
		by_type[u.type_id]["hp"] += u.hp
		by_type[u.type_id]["max"] += u.max_hp
	order.sort_custom(func(a, b): return int(by_type[a]["unit"].def["tier"]) < int(by_type[b]["unit"].def["tier"]))
	var out: Array = []
	for t in order:
		out.append(by_type[t].merged({"type_id": t}))
	return out


func _draw() -> void:
	if skirmish == null or skirmish.world == null:
		return
	if frame != null:
		draw_style_box(frame, Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.04, 0.88))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.45, 0.3), false, 2.0)
	_cards.clear()
	var groups := _summary()
	if groups.is_empty():
		draw_string(_font, Vector2(14, 30), "Nothing selected. Drag a box around your units.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.8, 0.75, 0.65))
		return
	var x := PAD + 4.0
	for g in groups:
		if x + CARD.x > size.x - PAD:
			break
		var r := Rect2(Vector2(x, PAD + 4.0), CARD)
		var pr := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.x - 6))
		var foot := Rect2(pr.end - Vector2(FOOT, FOOT), Vector2(FOOT, FOOT))
		_cards.append({"rect": r, "type_id": g["type_id"], "foot": foot, "ids": g["ids"]})
		_draw_card(r, g)
		x += CARD.x + PAD
	if groups.size() == 1 and groups[0]["n"] == 1:
		_draw_stats(Vector2(x + 10.0, PAD + 22.0), groups[0]["unit"])
	else:
		var n := 0
		for g in groups:
			n += int(g["n"])
		HudArt.text(self, WbStyle.DISPLAY_FONT, Vector2(size.x - 160, size.y - 14), "%d selected" % n, 15,
			Color("#e8d8b0"), HORIZONTAL_ALIGNMENT_RIGHT, 140)


func _draw_card(r: Rect2, g: Dictionary) -> void:
	var hot := r.has_point(get_local_mouse_position())
	HudArt.bevel(self, r, HudArt.BRASS if hot else HudArt.BRASS_DIM, Color("#16120e"))
	var u: SimUnit = g["unit"]
	var pr := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.x - 6))
	if u.is_hero():
		var t := HudArt.portrait(u.hero.class_id)
		if t != null:
			draw_texture_rect(t, pr, false)
	else:
		HudArt.unit_portrait(self, skirmish.unit_texture(g["type_id"]), String(u.def["sprite"]), pr)
	var ratio: float = g["hp"] / g["max"]
	var bar := Rect2(r.position + Vector2(4, r.size.y - 10), Vector2(r.size.x - 8, 6))
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.9))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
		Color(0.3, 0.85, 0.3).lerp(Color(0.95, 0.25, 0.2), 1.0 - ratio))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 1.5)), Color(1, 1, 1, 0.25))
	if g["n"] > 1:
		HudArt.badge(self, WbStyle.DISPLAY_FONT, r.position + Vector2(12, 12), str(g["n"]), 10.0, Color("#6b5a3a"))
	if skirmish.world.catalog.get_unit(g["type_id"])["role"] == "worker":
		_draw_tool_badge(r.position + Vector2(r.size.x - 11, 11))
	elif int(g["level"]) >= 1:
		draw_rank(self, r.position + Vector2(r.size.x - 17, 4), int(g["level"]), 13.0)
	var foot := Rect2(pr.end - Vector2(FOOT, FOOT), Vector2(FOOT, FOOT))
	draw_foot(self, foot, int(g["fleeing"]) > 0, foot.has_point(get_local_mouse_position()))


## A small pick on a gold disc marks workers, whose portraits borrow a soldier's sprite.
func _draw_tool_badge(c: Vector2) -> void:
	draw_circle(c, 8.0, Color(0, 0, 0, 0.85))
	draw_circle(c, 7.0, Color(0.85, 0.7, 0.35))
	draw_line(c + Vector2(-3, 4), c + Vector2(3, -3), Color(0.3, 0.2, 0.1), 2.0)
	draw_line(c + Vector2(-1, -5), c + Vector2(5, -1), Color(0.25, 0.25, 0.28), 2.5)


func _draw_stats(p: Vector2, u: SimUnit) -> void:
	var d := u.def
	var title := WbStyle.DISPLAY_FONT
	var name := u.display_name()
	var sub := "Tier %d %s" % [int(d["tier"]), String(d["role"])]
	if not u.is_worker() and not u.is_hero():
		sub += ", %s (rank %d of 5)" % [u.rank_name(), u.veteran]
		if u.veteran < 5:
			var th: Array = skirmish.world.catalog.rules["veterans"]["thresholds"]
			var lo := float(th[u.veteran - 1])
			sub += ", %d%% to next" % int(100.0 * clampf((u.vet_xp - lo) / (float(th[u.veteran]) - lo), 0.0, 1.0))
	if u.order == SimUnit.Order.RETREAT:
		sub += ", retreating"
	if u.is_hero():
		if u.label != "":
			name = u.label
		sub = "Level %d %s, hero" % [u.hero.level, d["name"]]
	HudArt.text(self, title, p + Vector2(0, -2), name, 17, Color("#f0dfb4"))
	draw_string(_font, p + Vector2(title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 12, -3), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HudArt.TEXT_DIM)
	HudArt.bar(self, Rect2(p + Vector2(0, 10), Vector2(220, 14)), u.hp_ratio(), "health",
		"%d / %d" % [ceili(u.hp), int(u.max_hp)], _font, 11)
	var chips := [
		["attack", "%.0f %s / %.1f s" % [float(d["damage"]), u.damage_type(), float(d["attack_interval"])],
			"Damage per blow and its type, every %.1f s" % float(d["attack_interval"])],
		["defense", "%d/%d/%d%%" % [roundi(u.defense("melee") * 100.0), roundi(u.defense("ranged") * 100.0),
			roundi(u.defense("magic") * 100.0)], "Defence against melee / ranged / magic: share of damage shrugged off"],
		["siege", "%.0f vs buildings" % UnitCatalog.building_damage_of(d), "Damage per blow against buildings, walls and towers"],
		["move", "%d" % int(float(d["speed"]) * SimUnit.speed_scale), "Speed"],
		["range", "melee" if float(d["range"]) < 50.0 else str(int(d["range"])), "Range"],
	]
	var x := p.x + 236.0
	for c: Array in chips:
		var icon: Texture2D = HudArt.ui_icon(c[0]) if c[0] in ["attack", "defense", "move"] \
			else HudArt.tex("res://assets/items/longwatch_bow.png") if c[0] == "range" else HudArt.ui_icon("banner")
		if icon != null:
			draw_texture_rect(icon, Rect2(Vector2(x, p.y + 6), Vector2(22, 22)), false)
		draw_string(_font, Vector2(x + 25, p.y + 23), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e6dac0"))
		x += 25.0 + _font.get_string_size(c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
	var abil: Array = d["abilities"]
	var ax := p.x
	for a in abil:
		var t := String(a).replace("_", " ").capitalize()
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		var tr := Rect2(Vector2(ax, p.y + 34), Vector2(tw, 19))
		HudArt.bevel(self, tr, HudArt.BRASS_DIM, Color("#211a12"), 1.0)
		draw_string(_font, tr.position + Vector2(7, 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#d8c08a"))
		ax += tw + 6.0
	if abil.is_empty():
		draw_string(_font, p + Vector2(0, 48), "No special abilities", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudArt.TEXT_DIM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for c in _cards:
			if c["foot"].has_point(event.position):
				skirmish.retreat(c["ids"])
				break
			if c["rect"].has_point(event.position):
				skirmish.select_type(c["type_id"], event.shift_pressed)
				break
		accept_event()


const FOOT := 17.0
const RANK_OUTLINE := Color("#120d0b")
const RANK_BRASS := Color("#c9a45c")
const RANK_STAR := Color("#f2c14e")


## The retreat button: a small bare foot on a dark disc, gold while those units retreat.
static func draw_foot(canvas: CanvasItem, r: Rect2, active: bool, hot: bool) -> void:
	var c := r.get_center()
	var k := r.size.x / 17.0
	canvas.draw_circle(c, 8.5 * k, Color(0, 0, 0, 0.85))
	canvas.draw_circle(c, 7.5 * k, Color("#e8b84a") if active else (Color("#8a7a5a") if hot else Color("#4a3f30")))
	var ink := Color("#1a130c") if active or hot else Color("#d8c8a0")
	var sole := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		# A sole leaning right: wider at the ball, narrow heel.
		var w := 2.3 if sin(a) < 0.0 else 1.7
		sole.append(c + Vector2(0.8, 1.6) * k + Vector2(cos(a) * w, sin(a) * 3.4).rotated(0.25) * k)
	canvas.draw_colored_polygon(sole, ink)
	for t: Array in [[-1.6, -3.9, 1.05], [0.2, -4.6, 0.95], [1.8, -4.3, 0.85], [3.1, -3.4, 0.75]]:
		canvas.draw_circle(c + Vector2(float(t[0]), float(t[1])) * k, float(t[2]) * k, ink)


## Veteran rank like the main game's: one to three chevrons, a gem at 4, a star at 5.
static func draw_rank(canvas: CanvasItem, at: Vector2, level: int, px: float) -> void:
	level = clampi(level, 1, 5)
	var color := RANK_STAR if level >= 5 else RANK_BRASS
	if level <= 3:
		var h := px * 0.32
		var step := px * 0.3
		var top := (px - (h + step * float(level - 1))) * 0.5
		for i in level:
			var y := top + step * float(i)
			var pts := PackedVector2Array([at + Vector2(0, y + h), at + Vector2(px * 0.5, y), at + Vector2(px, y + h)])
			canvas.draw_polyline(pts, RANK_OUTLINE, maxf(2.0, px * 0.17) + 2.5, true)
			canvas.draw_polyline(pts, color, maxf(2.0, px * 0.17), true)
		return
	var c := at + Vector2(px, px) * 0.5
	var pts := PackedVector2Array()
	if level == 4:
		pts = PackedVector2Array([c + Vector2(0, -px * 0.5), c + Vector2(px * 0.38, 0), c + Vector2(0, px * 0.5), c + Vector2(-px * 0.38, 0)])
	else:
		for i in 10:
			var rr := px * (0.54 if i % 2 == 0 else 0.23)
			var a := -PI * 0.5 + PI * float(i) / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
	var ring := pts.duplicate()
	ring.append(pts[0])
	canvas.draw_colored_polygon(pts, color)
	canvas.draw_polyline(ring, RANK_OUTLINE, 1.5, true)
