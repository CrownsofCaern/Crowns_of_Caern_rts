class_name BuildRing
extends Control
## The workers' build menu as a ring: each building's 2D sprite in a round
## medallion around the middle of the screen, its name and cost above it, and
## its description as a tooltip. Greyed out with a status line (built, needs
## hall II, too dear) when it cannot be built now. Click to start placing.
##
## options: [{"id", "sprite" (res path), "name", "cost" {resource: n},
##            "enabled", "status", "tooltip", "action" Callable}]

const RADIUS := 230.0
const MEDALLION := 92.0
const ITEM := Vector2(150, 150)

var _key: String = ""
var _items: Array = []  ## Button per option, in ring order
var _title: Label
var _hint: Label
var _resource_names: Dictionary = {}


func _init() -> void:
	name = "BuildRing"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the medallions take clicks
	visible = false


func _ready() -> void:
	theme = WbStyle.menu_theme()
	_title = WbStyle.heading("Build", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_hint = WbStyle.label("Click a building, then the ground\nB closes · Esc cancels", 13, WbStyle.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_child(_hint)
	resized.connect(_layout)


## resource_names: id -> display name, for the cost tooltips.
func show_options(key: String, options: Array, resource_names: Dictionary = {}) -> void:
	visible = true
	if key == _key:
		return
	_key = key
	_resource_names = resource_names
	for b in _items:
		remove_child(b)
		b.queue_free()
	_items.clear()
	for o: Dictionary in options:
		_items.append(_make_item(o))
	_layout()


func hide_ring() -> void:
	visible = false
	_key = ""


func item_count() -> int:
	return _items.size()


func item(i: int) -> Button:
	return _items[i]


func _make_item(o: Dictionary) -> Button:
	var enabled: bool = o.get("enabled", true)
	var b := Button.new()
	b.name = "Build_" + String(o.get("id", ""))
	b.custom_minimum_size = ITEM
	b.size = ITEM
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = String(o.get("tooltip", ""))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var act: Variant = o.get("action")
	if act is Callable:
		b.pressed.connect(func() -> void: (act as Callable).call())
	b.set_meta("option", o)
	b.draw.connect(_draw_item.bind(b))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	add_child(b)
	return b


func _layout() -> void:
	var c := size * 0.5 + Vector2(0, -20)
	var n := _items.size()
	for i in n:
		# Start at the top and go clockwise.
		var a := -PI * 0.5 + TAU * float(i) / float(maxi(n, 1))
		var p := c + Vector2(cos(a), sin(a)) * RADIUS
		_items[i].position = p - ITEM * 0.5
	if _title != null:
		_title.size = Vector2(240, 36)
		_title.position = c - Vector2(120, 34)
		_hint.size = Vector2(260, 40)
		_hint.position = c - Vector2(130, -4)
	queue_redraw()


func _draw() -> void:
	if _items.is_empty():
		return
	var c := size * 0.5 + Vector2(0, -20)
	# A dark disc behind the ring and a brass circle through the medallions.
	draw_circle(c, RADIUS + MEDALLION * 0.75, Color(0.03, 0.02, 0.02, 0.55))
	draw_arc(c, RADIUS, 0.0, TAU, 96, Color("#826c45aa"), 2.0, true)
	draw_circle(c, 92.0, Color(0.06, 0.05, 0.04, 0.85))
	draw_arc(c, 92.0, 0.0, TAU, 64, WbStyle.BRASS.darkened(0.2), 2.0, true)


func _draw_item(b: Button) -> void:
	var o: Dictionary = b.get_meta("option")
	var enabled: bool = not b.disabled
	var hover := enabled and b.is_hovered()
	var centre := Vector2(ITEM.x * 0.5, ITEM.y * 0.5 + 22.0)
	var r := MEDALLION * 0.5
	# Medallion: dark face, brass rim (bright on hover).
	draw_circle_on(b, centre, r + 3.0, Color(0, 0, 0, 0.8))
	draw_circle_on(b, centre, r, Color("#2a221a") if enabled else Color("#1a1714"))
	var rim := Color("#f0d488") if hover else (WbStyle.BRASS if enabled else Color("#5a5040"))
	b.draw_arc(centre, r, 0.0, TAU, 48, rim, 3.0 if hover else 2.0, true)
	var tex := WbStyle.texture(String(o.get("sprite", "")))
	if tex != null:
		var s := (r * 1.75) / maxf(tex.get_width(), tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * s
		var tint := Color.WHITE if enabled else Color(0.45, 0.42, 0.4)
		b.draw_texture_rect(tex, Rect2(centre - sz * 0.5 + Vector2(0, -3), sz), false, tint)
	var font := WbStyle.DISPLAY_FONT
	var body := WbStyle.BODY_FONT
	# Name and cost above the medallion.
	var name_col := Color("#fff0c8") if hover else (Color("#eadcba") if enabled else Color("#8a806e"))
	_text(b, font, String(o.get("name", "")), Vector2(ITEM.x * 0.5, centre.y - r - 26.0), 14, name_col)
	var cost: Dictionary = o.get("cost", {})
	var status := String(o.get("status", ""))
	if status != "":
		_text(b, body, status, Vector2(ITEM.x * 0.5, centre.y - r - 9.0), 12, WbStyle.WARN if enabled else Color("#a89a7c"))
	elif not cost.is_empty():
		_cost_row(b, cost, Vector2(ITEM.x * 0.5, centre.y - r - 9.0), enabled)


func _cost_row(b: Button, cost: Dictionary, at: Vector2, enabled: bool) -> void:
	var body := WbStyle.BODY_FONT
	var parts: Array = []
	var w := 0.0
	for res: String in cost:
		var t := str(int(cost[res]))
		var tw := body.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		parts.append({"tex": WbStyle.resource_icon(res), "text": t, "w": tw})
		w += 16.0 + 2.0 + tw + 8.0
	w -= 8.0
	var x := at.x - w * 0.5
	var col := WbStyle.TEXT if enabled else Color("#8a806e")
	for p: Dictionary in parts:
		if p["tex"] != null:
			b.draw_texture_rect(p["tex"], Rect2(Vector2(x, at.y - 12.0), Vector2(16, 16)), false,
				Color.WHITE if enabled else Color(0.6, 0.6, 0.6))
		x += 18.0
		b.draw_string_outline(body, Vector2(x, at.y), p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
		b.draw_string(body, Vector2(x, at.y), p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		x += float(p["w"]) + 8.0


static func draw_circle_on(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(p, r, col)


static func _text(ci: CanvasItem, font: Font, text: String, centre_baseline: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := centre_baseline - Vector2(w * 0.5, 0)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
