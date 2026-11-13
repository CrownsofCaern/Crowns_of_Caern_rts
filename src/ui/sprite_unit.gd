class_name SpriteUnit
extends Sprite3D
## A unit drawn with the main game's animated battle sprites (idle, move, attack, death),
## as a billboard that always faces the camera. The sheets come from
## tools/sync_unit_anims.py: assets/unit_anims/<sprite id>.png with data/unit_anims.json.
## The art faces right; face(right) mirrors it. The feet stay on the node's origin, so
## the sprite leans back with the camera pitch around the point it stands on.
## View-only: the skirmish view tells it what to play, it never reads the sim.

const DATA := "res://data/unit_anims.json"
const SHEETS := "res://assets/unit_anims/%s.png"
## Lights the art with the scene's sun and ambient (sprite_unit.gdshader).
const SHADER := "res://src/ui/sprite_unit.gdshader"
## Metres per sprite pixel: a man (about 125 px in the battle art) stands 1.8 m tall,
## like the 3D models. The battle art draws every creature at about that height, so each
## sprite also gets its own factor from data/unit_sizes.json (tools/size_unit_sprites.py):
## a giant stands well above a soldier, a cinderling below his knee.
const M_PER_PX := 1.8 / 125.0
const SIZES := "res://data/unit_sizes.json"

static var _data: Dictionary = {}
static var _sheets: Dictionary = {}
static var _sizes: Dictionary = {}
static var _mats: Dictionary = {}  ## "<id>" / "<id>:flat" -> ShaderMaterial
## Dark ink outline round every figure (the "Ink outlines" setting, set_ink()).
static var ink: bool = true

var sprite_id := ""
var action := ""
var facing_right := true
## Standing height in metres (top of the idle pose), for health bars and missiles.
var height := 1.8
var _t := 0.0
var _speed := 1.0
var _size := Vector2i.ZERO
var _anchor := Vector2.ZERO
var _actions: Dictionary = {}
var _dead := false


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary:
			_data = (parsed as Dictionary).get("units", {})
	return _data


## The size factor for a sprite id (1 when the art is already drawn at the unit's height).
static func size_k(id: String) -> float:
	if _sizes.is_empty() and FileAccess.file_exists(SIZES):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIZES))
		if parsed is Dictionary:
			_sizes = (parsed as Dictionary).get("units", {})
		if _sizes.is_empty():
			_sizes = {"": 1.0}  # loaded, nothing to scale
	if id.begins_with("asc_") and not _sizes.has(id):
		id = id.substr(4)  # an Ascendant (tools/sync_ascendant_anims.py) stands as tall as its form
	return float(_sizes.get(id, 1.0))


static func exists(id: String) -> bool:
	return data().has(id) and ResourceLoader.exists(SHEETS % id)


## A new sprite unit for a sprite id (the file name of a unit's still sprite), or null
## when it has no animation sheet.
static func spawn(id: String, scale_k: float = 1.0) -> SpriteUnit:
	if not exists(id):
		return null
	if not _sheets.has(id):
		_sheets[id] = load(SHEETS % id)
	var s := SpriteUnit.new()
	s._setup(id, _sheets[id], scale_k)
	return s


func _setup(id: String, tex: Texture2D, scale_k: float) -> void:
	sprite_id = id
	var d: Dictionary = data()[id]
	_size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	_anchor = Vector2(float(d["anchor"][0]), float(d["anchor"][1]))
	_actions = d["actions"]
	texture = tex
	region_enabled = true
	pixel_size = M_PER_PX * scale_k * size_k(id)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = true
	material_override = _material(id, tex, false)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	centered = true
	# Top of the figure: the anchor sits near the bottom of the shared box, which is
	# padded round every frame, so the box top is close to the tallest pose.
	height = (_anchor.y - 2.0) * pixel_size
	play("idle")


## The clip shown for an action: units without idle stand in their first stride
## frame, units without death keep their last pose (the view lays them down).
func _clip(name: String) -> Dictionary:
	if _actions.has(name):
		return _actions[name]
	if name == "idle" and _actions.has("move"):
		return {"row": _actions["move"]["row"], "frames": 1, "ms": [1000], "loop": true}
	return {}


static func _material(id: String, tex: Texture2D, flat: bool) -> ShaderMaterial:
	var key := id + (":flat" if flat else "")
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(SHADER)
		m.set_shader_parameter("sheet", tex)
		m.set_shader_parameter("billboard", 0.0 if flat else 1.0)
		m.set_shader_parameter("ink", 1.0 if ink else 0.0)
		_mats[key] = m
	return _mats[key]


## Turns the ink outline round every figure on or off (new and existing sprites).
static func set_ink(on: bool) -> void:
	ink = on
	for k in _mats:
		(_mats[k] as ShaderMaterial).set_shader_parameter("ink", 1.0 if on else 0.0)


## An Ascendant (veteran level 5) gets its own material: a pulsing glowing outline, and the
## dissolve the view runs when it falls (set_dissolve).
func set_ascendant(on: bool) -> void:
	var m := (_material(sprite_id, texture, false).duplicate() as ShaderMaterial) if on else _material(sprite_id, texture, false)
	if on:
		m.set_shader_parameter("aura", 1.0)
	material_override = m


## 0..1: how much of the figure has burned away into light (Ascendants only).
func set_dissolve(v: float) -> void:
	var m := material_override as ShaderMaterial
	if m != null and m.get_shader_parameter("aura") != null and float(m.get_shader_parameter("aura")) > 0.0:
		m.set_shader_parameter("dissolve", clampf(v, 0.0, 1.0))


## A body without a death clip: laid on the ground, stops animating.
func lay_flat() -> void:
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	material_override = _material(sprite_id, texture, true)
	rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	position.y = 0.05
	set_process(false)


func has_clip(name: String) -> bool:
	return _actions.has(name)


## Starts a clip from its first frame (or keeps it running when it already plays).
func play(name: String, speed: float = 1.0, restart: bool = false) -> void:
	if _dead:
		return
	_speed = speed
	if name == action and not restart:
		return
	action = name
	_t = 0.0
	_show()


## Walk cycle, faster or slower with the ground speed (m/s).
func walk(speed_ms: float) -> void:
	play("move", clampf(speed_ms / 1.6, 0.6, 1.8))


## One blow. A blow that comes sooner than the clip lasts plays faster.
func strike(interval: float) -> void:
	var total := clip_seconds("attack")
	play("attack", maxf(1.0, total / maxf(interval * 0.95, 0.1)), true)


## Whether a one-shot clip (attack, death) is still running.
func busy() -> bool:
	var c := _clip(action)
	return not c.is_empty() and not bool(c["loop"]) and _t < clip_seconds(action)


func die() -> void:
	if _dead:
		return
	if _actions.has("death"):
		play("death")
	_dead = true


func is_dead() -> bool:
	return _dead


func clip_seconds(name: String) -> float:
	var total := 0
	for ms in _clip(name).get("ms", []):
		total += int(ms)
	return total / 1000.0


## Mirrors the art: it is drawn facing right.
func face(right: bool) -> void:
	if right != facing_right:
		facing_right = right
		_show()


func frame_index() -> int:
	var c := _clip(action)
	var ms: Array = c.get("ms", [])
	if ms.is_empty():
		return 0
	var total := 0
	for m in ms:
		total += int(m)
	var t := int(_t * 1000.0)
	if bool(c["loop"]):
		t = t % maxi(total, 1)
	elif t >= total:
		return ms.size() - 1
	for i in ms.size():
		if t < int(ms[i]):
			return i
		t -= int(ms[i])
	return ms.size() - 1


func advance(delta: float) -> void:
	_t += delta * _speed
	_show()


func _process(delta: float) -> void:
	advance(delta)


func _show() -> void:
	var c := _clip(action)
	if c.is_empty():
		return
	var i := frame_index()
	region_rect = Rect2(i * _size.x, int(c["row"]) * _size.y, _size.x, _size.y)
	flip_h = not facing_right
	# Keep the feet (anchor) on the origin; flip_h mirrors the picture but not the offset.
	var ox := _size.x * 0.5 - _anchor.x
	offset = Vector2(ox if facing_right else -ox, _anchor.y - _size.y * 0.5)
