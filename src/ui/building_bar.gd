class_name BuildingBar
extends Control
## A row of small emblems above the minimap: your hall (home settlement), then one per unit-training building (tiers 1-2,
## 3-4, 5, 6, 7, 8: economy.json dwelling_slots), then your house's two faction buildings (tier = their index). Click one to select that building (again: the next one of its kind, and the camera jumps
## there). Greyed out while you have none finished.

const CELL := 25.0
const GAP := 3.0

var skirmish: Node
var _cells: Array = []  ## [{rect, kind, tier}]
var _font: Font


func _ready() -> void:
	_font = WbStyle.BODY_FONT
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	# Hero-only campaign maps have no town: the row only shows once there is something to pick.
	visible = skirmish != null and skirmish.world != null and (skirmish.mission == null or _has_any())
	queue_redraw()


func _has_any() -> bool:
	for b: Building in skirmish.world.economy.buildings:
		if b.owner == Skirmish.PLAYER and (b.kind == "dwelling" or b.kind == "special"):
			return true
	return not buildings_for("hall", 0).is_empty()


## What a slot picks, oldest first: for "hall" your home settlement (a Sector), for "dwelling" your
## buildings that train that tier (unfinished ones only when finished_only is false).
func buildings_for(kind: String, tier: int, finished_only: bool = true) -> Array:
	var out: Array = []
	if skirmish == null or skirmish.world == null:
		return out
	if kind == "hall":
		for sec: Sector in skirmish.world.economy.sectors:
			if sec.home_of == Skirmish.PLAYER and sec.owner == Skirmish.PLAYER:
				out.append(sec)
		return out
	var sid := _special_id(tier) if kind == "special" else ""
	for b: Building in skirmish.world.economy.buildings:
		if b.owner != Skirmish.PLAYER or b.kind != kind or (kind == "dwelling" and not b.trains(tier)) \
				or (kind == "special" and b.special != sid):
			continue
		if finished_only and not b.done():
			continue
		out.append(b)
	return out


func _slots() -> Array:
	var out: Array = [["hall", 0]]
	for t: int in skirmish.world.economy.slot_heads():
		out.append(["dwelling", t])
	for i in _specials().size():
		out.append(["special", i])
	return out


func _specials() -> Array:
	var eco: Economy = skirmish.world.economy
	return eco.special_defs(eco.player(Skirmish.PLAYER).faction)


func _special_id(i: int) -> String:
	var defs := _specials()
	return String(defs[i]["id"]) if i < defs.size() else ""


func _draw() -> void:
	if skirmish == null or skirmish.world == null:
		return
	_cells.clear()
	var mouse := get_local_mouse_position()
	var units: Array = skirmish.world.catalog.faction_units(skirmish.factions[0])
	var slots := _slots()
	var x := size.x - slots.size() * (CELL + GAP) + GAP
	var hover := -1
	for i in slots.size():
		var kind: String = slots[i][0]
		var tier: int = slots[i][1]
		var r := Rect2(Vector2(x + i * (CELL + GAP), size.y - CELL), Vector2(CELL, CELL))
		_cells.append({"rect": r, "kind": kind, "tier": tier})
		var have := not buildings_for(kind, tier).is_empty()
		var selected := _is_selected(kind, tier)
		var rim := HudArt.BRASS if selected else (HudArt.BRASS_DIM if have else Color(0.25, 0.22, 0.18))
		HudArt.bevel(self, r, rim, Color(0.06, 0.05, 0.04), 1.5)
		var mod := Color.WHITE if have else Color(0.3, 0.3, 0.3, 0.75)
		var ir := r.grow(-2.0)
		if kind == "hall":
			var crest := HudArt.tex("res://assets/ui/emblems/%s.png" % skirmish.factions[0])
			if crest != null:
				draw_texture_rect(crest, ir, false, mod)
		elif kind == "special":
			var st := HudArt.tex("res://assets/buildings/%s.png" % _specials()[tier]["key"])
			if st != null:
				draw_texture_rect(st, ir, false, mod)
		elif tier - 1 < units.size():
			var uid: String = units[tier - 1]
			HudArt.unit_portrait(self, skirmish.unit_texture(uid), String(skirmish.world.catalog.get_unit(uid)["sprite"]),
				ir, mod)
			var span: Array = skirmish.world.economy.slot_tiers(tier)
			draw_string(_font, Vector2(r.position.x + 2, r.end.y - 2), str(tier) if span.size() == 1 else "%d-%d" % [span[0], span[-1]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.95, 0.88, 0.7, 0.9 if have else 0.45))
		if r.has_point(mouse):
			hover = i
			draw_rect(r, Color(1, 0.95, 0.75, 0.12))
	if hover >= 0:
		_draw_tip(hover, units)


func _draw_tip(i: int, units: Array) -> void:
	var c: Dictionary = _cells[i]
	var r: Rect2 = c["rect"]
	var all := buildings_for(c["kind"], c["tier"], false)
	var done := buildings_for(c["kind"], c["tier"])
	var title := "Your hall"
	if c["kind"] == "dwelling":
		var span: Array = skirmish.world.economy.slot_tiers(int(c["tier"]))
		var names: Array = []
		for t: int in span:
			if t - 1 < units.size():
				names.append(String(skirmish.world.catalog.units[units[t - 1]]["name"]))
		var who := ", ".join(names)
		title = ("Tier %d: %s" % [span[0], who]) if span.size() == 1 else "Tiers %d-%d: %s" % [span[0], span[-1], who]
		if not all.is_empty():
			title = "%s (%s)" % [skirmish.world.catalog.building_names.get((all[0] as Building).key, title), who]
	if c["kind"] == "special":
		var d: Dictionary = _specials()[int(c["tier"])]
		title = "%s: %s" % [d["name"], d["text"]]
	var lines: Array = [title]
	if done.is_empty():
		lines.append("!Not built yet" if all.is_empty() else "~Still being built")
	else:
		lines.append("Click to select (%d)" % done.size() if done.size() > 1 else "Click to select")
		lines.append("~Click again to look at it")
	var bounds := Rect2(Vector2(-get_global_rect().position.x, -get_global_rect().position.y), get_viewport_rect().size)
	HudArt.tooltip(self, _font, Vector2(r.position.x - 120.0, r.position.y - 80.0), bounds, lines, Color("#f0dfb4"),
		null, 220.0)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for c: Dictionary in _cells:
		if (c["rect"] as Rect2).has_point(event.position):
			select_slot(c["kind"], c["tier"])
			accept_event()
			return


## Selects the slot's building; on a repeat click the next one of its kind, and the camera looks at it.
func select_slot(kind: String, tier: int) -> bool:
	var list := buildings_for(kind, tier)
	if list.is_empty():
		return false
	var cur: Variant = _current(kind)
	var again: bool = cur != null and list.has(cur)
	var idx := 0
	if again:
		idx = (list.find(cur) + 1) % list.size()
	if kind == "hall":
		skirmish.select_sector((list[idx] as Sector).id, again)
	else:
		skirmish.select_building((list[idx] as Building).id, again)
	return true


## The selected hall (Sector) or building, or null.
func _current(kind: String) -> Variant:
	if kind == "hall":
		for sec: Sector in skirmish.world.economy.sectors:
			if sec.id == skirmish.selected_sector:
				return sec
		return null
	return skirmish.world.economy.building(skirmish.selected_building)


func _is_selected(kind: String, tier: int) -> bool:
	var cur: Variant = _current(kind)
	if cur == null:
		return false
	if kind == "hall":
		return (cur as Sector).home_of == Skirmish.PLAYER
	var b := cur as Building
	if kind == "special":
		return b.owner == Skirmish.PLAYER and b.kind == "special" and b.special == _special_id(tier)
	return b.owner == Skirmish.PLAYER and b.kind == "dwelling" and b.tier == tier
