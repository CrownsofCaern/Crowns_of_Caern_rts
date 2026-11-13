extends SceneTree
## Top-down pictures of generated skirmish maps (headless, no GPU): terrain kinds, roads,
## bridges, set pieces, settlements, homes and sites. One PNG per template and seed.
##   godot --headless --path . --script res://tools/map_sheet.gd -- <out dir> [seeds=1] [template|all] [players]

const KIND_COLORS := {0: Color("#6b6340"), 1: Color("#2b2620"), 2: Color("#24414a"), 3: Color("#8a7a66"), 4: Color("#2f4220")}
const SCALE := 4


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/maps"
	var seeds := int(a[1]) if a.size() > 1 else 1
	var only: String = a[2] if a.size() > 2 else "all"
	DirAccess.make_dir_recursive_absolute(out)
	var pools := {2: ["concord", "hollow"], 3: ["concord", "frostmarch", "ashen"], 4: ["concord", "hollow", "darkelf", "frostmarch"]}
	for players in ([int(a[3])] if a.size() > 3 else [2, 4]):
		for id: String in MapGen.template_ids(players):
			if only != "all" and only != id:
				continue
			for s in seeds:
				var t0 := Time.get_ticks_msec()
				var w := SkirmishScenario.build_skirmish(101 + s * 7, pools[players], id)
				var ms := Time.get_ticks_msec() - t0
				var img := picture(w)
				var path := "%s/%s_%dp_%d.png" % [out, id, players, s]
				img.save_png(path)
				print("%s %dp seed %d: %dx%d, %d sectors, %d piles, %d bridges, %d props, %d lairs, %d units, %d ms" % [id, players, s,
					w.nav.width, w.nav.height, w.economy.sectors.size(), w.economy.nodes.size(), w.map_info["bridges"].size(),
					w.map_info["props"].size(), w.map_info["lairs"].size(), w.units.size(), ms])
	quit()


static func picture(w: SimWorld) -> Image:
	var nav := w.nav
	var img := Image.create(nav.width * SCALE, nav.height * SCALE, false, Image.FORMAT_RGB8)
	for y in nav.height:
		for x in nav.width:
			var c: Color = KIND_COLORS.get(nav.kind_at(Vector2i(x, y)), Color.MAGENTA)
			img.fill_rect(Rect2i(x * SCALE, y * SCALE, SCALE, SCALE), c)
	var k := float(SCALE) / NavGrid.CELL
	for rd in w.map_info.get("roads", []):
		_line(img, rd[0] * k, rd[1] * k, Color("#b89a62"), 1)
	for br in w.map_info.get("bridges", []):
		_line(img, br[0] * k, br[1] * k, Color("#c8752a"), 3)
	for p in w.map_info.get("props", []):
		_dot(img, p[1] * k, 2, Color("#d9d2c0"))
	for n in w.economy.nodes:
		_dot(img, n.pos * k, 2, Color("#e8d04a") if n.resource == "gems" else (Color("#3f8f3f") if n.resource == "wood" else Color("#9aa6b8")))
	for s in w.economy.sectors:
		var col := Color("#e0c27a")
		if s.home_of >= 0:
			col = [Color(0.35, 0.6, 1.0), Color(0.95, 0.3, 0.25), Color(0.4, 0.85, 0.35), Color(0.95, 0.8, 0.25)][s.home_of]
		_dot(img, s.center * k, {"waystone": 4, "farmstead": 5, "hamlet": 6, "village": 7, "town": 9, "city": 11}.get(s.size, 5), col)
	for l in w.map_info.get("lairs", []):
		_dot(img, l[0] * k, 3 + int(l[1]) * 2, Color("#c0201a"))
	for p in w.map_info.get("shrines", []):
		_dot(img, p * k, 4, Color("#7fd6ff"))
	for p in w.map_info.get("merchants", []):
		_dot(img, p * k, 4, Color("#f0a0ff"))
	return img


static func _dot(img: Image, p: Vector2, r: int, c: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var q := Vector2i(int(p.x) + x, int(p.y) + y)
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(q, c)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, wdt: int) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), wdt, c)
