class_name LiveUnit
## Copied unchanged from the main game (src/ui/live_unit.gd); edit it there, not here.
extends Node3D
## A live 3D unit made from assets/units3d/<id>.glb (written by
## tools/assets/export_live_units.gd). The model stands with its feet on y = 0,
## faces +X, and is sized in metres (a human soldier is about 1.8 m tall).
## Clips: idle, move, attack, death (any may be missing). Kept free of game
## code so the Warbound RTS can copy it unchanged.
##
##   var unit := LiveUnit.spawn("pike_militia")
##   add_child(unit)
##   unit.play("move")

const DIR := "res://assets/units3d/"
const LOOPS := ["idle", "move"]

var id := ""
## Standing height and footprint radius in metres, from the rest-pose bounds.
var height := 1.8
var radius := 0.3
## Ground speed (m/s) at which the move clip's feet do not slide.
var move_speed := 0.0
var player: AnimationPlayer
var action := ""
var fighting := false
var _rest := -1.0
static var _manifests := {}
var _fall := -1.0
var _fall_dir := 1.0


static func path_for(unit_id: String, dir: String = DIR) -> String:
	return dir + unit_id + ".glb"


static func exists(unit_id: String, dir: String = DIR) -> bool:
	var path := path_for(unit_id, dir)
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Spawns a unit, or returns null when it has no live model.
static func spawn(unit_id: String, dir: String = DIR) -> LiveUnit:
	var model := _load_model(path_for(unit_id, dir))
	if model == null:
		return null
	var unit := LiveUnit.new()
	unit.id = unit_id
	unit.name = unit_id
	unit.add_child(model)
	unit._setup(model)
	var entry: Dictionary = _manifest(dir).get(unit_id, {})
	unit.move_speed = float(entry.get("move_speed", 0.0))
	if unit.move_speed <= 0.0:
		unit.move_speed = unit.height
	return unit


static func _manifest(dir: String) -> Dictionary:
	if not _manifests.has(dir):
		var path := dir + "units3d.json"
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_manifests[dir] = data if data is Dictionary else {}
	return _manifests[dir]


static func _load_model(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	# Not imported (tools, fresh checkouts): read the GLB directly.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _setup(model: Node3D) -> void:
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for name in LOOPS:
			if player.has_animation(name):
				player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = _local_transform(mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	height = box.end.y
	radius = maxf(0.15, 0.5 * minf(box.size.x, box.size.z))
	# Bipeds: measure to the skull top, so a raised pike or staff does not count
	# (the exporter sizes the model the same way).
	for node in model.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		var head := sk.find_bone("mixamorig_Head")
		var neck := sk.find_bone("mixamorig_Neck")
		if head < 0 or neck < 0:
			continue
		var to_unit := _local_transform(sk)
		var h := to_unit * sk.get_bone_global_rest(head).origin
		var n := to_unit * sk.get_bone_global_rest(neck).origin
		height = minf(height, h.y + 2.0 * h.distance_to(n))
		radius = 0.17 * height
		break


func _local_transform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func has_clip(clip: String) -> bool:
	return player != null and player.has_animation(clip)


## Plays a clip (loops for idle/move). Looping clips start at a random phase
## when [param phase] is negative, so a block of units does not move in step.
func play(clip: String, speed: float = 1.0, blend: float = 0.15, phase: float = -1.0) -> void:
	fighting = false
	_play(clip, speed, blend, phase)


## Plays the move clip at the pace of a unit moving at [param speed] m/s, so the
## feet stay planted.
func walk(speed: float) -> void:
	var rate := clampf(speed / move_speed, 0.3, 2.5)
	if action == "move" and has_clip("move"):
		player.speed_scale = rate
		return
	play("move")
	if player != null:
		player.speed_scale = rate


## Swings again and again, with short random breaths between blows, until
## play(), walk() or die() is called. Without an attack clip it holds idle.
func fight() -> void:
	if fighting:
		return
	_play("attack" if has_clip("attack") else "idle", 1.0, 0.12, -1.0)
	fighting = true
	_rest = -1.0


func _play(clip: String, speed: float, blend: float, phase: float) -> void:
	action = clip
	if player != null:
		player.speed_scale = 1.0
	if not has_clip(clip):
		if clip == "idle" and has_clip("move"):
			# No idle (some beasts): hold the first walk frame, which stands on the
			# ground; the bare rest pose of such rigs may not.
			player.play("move", blend, 0.0)
			player.seek(0.0, true)
		return
	player.play(clip, blend, speed)
	if clip in LOOPS:
		var length := player.get_animation(clip).length
		player.seek(length * (phase if phase >= 0.0 else fposmod(float(get_instance_id() % 997) * 0.618, 1.0)), true)


## True while a one-shot clip (attack, death) is still running.
func busy() -> bool:
	return player != null and player.is_playing() and action not in LOOPS


## Plays the death clip, or topples the model sideways when it has none.
func die(away: float = 1.0) -> void:
	fighting = false
	if has_clip("death"):
		play("death", 1.0, 0.1)
		return
	action = "death"
	if player != null:
		player.pause()
	_fall = 0.0
	_fall_dir = away


## Stands a fallen unit up again (raised from the dead) and lets it idle.
func revive() -> void:
	_fall = -1.0
	rotation.x = 0.0
	set_process(true)
	play("idle", 1.0, 0.2)


func _process(delta: float) -> void:
	if fighting and action == "attack" and not player.is_playing():
		# Between blows: a short breath on the last frame, then the next swing.
		if _rest < 0.0:
			_rest = randf_range(0.05, 0.4)
		_rest -= delta
		if _rest <= 0.0:
			_rest = -1.0
			player.play("attack", 0.08, randf_range(0.9, 1.15))
			player.seek(0.0, true)
		return
	if _fall < 0.0:
		return
	_fall = minf(1.0, _fall + delta / 0.5)
	rotation.x = _fall_dir * _fall * 1.4
	if _fall >= 1.0:
		set_process(false)
