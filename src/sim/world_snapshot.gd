class_name WorldSnapshot
extends RefCounted
## A copy of a running world's changing state, to repair a drift online.
##
## Online every computer runs the same simulation (see Lockstep). If one of them
## drifts (a rounding difference between two kinds of computer, say), the host
## sends its snapshot and the others copy it over their own world, so they agree
## again. A snapshot holds the plain values (numbers, text, vectors, arrays and
## dictionaries of those) of every part of the world, its units, buildings,
## settlements, resource piles, players, melee blocks and heroes, and of any `extras` (the
## computer players). Lists of things must match one for one: when a unit lives
## on one computer and died on another, the worlds are too far apart and
## apply() refuses (the match then stops as out of sync).

## Fixed data, the same everywhere and large, or only for the view: never copied.
const SKIP := ["def", "catalog", "map_info", "_r", "e", "r", "d", "ir", "cat", "icat", "events", "notices",
	"script", "RefCounted", "Built-in script"]


## The state of the world (and of `extras`, objects outside it that run the game).
static func capture(w: SimWorld, extras: Array = []) -> Dictionary:
	var out := {}
	var parts := _parts(w, extras)
	for key: String in parts:
		var v: Variant = parts[key]
		if v is Array:
			var list: Array = []
			for o: Object in v:
				list.append(_props(o))
			out[key] = list
		else:
			out[key] = _props(v)
	return out


## Copies a snapshot over this world. False (and nothing half-done that matters)
## when the worlds hold different things.
static func apply(w: SimWorld, snap: Dictionary, extras: Array = []) -> bool:
	var parts := _parts(w, extras)
	# First check that every list matches, so a refusal leaves the world as it was.
	for key: String in parts:
		if not snap.has(key):
			return false
		var v: Variant = parts[key]
		if v is Array:
			var theirs: Variant = snap[key]
			if not theirs is Array or (theirs as Array).size() != (v as Array).size():
				return false
			for i in (v as Array).size():
				var mine: Object = v[i]
				var other: Variant = theirs[i]
				if not other is Dictionary:
					return false
				if "id" in mine and int((other as Dictionary).get("id", -1)) != int(mine.get("id")):
					return false
				if "owner" in mine and int((other as Dictionary).get("owner", -1)) != int(mine.get("owner")):
					return false
	for key: String in parts:
		var v: Variant = parts[key]
		if v is Array:
			for i in (v as Array).size():
				_set_props(v[i], snap[key][i])
		else:
			_set_props(v, snap[key])
	# `def` is never copied: a unit promoted on the host (veteran rank) takes its new form here too.
	for u in w.units:
		if w.catalog.units.has(u.type_id) and String(u.def.get("id", u.type_id)) != u.type_id:
			u.def = w.catalog.get_unit(u.type_id)
	return true


## Packs a snapshot for the network (compressed bytes).
static func pack(snap: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(snap)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {}
	var size := bytes.decode_u32(0)
	if size <= 0 or size > 64 * 1024 * 1024:
		return {}
	var raw := bytes.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}


## The parts of the world, by name: single objects, or arrays of objects in a fixed order.
static func _parts(w: SimWorld, extras: Array) -> Dictionary:
	var p := {"world": w, "rng": w.rng, "economy": w.economy, "heroes": w.heroes, "gear": w.heroes.gear,
		"sites": w.sites, "defense": w.defense, "forts": w.forts, "specials": w.specials, "vision": w.vision,
		"units": w.units.duplicate(), "structures": w.structures.duplicate(), "formations": w.formations.duplicate(),
		"sectors": w.economy.sectors.duplicate(), "nodes": w.economy.nodes.duplicate(), "buildings": w.economy.buildings.duplicate(),
		"players": w.economy.players.duplicate(), "hero_states": w.heroes.heroes.values(), "extras": extras.duplicate()}
	if w.sites._rng != null:
		p["sites_rng"] = w.sites._rng
	if w.heroes.gear._rng != null:
		p["gear_rng"] = w.heroes.gear._rng
	return p


## The plain values of an object's own variables.
static func _props(o: Object) -> Dictionary:
	var out := {}
	for prop: Dictionary in o.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := String(prop["name"])
		if SKIP.has(n):
			continue
		var v: Variant = o.get(n)
		if _plain(v):
			out[n] = v
	return out


static func _set_props(o: Object, vals: Dictionary) -> void:
	for n: String in vals:
		if SKIP.has(n) or not n in o:
			continue
		var v: Variant = vals[n]
		var cur: Variant = o.get(n)
		if typeof(cur) != typeof(v) or cur == v or not _plain(cur):
			continue  # same already, or not a value we copy (an object, a changed type)
		if cur is Array:
			var a: Array = (cur as Array).duplicate()  # keeps a typed array's type
			a.assign(v)
			o.set(n, a)
		elif cur is Dictionary:
			var d: Dictionary = (cur as Dictionary).duplicate()
			d.clear()
			d.assign(v)
			o.set(n, d)
		else:
			o.set(n, v)


## Numbers, text, vectors and packed arrays, and arrays/dictionaries holding only those.
static func _plain(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, \
				TYPE_RECT2, TYPE_COLOR, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _plain(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if not _plain(k) or not _plain(v[k]):
					return false
			return true
	return false
