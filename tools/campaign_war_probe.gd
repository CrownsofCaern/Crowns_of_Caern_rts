extends SceneTree
## Balance probe for a campaign war chapter: a computer player stands in for you (it runs
## Greyhold's economy at the given difficulty), and every 30 s your whole army attack-moves on
## the next target (the barrows in order, then the enemy home; hold:<zone>:<s> waits there). Prints progress each minute.
##   godot --headless --path . --script res://tools/campaign_war_probe.gd -- [chapter] [you: easy|normal|hard] [minutes] [flag,flag]

const TARGETS := {
	"ll_barrow_roads": ["barrow_mid", "barrow_north", "barrow_south", "mournfield"],
	"ll_knight": ["fenwick", "sluice_south", "sluice_north", "rest"],
	"ll_stumps": ["thornmere", "rootholm", "briarhall"],
	"ll_ford": ["hold:fordhead:600", "cinder_camp"],
	"ll_embers": ["south_guard", "pyrehold", "north_guard", "cindermaw", "go:gate"],
	"ph_barrow_lords": ["greywater", "hesk_howe", "deepfen"],
	"ph_rot": ["briarwatch", "elderfall", "ashbark"],
	"ph_hungry_fire": ["cinder_gallery", "kiln_halls", "furnace"],
	"ph_pale_crown": ["gate_host", "ash_galleries", "skarn_guard", "soot_halls", "ithra_guard", "ithra"],
	"ph_lantern_siege": ["lamp_west", "fenwick", "lamp_north", "oil_store", "lamp_south", "fortress"],
}

## The answers the bot prefers (the harder road), else the first answer.
const PREFER := ["I don't swear", "Leave it standing"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var chapter := args[0] if args.size() > 0 else "ll_barrow_roads"
	var you := args[1] if args.size() > 1 else "normal"
	var minutes := int(args[2]) if args.size() > 2 else 30
	var cc := CampaignCatalog.get_default()
	var start := cc.start(cc.campaign_of_chapter(chapter))
	if args.size() > 3:  # flags carried from earlier chapters, comma separated
		for f in args[3].split(","):
			start.flags[f] = true
	var m := StoryMission.new(cc.mission(cc.chapter(cc.campaign_of_chapter(chapter), chapter)), start)
	var w := m.build()
	var ais: Array[EconomyAi] = [EconomyAi.new(0, you)]
	for o in range(1, m.factions.size()):
		ais.append(EconomyAi.new(o, String(m.def.get("ai", "easy"))))
	var targets: Array = TARGETS.get(chapter, [])
	for i in w.tick_rate * 60 * minutes:
		if not m.dialogue.is_empty():
			var pick: int = int(m.choices()[0]["index"])
			for c: Dictionary in m.choices():
				if PREFER.any(func(p: String) -> bool: return String(c["text"]).begins_with(p)):
					pick = int(c["index"])
			m.command_choose(pick)
			continue
		for a in ais:
			a.update(w)
		w.step()
		for e in w.events:
			if String(e["type"]) == "lair_cleared":
				print("   %.0f s: lair %s cleared by %d" % [m.time, e["site"], int(e["owner"])])
		m.step()
		if w.tick % (w.tick_rate * 30) == 0:
			var t := _next(m, targets)
			if t != "":
				var ids: Array = w.units.filter(func(u: SimUnit) -> bool:
					return u.owner == 0 and not u.passive and not u.is_worker()).map(func(u: SimUnit) -> int: return u.id)
				w.command_attack_move(ids, m.pos_of(t))
		if w.tick % (w.tick_rate * 60) == 0:
			print("%2d min  you: %d units, %d settlements, %d gold  enemy: %d units, %d settlements  next: %s  level %d" % [
				int(m.time / 60.0), _army(w, 0), m._sectors_of(0), w.economy.player(0).amount("gold"),
				_army(w, 1), m._sectors_of(1), _next(m, targets), m.progress.story.level])
		if m.outcome != "":
			break
	print("outcome: %s after %.1f min (%s)" % [m.outcome if m.outcome != "" else "none", m.time / 60.0, m.lose_text])
	quit()


func _army(w: SimWorld, owner: int) -> int:
	return w.units.filter(func(u: SimUnit) -> bool: return u.owner == owner and u.alive and not u.is_worker()).size()


func _next(m: StoryMission, targets: Array) -> String:
	for t: String in targets:
		if t.begins_with("hold:"):  # hold:<zone>:<seconds>: stand there until then
			var parts := t.split(":")
			if m.time < float(parts[2]) and not m.check({"step": ["main", 1]}):
				return parts[1]
			continue
		if t.begins_with("go:"):  # go:<place>: always this
			return t.substr(3)
		if m.groups.has(t):  # a band: until it is dead
			if not m.check({"dead": t}):
				return t
			continue
		var refs: Dictionary = m.world.map_info["refs"]
		if refs[t].has("site"):
			if not m.world.sites.get_site(int(refs[t]["site"]))["cleared"]:
				return t
		elif not m.check({"held": t}):
			return t
	return ""
