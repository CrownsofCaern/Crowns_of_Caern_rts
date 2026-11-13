class_name SimTerrain
extends RefCounted
## Warbound's bridge from a SimWorld to the shared 3D ground (TerrainField.build_map),
## which must not know Warbound's sim types because the main game uses it too.


static func build(field: TerrainField, world: SimWorld, seed_value: int = 1, base_biome: String = "") -> void:
	var nav := world.nav
	var cells := PackedByteArray()
	cells.resize(nav.width * nav.height)
	for y in nav.height:
		for x in nav.width:
			cells[y * nav.width + x] = nav.kind_at(Vector2i(x, y))
	var homes: Array = []
	var road_segments: Array = []
	var settlements: Array = []
	var eco := world.economy
	if eco != null:
		for pl in eco.players:
			var home := eco.hall_of(pl.owner)
			if home != null:
				homes.append([home.center, pl.faction])
		if not eco.sectors.is_empty():
			road_segments = SkirmishScenario.roads(eco)
		for sec in eco.sectors:
			settlements.append([sec.center, sec.size == "waystone"])
	var extra := {}
	var info := world.map_info
	if not info.is_empty():
		extra = {"regions": info.get("regions", []), "bridges": info.get("bridges", []), "props": info.get("props", []),
			"border": info.get("border", "mountains"), "plateaus": info.get("plateaus", [])}
		if base_biome == "":
			base_biome = String(info.get("base_biome", ""))
	field.build_map(nav.width, nav.height, cells, homes, road_segments, settlements, seed_value, base_biome, extra)
