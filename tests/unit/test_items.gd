extends "res://tests/test_case.gd"

var ic: ItemCatalog = ItemCatalog.get_default()
var hc: HeroCatalog = HeroCatalog.get_default()


func _world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.setup_map(60, 40)
	return w


func _step(w: SimWorld, seconds: float) -> void:
	for i in int(seconds * w.tick_rate):
		w.step()


func _item(id: String) -> Dictionary:
	return ic.make_unique(id)


func test_item_data_is_valid() -> void:
	var errors := ic.validate(hc)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_rolls_follow_the_rarity_rules() -> void:
	var rng := GameRng.new(3)
	for i in 300:
		var rarity: String = ["common", "magic", "rare"][i % 3]
		var it := ic.roll(rng, rarity, 1 + i % 10)
		var n: int = it["affixes"].size()
		match rarity:
			"common":
				assert_eq(n, 0)
			"magic":
				assert_between(float(n), 1.0, 2.0, it["name"])
			"rare":
				assert_between(float(n), 3.0, 4.0, it["name"])
		var kinds := {"prefix": 0, "suffix": 0}
		for a in it["affixes"]:
			assert_true(it["slot"] in ic.affixes[a]["slots"], a + " fits " + it["slot"])
			kinds[ic.affixes[a]["kind"]] += 1
		assert_true(kinds["prefix"] <= 2 and kinds["suffix"] <= 2, it["name"])
		assert_true(int(ic.bases[it["base"]]["level"]) <= int(it["level"]), "base level within item level")


func test_rolls_are_deterministic() -> void:
	var a := GameRng.new(99)
	var b := GameRng.new(99)
	for i in 50:
		assert_eq(ic.roll_drop(a, "capture", 5), ic.roll_drop(b, "capture", 5))


func test_affixes_grow_with_item_level() -> void:
	assert_gt(ic.affix_value("keen", 10, 0.5), ic.affix_value("keen", 1, 0.5))
	assert_eq(ic.affix_value("brutal", 1, 0.0), 2.0)


func test_drop_level() -> void:
	assert_eq(ic.drop_level("hamlet", 0.0), 2)
	assert_eq(ic.drop_level("city", 13.0), 10, "capped")


func test_every_class_can_wear_its_weapon_kind() -> void:
	for id in hc.classes:
		var arch: String = hc.classes[id]["archetype"]
		for w in hc.classes[id]["weapons"]:
			var kind: String = w
			var it := {"slot": "shield" if kind == "shield" else "weapon", "kind": kind}
			assert_true(ic.can_wear(arch, it), id + " " + kind)
	assert_false(ic.can_wear("mystic", _item("headsmans_maul")), "a mystic can't swing a great weapon")


func test_gear_raises_hero_stats() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "templar", Vector2(400, 400))
	var h := u.hero
	var hp := u.max_hp
	var dmg := float(u.def["damage"])
	assert_true(w.heroes.gear.give(h, _item("headsmans_maul")))
	assert_true(w.heroes.gear.give(h, _item("scarred_plate")))
	assert_eq(h.worn["weapon"]["id"], "headsmans_maul")
	assert_gt(float(u.def["damage"]), dmg + 10.0)
	assert_gt(u.max_hp, hp + 100.0, "+60 health and +3 defense")
	assert_eq(h.attributes["attack"], hc.attributes_at("templar", 1)["attack"] + 3.0)


func test_level_up_keeps_gear() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "warlock", Vector2(400, 400))
	var h := u.hero
	w.heroes.gear.give(h, _item("sceptre_of_the_pyre"))
	var pf := h.power_factor
	w.heroes.add_xp(h, 200)
	assert_eq(h.level, 2)
	assert_gt(h.power_factor, pf, "more power at level 2, the sceptre still counts")
	assert_eq(float(u.def["damage"]), float(hc.make_def("warlock", 2, w.catalog, h.gear)["damage"]))


func test_set_bonus() -> void:
	var a := ic.total_mods({"helm": _item("gravewatch_visor")})
	assert_false(a.has("hp_regen"), "one piece, no bonus")
	var b := ic.total_mods({"helm": _item("gravewatch_visor"), "armor": _item("ossuary_brigandine")})
	assert_eq(float(b["hp_regen"]), 3.0, "1 from the brigandine, 2 from the bonus")
	var c := ic.total_mods({"helm": _item("gravewatch_visor"), "armor": _item("ossuary_brigandine"),
		"boots": _item("hobnailed_boots")})
	assert_eq(float(c["defense"]), 1.0 + 2.0 + 2.0)
	assert_eq(float(c["aura_ward"]), 0.05)


func test_two_handers_and_shields() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	var h := u.hero
	var g := w.heroes.gear
	assert_true(g.give(h, _item("gatewardens_tower")))
	var two := {"uid": 0, "id": "great_sword", "base": "great_sword", "slot": "weapon", "kind": "great_weapon",
		"rarity": "common", "name": "Great Sword", "level": 1, "mods": {"damage": 7.0}, "affixes": [], "set": ""}
	assert_false(ic.can_wear("guardian", two), "a guardian has no great weapons")
	var spear := ic.make_unique("bleeding_glaive")
	assert_true(g.give(h, spear), "a one-handed polearm goes with a shield")
	assert_true(h.worn.has("weapon") and h.worn.has("shield"))
	var w2 := _world()
	var u2 := w2.heroes.spawn_hero(0, "ranger", Vector2(400, 400))
	var h2 := u2.hero
	w2.heroes.gear.give(h2, _item("longwatch_bow"))
	assert_false(ic.can_wear("ranger", _item("vigil_pavise")), "a ranger has no shields")


func test_bag_equip_and_unequip() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	var h := u.hero
	var g := w.heroes.gear
	g.give(h, _item("scarred_plate"))
	g.give(h, _item("wardstone_mail"))
	assert_eq(h.bag.size(), 1, "the second armour goes into the bag")
	var hp := u.max_hp
	assert_true(g.command_equip(0, 0))
	assert_eq(h.worn["armor"]["id"], "wardstone_mail")
	assert_eq(h.bag[0]["id"], "scarred_plate")
	assert_true(u.max_hp != hp)
	assert_true(g.command_unequip(0, "armor"))
	assert_false(h.worn.has("armor"))
	assert_eq(h.bag.size(), 2)
	for i in 10:
		g.give(h, _item("flayed_banner"))
	assert_eq(h.bag.size(), int(ic.rules["bag_size"]), "the bag fills up")
	assert_false(g.give(h, _item("flayed_banner")))


func test_ai_swaps_in_better_gear() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400), true)
	var h := u.hero
	var g := w.heroes.gear
	var plain := ic.roll(GameRng.new(1), "common", 1, "armor")
	g.give(h, plain)
	g.give(h, _item("scarred_plate"))
	assert_eq(h.worn["armor"]["id"], "scarred_plate")
	assert_eq(h.bag.size(), 1)


func test_pickup_from_the_ground() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	var g := w.heroes.gear
	g.drop_item(_item("flayed_banner"), Vector2(700, 400))
	g._put({"potion": "health"}, Vector2(720, 400))
	_step(w, 0.2)
	assert_eq(g.ground.size(), 2, "too far away")
	w.command_move([u.id], Vector2(720, 400))
	_step(w, 8.0)
	assert_eq(g.ground.size(), 0)
	assert_eq(u.hero.worn["banner"]["id"], "flayed_banner")
	assert_eq(int(u.hero.potions["health"]), 1)


func test_banner_aura_and_regen() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	var g := w.heroes.gear
	g.give(u.hero, _item("flayed_banner"))
	g.give(u.hero, _item("saints_knucklebone"))
	var friend := w.spawn("pike_militia", 0, Vector2(450, 400))
	_step(w, 0.6)
	assert_eq(friend.status_value("might"), 0.07)
	u.hp = 100.0
	_step(w, 1.0)
	assert_gt(u.hp, 102.0, "3 health per second")


func test_potions() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "knight", Vector2(400, 400))
	var g := w.heroes.gear
	u.hero.potions["health"] = 2
	assert_false(g.command_drink(0, "health"), "full health")
	u.hp = 50.0
	assert_true(g.command_drink(0, "health"))
	assert_gt(u.hp, 50.0 + u.max_hp * 0.39)
	u.hp = 50.0
	assert_false(g.command_drink(0, "health"), "potion cooldown")
	_step(w, float(ic.rules["potion_cooldown"]) + 0.1)
	assert_true(g.command_drink(0, "health"))
	assert_eq(int(u.hero.potions["health"]), 0)


func test_cooldown_and_xp_gear() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "warlock", Vector2(400, 400))
	var h := u.hero
	var g := w.heroes.gear
	g.give(h, _item("hourglass_of_marrow"))
	w.heroes.command_learn(0, 0)
	var t := w.spawn("pike_militia", 1, Vector2(600, 400))
	w.command_hold([t.id])
	assert_true(w.heroes.command_cast(0, 0, t.id))
	assert_eq(h.cooldowns[0], 10.0 * 0.85)
	var w2 := _world()
	var h2 := w2.heroes.spawn_hero(0, "warlock", Vector2(400, 400)).hero
	w2.heroes.gear.give(h2, _item("scholars_quill"))
	w2.heroes.add_xp(h2, 100)
	assert_eq(h2.xp, 120)


func test_neutral_settlement_drops_loot_once() -> void:
	var w := SkirmishScenario.build_skirmish(5, ["concord", "ashen"])
	w.heroes.spawn_hero(0, "knight", w.economy.hall_of(0).center + Vector2(0, 80))
	var s: Sector = null
	for x in w.economy.sectors:
		if x.owner < 0 and x.home_of < 0:
			s = x
			break
	assert_true(s != null)
	var ev := {"type": "capture", "sector": s.id, "owner": 0, "from": -1}
	w.heroes.gear.on_capture(ev)
	w.heroes.gear.on_capture(ev)
	assert_eq(w.heroes.gear.ground.size(), 1 + int(ic.drops["capture"]["potions"]), "one item and its potions, once")
	w.heroes.gear.on_capture({"type": "capture", "sector": s.id + 1000, "owner": 0, "from": 1})
	assert_eq(w.heroes.gear.ground.size(), 1 + int(ic.drops["capture"]["potions"]), "taking from a player drops nothing")


func test_weapon_kinds_follow_gear() -> void:
	var w := _world()
	var u := w.heroes.spawn_hero(0, "templar", Vector2(400, 400))
	assert_eq(w.heroes.gear.weapon_kinds(0), ["great_weapon"])
	w.heroes.gear.give(u.hero, _item("bleeding_glaive"))
	assert_eq(w.heroes.gear.weapon_kinds(0), ["polearm"])


func test_loot_is_deterministic() -> void:
	var sums: Array = []
	for run in 2:
		var w := SkirmishScenario.build_skirmish(11, ["concord", "hollow"])
		w.heroes.spawn_hero(0, "ranger", w.economy.hall_of(0).center + Vector2(0, 80), true)
		w.heroes.spawn_hero(1, "necromancer", w.economy.hall_of(1).center + Vector2(0, 80), true)
		for s in w.economy.sectors:
			w.heroes.gear.on_capture({"type": "capture", "sector": s.id, "owner": 0, "from": -1})
		var names: Array = []
		for gi in w.heroes.gear.ground:
			names.append(gi["item"]["name"] if gi.has("item") else gi["potion"])
		sums.append(names)
	assert_eq(sums[0], sums[1])
	assert_gt(sums[0].size(), 2)


func test_every_item_has_an_icon() -> void:
	for id in ic.bases:
		var it := ic.roll(GameRng.new(1), "magic", 10, ic.bases[id]["slot"])
		assert_true(ResourceLoader.exists(ItemCatalog.icon_path(it)), "rolled %s has its base's icon" % it["base"])
		assert_true(ResourceLoader.exists("res://assets/items/%s.png" % id), id)
	for id in ic.uniques:
		assert_eq(ItemCatalog.icon_path(ic.make_unique(id)), "res://assets/items/%s.png" % id)
		assert_true(ResourceLoader.exists(ItemCatalog.icon_path(ic.make_unique(id))), id)
	var tex: Texture2D = load(ItemCatalog.icon_path(ic.make_unique("viperwake_kris")))
	assert_eq(tex.get_size(), Vector2(64, 64))


func test_artwork_relics_and_legendaries_drop() -> void:
	assert_eq(ic.make_unique("mooncleft_bardiche")["rarity"], "unique", "relics are uniques")
	assert_eq(ic.make_unique("starless_needle")["rarity"], "unique", "void legendaries are uniques")
	assert_eq(ic.make_unique("viperwake_kris")["set"], "emerald_blight", "poison legendaries are a set")
	var seen := {}
	var rng := GameRng.new(5)
	for i in 3000:
		seen[ic.roll_drop(rng, "capture", 10)["id"]] = true
	var art := 0
	for id in seen:
		if ic.uniques.has(id) and int(ic.uniques[id]["level"]) >= 8:
			art += 1
	assert_gt(art, 10, "many legendaries turn up at item level 10")
	var low := GameRng.new(6)
	for i in 500:
		var it := ic.roll_drop(low, "capture", 3)
		if ic.uniques.has(it["id"]):
			assert_true(int(ic.uniques[it["id"]]["level"]) <= 3, it["id"])


func test_elemental_set_bonuses() -> void:
	var worn := {}
	for id in ["viperwake_kris", "venomglass_panoply", "crown_of_the_plague_moon", "mistfang_treads",
			"witchseed_reliquary", "standard_of_the_emerald_blight"]:
		var it := _item(id)
		worn[it["slot"]] = it
	assert_true(ic.can_wear("ranger", worn["weapon"]), "a ranger wears six of the seven Blight pieces")
	var m := ic.total_mods(worn)
	assert_eq(float(m["damage_pct"]), 0.08 + 0.08, "the kris and the 2-piece bonus")
	assert_eq(float(m["aura_might"]), 0.06 + 0.06, "the standard and the 6-piece bonus")
	assert_eq(float(m["damage"]), 8.0 + 3.0 + 6.0)
	var frost := {}
	for id in ["winterglass_harpoon", "rime_cathedral_vestment", "glacierbreak_bulwark", "tear_of_the_frozen_deep",
			"aurora_of_the_silent_host"]:
		var it := _item(id)
		assert_true(ic.can_wear("guardian", it), id)
		frost[it["slot"]] = it
	assert_eq(float(ic.total_mods(frost)["hp"]), 100.0, "the full Silent Host")
