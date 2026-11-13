class_name LootMarks
extends RefCounted
## Draws the loot lying on the map (a glinting gem in the item's rarity colour, a flask for a
## potion) on any CanvasItem: the flat 2D map and the 3D view's overlay share it.
## Items show their inventory icon over a glow in their rarity colour.

static var _icons: Dictionary = {}


## The item's inventory icon (cached), or null when it has none.
static func icon(item: Dictionary) -> Texture2D:
	var path := ItemCatalog.icon_path(item)
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]


## to_screen: Callable(Vector2 sim position) -> Vector2 screen position, or null to skip.
static func draw_all(ci: CanvasItem, w: SimWorld, to_screen: Callable, t: float) -> void:
	if w == null or w.heroes.gear == null:
		return
	var font := ThemeDB.fallback_font
	var icat := w.heroes.gear.icat
	var mouse := ci.get_local_mouse_position()
	for g in w.heroes.gear.ground:
		var sp: Variant = to_screen.call(g["pos"])
		if sp == null:
			continue
		var p: Vector2 = sp
		var col := Color(0.85, 0.25, 0.2) if g.get("potion", "") == "health" else Color(0.3, 0.45, 0.95)
		if g.has("item"):
			col = icat.color(g["item"])
		var pulse := 0.6 + 0.4 * sin(t * 4.0 + float(g["uid"]))
		ci.draw_circle(p, 11.0, Color(col.r, col.g, col.b, 0.18 * pulse))
		var tex: Texture2D = icon(g["item"]) if g.has("item") else null
		if tex != null:
			ci.draw_circle(p, 9.0, Color(col.r, col.g, col.b, 0.35 * pulse))
			ci.draw_texture_rect(tex, Rect2(p - Vector2(12, 12), Vector2(24, 24)), false)
		elif g.has("item"):
			var d := PackedVector2Array([p + Vector2(0, -8), p + Vector2(6, 0), p + Vector2(0, 8), p + Vector2(-6, 0)])
			ci.draw_colored_polygon(d, col)
			ci.draw_polyline(d + PackedVector2Array([d[0]]), Color(0, 0, 0, 0.9), 1.5)
		else:
			ci.draw_circle(p + Vector2(0, 2), 5.0, col)
			ci.draw_rect(Rect2(p + Vector2(-2, -7), Vector2(4, 5)), Color(0.75, 0.7, 0.6))
		if g.has("item") and (p.distance_to(mouse) < 14.0 or icat.rarities[g["item"]["rarity"]]["rank"] >= 2):
			var name: String = g["item"]["name"]
			var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			ci.draw_string(font, p + Vector2(-tw * 0.5 + 1, -12), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0))
			ci.draw_string(font, p + Vector2(-tw * 0.5, -13), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
