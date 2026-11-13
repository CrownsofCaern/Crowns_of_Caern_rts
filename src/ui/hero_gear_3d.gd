class_name HeroGear3D
## Puts a hero's weapons (assets/weapons3d/<type>.glb, CC0, grip at the origin,
## shaft along +Y) into the hands of its LiveUnit body. Hero bodies are
## empty-handed Tripo models with a Mixamo skeleton, so a weapon rides on a
## BoneAttachment3D of mixamorig_RightHand or mixamorig_LeftHand.
## Kept out of LiveUnit so live_unit.gd stays a straight copy of the main game.

const DIR := "res://assets/weapons3d/"
## Hand per weapon type; the rest go in the right hand.
const LEFT := ["shield", "bow"]
## Grip per weapon type in the hand bone's space (Mixamo: +Y runs along the
## fingers): [euler degrees, offset in metres]. Checked on renders of the idle
## pose: one-handed weapons point forward from the fist, staves and long hafts
## stand upright leaning forward, the shield faces front, the bow hangs upright.
const GRIP_DEFAULT := [Vector3(-90.0, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)]
const GRIPS := {
	"staff": [Vector3(-150.0, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)],
	"polearm": [Vector3(-150.0, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)],
	"scythe": [Vector3(-150.0, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)],
	"great_weapon": [Vector3(-130.0, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)],
	"shield": [Vector3(180.0, 0.0, 0.0), Vector3(0.0, 0.06, 0.0)],
	"bow": [Vector3(0.0, -90.0, 0.0), Vector3(0.0, 0.08, 0.0)],
}

static var _scenes := {}


## Equips every weapon type the hero carries. Returns the attached nodes.
static func equip(unit: LiveUnit, weapons: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for w in weapons:
		var node := attach(unit, String(w))
		if node != null:
			out.append(node)
	return out


## Attaches one weapon type to its hand, or returns null when the unit has no
## Mixamo hand bone or the weapon model is missing.
static func attach(unit: LiveUnit, weapon: String) -> Node3D:
	var sk := _skeleton(unit)
	var bone := "mixamorig_LeftHand" if weapon in LEFT else "mixamorig_RightHand"
	if sk == null or sk.find_bone(bone) < 0:
		return null
	var model := _instance(weapon)
	if model == null:
		return null
	var socket := BoneAttachment3D.new()
	socket.name = "Socket_" + weapon
	socket.bone_name = bone
	sk.add_child(socket)
	var grip: Array = GRIPS.get(weapon, GRIP_DEFAULT)
	var rot: Vector3 = grip[0]
	var holder := Node3D.new()
	holder.name = weapon
	socket.add_child(holder)
	# Weapons are modelled in metres: undo whatever scale the exporter gave
	# the skeleton so a sword stays sword-sized on any body.
	var s := _world_scale(sk, unit)
	holder.transform = Transform3D(Basis.from_euler(rot * PI / 180.0).scaled(Vector3.ONE / s),
		(grip[1] as Vector3) / s)
	holder.add_child(model)
	return holder


static func _skeleton(unit: LiveUnit) -> Skeleton3D:
	for node in unit.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


static func _world_scale(sk: Skeleton3D, unit: LiveUnit) -> Vector3:
	var t := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != unit:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	var s := t.basis.get_scale()
	return Vector3(maxf(s.x, 1e-4), maxf(s.y, 1e-4), maxf(s.z, 1e-4))


static func _instance(weapon: String) -> Node3D:
	if not _scenes.has(weapon):
		var path := DIR + weapon + ".glb"
		_scenes[weapon] = load(path) if ResourceLoader.exists(path) else null
	var packed := _scenes[weapon] as PackedScene
	return packed.instantiate() as Node3D if packed != null else null
