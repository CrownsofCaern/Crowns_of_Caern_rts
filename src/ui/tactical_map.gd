class_name TacticalMap
extends RefCounted
## The tactical map's overlay (Tab, F3 or the map button by the ?): the flat 2D view draws
## the old F3 sprites (Skirmish._draw_world), and this adds, over the fog, what a commander
## needs at a glance: every sector's border, each settlement's name and the resource piles
## in its sector. Text and icons keep their screen size at any zoom. What the fog hides
## stays hidden: who holds a settlement that was never explored.

const BORDER := Color(0.92, 0.85, 0.66, 0.45)
const BORDER_SHADOW := Color(0.05, 0.03, 0.02, 0.3)
const DARK := Color(0.04, 0.03, 0.02, 0.92)
## Frame colours of the resource icons.
const RES_COLORS := {"wood": Color(0.62, 0.42, 0.22), "ore": Color(0.62, 0.62, 0.68),
	"gems": Color(0.4, 0.9, 0.6), "crystal": Color(0.75, 0.85, 1.0), "mercury": Color(0.85, 0.85, 0.92),
	"sulfur": Color(0.95, 0.85, 0.3), "gold": Color(1.0, 0.8, 0.25)}

var world: SimWorld
## Sector id -> {resource: number of piles}, keys sorted so the row never reshuffles.
var resources: Dictionary = {}
var _icons: Dictionary = {}  ## resource -> Texture2D or null


func rebuild(w: SimWorld) -> void:
	world = w
	resources = sector_resources(w)


## Sector id -> {resource: piles}, for every sector (empty when it has none).
static func sector_resources(w: SimWorld) -> Dictionary:
	var out := {}
	for sec in w.economy.sectors:
		out[sec.id] = {}
	for n in w.economy.nodes:
		var d: Dictionary = out.get(n.sector, {})
		d[n.resource] = int(d.get(n.resource, 0)) + 1
		out[n.sector] = d
	for id in out:
		var sorted := {}
		var keys: Array = out[id].keys()
		keys.sort()
		for k in keys:
			sorted[k] = out[id][k]
		out[id] = sorted
	return out


## The owner this player may know of: -1 (neutral look) for a settlement never explored.
static func known_owner(sk: Node, sec: Sector) -> int:
	if sec.owner == sk.PLAYER or sk.has_explored(sec.center):
		return sec.owner
	return -1


func _icon(res: String) -> Texture2D:
	if not _icons.has(res):
		var tex := WbStyle.resource_icon(res)  # the resource bar's icons
		if tex == null and ResourceLoader.exists("res://assets/resources/%s.png" % res):
			tex = load("res://assets/resources/%s.png" % res)
		_icons[res] = tex
	return _icons[res]


## Draws the overlay onto ci (the skirmish's 2D layer, in sim pixels), after the fog.
func draw_overlay(sk: Node, ci: CanvasItem) -> void:
	if world == null:
		return
	var px := 1.0 / float(sk.cam.zoom.x)  # one screen pixel in sim pixels
	var lines: PackedVector2Array = sk._border_lines
	if lines.size() > 1:
		ci.draw_multiline(lines, BORDER_SHADOW, 2.5 * px)
		ci.draw_multiline(lines, BORDER, 1.0 * px)
	ci.draw_rect(Rect2(Vector2.ZERO, world.nav.world_size()), BORDER, false, 1.5 * px)
	for sec in world.economy.sectors:
		_draw_sector(sk, ci, sec, px)


## The settlement's name (the hall's for a known capital) and its sector's resources.
func _draw_sector(sk: Node, ci: CanvasItem, sec: Sector, px: float) -> void:
	var eco := world.economy
	var font := ThemeDB.fallback_font
	var o := known_owner(sk, sec)
	var title: String = eco.settlement(sec)["name"] if sec.label == "" else sec.label
	if sec.home_of >= 0 and o >= 0 and o == sec.home_of:
		var hk := String(eco.e["buildings"][eco.player(o).faction]["hall"])
		title = "%s (%s)" % [world.catalog.building_names.get(hk, title), Skirmish.ROMAN[eco.player(o).hall_level - 1]]
	var col: Color = Color(0.93, 0.89, 0.76) if o < 0 else Skirmish.TEAM_COLORS[o].lightened(0.35)
	if sec.id == sk.selected_sector:
		col = Skirmish.SELECT_COLOR
	var at := sec.center + Vector2(0, maxf(16.0 * px, 30.0 * float(sk.sprite_k())))  # under the sprite
	_label(ci, font, at, title, 14, px, col)
	var res: Dictionary = resources.get(sec.id, {})
	if res.is_empty():
		return
	var icon := 18.0 * px
	var step := icon + 22.0 * px
	var x0 := sec.center.x - step * res.size() * 0.5 + 2.0 * px
	var y := at.y + 5.0 * px
	var i := 0
	for k: String in res:
		var q := Vector2(x0 + step * i, y)
		var usable := eco.uses(sk.PLAYER, k)
		var frame: Color = RES_COLORS.get(k, Color.WHITE)
		ci.draw_rect(Rect2(q, Vector2(icon, icon)).grow(1.5 * px), DARK)
		ci.draw_rect(Rect2(q, Vector2(icon, icon)), Color(frame.darkened(0.6), 0.9))
		var tex := _icon(k)
		if tex != null:
			ci.draw_texture_rect(tex, Rect2(q, Vector2(icon, icon)), false,
				Color.WHITE if usable else Color(0.5, 0.5, 0.5, 0.8))
		_text(ci, font, q + Vector2(icon + 2.0 * px, icon * 0.8), "x%d" % int(res[k]), 12, px,
			Color(0.95, 0.92, 0.82) if usable else Color(0.65, 0.63, 0.58))
		i += 1


## Centred text with a shadow, fs screen pixels tall at any zoom.
func _label(ci: CanvasItem, font: Font, at: Vector2, text: String, fs: int, px: float, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px
	_text(ci, font, at - Vector2(w * 0.5, 0), text, fs, px, col)


func _text(ci: CanvasItem, font: Font, at: Vector2, text: String, fs: int, px: float, col: Color) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(px, px))
	ci.draw_string(font, Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
