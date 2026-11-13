class_name BuildPanel
extends PanelContainer
## Context panel above the building emblems (BuildingBar) over the minimap: training for a
## dwelling, upgrades for a settlement, and so on. Rebuilt only when its content changes. It is
## only as wide as its content and grows upward from its bottom edge, so it never covers the emblems.

var skirmish: Node
var _key: String = ""
var _box: VBoxContainer
## Queue icons (an entry with "queue"): the grey veils over them, first = the unit in training.
var _veils: Array[ColorRect] = []
const QUEUE_ICON := 44.0
const MIN_WIDTH := 150.0
const HEADER_COLOR := Color(0.72, 0.62, 0.45)


## A small gold arrow pointing up: marks an upgrade icon.
class UpArrow extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, h * 0.55), Vector2(w * 0.68, h * 0.55),
			Vector2(w * 0.68, h), Vector2(w * 0.32, h), Vector2(w * 0.32, h * 0.55), Vector2(0, h * 0.55)])
		draw_colored_polygon(pts, Color(0.98, 0.8, 0.3))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.1, 0.06, 0.02), 1.5, true)


func _ready() -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.05, 0.04, 0.88)
	st.border_color = Color(0.55, 0.45, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	add_child(_box)
	mouse_filter = Control.MOUSE_FILTER_STOP


## entries: [{"text", "action": Callable or null, "enabled": bool}]; title first.
## Other entry shapes: {"header": String} a small section heading over a thin line;
## {"queue": [...], "tooltip"} queue icons; {"icons": [...], "side": bool} icon buttons (see _icon_row).
## title_tip: tooltip on the title (the place for explanations that would clutter the panel).
func show_entries(key: String, title: String, entries: Array, title_tip: String = "") -> void:
	visible = true
	if key == _key:
		return
	_key = key
	_veils.clear()
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	if title_tip != "":
		t.tooltip_text = title_tip
		t.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.add_child(t)
	for e: Dictionary in entries:
		if e.has("header"):
			_box.add_child(_header(String(e["header"])))
			continue
		if e.has("queue"):
			_box.add_child(_queue_row(e["queue"], String(e.get("tooltip", ""))))
			continue
		if e.has("icons"):
			_box.add_child(_icon_row(e["icons"], bool(e.get("side", false))))
			continue
		if e.get("action") == null:
			var l := Label.new()
			l.text = e["text"]
			l.add_theme_font_size_override("font_size", 13)
			_box.add_child(l)
			continue
		var b := Button.new()
		b.text = e["text"]
		b.disabled = not e.get("enabled", true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		if e.has("tooltip"):
			b.tooltip_text = e["tooltip"]
		var act: Callable = e["action"]
		b.pressed.connect(func() -> void: act.call())
		_box.add_child(b)
	_fit.call_deferred()


## A small section heading with a thin rule under it (e.g. "Units", "Upgrades").
func _header(text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", HEADER_COLOR)
	v.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(HEADER_COLOR, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	return v


## A row of unit icons, one per queued unit; a grey veil covers the part still to train.
## queue: [{"texture": Texture2D or null, "name": String}]; first_tip is added to the first
## icon's tooltip (e.g. whether it is training or waiting for a worker).
func _queue_row(queue: Array, first_tip: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for qi in queue.size():
		var q: Dictionary = queue[qi]
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(QUEUE_ICON, QUEUE_ICON)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.13, 0.1, 0.08)
		st.border_color = Color(0.55, 0.45, 0.3)
		st.set_border_width_all(1)
		frame.add_theme_stylebox_override("panel", st)
		frame.tooltip_text = String(q.get("name", ""))
		if qi == 0 and first_tip != "":
			frame.tooltip_text += "\n" + first_tip
		var tex: Texture2D = q.get("texture")
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(icon)
		var veil := ColorRect.new()
		veil.color = Color(0.05, 0.05, 0.05, 0.62)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.position = Vector2.ZERO
		veil.size = Vector2(QUEUE_ICON, QUEUE_ICON)
		frame.add_child(veil)
		_veils.append(veil)
		row.add_child(frame)
	return row


## A row of square icon buttons with a small badge (e.g. the level they buy) and the cost in
## resource icons under each (side: next to each, as a small column); every word of explanation
## lives in the tooltip.
## icons: [{"texture", "badge", "cost": {resource: n}, "enabled", "tooltip", "action", "progress" (0..1, optional),
## "arrow" (bool, optional: a gold up-arrow in the corner, for upgrades)}].
func _icon_row(icons: Array, side: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10 if side else 6)
	for ic: Dictionary in icons:
		var col: BoxContainer = HBoxContainer.new() if side else VBoxContainer.new()
		col.add_theme_constant_override("separation", 3 if side else 1)
		col.tooltip_text = String(ic.get("tooltip", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(QUEUE_ICON, QUEUE_ICON)
		# The picture fills the button (a themed button's content margins would shrink b.icon to a speck).
		var pic := TextureRect.new()
		pic.texture = ic.get("texture")
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = 2
		pic.offset_top = 2
		pic.offset_right = -2
		pic.offset_bottom = -2
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pic)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ic.get("enabled", true) or ic.get("action") == null
		b.tooltip_text = col.tooltip_text
		if b.disabled:
			pic.modulate = Color(0.5, 0.5, 0.5, 0.85)
		if ic.get("action") != null:
			var act: Callable = ic["action"]
			b.pressed.connect(func() -> void: act.call())
		var badge := Label.new()
		badge.text = String(ic.get("badge", ""))
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 4)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -3
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
		if ic.has("progress"):
			var veil := ColorRect.new()
			veil.color = Color(0.05, 0.05, 0.05, 0.62)
			veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			veil.size = Vector2(QUEUE_ICON, QUEUE_ICON * (1.0 - clampf(float(ic["progress"]), 0.0, 1.0)))
			b.add_child(veil)
		if ic.get("arrow", false):
			var arrow := UpArrow.new()
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			arrow.position = Vector2(QUEUE_ICON - 15, 2)
			arrow.size = Vector2(13, 15)
			b.add_child(arrow)
		col.add_child(b)
		var cost: Dictionary = ic.get("cost", {})
		var cost_box: BoxContainer = col
		if side:
			cost_box = VBoxContainer.new()
			cost_box.add_theme_constant_override("separation", 0)
			cost_box.alignment = BoxContainer.ALIGNMENT_CENTER
			cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(cost_box)
		for r in cost:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 2)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tex := WbStyle.resource_icon(String(r))
			if tex != null:
				line.add_child(WbStyle.icon(tex, Vector2(12, 12)))
			var n := Label.new()
			n.text = str(int(cost[r]))
			n.add_theme_font_size_override("font_size", 11)
			line.add_child(n)
			cost_box.add_child(line)
		row.add_child(col)
	return row


## Progress (0..1, trained so far) of each queued unit, in queue order: the veil shrinks
## from the bottom up as the unit trains. Cheap; call it every frame.
func set_queue_progress(progress: Array) -> void:
	for i in _veils.size():
		var k := clampf(float(progress[i]) if i < progress.size() else 0.0, 0.0, 1.0)
		_veils[i].size = Vector2(QUEUE_ICON, QUEUE_ICON * (1.0 - k))


## Grow upward from the bottom edge, whatever the content height.
func _fit() -> void:
	var m := get_combined_minimum_size()
	offset_top = offset_bottom - m.y
	offset_left = offset_right - maxf(m.x + 8.0, MIN_WIDTH)  # a little slack: the painted frame overlaps its margin


func hide_panel() -> void:
	visible = false
	_key = ""
