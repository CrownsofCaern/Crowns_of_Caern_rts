extends SceneTree
## Records a short gameplay clip with Godot's movie maker:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --write-movie /tmp/warbound.avi --fixed-fps 30 --script res://tools/record.gd
## A small "director" plays the player's part: selects, gives orders, moves the camera.

const LENGTH := 40.0

var s: Node2D
var t: float = 0.0
var _done: Dictionary = {}
var _cam_target := Vector2.ZERO
var _zoom_target: float = 0.75


func _init() -> void:
	s = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(s)
	process_frame.connect(_tick)


func _once(key: String, at: float) -> bool:
	if t >= at and not _done.has(key):
		_done[key] = true
		return true
	return false


func _centroid(owner: int) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for u in s.world.units:
		if owner < 0 or u.owner == owner:
			c += u.pos
			n += 1
	return c / maxi(n, 1)


func _tick() -> void:
	var dt := 1.0 / 30.0
	t += dt
	if _once("setup", 0.0):
		s.hud_help.visible = false
		s.cam.zoom = Vector2(0.75, 0.75)
		_cam_target = _centroid(0) + Vector2(250, 0)
		s.cam.position = _cam_target
	if _once("advance", 1.0):
		s._order_attack_move(Vector2(1950, 1150))
		s.audio.play("click", s._time, 0.8)
	if _once("lancers", 10.0):
		# Pick the lancers from the unit panel and send them around the flank.
		s.select_type("lancer", false)
		var c := _centroid(0)
		s._right_click(c + Vector2(380, -420))
	if _once("charge", 15.0):
		var archers := []
		for u in s.world.units:
			if u.owner == 1 and u.type_id == "marrow_archer":
				archers.append(u)
		if not archers.is_empty():
			s._right_click(archers[0].pos)
	if _once("all", 19.0):
		s.selection.clear()
		for u in s.world.units:
			if u.owner == 0:
				s.selection.append(u.id)
		s._order_attack_move(_centroid(1))
	# Camera: follow your army until the fighting starts, then the fighting itself.
	var fight := Vector2.ZERO
	var n := 0
	for u in s.world.units:
		if u.since_attack < 1.0:
			fight += u.pos
			n += 1
	if n >= 6:
		_cam_target = fight / n
	else:
		var a := _centroid(0)
		_cam_target = a.lerp(_centroid(1), 0.25)
	_zoom_target = 1.05 if n >= 6 else 0.8
	if t > 33.0:
		_zoom_target = 0.6
	s.cam.position = s.cam.position.lerp(_cam_target, 0.035)
	s._clamp_camera()
	var z: float = lerpf(s.cam.zoom.x, _zoom_target, 0.02)
	s.cam.zoom = Vector2(z, z)
	if t >= LENGTH:
		quit()
