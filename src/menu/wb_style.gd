class_name WbStyle
extends RefCounted
## Warbound's UI look, ported from the main game's UiStyle and MainMenu theme:
## faction palettes, the framed wood-and-brass panels, Cinzel/Lora fonts,
## the menu button plaques, labels, faction emblems and resource icons.
## Data comes from data/ui.json (tools/sync_ui_from_main.py).

const TITLE := "Crowns of Caern"
const SUBTITLE := "Warbound"
const DISPLAY_FONT := preload("res://assets/fonts/Cinzel.ttf")
const BODY_FONT := preload("res://assets/fonts/Lora.ttf")

const PANEL_BG := Color("#1d1813")
const PANEL_BG_LIGHT := Color("#2a221a")
const BRASS := Color("#c9a24a")
const TEXT := Color("#eadfc4")
const TEXT_DIM := Color("#a89a7c")
const GOOD := Color("#7fc06a")
const BAD := Color("#d96a52")
const WARN := Color("#e0b450")

static var _data: Dictionary = {}
static var _textures: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui.json"))
		if parsed is Dictionary:
			_data = parsed
	return _data


## Palette, name and colour of a faction; falls back to Concord.
static func faction_info(id: String) -> Dictionary:
	var f: Dictionary = data().get("factions", {})
	return f.get(id, f.get("concord", {}))


static func faction_name(id: String) -> String:
	if id == "random":
		return "Random"
	return String(faction_info(id).get("name", id.capitalize()))


static func accent(faction: String = "") -> Color:
	if faction == "":
		return BRASS
	return Color(String(faction_info(faction).get("accent", "#c9a24a")))


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_textures[path] = t
	return t


static func emblem(faction: String) -> Texture2D:
	return texture(emblem_path(faction))


## A small copy of a texture for OptionButton rows (they draw icons at native size).
static func small_icon(path: String, px: int = 28) -> Texture2D:
	var key := "%s@%d" % [path, px]
	if _textures.has(key):
		return _textures[key]
	var out: Texture2D = null
	var t := texture(path)
	if t != null:
		var img := t.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.resize(px, px, Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
	_textures[key] = out
	return out


static func emblem_path(faction: String) -> String:
	return "res://assets/ui/emblems/%s.png" % faction


## A hero class portrait, or its faction's crest when there is none.
static func hero_portrait_path(class_id: String) -> String:
	var p := "res://assets/ui/heroes/%s.png" % class_id
	if ResourceLoader.exists(p):
		return p
	var cls: Dictionary = HeroCatalog.get_default().classes.get(class_id, {})
	return emblem_path(String(cls.get("faction", "concord")))


static func resource_icon(resource: String) -> Texture2D:
	return texture("res://assets/ui/res_%s.png" % resource)


static func backdrop_texture(id: String) -> Texture2D:
	return texture("res://assets/ui/menu_%s.jpg" % id)


## A full-rect menu backdrop that covers the screen without stretching.
static func backdrop(id: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = "Backdrop"
	image.texture = backdrop_texture(id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return image


## The soft ember glow rising from the bottom of the menu screens.
static func ember_glow(color: Color = BRASS) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.16))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 1.05)
	t.fill_to = Vector2(0.5, 0.2)
	t.width = 256
	t.height = 256
	var glow := TextureRect.new()
	glow.name = "EmberGlow"
	glow.texture = t
	glow.self_modulate = color
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glow


## A darkening veil so panels read on top of the busy painted backdrops.
static func veil(alpha: float = 0.35) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Veil"
	r.color = Color(0, 0, 0, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


static func flat_box(bg: Color = PANEL_BG, border: Color = BRASS, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb


## The framed panel from the art set in a faction's material (wood, iron band,
## brass trim), or a flat panel if the art is missing.
static func frame_panel(faction: String = "concord", content_margin: float = 18.0) -> StyleBox:
	var key := "panel_" + faction
	var sprites: Dictionary = data().get("sprites", {})
	if not sprites.has(key):
		key = "panel_concord"
	var tex := texture("res://assets/ui/%s.png" % key)
	if tex == null or not sprites.has(key):
		var info := faction_info(faction)
		var flat := flat_box(Color(String(info.get("panel", "#1d1813"))), accent(faction))
		flat.set_content_margin_all(content_margin)
		return flat
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var ns: Array = sprites[key].get("nine_slice", [0, 0, 0, 0])
	sb.texture_margin_left = ns[0]
	sb.texture_margin_top = ns[1]
	sb.texture_margin_right = ns[2]
	sb.texture_margin_bottom = ns[3]
	# Painted material, not a tile: stretch the quiet centre, keep the corners.
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.set_content_margin_all(content_margin)
	return sb


## A quiet inset card for list entries (faction cards, campaign cards).
static func card_box(faction: String = "", selected: bool = false) -> StyleBoxFlat:
	var info := faction_info(faction if faction != "" else "concord")
	var bg := Color(String(info.get("raised", "#2a221a")))
	bg.a = 0.92
	var border := accent(faction) if selected else Color("#826c45")
	var sb := flat_box(bg, border, 2 if selected else 1)
	sb.shadow_size = 3
	sb.set_content_margin_all(10)
	return sb


## The menu theme: Lora body text, Cinzel buttons, dark brass-edged plaques,
## custom checkboxes. Shared by every Warbound menu and the pause menu.
static func menu_theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 16
	t.set_font("font", "Button", DISPLAY_FONT)
	t.set_font("font", "OptionButton", BODY_FONT)
	t.set_stylebox("panel", "PanelContainer", frame_panel())
	t.set_stylebox("panel", "Panel", frame_panel())
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 15)
	t.set_color("default_color", "RichTextLabel", TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": Color("#211c18ed"), "hover": Color("#3b2e20f5"),
			"pressed": Color("#15110ff5"), "disabled": Color("#201c1bc9")}[state]
		box.border_color = {"normal": Color("#826c45"), "hover": Color("#d4b46b"),
			"pressed": Color("#b08a4d"), "disabled": Color("#524a3a")}[state]
		box.set_border_width_all(1)
		box.set_corner_radius_all(1)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		box.shadow_color = Color(0, 0, 0, 0.6)
		box.shadow_size = 3
		for control_type in ["Button", "OptionButton"]:
			t.set_stylebox(state, control_type, box)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#e6c67c")
	focus.set_border_width_all(2)
	focus.set_content_margin_all(0)
	for control_type in ["Button", "OptionButton", "LineEdit"]:
		t.set_stylebox("focus", control_type, focus)
	for control_type in ["Button", "OptionButton"]:
		t.set_color("font_color", control_type, Color("#eadcba"))
		t.set_color("font_hover_color", control_type, Color("#fff0c8"))
		t.set_color("font_pressed_color", control_type, Color("#d8b879"))
		t.set_color("font_disabled_color", control_type, Color("#887d6b"))
		t.set_color("font_outline_color", control_type, Color("#17100b"))
		t.set_constant("outline_size", control_type, 1)
	# CheckBox inherits Button; keep its indicator and drop the plaque.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_font("font", "CheckBox", BODY_FONT)
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		t.set_icon(icon_name, "CheckBox", check_icon(icon_name.begins_with("checked"), icon_name.ends_with("disabled")))
	var edit := flat_box(Color("#15110f"), Color("#826c45"), 1)
	edit.set_content_margin_all(6)
	edit.shadow_size = 0
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", TEXT)
	var popup := flat_box(Color("#1d1813"), Color("#826c45"), 1)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color("#fff0c8"))
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#3b2e20")
	t.set_stylebox("hover", "PopupMenu", hover)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color("#15110f")
	slider.border_color = Color("#826c45")
	slider.set_border_width_all(1)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	var filled := StyleBoxFlat.new()
	filled.bg_color = BRASS.darkened(0.25)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var sep := StyleBoxLine.new()
	sep.color = Color("#826c4588")
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	return t


static func check_icon(checked: bool, disabled: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var edge := Color("#6d6046") if disabled else Color("#b69a61")
	var fill := Color("#211c18")
	for y in range(16):
		for x in range(16):
			image.set_pixel(x, y, edge if x == 0 or y == 0 or x == 15 or y == 15 else fill)
	if checked:
		var ink := Color("#e2c27a") if not disabled else Color("#847861")
		for point in [Vector2i(3, 8), Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11),
				Vector2i(7, 10), Vector2i(8, 9), Vector2i(9, 8), Vector2i(10, 7),
				Vector2i(11, 6), Vector2i(12, 5)]:
			image.set_pixelv(point, ink)
			image.set_pixelv(point + Vector2i(0, 1), ink)
	return ImageTexture.create_from_image(image)


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A Cinzel heading in brass with a dark outline.
static func heading(text: String, size: int = 24, color: Color = BRASS) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", DISPLAY_FONT)
	l.add_theme_color_override("font_outline_color", Color("#100b08"))
	l.add_theme_constant_override("outline_size", 4)
	return l


## A thin brass rule with the heading text, used to split forms into sections.
static func section(text: String, size: int = 16) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := heading(text, size)
	l.add_theme_constant_override("outline_size", 2)
	row.add_child(l)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


## A large menu plaque button (title screen, pause menu).
static func menu_button(text: String, cb: Callable, width: float = 292.0) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.replace(" ", "")
	b.custom_minimum_size = Vector2(width, 45)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_font_override("font", DISPLAY_FONT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


static func icon(tex: Texture2D, px: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = px
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The Crowns of Caern wordmark with "WARBOUND" set below it.
static func brand(compact: bool = false) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Brand"
	col.add_theme_constant_override("separation", -6 if not compact else -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := texture("res://assets/ui/wordmark.png")
	if tex != null:
		var mark := icon(tex, Vector2(420, 120) if compact else Vector2(720, 210))
		mark.name = "Wordmark"
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(mark)
	else:
		var t := heading(TITLE.to_upper(), 30 if compact else 48)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
	var sub := heading(SUBTITLE.to_upper(), 22 if compact else 34, Color("#e0c27a"))
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_constant_override("shadow_offset_y", 2)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	# Letter-spaced like an engraved plate.
	var spaced := ""
	for i in sub.text.length():
		spaced += sub.text[i] + ("  " if i < sub.text.length() - 1 else "")
	sub.text = spaced
	col.add_child(sub)
	return col
