class_name Biomes
extends RefCounted
## Ground looks per biome (data/biomes.json): colours, water or lava, pools, how
## many dead trees. View-only data; the rules never read it.

const PATH := "res://data/biomes.json"
const TEXTURES := "res://assets/terrain3d/%s.png"
const COLOR_KEYS := ["grass", "lush", "dry", "dirt", "rock", "moss", "ash", "water_deep", "water_sky", "tuft"]
const NUMBER_KEYS := ["puddles", "dead_trees", "trees", "bushes", "tufts", "snow"]
## Scenery lists a biome may set (models in assets/nature, sizes in MapScene3D).
const SCENERY_KINDS := ["trees", "dead", "rocks", "bushes", "cover", "litter", "water"]
const NATURE := "res://assets/nature/%s.glb"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func get_biome(biome_name: String) -> Dictionary:
	var b: Dictionary = data()["biomes"]
	return b.get(biome_name, b[data()["base"]])


static func for_faction(faction: String) -> String:
	return data()["factions"].get(faction, data()["base"])


static func color(b: Dictionary, key: String) -> Color:
	var a: Array = b[key]
	return Color(float(a[0]), float(a[1]), float(a[2]))


static func validate() -> Array[String]:
	var errors: Array[String] = []
	var d := data()
	if not d.get("biomes", {}).has(d.get("base", "")):
		errors.append("biomes: base biome missing")
	for f in d.get("factions", {}):
		if not d["biomes"].has(d["factions"][f]):
			errors.append("biomes: faction %s uses unknown biome %s" % [f, d["factions"][f]])
	for n in d.get("biomes", {}):
		var b: Dictionary = d["biomes"][n]
		for k in COLOR_KEYS:
			if not b.has(k) or (b[k] as Array).size() != 3:
				errors.append("biomes: %s needs colour %s" % [n, k])
		for k in NUMBER_KEYS:
			if not b.has(k) or float(b[k]) < 0.0:
				errors.append("biomes: %s needs a non-negative %s" % [n, k])
		if not b.has("lava"):
			errors.append("biomes: %s needs lava true/false" % n)
		for k in ["ground_tex", "rock_tex"]:
			if not ResourceLoader.exists(TEXTURES % (str(b.get(k, "")) + "_alb_ht")) \
					or not ResourceLoader.exists(TEXTURES % (str(b.get(k, "")) + "_nrm_rgh")):
				errors.append("biomes: %s needs %s with both texture files" % [n, k])
		if float(b.get("embers", -1.0)) < 0.0:
			errors.append("biomes: %s needs a non-negative embers" % n)
		var sc: Dictionary = b.get("scenery", {})
		for kind in sc:
			if kind == "litter_share":
				if float(sc[kind]) < 0.0 or float(sc[kind]) > 1.0:
					errors.append("biomes: %s scenery litter_share must be 0..1" % n)
				continue
			if not kind in SCENERY_KINDS:
				errors.append("biomes: %s scenery has unknown kind %s" % [n, kind])
				continue
			for m in sc[kind]:
				if MapScene3D.size_of(str(m)).is_empty() or not ResourceLoader.exists(NATURE % m):
					errors.append("biomes: %s scenery %s: unknown model %s" % [n, kind, m])
	return errors
