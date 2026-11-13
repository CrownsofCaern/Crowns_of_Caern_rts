class_name JourneyMap
extends Control
## The campaign's journey painting with one numbered stop per chapter, as in the main game's
## campaign screen (src/ui/campaign_journey_map.gd). Routes link the stops; the campaign's hero
## walks there as its live 3D model, rendered in a small SubViewport, from the last chapter won
## to the next one. Presentation only: clicking a stop selects it.

signal stop_selected(index: int)

const HERO_PX := Vector2(124, 124)
const STATE_COLORS := {"done": Color("b6dfc0"), "current": Color("ffe1a1"), "locked": Color("d0cdc5")}

var painting: Texture2D
var nodes: Array = []     ## [{chapter, at: [x, y] in 0..1, layer}]
var states: Array = []    ## "done" | "current" | "locked", one per stop
var buttons: Array[Button] = []
var selected := 0
var current := 0
var accent := Color("d6b576")
var elapsed := 0.0
var travel_duration := 2.4
var animate_travel := true
var zoom := 1.0
var pan := Vector2.ZERO
var hero_class := ""
var hero: LiveUnit          ## the walking hero (null without a model)
var hero_view: SubViewport
var _pivot: Node3D
var _zoom_controls: VBoxContainer
var _walking := false


func _ready() -> void:
	clip_contents = true
	resized.connect(_layout_stops)
	var controls := VBoxContainer.new()
	_zoom_controls = controls
	controls.z_index = 5
	for entry: Array in [["+", 1.35], ["−", 1.0 / 1.35]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = "Zoom in" if entry[1] > 1 else "Zoom out"
		b.pressed.connect(func() -> void: zoom_at(entry[1], size * 0.5))
		controls.add_child(b)
	add_child(controls)
	if hero_view == null:
		_build_hero_view()
	set_process(true)


func _build_hero_view() -> void:
	hero_view = SubViewport.new()
	hero_view.name = "HeroView"
	hero_view.size = Vector2i(int(HERO_PX.x) * 2, int(HERO_PX.y) * 2)
	hero_view.transparent_bg = true
	hero_view.own_world_3d = true
	hero_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(hero_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.68, 0.6)
	env.environment.ambient_light_energy = 1.1
	hero_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 2.0
	sun.rotation_degrees = Vector3(-40, -35, 0)
	hero_view.add_child(sun)
	_pivot = Node3D.new()
	hero_view.add_child(_pivot)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 28.0
	cam.current = true
	hero_view.add_child(cam)


## Shows a campaign. [param hero_id] is the hero class whose 3D body walks the map.
func configure(texture: Texture2D, stops: Array, stop_states: Array, progress: int, hero_id: String, color: Color) -> void:
	painting = texture
	nodes = stops
	states = stop_states
	current = clampi(progress, 0, maxi(nodes.size() - 1, 0))
	selected = current
	accent = color
	elapsed = 0.0
	zoom = 1.0
	pan = Vector2.ZERO
	_set_hero(hero_id)
	for b in buttons:
		remove_child(b)
		b.queue_free()
	buttons.clear()
	for i in nodes.size():
		var b := Button.new()
		b.name = "ChapterStop_%d" % (i + 1)
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(44, 44)
		b.size = Vector2(44, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(select_stop.bind(i))
		add_child(b)
		buttons.append(b)
	select_stop(selected)
	_layout_stops()


func _set_hero(hero_id: String) -> void:
	if hero_id == hero_class and hero != null:
		return
	hero_class = hero_id
	if hero_view == null:
		_build_hero_view()
	if hero != null:
		hero.queue_free()
		hero = null
	if hero_id == "" or not LiveUnit.exists(hero_id, SkirmishView3D.HEROES3D):
		return
	hero = LiveUnit.spawn(hero_id, SkirmishView3D.HEROES3D)
	if hero == null:
		return
	var weapons: Array = HeroCatalog.get_default().classes.get(hero_id, {}).get("weapons", [])
	HeroGear3D.equip(hero, weapons)
	_pivot.add_child(hero)
	# Frame the whole body, feet near the bottom edge.
	var cam: Camera3D = hero_view.get_node("Camera")
	var h := maxf(hero.height, 1.0)
	var eye := Vector3(0, h * 0.6, h * 2.9)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, h * 0.5, 0) - eye), eye)
	_walking = false
	_stand(hero)


## At rest the hero stands still: the idle clip's first pose, held (a looping idle on a
## picture reads as fidgeting).
static func _stand(unit: LiveUnit) -> void:
	unit.play("idle", 1.0, 0.0, 0.0)
	if unit.player != null:
		unit.player.seek(0.0, true)
		unit.player.pause()


## Whether the hero is still walking to the current stop.
func travelling() -> bool:
	return animate_travel and current > 0 and elapsed < travel_duration and nodes.size() > current


func image_rect() -> Rect2:
	var ratio := 1.5 if painting == null else float(painting.get_width()) / painting.get_height()
	var fitted := Vector2(minf(size.x, size.y * ratio), minf(size.y, size.x / ratio))
	return Rect2((size - fitted * zoom) * 0.5 + pan, fitted * zoom)


func stop_position(index: int) -> Vector2:
	var rect := image_rect()
	var xy: Array = nodes[index]["at"]
	return rect.position + Vector2(float(xy[0]), float(xy[1])) * rect.size


func _layout_stops() -> void:
	for i in buttons.size():
		buttons[i].position = stop_position(i) - buttons[i].size * 0.5
	if is_instance_valid(_zoom_controls):
		_zoom_controls.position = Vector2(maxf(4, size.x - 52), 8)
	queue_redraw()


func select_stop(index: int) -> void:
	if index < 0 or index >= nodes.size():
		return
	selected = index
	for i in buttons.size():
		var col: Color = STATE_COLORS.get(String(states[i]), STATE_COLORS["locked"])
		var box := StyleBoxFlat.new()
		box.bg_color = Color("10151bea")
		box.border_color = Color("fff0bc") if i == selected else col
		box.set_border_width_all(3 if i == selected else 1)
		box.set_corner_radius_all(22)
		for st in ["normal", "hover", "pressed", "focus"]:
			buttons[i].add_theme_stylebox_override(st, box)
		buttons[i].add_theme_color_override("font_color", col)
		buttons[i].add_theme_color_override("font_hover_color", col.lightened(0.2))
	stop_selected.emit(index)
	queue_redraw()


func _process(delta: float) -> void:
	if hero_view == null:
		return
	if not is_visible_in_tree():
		if hero_view != null:
			hero_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	hero_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elapsed += delta
	if hero != null:
		var walking := travelling()
		if walking != _walking:
			_walking = walking
			if walking:
				hero.walk(hero.move_speed)
			else:
				_stand(hero)
		# The model faces +X: walking, it shows its side in the direction of travel; at rest it
		# turns three-quarters toward the viewer.
		if walking:
			var pts := _leg_points(current)
			hero.rotation.y = PI if pts[-1].x < pts[0].x else 0.0
		else:
			hero.rotation.y = -deg_to_rad(60.0)
	queue_redraw()


func _leg_points(index: int) -> PackedVector2Array:
	var start := stop_position(index - 1)
	var finish := stop_position(index)
	var points := PackedVector2Array()
	var normal := (finish - start).orthogonal().normalized() * minf(20, start.distance_to(finish) * 0.1)
	for step in 17:
		var t := float(step) / 16
		points.append(start.lerp(finish, t) + normal * sin(t * PI))
	return points


## Where the hero's feet are now, in this control's coordinates.
func hero_position() -> Vector2:
	if nodes.is_empty():
		return Vector2.ZERO
	if not travelling():
		return stop_position(current)
	var points := _leg_points(current)
	var p := clampf(elapsed / travel_duration, 0, 1) * (points.size() - 1)
	var i := mini(int(p), points.size() - 2)
	return points[i].lerp(points[i + 1], p - i)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1015"))
	var rect := image_rect()
	if painting != null:
		draw_texture_rect(painting, rect, false)
	for i in range(1, nodes.size()):
		var points := _leg_points(i)
		var col := accent if i <= current else Color("c1b6a16b")
		if i <= current:
			draw_polyline(points, Color(0, 0, 0, 0.6), 4, true)
		var underground: bool = nodes[i].get("layer", "surface") != "surface" \
				or nodes[i - 1].get("layer", "surface") != "surface"
		for j in range(points.size() - 1):
			if (not underground and i <= current) or j % 2 == 0:
				draw_line(points[j], points[j + 1], col, 1.6, true)
	if nodes.is_empty() or hero == null:
		return
	# The hero stands beside the stop, not on it, so the stop stays clickable.
	var feet := hero_position() + (Vector2(-34, -20) if travelling() else _hero_offset())
	var r := Rect2(feet - Vector2(HERO_PX.x * 0.5, HERO_PX.y * 0.94), HERO_PX)
	var tex := hero_view.get_texture()
	# A shadow at the feet and a dark outline keep the small figure readable on the painting.
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-1.5, -1.5),
			Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
		draw_texture_rect(tex, Rect2(r.position + d, r.size), false, Color(0.05, 0.03, 0.02, 0.9))
	draw_texture_rect(tex, r, false)


## Where the idle hero stands relative to its stop: the first spot that covers no stop and
## stays on screen.
func _hero_offset() -> Vector2:
	var offsets := [Vector2(-52, -6), Vector2(52, -6), Vector2(0, -26), Vector2(0, 120)]
	var at := stop_position(current)
	for off: Vector2 in offsets:
		var feet: Vector2 = at + off
		var r := Rect2(feet - Vector2(HERO_PX.x * 0.5, HERO_PX.y), HERO_PX).grow(-30)
		var ok := Rect2(Vector2.ZERO, size).encloses(r)
		for i in nodes.size():
			if r.intersects(Rect2(stop_position(i) - Vector2(22, 22), Vector2(44, 44))):
				ok = false
		if ok:
			return off
	return offsets[0]


func zoom_at(factor: float, pivot: Vector2) -> void:
	var before := image_rect()
	if before.size.x <= 0 or before.size.y <= 0:
		return
	var point := (pivot - before.position) / before.size
	zoom = clampf(zoom * factor, 1, 3)
	var after := image_rect()
	pan += pivot - (after.position + point * after.size)
	_clamp_pan()
	_layout_stops()


func _clamp_pan() -> void:
	var excess := ((image_rect().size - size) * 0.5).max(Vector2.ZERO)
	pan = pan.clamp(-excess, excess)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(1.2, event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / 1.2, event.position)
			accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pan += event.relative
		_clamp_pan()
		_layout_stops()
		accept_event()
