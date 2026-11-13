extends SceneTree
## Balance probe for a campaign chapter: the hero (with whoever joins) fights the chapter's
## groups and lairs in a fixed order with plain attack-moves, drinking potions when low, and
## the probe reports time, hero level, falls and health after each fight.
##   godot --headless --path . --script res://tools/campaign_probe.gd -- [chapter] [deserters: join|hang|free] [start level]

## Each chapter's route: [kind, id] with kind group (kill it), site (clear the lair) or npc (walk
## over and talk).
const PLANS := {
	"ll_harvest": [["group", "rats"], ["npc", "bram"], ["site", "den"], ["site", "bell_tower"],
		["group", "road_dead"], ["npc", "grue"], ["site", "open_graves"], ["npc", "maelis"], ["group", "fen_ambush"],
		["group", "camp"]],
	"ll_lanterns": [["npc", "edda"], ["group", "reed_dead"], ["site", "lantern_west"], ["npc", "jory"],
		["site", "bog_den"], ["npc", "jory"], ["npc", "hester"], ["site", "drowned_chapel"], ["npc", "tam"],
		["site", "lantern_mid"], ["site", "lantern_east"], ["group", "causeway_watch"], ["group", "corvin_guard"],
		["group", "corvin"]],
	"ll_doors": [["npc", "greave"], ["site", "old_mine"], ["npc", "nim"], ["group", "patrol"], ["npc", "hessa"],
		["group", "workshop_raid"], ["site", "slag_heap"], ["group", "warden_post"], ["site", "troll_bridge"],
		["group", "vell_guard"], ["group", "vell"]],
	"ll_red_sky": [["group", "raid_hythe"], ["site", "wolf_rocks"], ["group", "raid_coldwater"], ["npc", "reeve"],
		["group", "raid_ostler"], ["npc", "ostler_npc"], ["site", "rime_cave"], ["npc", "hrodna"], ["group", "clan"],
		["group", "bjarr_guard"], ["group", "bjarr"]],
	"ll_ashes": [["npc", "sabine"], ["group", "abbey_raiders"], ["npc", "vessa"], ["site", "cinder_pit"],
		["group", "gorrath_guard"], ["group", "gorrath"], ["site", "ogre_den"], ["group", "sesk_wards"],
		["group", "sesk_guard"], ["group", "sesk"]],
	"ph_warm_earth": [["go", "mere"], ["npc", "hob"], ["npc", "brisa"], ["site", "drowned_chapel"], ["npc", "brisa"],
		["group", "lights"], ["site", "reed_den"], ["site", "cairn_west"], ["site", "cairn_east"], ["group", "vathek_guard"],
		["group", "vathek"]],
	"ph_living_shore": [["npc", "corvin"], ["group", "bridge_watch"], ["site", "millbridge_yard"], ["site", "witch_rocks"],
		["group", "ilse_levies"], ["group", "ilse"], ["site", "harpy_cliff"], ["group", "tamsin_guard"], ["group", "tamsin"]],
	"ph_twice_dead": [["group", "dike_watch"], ["npc", "reeve"], ["site", "bell_tower"], ["group", "road_patrol"],
		["group", "gate_guard"], ["group", "pyre_guard"], ["group", "aubert"], ["npc", "body"]],
	"ph_deep_barrows": [["group", "tunnel_rats"], ["npc", "ossric"], ["npc", "ambrel"], ["site", "scarab_nest"], ["npc", "ambrel"],
		["go", "scored_halls"], ["group", "halls_ambush"], ["group", "north_dig"], ["site", "sentinel_hall"], ["group", "south_dig"],
		["group", "garsh_guard"], ["group", "garsh"]],
	"ph_leviathan": [["group", "scouts"], ["npc", "sedge"], ["site", "wyvern_crag"], ["group", "gate_raiders"], ["site", "sunken_heart"],
		["go", "mire"], ["group", "mire_ambush"], ["npc", "leviathan"], ["group", "skarn_host"], ["group", "forge_guard"]],
}
## Answers the probe prefers (the first answer starting with one of these, else the first answer).
const PREFER := ["Then keep them", "Then walk with us", "I'll deal", "I'll go to", "Edda, can", "What is under",
	"Nothing. Feed", "I'll look for Nim", "Then shoot for us", "The Concord will pay", "What is wrong", "Coldwater will starve", "Hold the river", "You're Host now",
	"Go and see her", "I'll deal with your", "Nothing. Mossgate", "Bind his skull", "Walk with me, Father. We'll", "Raise them", "Keep your village", "Sleep. I'll stop", "I'll bring them", "A hundred marks"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var chapter := args[0] if args.size() > 0 else "ll_harvest"
	var choice := args[1] if args.size() > 1 else "join"
	var cc := CampaignCatalog.get_default()
	var ch := cc.chapter(cc.campaign_of_chapter(chapter), chapter)
	var start := cc.start(cc.campaign_of_chapter(chapter))
	# A later chapter: arrive as a player would, at this story level with chapter 1's companions.
	var level := int(args[2]) if args.size() > 2 else 1
	while start.story.level < level:
		start.story.add_xp(100)
	if start.campaign == "pale_inheritance":
		if level > 1:  # Orrin from chapter 1, Corvin from chapter 3
			start.companions = [{"type": "hero_gravewarden", "name": "Sir Orrin Wren"}]
		if level >= 10:
			start.companions.append({"type": "hero_blightcaller", "name": "Father Corvin Mire"})
	elif level > 1:
		start.companions = [{"type": "hero_ranger", "name": "Maelis Thorne"},
			{"type": "deserter_crossbows", "name": "Bram Holt"}, {"type": "deserter_crossbows", "name": "Deserter"}]
		if level >= 12:  # Edda has joined by now (chapter 3)
			start.companions[2] = {"type": "hero_oracle", "name": "Sister Edda Vey"}
	var m := StoryMission.new(cc.mission(ch), start)
	m.build()
	var plan: Array = PLANS[chapter]
	if chapter == "ll_harvest":
		m.flags["met_reeve"] = true
	var falls := 0
	for step: Array in plan:
		var t0 := m.time
		var target: String = step[1]
		if step[0] == "group" and target == "fen_ambush":
			m._act({"spawn": "fen_ambush"}, "")
		var fallen_before := m.world.heroes.hero_of(0).deaths
		var talked := false
		for i in 20 * 240:
			if not m.dialogue.is_empty():
				_answer(m, choice)
				talked = true
				continue
			if step[0] == "npc" and talked:
				break
			if step[0] == "npc" and m.hero_unit() != null and m.npc_unit(target) != null \
					and m.hero_unit().pos.distance_to(m.pos_of(target)) < 150.0:
				m.command_talk(target)
			var hu := m.hero_unit()
			if hu != null and m.world.tick % 20 == 0:
				var ids: Array = m.world.units.filter(func(u: SimUnit) -> bool: return u.owner == 0 and not u.passive).map(func(u: SimUnit) -> int: return u.id)
				m.world.command_attack_move(ids, m.pos_of(target))
				var h := m.world.heroes.hero_of(0)
				if hu.hp < hu.max_hp * 0.35:
					m.world.heroes.gear.command_drink(0, "health")
			var d0 := m.world.heroes.hero_of(0).deaths
			var near := []
			if OS.has_environment("PROBE_DEBUG") and hu != null:
				for u: SimUnit in m.world.units:
					if u.alive and u.owner != 0 and u.owner != StoryMission.NPC and u.pos.distance_to(hu.pos) < 300.0:
						near.append(u.type_id)
			m.world.step()
			m.step()
			if OS.has_environment("PROBE_DEBUG") and m.world.heroes.hero_of(0).deaths > d0:
				print("   fell at %s near %s" % [hu.pos.round() if hu != null else "?", near])
			if _done(m, step):
				break
		falls += m.world.heroes.hero_of(0).deaths - fallen_before
		var hu2 := m.hero_unit()
		print("%-12s %5.0f s  level %d  falls %d  hp %s  companions %s" % [target, m.time - t0, m.progress.story.level,
			m.world.heroes.hero_of(0).deaths - fallen_before, "dead" if hu2 == null else "%d/%d" % [hu2.hp, hu2.max_hp],
			m.companions.keys().filter(func(id: int) -> bool: return m.world.get_unit(id) != null and m.world.get_unit(id).alive).map(
				func(id: int) -> String: return m.world.get_unit(id).label if m.world.get_unit(id).label != "" else m.world.get_unit(id).type_id)])
		# Rest between fights, as a player would.
		for i in 20 * 20:
			if not m.dialogue.is_empty():
				_answer(m, choice)
				continue
			m.world.step()
			m.step()
	for step2: Array in plan:
		if step2[0] == "site":
			var st := m.world.sites.get_site(int(m.world.map_info["refs"][step2[1]]["site"]))
			var left := []
			for id in st["guards"]:
				var gu := m.world.get_unit(int(id))
				if gu != null and gu.alive:
					left.append("%s@%s hp%d" % [gu.type_id, gu.pos.round(), gu.hp])
			print("  %s cleared=%s left %s at %s" % [step2[1], st.get("cleared"), left, (st["pos"] as Vector2).round()])
		elif step2[0] == "group" and m.spawned.has(step2[1]):
			print("  %s left %s" % [step2[1], m.group_units(step2[1]).map(func(u: SimUnit) -> String: return "%s@%s" % [u.type_id, u.pos.round()])])
	print("outcome: %s  total %.0f s  falls %d  level %d" % [m.outcome, m.time, falls, m.progress.story.level])
	quit()


func _done(m: StoryMission, step: Array) -> bool:
	match step[0]:
		"group":
			return m.spawned.has(step[1]) and m.group_units(step[1]).is_empty()
		"site":
			return m.world.sites.get_site(int(m.world.map_info["refs"][step[1]]["site"]))["cleared"]
		"go":
			var hg := m.hero_unit()
			return hg != null and hg.pos.distance_to(m.pos_of(step[1])) < 120.0
		"npc":
			var hu := m.hero_unit()
			return hu != null and hu.pos.distance_to(m.pos_of(step[1])) < 200.0 and m.dialogue.is_empty() \
				and (m.flags.has(step[1] + "_decided") or step[1] == "maelis")
	return false


func _answer(m: StoryMission, choice: String) -> void:
	var cs := m.choices()
	var pick: int = int(cs[0]["index"])
	for c: Dictionary in cs:
		var t := String(c["text"])
		if (choice == "join" and t.begins_with("Then live")) or (choice == "hang" and t.begins_with("The law")) \
				or (choice == "free" and t.begins_with("Leave the grain")) \
				or PREFER.any(func(p: String) -> bool: return t.begins_with(p)):
			pick = int(c["index"])
	m.command_choose(pick)
