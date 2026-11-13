class_name HudArt
extends RefCounted
## The art and the drawing helpers shared by the hero HUD, the hero window and the skill trees.
## Every painted piece is optional: assets/ui/skills/<skill>.png, assets/ui/passives/<stat>.png and
## assets/ui/hud/<piece>.png come from the project's painted UI art (tools/import_ui_art.py); until a piece exists
## a stand-in is drawn (skills borrow a fitting item icon, bars and potions are drawn in code).
## UI only: reads data, holds no rules.

const BRASS := Color("#c9a24a")
const BRASS_DIM := Color("#826c45")
const IRON := Color("#16120f")
const TEXT := Color("#eadfc4")
const TEXT_DIM := Color("#a89a7c")
const GOOD := Color("#7fc06a")
const BAD := Color("#d96a52")
const KEYS := ["Q", "W", "E", "R"]

## Bar colours (top, bottom) when there is no painted fill.
const FILLS := {
	"health": [Color("#c8402f"), Color("#5c120d")],
	"mana": [Color("#4a78d8"), Color("#14245e")],
	"xp": [Color("#e0b450"), Color("#6e4c14")],
	"enemy": [Color("#b03a2a"), Color("#4a0f0a")],
}
## The empty-slot symbol of each gear slot (the main game's UI icons, assets/ui/icons).
const SLOT_ICONS := {"weapon": "attack", "armor": "armor", "helm": "hero", "shield": "defense", "boots": "move",
	"charm": "charm", "banner": "banner"}
## Until the painted skill icons arrive each skill borrows the icon of an item that fits it.
const SKILL_STAND_INS := {
	"cleave": "wyrmjaw_cleaver", "leap": "worldspark_striders", "red_harvest": "bleeding_glaive",
	"shield_bash": "hammerfall_rondache", "defend_aura": "vigil_pavise", "last_stand": "standard_of_the_hold",
	"power_shot": "longwatch_bow", "volley": "ashroot_longbow", "arrow_storm": "gloamwheel_arbalest",
	"binding": "ossified_spiral", "arcane_bolt": "prism_of_the_bound_tempest", "cataclysm": "heart_of_the_caldera",
	"mend": "saints_knucklebone", "blessing_aura": "emberphoenix_brooch", "revival": "seed_of_the_first_pyre",
	"summon_minions": "iron_orchard_standard", "drain": "gilded_leech_mask", "legion": "warhost_oriflamme",
	"rallying_oath": "oathring_greatsword", "pinning_shafts": "border_crossbow",
	"lantern_of_mending": "lanternward_shield", "judgement": "kilnheart_executioner", "warcry": "bronze_ram_gonfalon",
	"cinderfall": "sceptre_of_the_pyre", "brand_of_agony": "cinderbrand_rod", "slag_shield": "aegis_of_cinders",
	"knit_the_fallen": "bonewright_coif", "bone_bulwark": "ossuary_brigandine",
	"rot_cloud": "standard_of_the_emerald_blight", "grave_cleave": "headsmans_maul", "bramble_wall": "crown_of_thorns",
	"called_shot": "antler_recurve", "sap_of_renewal": "amber_button", "feral_howl": "mistfang_treads",
	"anvil_blow": "thunderstone_sledge", "bombard": "oriflamme_of_the_living_furnace",
	"spark_lattice": "thundercoil_aegis", "riveted_aegis": "wardstone_mail", "undertow": "sunken_court_trident",
	"tidal_rally": "last_harbour_vexillum", "called_harpoon": "winterglass_harpoon",
	"pearl_of_mending": "drowned_saints_locket", "whirlwind_of_steel": "eclipsed_suns_chakram",
	"unbroken_line": "gatewardens_tower", "hail_of_shafts": "stormsplitter_fork",
	"unmaking": "veil_of_the_blind_regent", "sanctuary": "mirror_of_the_last_vigil",
	"soul_harvest": "hourglass_of_marrow", "shield_wall": "glacierbreak_bulwark",
	"dawn_charge": "helm_of_the_first_sunrise", "ember_burst": "emberglass_visor", "firestorm": "shroud_of_ash",
	"grasp_of_the_dead": "hollow_kings_tooth", "raise_the_barrow": "cairn_door_ward", "entangle": "rootbound_aketon",
	"wrath_of_the_grove": "dawnroot_crozier", "overcharge": "ninefold_orrery", "iron_tide": "basalt_carapace",
	"brine_spray": "pearlwarden_coat", "drowning_tide": "tideworn_sabatons", "veiled_strike": "viperwake_kris",
	"venom_shot": "venomglass_panoply", "veil_of_shadows": "pall_of_the_unremembered",
	"silk_snare": "starless_needle", "horn_of_the_hold": "antlered_cairn_crown", "hail_of_axes": "sappers_hatchet",
	"frostbite": "tear_of_the_frozen_deep", "feast_fire": "witchseed_reliquary", "shadowstep": "voidwalk_greaves",
	"night_without_end": "diadem_of_falling_stars", "glacial_shards": "rime_cathedral_vestment",
	"call_of_the_giants": "mooncleft_bardiche",
	"reaping_blow": "kilnheart_executioner", "sunder": "thunderstone_sledge", "challenge": "gatewardens_tower",
	"call_to_arms": "bronze_ram_gonfalon", "hunters_mark": "border_crossbow", "caltrops": "briarhook_sickle",
	"chain_lightning": "stormsplitter_fork", "withering_hex": "crown_of_the_plague_moon",
	"resurrection": "helm_of_the_first_sunrise", "purify": "tin_pilgrim_bell", "bind_champion": "greathelm_of_dread",
	"raise_dead": "hollow_kings_tooth", "dawnbreak": "dawnroot_crozier", "blood_price": "bloodtithe_scourge",
	"bone_burst": "ossuary_brigandine", "call_the_pack": "ratcatchers_whistle",
	"steam_blast": "oriflamme_of_the_living_furnace", "riptide": "sunken_court_trident",
	"venom_blades": "viperwake_kris", "rime_shell": "glacierbreak_bulwark",
}
## Passive nodes until their painted icons arrive: the main game's UI icons, or an item.
const PASSIVE_STAND_INS := {
	"attack": "ui/icons/attack", "defense": "ui/icons/defense", "power": "ui/icons/power", "knowledge": "ui/icons/knowledge",
	"hp": "items/scarred_plate", "hp_regen": "items/saints_knucklebone", "damage": "items/pitted_estoc",
	"damage_pct": "items/oathring_greatsword", "attack_speed": "items/duelists_basketblade",
	"mana": "items/tear_of_the_frozen_deep", "mana_regen": "items/drowned_saints_locket",
	"move_pct": "ui/icons/move", "cooldown_pct": "items/hourglass_of_marrow", "skill_pct": "items/scholars_quill",
	"xp_pct": "ui/icons/xp", "aura_might": "items/warhost_oriflamme", "aura_ward": "items/vigil_pavise",
	"aura_haste": "items/moorland_streamer", "marks": "items/lead_prayer_weight",
}

static var _cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	return WbStyle.texture(path)


## A painted HUD piece (assets/ui/hud/<name>.png or .jpg), or null.
static func piece(name: String) -> Texture2D:
	var t := tex("res://assets/ui/hud/%s.png" % name)
	return t if t != null else tex("res://assets/ui/hud/%s.jpg" % name)


static func has_painted_skill(skill_id: String) -> bool:
	return ResourceLoader.exists("res://assets/ui/skills/%s.png" % skill_id)


static func skill_icon(skill_id: String) -> Texture2D:
	var t := tex("res://assets/ui/skills/%s.png" % skill_id)
	if t == null and SKILL_STAND_INS.has(skill_id):
		t = tex("res://assets/items/%s.png" % SKILL_STAND_INS[skill_id])
	return t


## The icon of a stat or a passive node (StoryTrees.node_icon).
static func stat_icon(stat: String) -> Texture2D:
	var t := tex("res://assets/ui/passives/%s.png" % stat)
	if t == null and PASSIVE_STAND_INS.has(stat):
		t = tex("res://assets/%s.png" % PASSIVE_STAND_INS[stat])
	return t


static func ui_icon(name: String) -> Texture2D:
	return tex("res://assets/ui/icons/%s.png" % name)


static func slot_icon(slot: String) -> Texture2D:
	return ui_icon(String(SLOT_ICONS.get(slot, "pack")))


static func portrait(class_id: String) -> Texture2D:
	return tex(WbStyle.hero_portrait_path(class_id))


## The portrait square [x, y, size] of a unit sprite on its 128x128 sheet, from
## data/unit_portraits.json (tools/portrait_rects.py). The square may reach past the sprite's edges.
static func unit_portrait_rect(sprite_path: String) -> Rect2:
	if not _cache.has("unit_portraits"):
		var f := FileAccess.open("res://data/unit_portraits.json", FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		_cache["unit_portraits"] = parsed["rects"] if parsed is Dictionary else {}
	var r: Variant = _cache["unit_portraits"].get(sprite_path.get_file().get_basename())
	if r is Array and r.size() == 3:
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[2]))
	return Rect2(24, 14, 80, 80)


## Draws a unit's portrait into dest: its framed square, the part past the sprite's edges left empty.
static func unit_portrait(ci: CanvasItem, tex: Texture2D, sprite_path: String, dest: Rect2,
		modulate: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var src := unit_portrait_rect(sprite_path)
	var inside := src.intersection(Rect2(Vector2.ZERO, tex.get_size()))
	if inside.size.x <= 0.0 or inside.size.y <= 0.0:
		return
	var k := dest.size / src.size
	ci.draw_texture_rect_region(tex, Rect2(dest.position + (inside.position - src.position) * k, inside.size * k),
		inside, modulate)


## The main game's brass slot frame as a nine-slice.
static func slot_box() -> StyleBox:
	if _cache.has("slot_box"):
		return _cache["slot_box"]
	var sb: StyleBox
	var t := tex("res://assets/ui/slot.png")
	if t != null:
		var st := StyleBoxTexture.new()
		st.texture = t
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			st.set_texture_margin(side, 8)
		sb = st
	else:
		sb = WbStyle.flat_box(Color("#120f0b"), BRASS_DIM, 1)
	_cache["slot_box"] = sb
	return sb


## Where a painted frame's inside sits, as shares of its size (from assets/ui/hud/frames.json,
## written by tools/import_ui_art.py). Falls back to an even 15% rim.
static func opening(name: String) -> Rect2:
	if not _cache.has("frames_json"):
		var d := {}
		var f := FileAccess.open("res://assets/ui/hud/frames.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				d = parsed
		_cache["frames_json"] = d
	var o: Variant = (_cache["frames_json"] as Dictionary).get(name)
	if o is Array and (o as Array).size() == 4:
		var a: Array = o
		return Rect2(float(a[0]), float(a[1]), float(a[2]) - float(a[0]), float(a[3]) - float(a[1]))
	return Rect2(0.15, 0.15, 0.7, 0.7)


## Where to draw a painted frame so its inside covers `content`.
static func frame_rect(name: String, content: Rect2) -> Rect2:
	var o := opening(name)
	var size := Vector2(content.size.x / o.size.x, content.size.y / o.size.y)
	return Rect2(content.position - o.position * size, size)


## Draws a painted frame around `content`; false when there is no painted piece.
static func draw_framed(ci: CanvasItem, name: String, content: Rect2, mod: Color = Color.WHITE) -> bool:
	var t := piece(name)
	if t == null:
		return false
	ci.draw_texture_rect(t, frame_rect(name, content), false, mod)
	return true


## Draws a long horizontal frame (the bar frame) around `content`: the end caps keep their shape and
## only the middle stretches. False when there is no painted piece.
static func draw_hframe(ci: CanvasItem, name: String, content: Rect2) -> bool:
	var t := piece(name)
	if t == null:
		return false
	var o := opening(name)
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var h := content.size.y / o.size.y
	var s := h / th
	var top := content.position.y - o.position.y * h
	var cap_l := o.position.x * tw
	var cap_r := (1.0 - o.end.x) * tw
	var x0 := content.position.x - cap_l * s
	var x1 := content.end.x + cap_r * s
	ci.draw_texture_rect_region(t, Rect2(x0, top, cap_l * s, h), Rect2(0, 0, cap_l, th))
	ci.draw_texture_rect_region(t, Rect2(content.position.x, top, content.size.x, h),
		Rect2(cap_l, 0, tw - cap_l - cap_r, th))
	ci.draw_texture_rect_region(t, Rect2(content.end.x, top, cap_r * s, h), Rect2(tw - cap_r, 0, cap_r, th))
	return true


static func _gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var key := "g_%s_%s" % [top.to_html(), bottom.to_html()]
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([top.lightened(0.25), top, bottom])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 32
	_cache[key] = t
	return t


static func _radial(inner: Color, outer: Color) -> GradientTexture2D:
	var key := "r_%s_%s" % [inner.to_html(), outer.to_html()]
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	g.colors = PackedColorArray([inner, outer])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.42)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 64
	t.height = 64
	_cache[key] = t
	return t


# --- Drawing ------------------------------------------------------------------------------------

## Text with a dark outline, so it reads over art.
static func text(ci: CanvasItem, font: Font, p: Vector2, s: String, fs: int, col: Color = TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	ci.draw_string_outline(font, p, s, align, w, fs, 4, Color(0.04, 0.03, 0.02, 0.9))
	ci.draw_string(font, p, s, align, w, fs, col)


## A recessed iron frame with a brass rim: the base of slots, bars and portraits.
static func bevel(ci: CanvasItem, r: Rect2, rim: Color = BRASS_DIM, fill: Color = IRON, width: float = 2.0) -> void:
	ci.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.85))
	ci.draw_rect(r, fill)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), Color(0, 0, 0, 0.45))
	ci.draw_rect(r, rim, false, width)
	ci.draw_rect(r.grow(-width), Color(1, 1, 1, 0.05), false, 1.0)


## A resource bar (health, mana, xp): recessed channel, a shaded liquid fill, a bright meniscus,
## the frame and the centred text. kind picks the colours or the painted fill.
static func bar(ci: CanvasItem, r: Rect2, ratio: float, kind: String, label: String = "", font: Font = null,
		fs: int = 12) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	# The painted frame has its own dark channel, so it goes under the fill.
	var framed := draw_hframe(ci, "bar_frame", r)
	if not framed:
		ci.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.9))
	ci.draw_rect(r, Color(0.04, 0.03, 0.03, 0.55 if framed else 1.0))
	var fr := Rect2(r.position, Vector2(r.size.x * ratio, r.size.y))
	if fr.size.x > 0.5:
		var painted := piece("fill_" + kind)
		if painted != null:
			ci.draw_texture_rect_region(painted, fr, Rect2(Vector2.ZERO, Vector2(painted.get_width() * ratio,
				painted.get_height())))
		else:
			var c: Array = FILLS.get(kind, FILLS["health"])
			ci.draw_texture_rect(_gradient(c[0], c[1]), fr, false)
		ci.draw_rect(Rect2(fr.position + Vector2(0, 1), Vector2(fr.size.x, 1.5)), Color(1, 1, 1, 0.22))
		if ratio < 1.0:
			ci.draw_rect(Rect2(Vector2(fr.end.x - 1.5, fr.position.y), Vector2(1.5, fr.size.y)), Color(1, 0.95, 0.85, 0.5))
	# Quarter ticks.
	for q in [0.25, 0.5, 0.75]:
		ci.draw_line(Vector2(r.position.x + r.size.x * q, r.end.y - 3), Vector2(r.position.x + r.size.x * q, r.end.y),
			Color(0, 0, 0, 0.5), 1.0)
	if not framed:
		ci.draw_rect(r.grow(1.0), BRASS_DIM, false, 1.5)
		ci.draw_rect(r.grow(2.5), Color(0, 0, 0, 0.6), false, 1.0)
	if label != "" and font != null:
		text(ci, font, Vector2(r.position.x, r.get_center().y + fs * 0.36), label, fs, Color("#f4ecd8"),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## A potion flask: the painted icon, or a drawn round flask with glowing liquid, a cork and a shine.
static func potion(ci: CanvasItem, r: Rect2, kind: String, full: bool) -> void:
	var painted := piece("potion_" + kind)
	var mod := Color.WHITE if full else Color(0.35, 0.35, 0.35, 0.8)
	if painted != null:
		ci.draw_texture_rect(painted, r, false, mod)
		return
	var c: Array = FILLS.get(kind, FILLS["health"])
	var s := minf(r.size.x, r.size.y)
	var centre := r.get_center() + Vector2(0, s * 0.1)
	var rad := s * 0.32
	ci.draw_circle(centre, rad + 2.0, Color(0, 0, 0, 0.85))
	ci.draw_circle(centre, rad, Color(0.25, 0.27, 0.3, 0.55))
	if full:
		ci.draw_texture_rect(_radial((c[0] as Color).lightened(0.2), c[1]), Rect2(centre - Vector2(rad, rad) * 0.92,
			Vector2(rad, rad) * 1.84), false)
	var neck := Rect2(centre + Vector2(-s * 0.08, -rad - s * 0.17), Vector2(s * 0.16, s * 0.19))
	ci.draw_rect(neck.grow(1.0), Color(0, 0, 0, 0.85))
	ci.draw_rect(neck, Color(0.3, 0.32, 0.35, 0.8))
	var cork := Rect2(neck.position + Vector2(-1.5, -s * 0.09), Vector2(neck.size.x + 3.0, s * 0.1))
	ci.draw_rect(cork.grow(1.0), Color(0, 0, 0, 0.85))
	ci.draw_rect(cork, Color("#7a5532") if full else Color("#4a3a2a"))
	ci.draw_arc(centre, rad - 1.0, PI * 1.1, PI * 1.45, 8, Color(1, 1, 1, 0.45 if full else 0.15), 2.0)
	ci.draw_arc(centre, rad, 0, TAU, 32, BRASS_DIM if full else Color(0.3, 0.27, 0.22), 1.5)


## A skill tile: the icon in a framed square. state: "ready", "locked", "cooldown", "mana".
## cd: share of the cooldown left (0..1), drawn as a clock sweep.
static func skill_tile(ci: CanvasItem, r: Rect2, skill_id: String, state: String = "ready", cd: float = 0.0,
		rim: Color = BRASS_DIM) -> void:
	bevel(ci, r, rim, IRON, 2.0)
	var icon := skill_icon(skill_id) if skill_id != "" else null
	if icon != null:
		var mod := Color.WHITE
		if state == "locked":
			mod = Color(0.32, 0.3, 0.28)
		elif state == "mana":
			mod = Color(0.55, 0.6, 1.0)
		var ir := r.grow(-3.0)
		if not has_painted_skill(skill_id):
			# Item stand-in: on a warm glow so it reads as a skill, not loot.
			ci.draw_texture_rect(_radial(Color(0.45, 0.25, 0.12, 0.9), Color(0.05, 0.04, 0.03, 1.0)), ir, false, mod)
			ir = ir.grow(-2.0)
		ci.draw_texture_rect(icon, ir, false, mod)
	if cd > 0.0:
		_sweep(ci, r.grow(-3.0), cd)
	draw_framed(ci, "skill_slot", r.grow(-1.0))


## An empty slot or a button: the iron bevel inside the painted skill-slot frame.
static func slot(ci: CanvasItem, r: Rect2, rim: Color = BRASS_DIM, fill: Color = IRON, width: float = 2.0) -> void:
	bevel(ci, r, rim, fill, width)
	draw_framed(ci, "skill_slot", r.grow(-1.0))


## A clock-wise darkening sweep over a rect: the share still waiting.
static func _sweep(ci: CanvasItem, r: Rect2, f: float) -> void:
	var c := r.get_center()
	var rad := r.size.length() * 0.5
	var pts := PackedVector2Array([c])
	var start := -PI * 0.5
	var steps := 24
	for i in steps + 1:
		var a := start + TAU * (1.0 - f) + TAU * f * float(i) / steps
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	# Clip to the square by drawing into it with a polygon then masking edges with the frame.
	var clipped := PackedVector2Array()
	for p in pts:
		clipped.append(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))
	ci.draw_colored_polygon(clipped, Color(0, 0, 0, 0.62))


## An item cell: rarity-tinted backing, the item icon, the rarity rim; an empty cell shows the
## slot's symbol faded.
static func item_cell(ci: CanvasItem, r: Rect2, item: Dictionary, icat: ItemCatalog, slot: String = "",
		hover: bool = false, usable: bool = true) -> void:
	var box := slot_box()
	ci.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.8))
	ci.draw_style_box(box, r)
	if item.is_empty():
		var t := slot_icon(slot) if slot != "" else null
		if t != null:
			var s := r.size.x * 0.62
			ci.draw_texture_rect(t, Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false,
				Color(1, 1, 1, 0.22))
		if hover:
			ci.draw_rect(r.grow(-2.0), Color(1, 0.9, 0.6, 0.08))
		return
	var col := icat.color(item)
	ci.draw_texture_rect(_radial(Color(col.r, col.g, col.b, 0.38), Color(0, 0, 0, 0.0)), r.grow(-3.0), false)
	var icon := LootMarks.icon(item)
	if icon != null:
		ci.draw_texture_rect(icon, r.grow(-4.0), false, Color.WHITE if usable else Color(0.8, 0.35, 0.3))
	ci.draw_rect(r.grow(-1.0), col if item["rarity"] != "common" else BRASS_DIM, false, 2.0)
	if hover:
		ci.draw_rect(r.grow(-2.0), Color(1, 0.95, 0.75, 0.12))


## A framed tooltip box. Lines: the first is the title (title_col); a line starting with "!" is a
## warning, with "+" a bonus, with "~" dim. Placed at `at` and kept inside `bounds`.
static func tooltip(ci: CanvasItem, font: Font, at: Vector2, bounds: Rect2, lines: Array, title_col: Color,
		icon: Texture2D = null, width: float = 300.0) -> void:
	var lh := 17.0
	var icon_w := 0.0 if icon == null else 70.0
	var w := width + icon_w
	# Long lines wrap (each keeps its colour), so nothing is cut off.
	var rows: Array = []  ## [text, colour, font size]
	for i in lines.size():
		var s := String(lines[i])
		var col := Color("#d9d0bc")
		var fs := 13
		if i == 0:
			col = title_col
			fs = 15
		elif s.begins_with("!"):
			col = BAD
			s = s.substr(1)
		elif s.begins_with("+"):
			col = Color("#9ccf86")
		elif s.begins_with("~"):
			col = TEXT_DIM
			s = s.substr(1)
		for part in wrap_text(font, s, width - 14.0, fs):
			rows.append([part, col, fs])
	var h := lh * rows.size() + 14.0
	if icon != null:
		h = maxf(h, 78.0)
	var p := at
	p.x = clampf(p.x, bounds.position.x + 4.0, bounds.end.x - w - 4.0)
	p.y = clampf(p.y, bounds.position.y + 4.0, bounds.end.y - h - 4.0)
	var r := Rect2(p, Vector2(w, h))
	ci.draw_rect(r.grow(3.0), Color(0, 0, 0, 0.5))
	ci.draw_rect(r, Color(0.06, 0.05, 0.04, 0.97))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 22.0)), Color(title_col.r, title_col.g, title_col.b, 0.1))
	ci.draw_rect(r, BRASS_DIM, false, 1.5)
	ci.draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.04), false, 1.0)
	if icon != null:
		var ir := Rect2(r.position + Vector2(w - 68.0, 7.0), Vector2(60, 60))
		bevel(ci, ir, title_col.darkened(0.2))
		ci.draw_texture_rect(icon, ir.grow(-2.0), false)
	for i in rows.size():
		var row: Array = rows[i]
		ci.draw_string(font, r.position + Vector2(9, 18 + i * lh), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, row[2], row[1])


## Splits text into lines no wider than width at font size fs (a single over-long word stays whole).
static func wrap_text(font: Font, text: String, width: float, fs: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var t := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(line)
			line = word
		else:
			line = t
	out.append(line)
	return out


## The portrait in an iron-and-brass frame (or the painted portrait frame).
static func framed_portrait(ci: CanvasItem, r: Rect2, class_id: String, dim: bool = false,
		rim: Color = BRASS) -> void:
	var t := portrait(class_id)
	var mod := Color(0.4, 0.4, 0.4) if dim else Color.WHITE
	var pf := piece("portrait_frame")
	if pf != null:
		# The painted frame is tall (an arch over a shield plate): it is fitted round the square, a
		# little taller than it, and the portrait is cropped to the frame's opening.
		var fh := r.size.y * 1.3
		var fw := fh * pf.get_width() / pf.get_height()
		var f := Rect2(Vector2(r.get_center().x - fw * 0.5, r.position.y - r.size.y * 0.08), Vector2(fw, fh))
		var o := opening("portrait_frame")
		var inner := Rect2(f.position + o.position * f.size, o.size * f.size)
		ci.draw_rect(inner, Color(0.03, 0.025, 0.02))
		if t != null:
			var tw := float(t.get_width())
			var th := float(t.get_height())
			var cw := minf(tw, th * inner.size.x / inner.size.y)
			ci.draw_texture_rect_region(t, inner, Rect2((tw - cw) * 0.5, 0, cw, cw * inner.size.y / inner.size.x), mod)
		ci.draw_texture_rect(pf, f, false, Color(0.6, 0.6, 0.6) if dim else Color.WHITE)
		return
	ci.draw_rect(r.grow(3.0), Color(0, 0, 0, 0.9))
	if t != null:
		ci.draw_texture_rect(t, r, false, mod)
	ci.draw_rect(r, rim, false, 2.0)
	ci.draw_rect(r.grow(2.5), Color("#3a2f22"), false, 2.0)
	# Small brass corner pieces.
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		ci.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.9))
		ci.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), rim)


## A small round badge with a number (levels, counts).
static func badge(ci: CanvasItem, font: Font, c: Vector2, s: String, radius: float = 11.0, col: Color = BRASS) -> void:
	ci.draw_circle(c, radius + 2.0, Color(0, 0, 0, 0.9))
	ci.draw_texture_rect(_radial(col.lightened(0.15), col.darkened(0.55)), Rect2(c - Vector2(radius, radius),
		Vector2(radius, radius) * 2.0), false)
	ci.draw_arc(c, radius, 0, TAU, 24, col.lightened(0.3), 1.5)
	var fs := int(maxf(11.0, radius * 1.2))
	text(ci, font, Vector2(c.x - radius - 4.0, c.y + fs * 0.36), s, fs, Color("#fff6e0"),
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 8.0)


## A "+" button to spend a point, glowing green.
static func plus_button(ci: CanvasItem, font: Font, r: Rect2, hover: bool = false) -> void:
	ci.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.9))
	ci.draw_texture_rect(_gradient(Color("#5fb04a") if not hover else Color("#7fd060"), Color("#1d4a16")), r, false)
	ci.draw_rect(r, Color("#b8e08a"), false, 1.0)
	var c := r.get_center()
	ci.draw_rect(Rect2(c - Vector2(r.size.x * 0.3, 1.5), Vector2(r.size.x * 0.6, 3)), Color.WHITE)
	ci.draw_rect(Rect2(c - Vector2(1.5, r.size.y * 0.3), Vector2(3, r.size.y * 0.6)), Color.WHITE)
