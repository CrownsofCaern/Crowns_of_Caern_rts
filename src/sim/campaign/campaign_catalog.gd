class_name CampaignCatalog
extends RefCounted
## The campaigns (data/campaigns/campaigns.json): one per house, each a list of chapters. A
## chapter with a "file" is playable (its mission in data/campaigns/<file>); the others are
## planned. validate() checks every mission: its map, units, places, quests, dialogues,
## conditions and actions.

const PATH := "res://data/campaigns/campaigns.json"
const DIR := "res://data/campaigns/"
const KINDS := ["hero", "war"]

static var _default: CampaignCatalog

var campaigns: Dictionary = {}  ## id -> {name, faction, text, chapters: [{id, title, kind, text, file?}]}
var _missions: Dictionary = {}


static func get_default() -> CampaignCatalog:
	if _default == null:
		_default = CampaignCatalog.new()
		_default.load_file(PATH)
	return _default


func load_file(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	campaigns = d.get("campaigns", {})
	_missions.clear()


## The campaign of a house ("" if it has none yet).
func campaign_of(faction: String) -> String:
	for id in campaigns:
		if campaigns[id]["faction"] == faction:
			return id
	return ""


func chapters(campaign_id: String) -> Array:
	return campaigns.get(campaign_id, {}).get("chapters", [])


func chapter(campaign_id: String, chapter_id: String) -> Dictionary:
	for c: Dictionary in chapters(campaign_id):
		if c["id"] == chapter_id:
			return c
	return {}


## The campaign a chapter belongs to ("" when none).
func campaign_of_chapter(chapter_id: String) -> String:
	for id: String in campaigns:
		if not chapter(id, chapter_id).is_empty():
			return id
	return ""


func playable(c: Dictionary) -> bool:
	return String(c.get("file", "")) != ""


## A new campaign for its own hero (class and name from campaigns.json).
func start(campaign_id: String) -> CampaignProgress:
	var c: Dictionary = campaigns[campaign_id]
	var hero: Dictionary = c.get("hero", {})
	return CampaignProgress.start(campaign_id, String(c["faction"]), String(hero.get("class", "")), String(hero.get("name", "")))


## The next chapter to play: the first playable one not won yet ({} when none is left).
func next_chapter(p: CampaignProgress) -> Dictionary:
	for c: Dictionary in chapters(p.campaign):
		if not p.done.has(c["id"]):
			return c if playable(c) else {}
	return {}


func mission(chapter_def: Dictionary) -> Dictionary:
	var f := String(chapter_def.get("file", ""))
	if f == "":
		return {}
	if not _missions.has(f):
		_missions[f] = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
	return _missions[f]


# --- Validation ----------------------------------------------------------------------------

func validate() -> Array[String]:
	var errors: Array[String] = []
	var heroes := HeroCatalog.get_default()
	for id: String in campaigns:
		var c: Dictionary = campaigns[id]
		var classes := heroes.faction_classes(String(c.get("faction", "")))
		if classes.is_empty():
			errors.append("campaign %s: house %s has no hero classes" % [id, c.get("faction", "")])
		var hero: Dictionary = c.get("hero", {})
		var any_playable := (c.get("chapters", []) as Array).any(func(x: Dictionary) -> bool: return playable(x))
		if any_playable and not classes.has(String(hero.get("class", ""))):
			errors.append("campaign %s: a playable campaign needs a hero of class from its house" % id)
		var seen := {}
		for ch: Dictionary in c.get("chapters", []):
			if seen.has(ch["id"]):
				errors.append("campaign %s: chapter %s twice" % [id, ch["id"]])
			seen[ch["id"]] = true
			if not String(ch.get("kind", "")) in KINDS:
				errors.append("campaign %s: chapter %s: kind must be hero or war" % [id, ch["id"]])
			if playable(ch):
				if not FileAccess.file_exists(DIR + String(ch["file"])):
					errors.append("campaign %s: chapter %s: missing file %s" % [id, ch["id"], ch["file"]])
					continue
				var m := mission(ch)
				if String(m.get("id", "")) != String(ch["id"]):
					errors.append("chapter %s: mission id is %s" % [ch["id"], m.get("id", "")])
				errors.append_array(validate_mission(m, String(c["faction"])))
	return errors


static func validate_mission(m: Dictionary, faction: String) -> Array[String]:
	var v := _Checker.new()
	v.m = m
	v.where = "mission %s: " % m.get("id", "?")
	v.run(faction)
	return v.errors


## Walks a mission and collects every problem.
class _Checker:
	var m: Dictionary
	var where: String
	var errors: Array[String] = []
	var places := {}  ## every id a position may name
	var npcs := {}
	var groups := {}
	var sites := {}
	var zones := {}
	var hero_groups := {}  ## groups led by a named hero, who may speak in dialogues
	var speakers := {}  ## "speakers": short id -> name, for companions carried in from earlier chapters

	func err(s: String) -> void:
		errors.append(where + s)

	func run(faction: String) -> void:
		var cat := UnitCatalog.get_default()
		HeroCatalog.get_default().register(cat)
		speakers = m.get("speakers", {})
		for k: String in speakers:
			if String(speakers[k]) == "":
				err("speaker %s has no name" % k)
		var absent: Variant = m.get("absent", [])
		if not absent is Array or (absent as Array).any(func(x: Variant) -> bool: return not x is String or String(x) == ""):
			err("absent must be a list of companion names")
		var players: Array = m.get("players", [])
		if players.is_empty() or String(players[0].get("faction", "")) != faction:
			err("players[0] must be the campaign's house %s" % faction)
		for p: Dictionary in players:
			if not cat.factions.has(String(p.get("faction", ""))):
				err("unknown house %s" % p.get("faction", ""))
		if not String(m.get("kind", "")) in KINDS:
			err("kind must be hero or war")
		for k in ["title", "intro", "map", "quests", "dialogues"]:
			if not m.has(k):
				err("missing " + k)
		if not errors.is_empty():
			return
		_map(cat)
		var war := String(m["kind"]) == "war"
		if m.has("max_tier") and (int(m["max_tier"]) < 1 or int(m["max_tier"]) > 8):
			err("max_tier must be 1 to 8")
		if m.has("ai") and not String(m["ai"]) in EconomyAi.DIFFICULTIES:
			err("ai must be one of %s" % [EconomyAi.DIFFICULTIES])
		if war:
			# A war chapter needs a home for every player: the RTS starts there.
			for i in (m.get("players", []) as Array).size():
				var found := false
				for z: Dictionary in m["map"].get("zones", []):
					if z.get("home", false) and int(z.get("owner", -1)) == i:
						found = true
				if not found:
					err("war chapter: player %d has no home zone" % i)
		for k in m.get("hero_boost", {}):
			if not k in ItemCatalog.STATS:
				err("hero_boost: unknown stat %s" % k)
		for n: Dictionary in m.get("npcs", []):
			if npcs.has(n["id"]) or places.has(n["id"]):
				err("id %s used twice" % n["id"])
			npcs[n["id"]] = true
			places[n["id"]] = true
			if cat.get_unit(String(n.get("look", ""))).is_empty():
				err("npc %s: unknown look %s" % [n["id"], n.get("look", "")])
			if String(n.get("name", "")) == "":
				err("npc %s: no name" % n["id"])
		for g: Dictionary in m.get("groups", []):
			if groups.has(g["id"]) or places.has(g["id"]):
				err("id %s used twice" % g["id"])
			groups[g["id"]] = true
			places[g["id"]] = true
			for pair: Array in g.get("units", []):
				if not cat.units.has(String(pair[0])):
					err("group %s: unknown unit %s" % [g["id"], pair[0]])
				if int(pair[1]) < 1:
					err("group %s: count must be at least 1" % g["id"])
			if g.has("hero"):
				hero_groups[g["id"]] = true
			if g.has("hero") and not HeroCatalog.get_default().classes.has(String(g["hero"].get("class", ""))):
				err("group %s: unknown hero class" % g["id"])
		for n: Dictionary in m.get("npcs", []):
			_place(n.get("at"), "npc %s" % n["id"])
			if n.has("if"):
				_cond(n["if"], "npc %s" % n["id"])
			for e: Dictionary in n.get("talk", []):
				if not m["dialogues"].has(String(e.get("dialogue", ""))):
					err("npc %s: unknown dialogue %s" % [n["id"], e.get("dialogue", "")])
				if e.has("if"):
					_cond(e["if"], "npc %s talk" % n["id"])
				if not String(e.get("mark", "")) in ["", "!", "?"]:
					err("npc %s: mark must be ! or ?" % n["id"])
		for g: Dictionary in m.get("groups", []):
			_place(g.get("at"), "group %s" % g["id"])
			if g.has("attack"):
				_place(g["attack"], "group %s attack" % g["id"])
		_place(m.get("hero", {}).get("at"), "hero")
		if m.has("checkpoint"):
			_place(m["checkpoint"], "checkpoint")
		_actions(m.get("start", []), "start")
		for q: String in m["quests"]:
			var qd: Dictionary = m["quests"][q]
			if String(qd.get("title", "")) == "":
				err("quest %s: no title" % q)
			if not String(qd.get("kind", "")) in ["main", "side"]:
				err("quest %s: kind must be main or side" % q)
			var steps: Array = qd.get("steps", [])
			if steps.is_empty():
				err("quest %s: no steps" % q)
			for s: Dictionary in steps:
				if String(s.get("text", "")) == "":
					err("quest %s: a step without text" % q)
				if s.has("done"):
					_cond(s["done"], "quest %s" % q)
				_actions(s.get("do", []), "quest %s" % q)
			_actions(qd.get("reward", []), "quest %s reward" % q)
		for did: String in m["dialogues"]:
			var dd: Dictionary = m["dialogues"][did]
			var nodes: Dictionary = dd.get("nodes", {})
			if not nodes.has(String(dd.get("start", "start"))):
				err("dialogue %s: no start node" % did)
			for nid: String in nodes:
				var n: Dictionary = nodes[nid]
				var at := "dialogue %s/%s" % [did, nid]
				if String(n.get("text", "")) == "":
					err(at + ": no text")
				var who := String(n.get("who", ""))
				if who != "" and who != "hero" and not npcs.has(who) and not hero_groups.has(who) and not speakers.has(who):
					err(at + ": unknown speaker %s" % who)
				if n.has("next") and not nodes.has(String(n["next"])):
					err(at + ": unknown next %s" % n["next"])
				_actions(n.get("do", []), at)
				for c: Dictionary in n.get("choices", []):
					if String(c.get("text", "")) == "":
						err(at + ": a choice without text")
					if c.has("if"):
						_cond(c["if"], at)
					if c.has("next") and String(c["next"]) != "" and not nodes.has(String(c["next"])):
						err(at + ": unknown next %s" % c["next"])
					_actions(c.get("do", []), at)
		for t: Dictionary in m.get("triggers", []):
			if not t.has("when"):
				err("a trigger without when")
				continue
			_cond(t["when"], "trigger")
			if t.has("repeat") and float(t["repeat"]) <= 0.0:
				err("trigger: repeat must be seconds above 0")
			_actions(t.get("do", []), "trigger")
		var wins := JSON.stringify(m).count("\"win\"")
		if wins == 0:
			err("nothing wins the chapter (no win action)")
		for o: Dictionary in m.get("outro", []):
			if o.has("if"):
				_cond(o["if"], "outro")
			if (o.get("text", []) as Array).is_empty():
				err("outro without text")

	func _map(cat: UnitCatalog) -> void:
		var mp: Dictionary = m["map"]
		var biomes: Dictionary = Biomes.data()["biomes"]
		var sizes: Dictionary = cat.economy["settlements"]
		if String(mp.get("symmetry", "none")) != "none":
			err("map: a campaign map has symmetry none")
		if (mp.get("size", []) as Array).size() != 2 or int(mp["size"][0]) < 64 or int(mp["size"][1]) < 48:
			err("map: size must be [w, h], at least 64 x 48")
		if not biomes.has(String(mp.get("base", "meadow"))):
			err("map: unknown base biome")
		var homes := {}
		for z: Dictionary in mp.get("zones", []):
			places[z["id"]] = true
			zones[z["id"]] = z
			if z.get("home", false):
				if not z.has("owner"):
					err("map zone %s: a home zone needs an owner" % z["id"])
				elif homes.has(int(z["owner"])):
					err("map zone %s: player %d has two homes" % [z["id"], int(z["owner"])])
				homes[int(z.get("owner", -1))] = true
			if not sizes.has(String(z.get("size", ""))):
				err("map zone %s: size must be one settlement key" % z["id"])
			var b := String(z.get("biome", "base"))
			if b != "base" and not biomes.has(b):
				err("map zone %s: unknown biome %s" % [z["id"], b])
			if int(z.get("owner", 0)) >= (m.get("players", []) as Array).size():
				err("map zone %s: owner is not a player" % z["id"])
		for s: Dictionary in mp.get("sites", []):
			places[s["id"]] = true
			sites[s["id"]] = s
			if not String(s.get("kind", "")) in MapGen.SITE_KINDS:
				err("map site %s: unknown kind" % s["id"])
			if s.has("set") and not MapGen.SET_PIECES.has(s["set"]):
				err("map site %s: unknown set piece %s" % [s["id"], s["set"]])
			if s.has("keeper") and (int(s["keeper"]) < 0 or int(s["keeper"]) >= (m.get("players", []) as Array).size()):
				err("map site %s: keeper is not a player" % s["id"])
			for g: Array in s.get("guards", []):
				if not cat.units.has(String(g[0])):
					err("map site %s: unknown guard %s" % [s["id"], g[0]])
		for l: Array in mp.get("links", []):
			for e in [l[0], l[1]]:
				if not places.has(String(e)):
					err("map: link to unknown %s" % e)
			if not MapGen.LINK_WIDTH.has(String(l[2])):
				err("map: unknown link kind %s" % l[2])

	func _place(p: Variant, at: String) -> void:
		if p == null:
			err(at + ": no place")
		elif p is Array:
			var a: Array = p
			if a.size() < 2:
				err(at + ": a place needs [x, y]")
			elif a.size() == 2 and (float(a[0]) < 0.0 or float(a[0]) > 1.0 or float(a[1]) < 0.0 or float(a[1]) > 1.0):
				err(at + ": a place in map fractions is between 0 and 1")
		elif String(p) != "hero" and not places.has(String(p)):
			err(at + ": unknown place %s" % p)

	func _quest(q: Variant, at: String) -> void:
		if not m["quests"].has(String(q)):
			err(at + ": unknown quest %s" % q)

	func _cond(c: Variant, at: String) -> void:
		if c is bool:
			return
		if c is Array:
			for x in c:
				_cond(x, at)
			return
		if not c is Dictionary:
			err(at + ": a condition is a dictionary")
			return
		var d: Dictionary = c
		var kind := ""
		for k in StoryMission.CONDITIONS:
			if d.has(k):
				kind = k
				break
		if kind == "":
			err(at + ": unknown condition %s" % d)
			return
		match kind:
			"not":
				_cond(d["not"], at)
			"all", "any":
				for x in d[kind]:
					_cond(x, at)
			"quest":
				_quest(d["quest"], at)
				if not String(d.get("is", "active")) in StoryMission.QUEST_STATES:
					err(at + ": unknown quest state %s" % d.get("is"))
			"step":
				_quest(d["step"][0], at)
				if m["quests"].has(String(d["step"][0])) and int(d["step"][1]) >= (m["quests"][String(d["step"][0])]["steps"] as Array).size():
					err(at + ": quest %s has no step %s" % d["step"])
			"dead", "spawned":
				if not groups.has(String(d[kind])):
					err(at + ": unknown group %s" % d[kind])
			"alive", "talked":
				if not groups.has(String(d[kind])) and not npcs.has(String(d[kind])):
					err(at + ": unknown npc or group %s" % d[kind])
			"near":
				_place(d["near"], at)
			"held":
				if not zones.has(String(d["held"])):
					err(at + ": %s is not a map zone" % d["held"])
			"holds":
				if not d["holds"] is Array or (d["holds"] as Array).size() != 2:
					err(at + ": holds is [owner, count]")
			"cleared":
				if not sites.has(String(d["cleared"])) or sites[String(d["cleared"])]["kind"] != "lair":
					err(at + ": %s is not a lair" % d["cleared"])

	func _actions(list: Variant, at: String) -> void:
		if not list is Array:
			err(at + ": actions are a list")
			return
		for a: Variant in list:
			if not a is Dictionary:
				err(at + ": an action is a dictionary")
				continue
			var d: Dictionary = a
			if d.has("if"):
				_cond(d["if"], at)
			var kind := ""
			for k in StoryMission.ACTIONS:
				if d.has(k):
					kind = k
					break
			if kind == "":
				err(at + ": unknown action %s" % d)
				continue
			match kind:
				"start_quest", "advance", "complete_quest", "fail_quest":
					_quest(d[kind], at)
				"spawn", "attack":
					if not groups.has(String(d[kind])):
						err(at + ": unknown group %s" % d[kind])
					if d.has("to"):
						_place(d["to"], at)
				"hostile", "join", "leave", "remove":
					if not groups.has(String(d[kind])) and not npcs.has(String(d[kind])):
						err(at + ": unknown npc or group %s" % d[kind])
					if d.has("to"):
						_place(d["to"], at)
				"move":
					if not npcs.has(String(d["move"])):
						err(at + ": unknown npc %s" % d["move"])
					_place(d.get("to"), at)
				"dialogue":
					if not m["dialogues"].has(String(d["dialogue"])):
						err(at + ": unknown dialogue %s" % d["dialogue"])
				"checkpoint":
					_place(d["checkpoint"], at)
				"res":
					var known: Dictionary = UnitCatalog.get_default().economy.get("resources", {})
					if not d["res"] is Dictionary:
						err(at + ": res is {resource: amount}")
					else:
						for r: String in d["res"]:
							if not known.has(r):
								err(at + ": unknown resource %s" % r)
				"item":
					var it: Variant = d["item"]
					var icat := ItemCatalog.get_default()
					if it is String:
						if not icat.uniques.has(it):
							err(at + ": unknown unique %s" % it)
					elif it is Dictionary:
						if (it as Dictionary).has("unique") and not icat.uniques.has(String(it["unique"])):
							err(at + ": unknown unique %s" % it["unique"])
						elif not (it as Dictionary).has("unique") and not icat.rarities.has(String(it.get("rarity", "magic"))):
							err(at + ": unknown rarity %s" % it.get("rarity"))
						if (it as Dictionary).has("slot") and not icat.bases.values().any(
								func(b: Dictionary) -> bool: return String(b.get("slot", "")) == String(it["slot"])):
							err(at + ": no item fits slot %s" % it["slot"])
				"potion":
					if not String(d["potion"]) in ["health", "mana"]:
						err(at + ": potion is health or mana")
				"say":
					var w := String(d.get("who", ""))
					if w != "" and w != "hero" and not npcs.has(w) and not speakers.has(w):
						err(at + ": unknown speaker %s" % w)
