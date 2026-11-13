class_name SiteMarks
extends RefCounted
## Draws the hero sites (lairs, shrines, merchants) on any CanvasItem: a ring, a sign and a
## label with what the site offers. The flat 2D map and the 3D view's overlay share it;
## the minimap uses draw_minimap. Sites show once the player has explored them.

const LAIR_COL := Color(0.85, 0.22, 0.18)
const CLEARED_COL := Color(0.55, 0.5, 0.45)
const SHRINE_COL := Color(0.45, 0.65, 1.0)
const MERCHANT_COL := Color(0.95, 0.8, 0.35)


static func color(s: Dictionary) -> Color:
	match s["kind"]:
		"lair":
			return CLEARED_COL if s["cleared"] else LAIR_COL
		"shrine":
			return SHRINE_COL if float(s["ready_in"]) <= 0.0 else CLEARED_COL
		_:
			return MERCHANT_COL


static func label(w: SimWorld, s: Dictionary) -> String:
	match s["kind"]:
		"lair":
			if s["cleared"]:
				return "%s (cleared)" % w.sites.title(s)
			return "%s %s: %d guards" % [w.sites.title(s), "★".repeat(int(s["tier"])), w.sites.guards_alive(s)]
		"shrine":
			var rest := float(s["ready_in"])
			return w.sites.title(s) if rest <= 0.0 else "%s (%d s)" % [w.sites.title(s), ceili(rest)]
		_:
			return "%s: %d wares" % [w.sites.title(s), s["stock"].size()]


## to_screen: Callable(Vector2 sim position) -> Vector2 screen position, or null to skip.
## explored: Callable(Vector2) -> bool. scale: screen pixels per sim pixel near the site.
static func draw_all(ci: CanvasItem, w: SimWorld, to_screen: Callable, explored: Callable, scale: float, t: float) -> void:
	if w == null or w.sites.all.is_empty():
		return
	var font := ThemeDB.fallback_font
	var radius := {"lair": float(w.sites.d["lair"]["radius"]), "shrine": float(w.sites.d["shrine"]["radius"]),
		"merchant": float(w.sites.d["merchant"]["radius"])}
	for s in w.sites.all:
		if not explored.call(s["pos"]):
			continue
		var sp: Variant = to_screen.call(s["pos"])
		if sp == null:
			continue
		var p: Vector2 = sp
		var col := color(s)
		var r: float = radius[s["kind"]] * scale
		ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		var pulse := 0.5 + 0.5 * sin(t * 2.0 + float(s["id"]))
		ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(col, 0.35 + 0.25 * pulse), 2.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_sign(ci, p + Vector2(0, -r * 0.6 - 18), s, col)
		var text := label(w, s)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var at := p + Vector2(-tw * 0.5, -r * 0.6 - 30)
		ci.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.9))
		ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.2))


static func _sign(ci: CanvasItem, p: Vector2, s: Dictionary, col: Color) -> void:
	var dark := Color(0, 0, 0, 0.85)
	match s["kind"]:
		"lair":  # a fang
			var f := PackedVector2Array([p + Vector2(-6, -6), p + Vector2(6, -6), p + Vector2(0, 8)])
			ci.draw_colored_polygon(f, col)
			ci.draw_polyline(f + PackedVector2Array([f[0]]), dark, 1.5)
		"shrine":  # a flame
			ci.draw_circle(p + Vector2(0, 2), 5.0, col)
			var f := PackedVector2Array([p + Vector2(-5, 1), p + Vector2(0, -9), p + Vector2(5, 1)])
			ci.draw_colored_polygon(f, col)
		_:  # a coin
			ci.draw_circle(p, 6.5, dark)
			ci.draw_circle(p, 5.5, col)
			ci.draw_circle(p, 2.0, col.darkened(0.4))


static func draw_minimap(ci: CanvasItem, w: SimWorld, to_map: Callable, explored: Callable) -> void:
	for s in w.sites.all:
		if not explored.call(s["pos"]):
			continue
		var m: Vector2 = to_map.call(s["pos"])
		ci.draw_circle(m, 3.0, Color(0, 0, 0, 0.85))
		ci.draw_circle(m, 2.2, color(s))
