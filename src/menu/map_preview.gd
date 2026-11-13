class_name MapPreview
extends Control
## A small parchment-style picture of a skirmish map: ground, rock, water and
## forest per cell, roads, bridges, lairs and shrines, each sector's centre (sized by its
## settlement) and both homes in their team colours. Built from the headless
## SimWorld, so what you see is the map you will play.

const KIND_COLORS := {
	NavGrid.Kind.GROUND: Color("#5c5233"),
	NavGrid.Kind.ROCK: Color("#2b2620"),
	NavGrid.Kind.WATER: Color("#24414a"),
	NavGrid.Kind.BUILDING: Color("#5c5233"),
	NavGrid.Kind.FOREST: Color("#33401f"),
}
const SETTLEMENT_RADIUS := {"waystone": 3.0, "farmstead": 4.0, "hamlet": 5.0, "village": 6.0, "town": 7.0, "city": 8.0}

var _tex: ImageTexture
var _world: SimWorld
var _map_px := Vector2.ONE  ## world pixels


func _init() -> void:
	custom_minimum_size = Vector2(300, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows the map a skirmish with this seed, these factions and this map template would get.
func show_map(seed_value: int, factions: Array, template: String = "") -> void:
	_world = SkirmishScenario.build_skirmish(seed_value, factions, template)
	_map_px = _world.nav.world_size()
	_tex = ImageTexture.create_from_image(terrain_image(_world))
	queue_redraw()


func world() -> SimWorld:
	return _world


static func terrain_image(w: SimWorld) -> Image:
	var nav := w.nav
	var img := Image.create(nav.width, nav.height, false, Image.FORMAT_RGB8)
	for y in nav.height:
		for x in nav.width:
			var c: Color = KIND_COLORS.get(nav.kind_at(Vector2i(x, y)), Color("#5c5233"))
			# A faint grain so it reads as a drawn map, stable per cell.
			var h := absi((x * 73856093) ^ (y * 19349663)) % 7
			img.set_pixel(x, y, c.lightened(float(h) * 0.012))
	return img


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#15110f"))
	if _tex == null or _world == null:
		return
	# Keep the map's aspect, centred.
	var scale := minf(size.x / _map_px.x, size.y / _map_px.y)
	var m := Rect2((size - _map_px * scale) * 0.5, _map_px * scale)
	draw_texture_rect(_tex, m, false)
	var eco := _world.economy
	# Roads, bridges and sites from the generator.
	var info: Dictionary = _world.map_info
	for rd in info.get("roads", []):
		draw_line(m.position + (rd[0] as Vector2) * scale, m.position + (rd[1] as Vector2) * scale, Color("#c9a24a88"), 1.5)
	for br in info.get("bridges", []):
		draw_line(m.position + (br[0] as Vector2) * scale, m.position + (br[1] as Vector2) * scale, Color("#d08a3a"), 3.0)
	for l in info.get("lairs", []):
		var lp: Vector2 = m.position + (l[0] as Vector2) * scale
		var lr := 2.0 + float(l[1]) * 1.2
		draw_circle(lp, lr + 1.0, Color(0, 0, 0, 0.8))
		draw_circle(lp, lr, Color("#b3261e"))
	for sp in info.get("shrines", []):
		draw_circle(m.position + (sp as Vector2) * scale, 2.5, Color("#7fd6ff"))
	for sp in info.get("merchants", []):
		draw_circle(m.position + (sp as Vector2) * scale, 2.5, Color("#e9b0ff"))
	var font := WbStyle.BODY_FONT
	for s: Sector in eco.sectors:
		var p := m.position + s.center * scale
		var rad: float = SETTLEMENT_RADIUS.get(s.size, 4.0)
		var col := Color("#e0c27a")
		if s.home_of >= 0 and s.home_of < SkirmishSetup.PLAYER_COLORS.size():
			col = SkirmishSetup.PLAYER_COLORS[s.home_of]
		draw_circle(p, rad + 1.5, Color(0, 0, 0, 0.8))
		if s.size == "waystone":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -rad), p + Vector2(rad, 0),
				p + Vector2(0, rad), p + Vector2(-rad, 0)]), col.darkened(0.2))
		else:
			draw_circle(p, rad, col)
		var name: String = String(eco.settlement(s).get("name", s.size))
		if s.home_of >= 0:
			name = "You" if s.home_of == 0 else String(SkirmishSetup.PLAYER_NAMES[s.home_of % SkirmishSetup.PLAYER_NAMES.size()])
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tp := p + Vector2(-tw * 0.5, rad + 12)
		draw_string_outline(font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
		draw_string(font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#eadfc4"))
	draw_rect(m, Color("#826c45"), false, 2.0)
