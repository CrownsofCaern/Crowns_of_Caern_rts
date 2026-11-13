class_name StoryHero
extends RefCounted
## A campaign hero's lasting progress: level (up to 40), XP, skill points spent in the class's
## three trees, the signature's rank, and which skills sit in the 4 slots (Q W E basic, R
## ultimate). Plain data plus rules; the battle copy is made by HeroSystem.spawn_story_hero().

const SIGNATURE := "signature"  ## the node id used for the class signature's rank

var class_id: String = ""
var level: int = 1
var xp: int = 0
var points: int = 0
var ranks: Dictionary = {}  ## node id (or SIGNATURE) -> rank
var slots: Array = ["", "", "", ""]  ## skill ids; slot 3 holds an ultimate

var _trees: StoryTrees
var _heroes: HeroCatalog


func _init(class_name_id: String = "", trees: StoryTrees = null, heroes: HeroCatalog = null) -> void:
	_trees = trees if trees != null else StoryTrees.get_default()
	_heroes = heroes if heroes != null else HeroCatalog.get_default()
	if class_name_id != "":
		class_id = class_name_id
		points = int(_trees.rules["start_points"])
		slots[0] = signature()


func signature() -> String:
	return _heroes.kit(class_id)[0]


func trees() -> Array:
	return _trees.class_trees(_heroes, class_id)


## Gains XP; each level gives skill points. Returns the levels gained.
func add_xp(amount: int) -> int:
	var cap := int(_trees.rules["max_level"])
	var gained := 0
	xp += amount
	while level < cap and xp >= _trees.xp_to_next(level):
		xp -= _trees.xp_to_next(level)
		level += 1
		points += int(_trees.rules["points_per_level"])
		gained += 1
	if level >= cap:
		xp = 0
	return gained


func rank(node_id: String) -> int:
	return int(ranks.get(node_id, 0))


func spent_in(tree_id: String) -> int:
	var n := 0
	for nid in ranks:
		if nid != SIGNATURE and _trees.nodes[nid]["tree"] == tree_id:
			n += int(ranks[nid])
	return n


## Why a node can't take a point now ("" = it can).
func learn_problem(node_id: String) -> String:
	if points <= 0:
		return "no points"
	if node_id == SIGNATURE:
		return "max rank" if rank(SIGNATURE) >= _heroes.max_rank(signature()) - 1 else ""
	if not _trees.nodes.has(node_id):
		return "unknown"
	var n: Dictionary = _trees.nodes[node_id]
	if not n["tree"] in trees():
		return "not your tree"
	if rank(node_id) >= _trees.max_rank(_heroes, node_id):
		return "max rank"
	if spent_in(n["tree"]) < int(_trees.rules["row_points"][int(n["row"])]):
		return "row locked"
	if n["kind"] == "active" and _heroes.skills[n["skill"]].get("ultimate", false) \
			and level < int(_trees.rules["ultimate_level"]):
		return "level"
	return ""


func learn(node_id: String) -> bool:
	if learn_problem(node_id) != "":
		return false
	ranks[node_id] = rank(node_id) + 1
	points -= 1
	# A newly learned skill goes into a free slot of its kind.
	if node_id != SIGNATURE and rank(node_id) == 1 and _trees.nodes[node_id]["kind"] == "active":
		var sid: String = _trees.nodes[node_id]["skill"]
		var ult: bool = _heroes.skills[sid].get("ultimate", false)
		if ult and slots[3] == "":
			slots[3] = sid
		elif not ult:
			for i in 3:
				if slots[i] == "":
					slots[i] = sid
					break
	return true


## Gives back every point (the camp's respec). Returns its gold cost.
func respec() -> int:
	var refund := 0
	for nid in ranks:
		refund += int(ranks[nid])
	points += refund
	ranks.clear()
	slots = [signature(), "", "", ""]
	return int(_trees.rules.get("respec_gold_per_level", 0)) * level


## Skill id -> rank for every skill the hero knows (the signature starts at rank 1).
func known_skills() -> Dictionary:
	var out := {signature(): 1 + rank(SIGNATURE)}
	for nid in ranks:
		if nid != SIGNATURE and _trees.nodes[nid]["kind"] == "active" and int(ranks[nid]) > 0:
			out[_trees.nodes[nid]["skill"]] = int(ranks[nid])
	return out


## Puts a known skill into a slot (0-2 basic, 3 ultimate). It leaves any other slot it was in.
func set_slot(slot: int, skill_id: String) -> bool:
	if slot < 0 or slot > 3:
		return false
	if skill_id != "":
		if not known_skills().has(skill_id):
			return false
		if bool(_heroes.skills[skill_id].get("ultimate", false)) != (slot == 3):
			return false
		for i in 4:
			if slots[i] == skill_id:
				slots[i] = ""
	slots[slot] = skill_id
	return true


## Stats from passive nodes (ItemCatalog stat -> value).
func passive_mods() -> Dictionary:
	var out := {}
	var ids := ranks.keys()
	ids.sort()
	for nid in ids:
		if nid == SIGNATURE or _trees.nodes[nid]["kind"] != "passive":
			continue
		var m: Dictionary = _trees.nodes[nid].get("mods", {})
		for k in m:
			out[k] = float(out.get(k, 0.0)) + float(m[k]) * float(ranks[nid])
	return out


## Talents from passive nodes (StoryTrees.TALENTS type -> value at the learned ranks). Most add
## up; the "every Nth" and cooldown talents keep the smallest value.
func talents() -> Dictionary:
	var out := {}
	var ids := ranks.keys()
	ids.sort()
	for nid in ids:
		if nid == SIGNATURE or not _trees.nodes[nid].has("talent"):
			continue
		var n: Dictionary = _trees.nodes[nid]
		var type: String = n["talent"]["type"]
		var v := StoryTrees.talent_value(n, int(ranks[nid]))
		if v <= 0.0:
			continue
		if type in StoryTrees.MIN_TALENTS:
			out[type] = minf(float(out.get(type, v)), v)
		else:
			out[type] = float(out.get(type, 0.0)) + v
	return out


func to_dict() -> Dictionary:
	return {"class_id": class_id, "level": level, "xp": xp, "points": points, "ranks": ranks.duplicate(),
		"slots": slots.duplicate()}


static func from_dict(d: Dictionary) -> StoryHero:
	var s := StoryHero.new()
	s.class_id = d["class_id"]
	s.level = int(d["level"])
	s.xp = int(d["xp"])
	s.points = int(d["points"])
	for k in d["ranks"]:
		s.ranks[k] = int(d["ranks"][k])
	s.slots = (d["slots"] as Array).duplicate()
	s._fit_to_trees()
	return s


## Old saves after a tree changed: points in a node that is gone, or above its new top rank, come
## back as unspent points; a slotted skill the hero no longer knows leaves its slot.
func _fit_to_trees() -> void:
	for nid in ranks.keys():
		if nid == SIGNATURE:
			continue
		var cap := _trees.max_rank(_heroes, nid) if _trees.nodes.has(nid) else 0
		if int(ranks[nid]) > cap:
			points += int(ranks[nid]) - cap
			if cap <= 0:
				ranks.erase(nid)
			else:
				ranks[nid] = cap
	var known := known_skills()
	for i in slots.size():
		if String(slots[i]) != "" and not known.has(slots[i]):
			slots[i] = ""
