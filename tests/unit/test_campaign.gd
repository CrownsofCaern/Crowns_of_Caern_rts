extends "res://tests/test_case.gd"
## Campaigns: the catalog and its validation, handcrafted maps, NPCs, dialogue, quests,
## triggers, the campaign hero and its progress, and play-throughs of the pilot chapter.

var cc: CampaignCatalog = CampaignCatalog.get_default()


func _pilot() -> StoryMission:
	var ch := cc.chapter("last_light", "ll_harvest")
	var m := StoryMission.new(cc.mission(ch), cc.start("last_light"))
	m.build()
	return m


func _steps(m: StoryMission, seconds: float) -> void:
	for i in int(seconds * m.world.tick_rate):
		if not m.dialogue.is_empty() or m.outcome != "":
			return
		m.world.step()
		m.step()


func _put_hero(m: StoryMission, at: Variant) -> void:
	var hu := m.hero_unit()
	var p := m.pos_of(at)
	hu.pos = m.world.nav.nearest_free(p + Vector2(30, 0))
	hu.prev_pos = hu.pos
	m.world.command_stop([hu.id])
	m._step_rules()


func _kill_group(m: StoryMission, gid: String) -> void:
	for u in m.group_units(gid):
		m.world.deal_damage(u, 1.0e9, -1)
	m.world.step()
	m.step()
	m._step_rules()


func _kill_site(m: StoryMission, site_ref: String) -> void:
	var s := m.world.sites.get_site(int(m.world.map_info["refs"][site_ref]["site"]))
	for id in s["guards"]:
		var u := m.world.get_unit(int(id))
		if u != null:
			m.world.deal_damage(u, 1.0e9, -1)
	_put_hero(m, site_ref)
	for i in 10:
		m.world.step()
		m.step()


## Picks the answer whose text starts with `start`; fails the test if there is none.
func _say(m: StoryMission, start: String) -> void:
	for c: Dictionary in m.choices():
		if String(c["text"]).begins_with(start):
			m.command_choose(int(c["index"]))
			return
	_fail("no answer '%s' in %s" % [start, m.choices()])


## Clicks through lines without choices until the conversation ends.
func _continue(m: StoryMission) -> void:
	for i in 10:
		if m.dialogue.is_empty():
			return
		var cs := m.choices()
		if cs.size() == 1 and int(cs[0]["index"]) == -1:
			m.command_choose(-1)
		else:
			return


func _talk(m: StoryMission, nid: String) -> void:
	_put_hero(m, nid)
	assert_true(m.command_talk(nid), "talk to " + nid)
	assert_false(m.dialogue.is_empty(), "a conversation opens with " + nid)


func test_catalog_is_valid() -> void:
	var errors := cc.validate()
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_campaigns_follow_the_main_game() -> void:
	assert_eq(cc.campaign_of("concord"), "last_light")
	var chs := cc.chapters("last_light")
	assert_eq(chs.size(), 10)
	assert_eq(chs[0]["title"], "Greyhold Harvest")
	var hero := 0
	for c: Dictionary in chs:
		if c["kind"] == "hero":
			hero += 1
	assert_eq(hero, 5, "half hero chapters, half war")


func test_validation_catches_broken_missions() -> void:
	var m: Dictionary = cc.mission(cc.chapter("last_light", "ll_harvest")).duplicate(true)
	m["quests"]["main"]["steps"][1]["done"] = {"dead": "no_such_group"}
	m["dialogues"]["reeve_idle"]["nodes"]["start"]["next"] = "nowhere"
	m["npcs"][0]["look"] = "no_such_unit"
	m["triggers"].append({"when": {"weather": "rain"}, "do": [{"dance": true}]})
	var errors := CampaignCatalog.validate_mission(m, "concord")
	var text := "\n".join(errors)
	for want in ["no_such_group", "nowhere", "no_such_unit", "unknown condition", "unknown action"]:
		assert_true(want in text, "reports " + want + ":\n" + text)


func test_handcrafted_map_is_exact() -> void:
	var a := _pilot()
	var b := _pilot()
	var refs: Dictionary = a.world.map_info["refs"]
	for id in ["greyhold", "hobbs_acre", "mill", "barrowfield", "barrow_camp", "den", "bell_tower", "greyhold_chapel"]:
		assert_true(refs.has(id), "map knows " + id)
	var size := a.world.nav.world_size()
	assert_lt((refs["barrowfield"]["pos"] as Vector2).distance_to(Vector2(0.6, 0.5) * size), 1.0, "no jitter")
	assert_eq(a.world.checksum(), b.world.checksum(), "same map every time")
	var names: Array = a.world.economy.sectors.map(func(s: Sector) -> String: return s.label)
	assert_true(names.has("Greyhold") and names.has("Barrow Camp"))


func test_hero_map_has_no_economy() -> void:
	var m := _pilot()
	for u in m.world.units:
		assert_false(u.is_worker() and not u.passive, "no workers on a hero map (villagers are NPCs)")
		assert_ne(u.type_id, "militia", "no militia")
	assert_eq(m.world.economy.nodes.size(), 0, "no resource piles")
	var grey: Sector = m.world.economy.sectors[m.world.map_info["refs"]["greyhold"]["sector"]]
	assert_eq(grey.owner, 0)
	# An enemy next to a settlement does not take it.
	var s: Sector = m.world.economy.sectors[m.world.map_info["refs"]["hobbs_acre"]["sector"]]
	m.world.spawn("shambler", 1, s.center)
	_steps(m, 20.0)
	assert_eq(s.owner, 0, "settlements are scenery")


func test_the_campaign_hero() -> void:
	var m := _pilot()
	var hu := m.hero_unit()
	assert_true(hu != null)
	assert_eq(hu.label, "Aldous Wren")
	assert_eq(m.world.heroes.hero_of(0).class_id, "knight")
	assert_true(m.world.heroes.hero_of(0).story)
	assert_eq(m.quests["main"]["state"], "active", "the main quest starts with the chapter")


func test_npcs_are_left_alone() -> void:
	var m := _pilot()
	var reeve := m.npc_unit("reeve")
	assert_true(reeve.passive)
	var hp := reeve.hp
	var rats := m.world.spawn("plague_rats", 1, reeve.pos + Vector2(20, 0))
	m.world.command_attack_move([rats.id], reeve.pos + Vector2(-100, 0))
	_steps(m, 6.0)
	assert_eq(reeve.hp, hp, "nobody attacks a villager")
	assert_true(reeve.alive)


func test_talking_walks_the_hero_over() -> void:
	var m := _pilot()
	assert_eq(m.mark("reeve"), "!", "the reeve has a quest")
	assert_true(m.command_talk("reeve"))
	assert_true(m.dialogue.is_empty(), "too far: the hero walks first")
	_steps(m, 60.0)
	assert_false(m.dialogue.is_empty(), "the conversation opens on arrival")
	assert_eq(m.dialogue["npc"], "reeve")


func test_dialogue_choices_and_quests() -> void:
	var m := _pilot()
	_talk(m, "reeve")
	_continue(m)
	_say(m, "I'll clear the rats")
	assert_true(m.dialogue.is_empty())
	assert_true(m.flags.has("met_reeve"))
	m._step_rules()
	assert_eq(m.quests["main"]["step"], 1, "next: the rats")
	_kill_group(m, "rats")
	assert_eq(m.quests["main"]["step"], 2)
	assert_eq(m.mark("reeve"), "?", "report back")
	_talk(m, "reeve")
	_continue(m)
	_say(m, "I'll go to the mill")
	m._step_rules()
	assert_eq(m.quests["main"]["step"], 3)
	assert_eq(m.quests["mill"]["state"], "active", "the reeve gives a side quest")


func test_xp_raises_the_story_hero() -> void:
	var m := _pilot()
	var lvl := m.progress.story.level
	m._act({"xp": 2000}, "")
	assert_gt(m.progress.story.level, lvl)
	assert_eq(m.world.heroes.hero_of(0).level, m.progress.story.level, "the battle hero follows at once")
	# Kills near the hero bank XP into the story hero too.
	var before := m.progress.story.xp + m.progress.story.level * 100000
	var hu := m.hero_unit()
	var rat := m.world.spawn("plague_rats", 1, hu.pos + Vector2(40, 0))
	rat.hp = 1.0
	m.world.command_attack([hu.id], rat.id)
	_steps(m, 5.0)
	assert_false(rat.alive)
	assert_gt(m.progress.story.xp + m.progress.story.level * 100000, before)


func test_fallen_hero_wakes_at_the_checkpoint() -> void:
	var m := _pilot()
	m.world.heroes.hero_of(0).marks = 200
	m.world.economy.player(0).res["gold"] = 200
	var hu := m.hero_unit()
	m.world.deal_damage(hu, 1.0e9, -1)
	_steps(m, 1.0)
	assert_true(m.hero_unit() == null)
	assert_eq(m.world.heroes.hero_of(0).marks, 180, "a fall costs a tenth of the marks")
	assert_eq(m.world.economy.player(0).amount("gold"), 200, "the army's gold is untouched")
	_steps(m, 12.0)
	var back := m.hero_unit()
	assert_true(back != null, "back after 10 s")
	assert_lt(back.pos.distance_to(m.pos_of("greyhold_chapel")), 100.0, "at the chapel shrine")


func test_deserters_can_join() -> void:
	var m := _pilot()
	_put_hero(m, "bram")
	assert_false(m.dialogue.is_empty(), "Bram hails the hero")
	_continue(m)
	_say(m, "Then live under my banner")
	_continue(m)
	assert_true(m.flags.has("deserters_joined"))
	for u in m.group_units("deserters"):
		assert_eq(u.owner, 0)
		assert_false(u.passive)
	assert_true(m.world.get_unit(m.companions.keys()[0]) != null)


func test_deserters_can_be_hanged() -> void:
	var m := _pilot()
	_put_hero(m, "bram")
	_continue(m)
	_say(m, "The law is the law")
	assert_true(m.dialogue.is_empty())
	var bram := m.world.get_unit(int(m.npcs["bram"]))
	assert_eq(bram.owner, 1)
	assert_false(bram.passive)
	for u in m.group_units("deserters"):
		assert_eq(u.owner, 1)
	m.world.deal_damage(bram, 1.0e9, -1)
	_kill_group(m, "deserters")
	assert_eq(m.quests["mill"]["step"], 1, "next: tell the reeve")
	m._act({"advance": "main"}, "")
	assert_eq(m.talk_entry("reeve")["dialogue"], "reeve_mill_hanged")


func _play_to_the_end(m: StoryMission, grue_answer: String) -> void:
	_talk(m, "reeve")
	_continue(m)
	_say(m, "I'll clear the rats")
	_kill_group(m, "rats")
	_talk(m, "reeve")
	_continue(m)
	_say(m, "The dead come first")
	_put_hero(m, "barrowfield")
	_put_hero(m, "grue")
	assert_false(m.dialogue.is_empty(), "Grue speaks first")
	_continue(m)
	_say(m, grue_answer)
	_continue(m)
	if m.flags.has("grue_fight"):
		_kill_group(m, "grue_dead")
		m.world.deal_damage(m.world.get_unit(int(m.npcs["grue"])), 1.0e9, -1)
		_steps(m, 1.0)
	_put_hero(m, "maelis")
	_continue(m)
	assert_eq(m.quests["main"]["step"], 5, "next: Barrow Camp")
	_kill_group(m, "camp")


func test_pilot_can_be_won_three_ways() -> void:
	var texts := {}
	for answer in ["Then keep them", "You're coming to Greyhold", "You command the dead"]:
		var m := _pilot()
		_play_to_the_end(m, answer)
		assert_eq(m.outcome, "won", answer)
		var outro := m.outro()
		assert_eq(outro.size(), 2)
		texts[outro[1]] = true
		m.harvest()
		assert_true(m.progress.done.has("ll_harvest"))
		assert_eq(m.progress.flags.size(), m.flags.size())
		assert_true(m.progress.companions.any(func(c: Dictionary) -> bool: return c["name"] == "Maelis Thorne"),
			"Maelis follows into the next chapter")
	assert_eq(texts.size(), 3, "each choice has its own ending")


func test_side_quests() -> void:
	var m := _pilot()
	# Marta's boy: keep the relic.
	_talk(m, "marta")
	_say(m, "I'll find him")
	_put_hero(m, "tobin")
	assert_eq(m.quests["boy"]["step"], 1)
	_kill_site(m, "den")
	assert_eq(m.quests["boy"]["step"], 2)
	_talk(m, "tobin")
	_continue(m)
	_say(m, "A knight's relic")
	_continue(m)
	m._step_rules()
	_talk(m, "marta")
	_continue(m)
	m._step_rules()
	assert_eq(m.quests["boy"]["state"], "done")
	assert_true(m.flags.has("reliquary_kept"))
	# The chapel bell.
	_talk(m, "anselm")
	_say(m, "I'll clear the tower")
	_kill_site(m, "bell_tower")
	_talk(m, "anselm")
	_continue(m)
	m._step_rules()
	assert_eq(m.quests["bell"]["state"], "done")
	assert_true(m.flags.has("chapel_cleansed"))
	assert_lt(m.world.heroes.respawn_at[0].distance_to(m.pos_of("wayside_chapel")), 1.0, "a new checkpoint")
	# Old Wenna: mercy.
	_put_hero(m, "wenna")
	_continue(m)
	_say(m, "Then go")
	_continue(m)
	m._step_rules()
	assert_eq(m.quests["wenna"]["state"], "done")
	assert_true(m.flags.has("mercy_to_the_dead"))


func test_progress_saves_and_loads() -> void:
	var m := _pilot()
	_play_to_the_end(m, "Then keep them")
	m.harvest()
	var p := m.progress
	var back := CampaignProgress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.story.level, p.story.level)
	assert_eq(back.story.class_id, "knight")
	assert_eq(back.hero_name, "Aldous Wren")
	assert_eq(back.flags.keys(), p.flags.keys())
	assert_eq(back.done, ["ll_harvest"])
	assert_eq(back.companions.size(), p.companions.size())
	assert_eq(String(cc.next_chapter(back).get("id", "")), "ll_barrow_roads", "on to chapter 2")


func test_missions_are_deterministic() -> void:
	var sums: Array = []
	for k in 2:
		var m := _pilot()
		m.command_talk("reeve")
		_steps(m, 30.0)
		if not m.dialogue.is_empty():
			_continue(m)
			_say(m, "The dead first")
			_continue(m)
		m.world.command_attack_move([m.hero_unit().id], m.pos_of("rats"))
		_steps(m, 40.0)
		sums.append(m.world.checksum())
	assert_eq(sums[0], sums[1])


func test_hero_coin_is_marks_and_carries_over() -> void:
	var m := _pilot()
	var hs := m.world.heroes.hero_of(0)
	assert_eq(hs.marks, 40, "the chapter starts by giving 40 marks")
	m._act({"marks": 25}, "")
	assert_eq(hs.marks, 65)
	assert_true(m.check({"marks": 60}))
	assert_false(m.check({"marks": 70}))
	m.harvest()
	assert_eq(m.progress.marks, 65, "marks carry to the next chapter")
	assert_eq(int(m.progress.to_dict()["marks"]), 65)
	# A save from before marks kept the hero's coin as "gold".
	var d := m.progress.to_dict()
	d.erase("marks")
	d["gold"] = 90
	assert_eq(CampaignProgress.from_dict(d).marks, 90, "old saves map gold to marks")
	var m2 := StoryMission.new(cc.mission(cc.chapter("last_light", "ll_harvest")), CampaignProgress.from_dict(d))
	m2.build()
	assert_eq(m2.world.heroes.hero_of(0).marks, 130, "the hero starts with the saved marks (+40 from the start)")


# --- War chapters ---------------------------------------------------------------------

func _war() -> StoryMission:
	var ch := cc.chapter("last_light", "ll_barrow_roads")
	var m := StoryMission.new(cc.mission(ch), cc.start("last_light"))
	m.build()
	return m


func test_war_chapter_runs_an_economy() -> void:
	var m := _war()
	assert_true(m.is_war())
	assert_true(m.world.economy.settlements_active, "settlements can be taken")
	assert_eq(m.sector_of("greyhold").owner, 0, "Greyhold is the player's home")
	assert_eq(m.sector_of("mournfield").owner, 1, "Mournfield is the enemy's home")
	assert_true(m.check({"held": "greyhold"}))
	assert_false(m.check({"held": "mournfield"}))
	assert_true(m.check({"holds": [1, 1]}))
	assert_false(m.check({"holds": [0, 2]}))
	var workers := 0
	for u in m.world.units:
		if u.owner == 0 and u.is_worker() and not u.passive:
			workers += 1
	assert_gt(workers, 0, "Greyhold starts with workers")
	assert_eq(m.world.economy.tier_cap, 3)
	m.world.economy.player(0).hall_level = m.world.economy.e["hall_levels"].size()
	assert_eq(m.world.economy.max_tier(0), 3, "even a full hall trains no higher than the chapter allows")


func test_keepers_do_not_claim_their_own_barrows() -> void:
	var m := _war()
	var s := m.world.sites.get_site(int(m.world.map_info["refs"]["barrow_north"]["site"]))
	assert_eq(int(s["keeper"]), 1)
	for id in s["guards"]:
		var u := m.world.get_unit(int(id))
		assert_eq(u.owner, 1, "barrow guards fight for Grue")
		assert_true(u.scripted, "the enemy AI leaves them be")
		m.world.deal_damage(u, 1.0e9, -1)
	m.world.spawn("shambler", 1, s["pos"] + Vector2(10, 0))
	for i in 10:
		m.world.step()
	assert_false(bool(s.get("cleared", false)), "the keeper standing on its barrow claims nothing")
	_kill_site(m, "barrow_north")
	assert_true(bool(s.get("cleared", false)), "the player burns it")
	assert_true(m.check({"cleared": "barrow_north"}))


func test_barrow_columns_repeat_until_burnt() -> void:
	var m := _war()
	_steps(m, 121.0)
	assert_true(m.spawned.has("column_0"), "the first columns march at two minutes")
	var first: Array = m.groups["column_0"].duplicate()
	assert_gt(first.size(), 0)
	_steps(m, 91.0)
	var fresh: Array = m.groups["column_0"].filter(func(id: int) -> bool: return not first.has(id))
	assert_gt(fresh.size(), 0, "a second column marches")
	for u in m.group_units("column_0"):
		assert_true(u.scripted, "columns are the story's, not the enemy AI's")


func test_war_actions_and_conditions() -> void:
	var m := _war()
	var gold := m.world.economy.player(0).amount("gold")
	m._act({"res": {"gold": 300}}, "")
	assert_eq(m.world.economy.player(0).amount("gold"), gold + 300, "res pays into the war chest")
	assert_false(m.check({"companion": "Maelis Thorne"}))
	_talk(m, "maelis")
	_continue(m)
	assert_true(m.check({"companion": "Maelis Thorne"}), "Maelis rides along")


func test_losing_every_settlement_loses_a_war_chapter() -> void:
	var m := _war()
	for s: Sector in m.world.economy.sectors:
		if s.owner == 0:
			s.owner = 1
	m._step_rules()
	assert_eq(m.outcome, "lost")


func test_war_chapter_validation() -> void:
	var m: Dictionary = cc.mission(cc.chapter("last_light", "ll_barrow_roads")).duplicate(true)
	m["max_tier"] = 12
	m["ai"] = "godlike"
	m["triggers"][0]["repeat"] = -5
	m["triggers"].append({"when": {"held": "atlantis"}, "do": [{"res": {"mana_crystals": 5}}]})
	for z: Dictionary in m["map"]["zones"]:
		if z["id"] == "mournfield":
			z.erase("home")
	var text := "\n".join(CampaignCatalog.validate_mission(m, "concord"))
	for want in ["max_tier", "ai must", "repeat", "atlantis", "mana_crystals", "home zone"]:
		assert_true(want in text, "reports " + want + ":\n" + text)


func test_barrow_roads_is_deterministic() -> void:
	var a := _war()
	var b := _war()
	_steps(a, 30.0)
	_steps(b, 30.0)
	assert_eq(a.world.checksum(), b.world.checksum())


# --- Chapter 3: Lanterns in the Fen ----------------------------------------------------

func _lanterns(flags: Array = []) -> StoryMission:
	var p := cc.start("last_light")
	for f: String in flags:
		p.flags[f] = true
	var m := StoryMission.new(cc.mission(cc.chapter("last_light", "ll_lanterns")), p)
	m.build()
	return m


func test_lanterns_reads_earlier_choices() -> void:
	var m := _lanterns(["refugees_taken", "learned_corvin"])
	assert_false(m.is_war())
	assert_false(m.world.economy.settlements_active)
	assert_true(m.npc_unit("ama") != null, "Ama, taken in at Waymeet, waits at the crossing")
	assert_true(m.npc_unit("hester") == null)
	var said := m.events.filter(func(e: Dictionary) -> bool: return e["type"] == "say")
	assert_true(said.any(func(e: Dictionary) -> bool: return "Grue named him" in String(e["text"])))
	var n := _lanterns()
	assert_true(n.npc_unit("hester") != null, "without the refugees Hester asks instead")
	assert_true(n.npc_unit("ama") == null)


func test_edda_joins_or_stays() -> void:
	var m := _lanterns()
	_talk(m, "edda")
	_continue(m)
	_say(m, "Then walk with us")
	_continue(m)
	assert_true(m.check({"companion": "Sister Edda Vey"}), "Edda walks with Wren")
	m._step_rules()
	assert_eq(int(m.quests["main"]["step"]), 1, "on to the lanterns")
	var n := _lanterns()
	_talk(n, "edda")
	_continue(n)
	_say(n, "Stay with the temple")
	_continue(n)
	assert_false(n.check({"companion": "Sister Edda Vey"}))
	assert_true(n.flags.has("edda_stays"))
	assert_true(n.npc_unit("edda") != null, "she stays at the Lantern House")


func test_the_walked_away() -> void:
	var m := _lanterns()
	_talk(m, "hester")
	_continue(m)
	_say(m, "I'll go to the chapel")
	_continue(m)
	assert_eq(m.quests["walked"]["state"], "active")
	_kill_site(m, "drowned_chapel")
	_talk(m, "tam")
	_continue(m)
	var texts: Array = m.choices().map(func(c: Dictionary) -> String: return String(c["text"]))
	assert_false(texts.any(func(t: String) -> bool: return t.begins_with("Edda")), "no Edda, no blessing")
	_say(m, "Walk to Stilt Market")
	_continue(m)
	assert_true(m.flags.has("folk_home"))
	_talk(m, "hester")
	_continue(m)
	m._step_rules()
	assert_eq(m.quests["walked"]["state"], "done")


func test_lanterns_can_be_won() -> void:
	var m := _lanterns()
	m.flags["edda_met"] = true
	m._step_rules()
	for l in ["lantern_west", "lantern_mid", "lantern_east"]:
		_kill_site(m, l)
		_continue(m)
	assert_eq(int(m.quests["main"]["step"]), 2, "the lanterns are out")
	_put_hero(m, "fenlight")
	assert_false(m.dialogue.is_empty(), "Corvin speaks before the fight")
	_continue(m)
	_say(m, "What is under the fen")
	_continue(m)
	assert_true(m.flags.has("heard_leak"))
	_kill_group(m, "corvin_guard")
	_kill_group(m, "corvin")
	_continue(m)
	assert_eq(m.outcome, "won")


# --- The whole of The Last Light -------------------------------------------------------

func _chapter(id: String, flags: Array = [], companions: Array = []) -> StoryMission:
	var camp := cc.campaign_of_chapter(id)
	var p := cc.start(camp)
	for f: String in flags:
		p.flags[f] = true
	p.companions = companions
	var m := StoryMission.new(cc.mission(cc.chapter(camp, id)), p)
	m.build()
	return m


func test_the_last_light_is_written() -> void:
	var chs := cc.chapters("last_light")
	for i in chs.size():
		var ch: Dictionary = chs[i]
		assert_true(cc.playable(ch), "%s is playable" % ch["id"])
		var m := cc.mission(ch)
		assert_eq(String(m.get("kind", "hero")), String(ch["kind"]), "%s: the file's kind matches" % ch["id"])
		assert_eq(String(ch["kind"]), "hero" if i % 2 == 0 else "war", "odd chapters hero, even war")


func test_every_new_chapter_builds() -> void:
	for id in ["ll_knight", "ll_doors", "ll_stumps", "ll_red_sky", "ll_ford", "ll_ashes", "ll_embers",
			"ph_warm_earth", "ph_barrow_lords", "ph_living_shore", "ph_rot", "ph_twice_dead", "ph_lantern_siege",
			"ph_deep_barrows", "ph_hungry_fire", "ph_leviathan", "ph_pale_crown"]:
		var m := _chapter(id)
		assert_true(m.hero_unit() != null, id + ": the hero is on the map")
		assert_eq(m.world.economy.settlements_active, m.is_war(), id + ": only war chapters run the economy")
		assert_eq(m.quests["main"]["state"], "active", id + ": the main quest starts")
		if m.is_war():
			assert_gt(float(m._sectors_of(0)), 0.0, id + ": you start with a settlement")
			assert_gt(float(m._sectors_of(1)), 0.0, id + ": so does the enemy")


func test_companions_with_hero_bodies_carry_over() -> void:
	var m := _chapter("ll_knight", [], [{"type": "hero_ranger", "name": "Maelis Thorne"},
		{"type": "hero_oracle", "name": "Sister Edda Vey"}])
	assert_true(m.check({"companion": "Maelis Thorne"}), "Maelis follows Wren into the next chapter")
	assert_true(m.check({"companion": "Sister Edda Vey"}), "so does Edda")
	var said := m.events.filter(func(e: Dictionary) -> bool: return e["type"] == "say")
	assert_true(said.any(func(e: Dictionary) -> bool: return e["who"] == "Sister Edda Vey"),
		"a carried companion speaks under her own name")


func test_old_choices_bring_allies_to_the_gate() -> void:
	var lone := _chapter("ll_embers")
	assert_false(lone.spawned.has("grimfell_axes"))
	var m := _chapter("ll_embers", ["hrodna_fed", "paid_debt", "heartwood_oath", "margraves_ride"])
	for g in ["grimfell_axes", "forge_battery", "covenant_bows", "margrave_lances"]:
		assert_gt(m.group_units(g).size(), 0, g + " comes")
		assert_eq(m.group_units(g)[0].owner, 0, g + " fights for you")
	var broken := _chapter("ll_embers", ["heartwood_oath", "oathbreaker"])
	assert_false(broken.spawned.has("covenant_bows"), "a broken oath brings no bows")


func test_the_ford_holds_for_ten_minutes_or_less() -> void:
	var m := _chapter("ll_ford")
	m.time = 500.0
	m._step_rules()
	assert_eq(int(m.quests["main"]["step"]), 0, "still holding at 500 s")
	m.flags["captain_rode"] = true
	m._step_rules()
	assert_eq(int(m.quests["main"]["step"]), 1, "a rider fetched the levies early")
	assert_true(m.spawned.has("reinforcements"))


func test_the_gate_is_held_in_three_waves() -> void:
	var m := _chapter("ll_embers")
	m.quests["main"]["step"] = 2
	_put_hero(m, "gate")
	_continue(m)
	m._step_rules()
	assert_true(m.spawned.has("gate_wave_1"))
	for g in ["gate_wave_1", "gate_wave_2", "gate_wave_3"]:
		assert_true(m.spawned.has(g), g + " comes out of the Wound")
		_kill_group(m, g)
		_continue(m)
		m._step_rules()
	assert_eq(m.outcome, "won")


func test_a_witch_can_break_sesks_wards() -> void:
	var m := _chapter("ll_ashes")
	_kill_group(m, "abbey_raiders")
	_put_hero(m, "vessa")
	_continue(m)
	_say(m, "Break the wards")
	_continue(m)
	assert_true(m.check({"dead": "sesk_wards"}), "the wards are gone")
	assert_true(m.flags.has("witch_bargain"))


func test_speakers_must_be_known() -> void:
	var m: Dictionary = cc.mission(cc.chapter("last_light", "ll_knight")).duplicate(true)
	m.erase("speakers")
	var text := "\n".join(CampaignCatalog.validate_mission(m, "concord"))
	assert_true("unknown speaker edda" in text, text)


func test_the_chapter_tier_cap_is_explained() -> void:
	var m := _war()
	assert_true(m.events.any(func(e: Dictionary) -> bool: return e["type"] == "tier_cap" and int(e["tier"]) == 3),
		"the chapter says which tiers it allows")
	var eco := m.world.economy
	assert_true(eco.capped(4))
	assert_false(eco.capped(3))
	assert_eq(eco.tier_lock_text(4), "Tier 4 is locked in this chapter")
	assert_eq(eco.tier_lock_text(3), "Upgrade the hall first")
	assert_eq(CampaignHud.notice_for({"type": "tier_cap", "tier": 3}), "This chapter: halls train tiers 1 to 3")


# --- The Pale Inheritance ------------------------------------------------------------------

const ORRIN := {"type": "hero_gravewarden", "name": "Sir Orrin Wren"}
const CORVIN := {"type": "hero_blightcaller", "name": "Father Corvin Mire"}


func _named_unit(m: StoryMission, label: String) -> SimUnit:
	for id: int in m.companions:
		var u := m.world.get_unit(id)
		if u != null and u.label == label:
			return u
	return null


func test_the_regent_leads_the_pale_inheritance() -> void:
	assert_eq(cc.campaign_of_chapter("ph_rot"), "pale_inheritance")
	var p := cc.start("pale_inheritance")
	assert_eq(p.hero_name, "Ysmay Vane")
	assert_eq(p.story.class_id, "necromancer")
	var m := _chapter("ph_warm_earth")
	assert_true(m.check({"companion": "Sir Orrin Wren"}), "Orrin walks with the Regent from the first chapter")


func test_vathek_can_be_bound_or_laid_to_rest() -> void:
	for answer: String in ["Bind his skull", "Let him sleep"]:
		var m := _chapter("ph_warm_earth")
		_kill_group(m, "vathek_guard")
		_kill_group(m, "vathek")
		_steps(m, 1.0)
		assert_false(m.dialogue.is_empty(), "Vathek speaks as he falls")
		_continue(m)
		_say(m, answer)
		_continue(m)
		assert_true(m.flags.has("vathek_refused"), "beating him counts as his answer")
		assert_true(m.flags.has("vathek_bound" if answer == "Bind his skull" else "vathek_rests"))


func test_fallen_companions_get_back_up() -> void:
	var m := _chapter("ph_warm_earth")
	var orrin := _named_unit(m, "Sir Orrin Wren")
	m.world.deal_damage(orrin, 1.0e9, -1)
	m.world.step()
	m.step()
	assert_false(m.check({"companion": "Sir Orrin Wren"}), "Orrin is down")
	_steps(m, 2.0)
	var up := _named_unit(m, "Sir Orrin Wren")
	assert_true(up != null, "he gets back up once the fight is over")
	assert_true(up.hp < up.max_hp, "but not at full health")
	assert_true(m.events.any(func(e: Dictionary) -> bool: return e["type"] == "rise"))
	assert_eq(CampaignHud.notice_for({"type": "rise", "name": "Sir Orrin Wren"}), "Sir Orrin Wren gets back up")


func test_companions_can_sit_a_chapter_out() -> void:
	var d: Dictionary = cc.mission(cc.chapter("pale_inheritance", "ph_living_shore")).duplicate(true)
	d["absent"] = ["Sir Orrin Wren"]
	var p := cc.start("pale_inheritance")
	p.companions = [ORRIN]
	var m := StoryMission.new(d, p)
	m.build()
	assert_false(m.check({"companion": "Sir Orrin Wren"}), "an absent companion stays behind")
	d["absent"] = [""]
	var text := "\n".join(CampaignCatalog.validate_mission(d, "hollow"))
	assert_true("absent must be a list" in text, text)


func test_lady_hesk_kneels_once_tarn_falls() -> void:
	var m := _chapter("ph_barrow_lords")
	_put_hero(m, "hesk")
	_continue(m)
	_say(m, "Tarn first")
	_continue(m)
	assert_eq(m.quests["hesk"]["state"], "active")
	_kill_group(m, "tarn")
	_talk(m, "hesk")
	_continue(m)
	assert_true(m.flags.has("hesk_knelt"))
	assert_eq(m.group_units("hesk_guard")[0].owner, 0, "her dead march with yours")


func test_columns_stop_when_hesk_kneels() -> void:
	var m := _chapter("ph_barrow_lords")
	m.time = 160.0
	m._step_rules()
	assert_true(m.spawned.has("column"), "Morrow sends his dead while he holds every hall")
	var knelt := _chapter("ph_barrow_lords", ["hesk_knelt"])
	knelt.time = 160.0
	knelt._step_rules()
	assert_false(knelt.spawned.has("column"))


func test_corvin_joins_and_the_choir_can_let_you_pass() -> void:
	var m := _chapter("ph_living_shore", [], [ORRIN])
	_put_hero(m, "corvin")
	_continue(m)
	_say(m, "Walk with me, Father. We'll")
	_continue(m)
	assert_true(m.check({"companion": "Father Corvin Mire"}), "Corvin joins the Regent")
	assert_eq(m.quests["list"]["state"], "active", "and his list becomes a quest")
	_put_hero(m, "sunken")
	_continue(m)
	_say(m, "Keep your chapel")
	_continue(m)
	assert_true(m.flags.has("chapel_passed"), "the chapel road opens without a fight")
	var again := _chapter("ph_living_shore", [], [ORRIN, CORVIN])
	assert_true(again.flags.has("corvin_joined"), "a Corvin already at her side counts as joined")


func test_a_pact_for_heartwood_puts_out_the_torches() -> void:
	var m := _chapter("ph_rot")
	m.time = 200.0
	m._step_rules()
	assert_true(m.spawned.has("burners_north"), "the burning bands come while the Covenant holds its camps")
	var pact := _chapter("ph_rot", ["rot_pact"])
	pact.time = 200.0
	pact._step_rules()
	assert_false(pact.spawned.has("burners_north"))


func test_the_pale_inheritance_is_written() -> void:
	var chs := cc.chapters("pale_inheritance")
	assert_eq(chs.size(), 10)
	for i in chs.size():
		var ch: Dictionary = chs[i]
		assert_true(cc.playable(ch), "%s is playable" % ch["id"])
		assert_eq(String(cc.mission(ch).get("kind", "hero")), String(ch["kind"]), "%s: the file's kind matches" % ch["id"])
		assert_eq(String(ch["kind"]), "hero" if i % 2 == 0 else "war", "odd chapters hero, even war")


func test_orrin_sits_out_twice_dead_until_he_is_raised() -> void:
	var m := _chapter("ph_twice_dead", [], [ORRIN, CORVIN])
	assert_false(m.check({"companion": "Sir Orrin Wren"}), "Orrin fell at the Rest; he is not with her")
	assert_true(m.check({"companion": "Father Corvin Mire"}))
	_talk(m, "body")
	_continue(m)
	assert_true(m.flags.has("orrin_raised"))
	assert_true(m.check({"companion": "Sir Orrin Wren"}), "raised a second time, he walks with her again")


func test_the_pyre_is_lit_at_dawn() -> void:
	var m := _chapter("ph_twice_dead")
	m.time = 1201.0
	m._step_rules()
	assert_eq(m.outcome, "lost", "the bell rings and Orrin burns")
	var bell := _chapter("ph_twice_dead", ["bell_silenced"])
	bell.time = 1201.0
	bell._step_rules()
	assert_eq(bell.outcome, "", "a silenced bell buys time")
	bell.time = 1501.0
	bell._step_rules()
	assert_eq(bell.outcome, "lost")


func test_garran_stands_aside_for_a_regent_who_spared_the_acre() -> void:
	var m := _chapter("ph_lantern_siege", ["acre_spared"])
	_put_hero(m, "garran")
	_continue(m)
	_say(m, "Because I spared Hobb's Acre")
	_continue(m)
	assert_true(m.flags.has("garran_aside"))
	var other := _chapter("ph_lantern_siege")
	_put_hero(other, "garran")
	_continue(other)
	assert_false(other.choices().any(func(c: Dictionary) -> bool: return String(c["text"]).begins_with("Because")),
		"the Acre answer needs the Acre spared")


func test_burning_the_oil_sends_the_lamp_wardens_home() -> void:
	var m := _chapter("ph_lantern_siege")
	assert_gt(m.group_units("lamp_wardens").size(), 0)
	_kill_site(m, "oil_store")
	m._step_rules()
	assert_eq(m.group_units("lamp_wardens").size(), 0)


func test_king_ossric_wakes_and_marches_to_the_fire() -> void:
	var m := _chapter("ph_deep_barrows")
	_put_hero(m, "ossric")
	_continue(m)
	_say(m, "Get up, King Ossric")
	_continue(m)
	assert_eq(m.group_units("sleepers")[0].owner, 0, "his sleepers fight for the Regent")
	var fire := _chapter("ph_hungry_fire", ["ossric_woken", "knows_burrows"])
	assert_gt(fire.group_units("ossric_sleepers").size(), 0, "and come to the Hungry Fire")
	assert_eq(fire.group_units("tunnel_watch").size(), 0, "Ambrel's tablets show the way round the watch")


func test_a_tomb_that_falls_burns() -> void:
	var m := _chapter("ph_hungry_fire")
	m._step_rules()
	assert_eq(m.quests["tombs"]["state"], "active")
	m.sector_of("tomb_kings").owner = 1
	m.time = 10.0
	m._step_rules()
	assert_true(m.flags.has("tomb_burned"))
	assert_eq(m.quests["tombs"]["state"], "failed")


func test_the_leviathan_needs_a_heart_a_name_and_a_bell() -> void:
	var m := _chapter("ph_leviathan", ["living_protected"])
	_talk(m, "leviathan")
	_continue(m)
	assert_false(m.flags.has("leviathan_raised"), "not without the three things")
	_talk(m, "sedge")
	_continue(m)
	_say(m, "Mossgate is under my hand")
	_continue(m)
	assert_true(m.flags.has("has_name"), "Sedge takes the Mossgate peat for the name")
	m.flags["has_heart"] = true
	m.flags["has_bell"] = true
	_talk(m, "leviathan")
	_continue(m)
	assert_true(m.check({"companion": "The Rotwing"}), "the leviathan rises and follows the Regent")


func test_old_friends_come_to_the_crowning() -> void:
	var lone := _chapter("ph_pale_crown")
	for g in ["hesk_host", "ossric_sleepers", "tomb_kings", "choir"]:
		assert_false(lone.spawned.has(g), g + " needs an earlier choice")
	var m := _chapter("ph_pale_crown", ["hesk_knelt", "ossric_woken", "tombs_kept", "cantor_spared"])
	for g in ["hesk_host", "ossric_sleepers", "tomb_kings", "choir"]:
		assert_gt(m.group_units(g).size(), 0, g + " comes")
		assert_eq(m.group_units(g)[0].owner, 0, g + " fights for the Regent")
	assert_eq(m.sector_of("skarn_burrow").owner, 1, "Skarn's brood")
	assert_eq(m.sector_of("ithra_kiln").owner, 2, "and Ithra's, a third player")


func test_items_need_a_real_slot() -> void:
	var m: Dictionary = cc.mission(cc.chapter("pale_inheritance", "ph_deep_barrows")).duplicate(true)
	m["start"].append({"item": {"rarity": "rare", "slot": "helmet", "level": 3}})
	var text := "\n".join(CampaignCatalog.validate_mission(m, "hollow"))
	assert_true("no item fits slot helmet" in text, text)
