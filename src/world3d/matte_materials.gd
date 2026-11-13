class_name MatteMaterials
extends RefCounted
## Takes the plastic shine off imported 3D models (units, heroes, buildings, props).
## Tripo and glTF models arrive as full PBR with metal and gloss maps, which under our
## dim light reads as wet plastic. The matte copy drops those maps, keeps the painted
## albedo, makes the surface rough and nearly without specular, and dulls the colour a
## little, so models sit in the dark gothic look like worn cloth, leather and old iron.
## One matte copy per source material (cached), so instancing and batching still work.
## Atmosphere3D applies it to every model added under its viewport.

const ROUGHNESS := 0.92
const SPECULAR := 0.12  ## Godot's default is 0.5
const METALLIC := 0.0
const TINT := Color(0.9, 0.88, 0.88)  ## a touch darker, slightly drained of colour

static var _cache: Dictionary = {}  ## source material instance id -> matte copy


## The matte version of a material (the same material if it is not a lit BaseMaterial3D).
static func matte(m: Material) -> Material:
	if not m is BaseMaterial3D:
		return m
	var b := m as BaseMaterial3D
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or b.has_meta("matte"):
		return m
	var id := b.get_instance_id()
	if _cache.has(id):
		var hit: Material = _cache[id]
		if is_instance_valid(hit):
			return hit
	var c := b.duplicate() as BaseMaterial3D
	c.metallic = METALLIC
	c.metallic_texture = null
	c.roughness = ROUGHNESS
	c.roughness_texture = null
	c.metallic_specular = SPECULAR
	c.clearcoat_enabled = false
	c.anisotropy_enabled = false
	c.albedo_color = c.albedo_color * Color(TINT, 1.0)
	c.set_meta("matte", true)
	_cache[id] = c
	return c


## Makes every lit model under (and including) a node matte. Surfaces with a material
## override keep their override, made matte too.
static func apply(root: Node) -> void:
	if root is MeshInstance3D:
		_mesh_instance(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		_mesh_instance(n)


static func _mesh_instance(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	if mi.material_override != null:
		mi.material_override = matte(mi.material_override)
		return
	for i in mi.mesh.get_surface_count():
		var cur := mi.get_surface_override_material(i)
		var src := cur if cur != null else mi.mesh.surface_get_material(i)
		if src == null:
			continue
		var m := matte(src)
		if m != src:
			mi.set_surface_override_material(i, m)
