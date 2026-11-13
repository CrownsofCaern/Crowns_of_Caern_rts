class_name GroupBar
extends Control
## Control groups (Ctrl + 1-9) as a row of portraits in the top right corner, left of the ? button:
## the group's strongest unit, its number and how many of its units are still alive.
## Click a portrait to select that group (again quickly: the camera looks at it), like pressing its key.

const CARD := Vector2(46, 52)
const GAP := 5.0

var skirmish: Node
var _cards: Array = []  ## [{rect, group}]
var _font: Font


func _ready() -> void:
	_font = WbStyle.BODY_FONT
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	var n := shown_groups().size()
	visible = n > 0
	# The row grows to the left from its right edge and is only as wide as its cards,
	# so clicks beside it still reach the map.
	offset_left = offset_right - maxf(n * (CARD.x + GAP) - GAP, 0.0)
	queue_redraw()


## The group numbers that have a living unit, in key order.
func shown_groups() -> Array:
	var out: Array = []
	if skirmish == null or skirmish.world == null:
		return out
	for g in range(1, 10):
		if not alive_units(skirmish.world, skirmish.groups.get(g, [])).is_empty():
			out.append(g)
	return out


## The group's units that are still on the field.
static func alive_units(world: SimWorld, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var u := world.get_unit(id)
		if u != null:
			out.append(u)
	return out


## The unit whose portrait stands for the group: a hero first, then the highest tier,
## then the most health; null for an empty group.
static func strongest(units: Array) -> SimUnit:
	var best: SimUnit = null
	for u: SimUnit in units:
		if best == null or _rank(u) > _rank(best):
			best = u
	return best


static func _rank(u: SimUnit) -> Vector3:
	return Vector3(1.0 if u.is_hero() else 0.0, float(u.def.get("tier", 0)), u.max_hp)


func _cards_rects(gs: Array) -> Array:
	var out: Array = []
	var x := size.x - (gs.size() * (CARD.x + GAP) - GAP)
	for i in gs.size():
		out.append({"rect": Rect2(Vector2(x + i * (CARD.x + GAP), 0.0), CARD), "group": gs[i]})
	return out


func _draw() -> void:
	if skirmish == null or skirmish.world == null:
		return
	_cards = _cards_rects(shown_groups())
	var mouse := get_local_mouse_position()
	var sel: Array = skirmish.selection
	for c: Dictionary in _cards:
		var r: Rect2 = c["rect"]
		var g: int = c["group"]
		var units := alive_units(skirmish.world, skirmish.groups[g])
		var hot := r.has_point(mouse)
		var picked := not sel.is_empty() and _same(units, sel)
		HudArt.bevel(self, r, HudArt.BRASS if (hot or picked) else HudArt.BRASS_DIM, Color("#16120e"), 1.5)
		var pr := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.x - 6))
		draw_portrait(self, skirmish, strongest(units), pr)
		if picked:
			draw_rect(pr, Color(1, 0.9, 0.6, 0.12))
		if hot:
			draw_rect(pr, Color(1, 0.95, 0.75, 0.12))
		# Group number top left, unit count along the bottom.
		HudArt.text(self, WbStyle.DISPLAY_FONT, r.position + Vector2(5, 15), str(g), 15, Color("#f3e2b0"))
		HudArt.text(self, _font, Vector2(r.position.x, r.end.y - 3), str(units.size()), 12, HudArt.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5)
		if hot:
			var bounds := Rect2(-get_global_rect().position, get_viewport_rect().size)
			HudArt.tooltip(self, _font, Vector2(r.position.x - 150.0, r.end.y + 6.0), bounds,
				["Group %d: %d unit%s" % [g, units.size(), "" if units.size() == 1 else "s"],
				"Click to select (key %d)" % g, "~Click twice to look at them"], Color("#f0dfb4"), null, 220.0)


static func _same(units: Array, sel: Array) -> bool:
	if units.size() != sel.size():
		return false
	for u: SimUnit in units:
		if not sel.has(u.id):
			return false
	return true


## The unit's face: a hero's painted portrait, otherwise the upper part of its sprite (as in the unit panel).
static func draw_portrait(ci: CanvasItem, sk: Node, u: SimUnit, r: Rect2) -> void:
	if u == null:
		return
	if u.is_hero():
		var t := HudArt.portrait(u.hero.class_id)
		if t != null:
			ci.draw_texture_rect(t, r, false)
			return
	var tex: Texture2D = sk.unit_texture(u.type_id)
	if tex != null:
		ci.draw_texture_rect_region(tex, r, Rect2(24, 14, 80, 80))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for c: Dictionary in _cards:
		if (c["rect"] as Rect2).has_point(event.position):
			skirmish.recall_group(int(c["group"]))
			accept_event()
			return
