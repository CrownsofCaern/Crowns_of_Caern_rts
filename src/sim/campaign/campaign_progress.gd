class_name CampaignProgress
extends RefCounted
## One campaign's lasting state between chapters: the story hero (level, trees, slots), its
## gear and potions, marks (the hero's coin), companions, the flags every choice set, and the chapters won.
## Plain data; saved as JSON (user://warbound_campaign_<id>.json).

const SAVE_VERSION := 1

var campaign: String = ""
var faction: String = ""
var story: StoryHero
var hero_name: String = ""  ## the campaign hero's name (shown over it)
var worn: Dictionary = {}  ## slot -> item
var bag: Array = []
var potions: Dictionary = {"health": 2, "mana": 1}
var marks: int = 0
## Units that follow the hero from chapter to chapter: [{type, name}].
var companions: Array = []
var flags: Dictionary = {}  ## flag -> true, in the order they were set
var done: Array = []  ## chapter ids won, in order


static func start(campaign_id: String, faction_id: String, class_id: String, name: String = "") -> CampaignProgress:
	var p := CampaignProgress.new()
	p.hero_name = name
	p.campaign = campaign_id
	p.faction = faction_id
	p.story = StoryHero.new(class_id)
	return p


func has_flag(f: String) -> bool:
	return flags.has(f)


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "campaign": campaign, "faction": faction, "hero_name": hero_name, "story": story.to_dict(),
		"worn": worn.duplicate(true), "bag": bag.duplicate(true), "potions": potions.duplicate(),
		"marks": marks, "companions": companions.duplicate(true), "flags": flags.keys(), "done": done.duplicate()}


static func from_dict(d: Dictionary) -> CampaignProgress:
	var p := CampaignProgress.new()
	p.campaign = String(d.get("campaign", ""))
	p.faction = String(d.get("faction", ""))
	p.hero_name = String(d.get("hero_name", ""))
	p.story = StoryHero.from_dict(d["story"])
	p.worn = (d.get("worn", {}) as Dictionary).duplicate(true)
	p.bag = (d.get("bag", []) as Array).duplicate(true)
	p.potions = {}
	var pots: Dictionary = d.get("potions", {"health": 0, "mana": 0})
	for k in pots:
		p.potions[k] = int(pots[k])
	p.marks = int(d.get("marks", d.get("gold", 0)))  # saves before marks kept the coin as "gold"
	p.companions = (d.get("companions", []) as Array).duplicate(true)
	for f in d.get("flags", []):
		p.flags[String(f)] = true
	p.done = (d.get("done", []) as Array).duplicate()
	# Items come back from JSON with float numbers; the rules read them as floats anyway.
	return p


static func path_for(campaign_id: String) -> String:
	return "user://warbound_campaign_%s.json" % campaign_id


func save() -> bool:
	var f := FileAccess.open(path_for(campaign), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


static func load_saved(campaign_id: String) -> CampaignProgress:
	if not FileAccess.file_exists(path_for(campaign_id)):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(campaign_id)))
	if not d is Dictionary or not (d as Dictionary).has("story"):
		return null
	return from_dict(d)


static func erase_saved(campaign_id: String) -> void:
	if FileAccess.file_exists(path_for(campaign_id)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(campaign_id)))
