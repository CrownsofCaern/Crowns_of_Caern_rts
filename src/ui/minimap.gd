class_name Minimap
extends Control
## Classic minimap: terrain, units as dots, the camera's view as a frame.
## Sector borders show over the fog, so the shape of the map is always known; who holds a
## settlement shows only once it has been explored.
## Left click or drag looks there; right click sends the selection there.

signal look_at(world_pos: Vector2)
signal order_to(world_pos: Vector2)

var skirmish: Node
var _tex: ImageTexture
var frame: StyleBox  ## set by HudSkin (src/menu): a framed border
var _dragging: bool = false
const BORDER := Color(0.95, 0.87, 0.62, 0.45)


func rebuild(world: SimWorld) -> void:
	var nav := world.nav
	var img := Image.create(nav.width, nav.height, false, Image.FORMAT_RGBA8)
	for y in nav.height:
		for x in nav.width:
			var c := Color(0.2, 0.27, 0.12)
			match nav.kind_at(Vector2i(x, y)):
				NavGrid.Kind.ROCK:
					c = Color(0.45, 0.43, 0.4)
				NavGrid.Kind.WATER:
					c = Color(0.12, 0.22, 0.25)
				NavGrid.Kind.FOREST:
					c = Color(0.08, 0.14, 0.06)
			img.set_pixel(x, y, c)
	_tex = ImageTexture.create_from_image(img)


func _to_world(p: Vector2) -> Vector2:
	var ws: Vector2 = skirmish.world.nav.world_size()
	return Vector2(p.x / size.x * ws.x, p.y / size.y * ws.y)


func _to_map(p: Vector2) -> Vector2:
	var ws: Vector2 = skirmish.world.nav.world_size()
	return Vector2(p.x / ws.x * size.x, p.y / ws.y * size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				look_at.emit(_to_world(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			order_to.emit(_to_world(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		look_at.emit(_to_world(event.position))
		accept_event()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if skirmish == null or skirmish.world == null:
		return
	if frame != null:
		draw_style_box(frame, Rect2(Vector2(-10, -10), size + Vector2(20, 20)))
	else:
		draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0.05, 0.04, 0.03, 0.9))
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var eco: Economy = skirmish.world.economy
	for b in eco.buildings:
		if b.owner != skirmish.PLAYER and not skirmish.has_explored(b.pos):
			continue
		draw_rect(Rect2(_to_map(b.pos) - Vector2(2.5, 2.5), Vector2(5, 5)), skirmish.TEAM_COLORS[b.owner].darkened(0.2))
	for n in eco.nodes:
		if eco.uses(skirmish.PLAYER, n.resource) and not n.depleted():
			draw_rect(Rect2(_to_map(n.pos) - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.85, 0.4))
	SiteMarks.draw_minimap(self, skirmish.world, _to_map, skirmish.has_explored)
	for u in skirmish.world.units:
		if not skirmish.can_see(u):
			continue
		var c: Color = skirmish.TEAM_COLORS[u.owner]
		if u.id in skirmish.selection:
			c = skirmish.SELECT_COLOR
		var s := 2.0 if u.radius() < 15.0 else 3.0
		draw_rect(Rect2(_to_map(u.pos) - Vector2(s, s) * 0.5, Vector2(s, s)), c)
	var fog: ImageTexture = skirmish.fog_texture()
	if fog != null and skirmish.fog_enabled:
		draw_texture_rect(fog, Rect2(Vector2.ZERO, size), false)
	var lines: PackedVector2Array = skirmish._border_lines
	if lines.size() > 1:
		var ws: Vector2 = skirmish.world.nav.world_size()
		draw_set_transform(Vector2.ZERO, 0.0, size / ws)
		draw_multiline(lines, BORDER, -1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for sec in eco.sectors:
		var o := TacticalMap.known_owner(skirmish, sec)
		var c: Color = Color(0.85, 0.8, 0.6) if o < 0 else skirmish.TEAM_COLORS[o]
		var m := _to_map(sec.center)
		draw_rect(Rect2(m - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), c)
	var view: Rect2 = skirmish.view_rect()
	var a := _to_map(view.position)
	var b := _to_map(view.end)
	draw_rect(Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, size)), Color(1, 1, 1, 0.85), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.45, 0.3), false, 2.0)
