#!/usr/bin/env python3
"""Copy content from the main game (Crowns of Caern) into the spinoff.

Run from anywhere:  python3 tools/sync_from_main.py

* data/units.json: real-time stats for the base units of the factions below,
  converted from the main game's creature data with the formulas in this file.
  Tune balance here (ROLE table, formulas), then re-run.
* assets/units/<id>.png: the unit's 128x128 sprite, cropped from the main
  game's unit atlases (each sprite's own atlas from the manifest).
* assets/terrain/: seamless 480x480 grass and water fields and a boulder strip,
  cut from the main game's terrain and decoration atlases.
* assets/units3d/<id>.glb and src/ui/live_unit.gd: the live 3D unit models and their
  loader, made by the main game's tools/assets/export_live_units.gd. Copied unchanged;
  units without a model keep their sprite in the 3D view.
* wild creatures (main data/creatures/wilds.json) as neutral lair guards, with their sprites.
* assets/audio/: battle sounds and music (rendered by the main game's
  tools/audio/synth.py, so they are the project's own).
* data/combat_fx.json "units": each unit's attack element (the main game's assets/battle_fx.json
  and its fallbacks), gore kind (from creature tags, as the main game's BattleGore) and missile.
  The rest of that file (skills, hero archetypes) is Warbound's own and kept.
  `sync_from_main.py fx` refreshes only this table.
* assets/ui/cursors/ is no longer synced: Warbound has its own cursor set (CommandCursor).

`sync_from_main.py units` rewrites only data/units.json (no art, sound or models), for tuning.

Combat depth (Warbound's own, Nov 13): each unit gets a damage_type (melee, ranged or magic), a
defense against each type (its base armour moved by its body: DEFENSE_TAGS, ROLE_DEFENSE), a
building_damage per blow (SIEGE_ROLE, SIEGE_TAGS) and maybe a damage over time (DOTS).
"""
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")
FACTIONS = ["concord", "hollow", "ashen", "thornwood", "forge", "fishmen", "darkelf", "frostmarch"]
# Rare costs a faction does not gather in the skirmish are paid in one it does.
RARE_REMAP = {"ashen": {"mercury": "gems"}, "thornwood": {"wood": "crystal"},
              "forge": {"crystal": "gems", "sulfur": "mercury"}}
# Building keys whose main-game town art uses another prefix (Warbound s_* = main fm_*, e_* = de_*).
MAIN_BUILDING_PREFIX = {"fishmen": "fm", "darkelf": "de"}
# Per-unit tuning on top of the formulas, from skirmish balance runs (reports/).
UNIT_TUNING = {
    "scorchhound": {"gold": 40},  # tier 2 cavalry with charge was by far the best buy
    "thorn_skulker": {"gold": 17},  # Thornwood lost 1-6 at 20 gold (before the warden fix)
    "briar_huntress": {"gold": 40},
    "barkhide_warden": {"gold": 25},  # tier 2 tank; with an added shield wall Thornwood won 26 of 32
    "rootbound_ancient": {"add": ["shield_wall"]},
    "pike_militia": {"drop": ["brace"]},  # braced pikes made Concord beat every cavalry army (19-7)
}
# Wild creatures left out of the lairs: the ancient dragon is a campaign boss (4400 hp in the main game).
WILD_SKIP = {"ancient_dragon"}
# Workers: name and still sprite, assets/units/worker_<faction>.png: idle frame 0 of the
# worker's own sheet baked from its 3D body (tools/bake_hero_sprites.py --units).
WORKERS = {"concord": ("Labourer", "worker_concord"), "hollow": ("Grave Thrall", "worker_hollow"),
           "ashen": ("Slag Thrall", "worker_ashen"), "thornwood": ("Grove Tender", "worker_thornwood"),
           "forge": ("Pit Hand", "worker_forge"), "fishmen": ("Shore Drudge", "worker_fishmen"),
           "darkelf": ("Bound Hand", "worker_darkelf"), "frostmarch": ("Clan Hauler", "worker_frostmarch")}
# Campaign NPC bodies (assets/source/npcs3d/npcs.json in the main repo): id -> name.
NPCS = {"npc_peddler": "Peddler", "npc_priest": "Chapel Monk", "npc_elder": "Village Elder",
        "npc_woman": "Villager", "npc_child": "Farm Child", "npc_risen": "Risen Villager", "npc_noble": "Envoy"}

# Per-role real-time constants. interval = seconds between attacks.
ROLE = {
    "infantry": {"interval": 1.0, "range": 0.0, "speed_bonus": 0},
    "ranged": {"interval": 1.6, "range": 230.0, "speed_bonus": 0},
    "cavalry": {"interval": 1.2, "range": 0.0, "speed_bonus": 10},
    "flyer": {"interval": 1.1, "range": 0.0, "speed_bonus": 20},  # flyers are the fastest, ~15% above cavalry
    "support": {"interval": 1.4, "range": 0.0, "speed_bonus": 0},
    "heavy": {"interval": 1.8, "range": 0.0, "speed_bonus": -5},
}
# Abilities the real-time rules implement. Others are dropped until they do.
IMPLEMENTED = {"reach", "flying", "ranged", "heal", "charge", "regenerate", "shield_wall", "curse", "poison", "brace", "relentless"}
# Specials only upgraded units carry (their dwelling's paid upgrade), with real-time rules in
# SimWorld. Base units with these keep them dropped so the upgrade stays the way to get them.
UPGRADE_SPECIALS = {"life_drain", "armor_pierce", "cleave", "stun", "double_strike", "sunder",
                    "first_strike", "aura", "fear", "splash"}
REACH_RANGE = 14.0
# Every unit's health x this (Nov 13: +10% so wounded troops live long enough to retreat).
HP_SCALE = 1.1


def scaled_hp(hp: float) -> int:
    return int(round(hp * HP_SCALE, 6))


def radius_for(tier: int, role: str) -> float:
    r = [9, 9, 11, 11, 13, 13, 18, 18][tier - 1]
    if role == "heavy":
        r += 3
    return float(r)


def convert(cid: str, c: dict, specials: bool = False) -> dict:
    role = c["role"]
    rc = ROLE[role]
    allowed = IMPLEMENTED | UPGRADE_SPECIALS if specials else IMPLEMENTED
    abilities = [a["id"] for a in c.get("abilities", []) if a["id"] in allowed]
    lo, hi = c["damage"]
    dmg = (lo + hi) * 1.0 + c["attack"] * 0.5
    rng = rc["range"]
    if "reach" in abilities and rng == 0.0:
        rng = REACH_RANGE
    if "ranged" in abilities and rng == 0.0:
        rng = ROLE["ranged"]["range"] * 0.8  # casters shoot, a little shorter than archers
    remap = RARE_REMAP.get(c["faction"], {})
    cost = {}
    for k, v in c["cost"].items():
        k = remap.get(k, k)
        cost[k] = cost.get(k, 0) + v
    cost["gold"] = int(round(cost.get("gold", 0) / 5.0 / 5.0) * 5)
    tune = UNIT_TUNING.get(cid, {})
    if "gold" in tune:
        cost["gold"] = tune["gold"]
    abilities += [a for a in tune.get("add", []) if a not in abilities]
    abilities = [a for a in abilities if a not in tune.get("drop", [])]
    u = {
        "id": cid,
        "name": c["name"],
        "faction": c["faction"],
        "tier": c["tier"],
        "role": role,
        "hp": scaled_hp(int(c["hp"] * 8 + 40)),
        "armor_pct": round(c["defense"] / (c["defense"] + 20.0), 3),
        "damage": round(dmg, 1),
        "attack_interval": rc["interval"],
        "range": rng,
        "speed": 26 + c["speed"] * 8 + rc["speed_bonus"],
        "sight": 300.0 if role != "ranged" else 320.0,
        "radius": radius_for(c["tier"], role),
        "abilities": abilities,
        "cost": cost,
        "sprite": "res://assets/units/%s.png" % cid,
    }
    combat_depth(cid, c, u)
    return u


# --- Combat depth: damage types, three defences, building damage, damage over time ---------
DAMAGE_TYPES = ["melee", "ranged", "magic"]
# Body tags for units whose main-game creature has none that tell what they are.
EXTRA_TAGS = {
    "de_veil_adept": ["caster"], "de_mirror_witch": ["caster"],
    "de_silk_stalker": ["beast", "insect"], "de_widow_matriarch": ["beast", "insect"],
    "de_obsidian_guard": ["plate"], "de_onyx_executioner": ["plate"],
    "de_gloam_drake": ["wyrm"], "de_eclipse_dragon": ["wyrm"],
    "fm_shellback": ["shell"], "fm_barnacle_bulwark": ["shell"], "fm_mire_crab": ["shell"],
    "fm_siege_carapace": ["shell"], "fm_lantern_acolyte": ["caster"], "fm_drowned_oracle": ["caster"],
    "fm_coil_serpent": ["wyrm"], "fm_storm_leviathan": ["wyrm"],
    "fm_trench_titan": ["giant"], "fm_abyss_sovereign": ["giant"],
    "marrow_deadeye": ["archer"], "gibbet_knight": ["plate"], "gibbet_lord": ["plate"],
    "lancer": ["plate"], "oathbound_lancer": ["plate"], "iron_margrave": ["plate"], "iron_sovereign": ["plate"],
}
# Defence offsets (melee, ranged, magic) added to a unit's base armour for each tag it carries:
# shields and plate stop arrows, robed casters and the holy resist spells, bone lets arrows
# through but breaks under holy light, spirits shrug off steel and fear magic.
DEFENSE_TAGS = {
    "shield": (0.0, 0.10, -0.05), "plate": (0.05, 0.10, -0.05), "shell": (0.05, 0.10, -0.05),
    "construct": (0.05, 0.10, -0.15), "siege": (0.0, 0.05, -0.05), "mounted": (0.0, -0.05, 0.0),
    "caster": (-0.10, 0.0, 0.20), "holy": (0.0, 0.0, 0.15), "hag": (0.0, 0.0, 0.15), "artificer": (0.0, 0.0, 0.05),
    "undead": (0.0, 0.05, -0.10), "spirit": (0.20, 0.20, -0.20), "abomination": (0.05, 0.05, -0.05),
    "demon": (0.0, 0.0, 0.10), "sylvan": (0.0, 0.0, 0.05), "treant": (0.0, 0.15, -0.15),
    "fungus": (0.0, 0.05, -0.05), "plant": (0.0, 0.05, -0.05), "beast": (0.0, 0.0, -0.05),
    "giant": (0.05, 0.0, -0.10), "wyrm": (0.0, 0.10, -0.05), "reptile": (0.0, 0.05, 0.0),
    "insect": (0.0, 0.10, -0.05), "darkelf": (-0.05, 0.0, 0.10), "fishmen": (0.0, 0.05, -0.05),
    "deepfolk": (0.05, 0.0, 0.05), "northman": (0.0, 0.0, 0.05),
}
# And by role: archers and casters are soft in melee, riders and flyers are big targets for arrows.
ROLE_DEFENSE = {"infantry": (0.0, 0.0, 0.0), "ranged": (-0.05, 0.0, 0.0), "cavalry": (0.0, -0.05, 0.0),
                "flyer": (0.0, -0.10, 0.0), "support": (-0.05, 0.0, 0.05), "heavy": (0.0, 0.0, 0.0)}
DEFENSE_CAP = 0.8
# Who strikes with magic: casters, the holy, hags and spirits; plus these.
MAGIC_TAGS = {"caster", "holy", "hag", "spirit"}
DAMAGE_TYPE = {"wyrdthorn_mother": "magic", "wyrdthorn_matriarch": "magic"}
# Building damage = damage x this: the role's, or the biggest of the unit's siege tags.
SIEGE_ROLE = {"infantry": 1.0, "cavalry": 0.6, "ranged": 0.5, "flyer": 0.5, "support": 0.5, "heavy": 1.6}
SIEGE_TAGS = {"siege": 4.0, "construct": 2.5, "giant": 2.5, "treant": 2.5}
SIEGE_UNIT = {"brimstone_hurler": 1.2, "brimstone_bombardier": 1.2, "wyrdthorn_mother": 1.0,
              "wyrdthorn_matriarch": 1.0, "fm_siege_carapace": 2.5}
# Damage over time (rules.json): burn (fire, through magic defence, sets buildings alight), bleed
# (through armour, not on the bloodless) and frost (slows). A unit that gains one deals
# DOT_DAMAGE_FACTOR x its damage per blow, so the extra is a different kind of damage, not more.
DOTS = {
    "burn": ["seared_cinderling", "scorchhound", "hellmaw_hound", "brimstone_hurler", "brimstone_bombardier",
             "pyre_titan", "pyre_sovereign", "cinder_maw", "maw_of_ruin", "thunder_bombard", "doom_bombard",
             "molten_engine", "worldforge_engine", "cinder_wraith"],
    "bleed": ["flayer", "flayer_exalted", "de_knifedancer", "de_blood_scythe", "oathless_berserker",
              "bloodfrenzy_berserker", "road_cutthroat", "shrieking_harpy", "gloom_panther"],
    "frost": ["frost_shaman", "storm_shaman", "winter_wyrm", "winter_wyrm_ancient", "rime_wight", "frost_drake",
              "rimefang_hound", "rimefang_packleader"],
}
DOT_DAMAGE_FACTOR = {"burn": 0.85, "bleed": 0.85, "frost": 0.9}
# Fire takes the place of these units' venom.
DOT_REPLACES = {"seared_cinderling": "poison", "cinder_wraith": "poison"}
BLOODLESS_TAGS = {"undead", "spirit", "construct", "treant", "plant", "fungus", "siege"}


def combat_depth(cid: str, c: dict, u: dict) -> None:
    """Adds damage_type, defense, building_damage, bloodless and a damage over time to unit u."""
    tags = list(c.get("tags", [])) + EXTRA_TAGS.get(cid, [])
    role = u["role"]
    base = u["armor_pct"]
    off = list(ROLE_DEFENSE[role])
    for t in tags:
        for i, v in enumerate(DEFENSE_TAGS.get(t, (0.0, 0.0, 0.0))):
            off[i] += v
    u["defense"] = {k: round(min(DEFENSE_CAP, max(0.0, base + off[i])), 3) for i, k in enumerate(DAMAGE_TYPES)}
    if cid in DAMAGE_TYPE:
        u["damage_type"] = DAMAGE_TYPE[cid]
    elif MAGIC_TAGS & set(tags):
        u["damage_type"] = "magic"
    elif "ranged" in u["abilities"]:
        u["damage_type"] = "ranged"
    else:
        u["damage_type"] = "melee"
    for kind, ids in DOTS.items():
        if cid not in ids:
            continue
        old = DOT_REPLACES.get(cid, "")
        if old in u["abilities"]:
            u["abilities"][u["abilities"].index(old)] = kind
        elif kind not in u["abilities"]:
            u["abilities"].append(kind)
            u["damage"] = round(u["damage"] * DOT_DAMAGE_FACTOR[kind], 1)
    factor = SIEGE_ROLE[role]
    for t in tags:
        factor = max(factor, SIEGE_TAGS.get(t, 0.0))
    factor = SIEGE_UNIT.get(cid, factor)
    u["building_damage"] = round(u["damage"] * factor, 1)
    if BLOODLESS_TAGS & set(tags):
        u["bloodless"] = True

def balance_defenses(units: dict) -> None:
    """Keeps each faction as tough as before on the whole: the faction's mean shift of its three
    defences, weighted by how much of each damage type comes at it, is taken off all of its units. Its shape stays (bone still stops arrows and fears
    magic), but Hollow or Forge don't grow tougher overall."""
    trained = [u for u in units.values() if u["faction"] in FACTIONS]
    # Damage per second per gold of each type across the rosters (archers count double: they
    # hit most of a battle and get role matchups x2 on foot).
    dps = {t: 0.0 for t in DAMAGE_TYPES}
    for u in trained:
        dps[u["damage_type"]] += u["damage"] / u["attack_interval"] / max(1.0, u["cost"].get("gold", 1)) \
            * (2.0 if u["damage_type"] == "ranged" else 1.0)
    weight = {t: dps[t] / sum(dps.values()) for t in DAMAGE_TYPES}
    for fac in FACTIONS:
        mine = [u for u in trained if u["faction"] == fac]
        shift = sum(weight[t] * (u["defense"][t] - u["armor_pct"]) for u in mine for t in DAMAGE_TYPES) / len(mine)
        for u in mine:
            u["defense"] = {t: round(min(DEFENSE_CAP, max(0.0, v - shift)), 3) for t, v in u["defense"].items()}


# Workers and townsfolk: no armour of any kind; they hit a building as hard as anyone.
PEOPLE_COMBAT = {"damage_type": "melee", "defense": {"melee": 0.0, "ranged": 0.0, "magic": 0.0}, "building_damage": 2.0}


UPGRADE_GOLD = 1.3  # ~10% more hp and damage plus a special: a bit dearer per head, worth it per worker


def upgrade_convert(cid: str, c: dict, base_id: str, base_c: dict, base_unit: dict) -> dict:
    """An upgraded unit: the main game's upgraded stats and specials, UPGRADE_GOLD x its (tuned)
    base's gold, and any ability the tuning added to its base."""
    u = convert(cid, c, specials=True)
    u["upgrade_of"] = base_id
    u["cost"]["gold"] = max(base_unit["cost"]["gold"] + 5, int(round(base_unit["cost"]["gold"] * UPGRADE_GOLD / 5.0)) * 5)
    for a in UNIT_TUNING.get(base_id, {}).get("add", []):
        if a not in u["abilities"]:
            u["abilities"].append(a)
    return u


def upgrade_building_names() -> dict:
    """Names of the main game's dwelling upgrades (c_up1 ...), keyed by Warbound dwelling key + "_up"."""
    economy = json.load(open(os.path.join(PROJECT, "data", "economy.json")))
    towns = json.load(open(os.path.join(MAIN, "data", "buildings.json")))["towns"]
    names = {}
    for fac, b in economy["buildings"].items():
        main_prefix = MAIN_BUILDING_PREFIX.get(fac, b["hall"][:b["hall"].index("_")])
        for i, key in enumerate(b["dwellings"]):
            src = "%s_up%d" % (main_prefix, i + 1)
            info = towns[fac]["buildings"].get(src)
            if info is not None:
                names[key + "_up"] = info["name"]
    return names


SOUNDS = ["battle_hit", "battle_hit_2", "battle_hit_3", "battle_hit_4", "battle_shot", "battle_shot_2",
          "battle_shot_3", "battle_horn", "battle_start", "ui_click", "ui_click_2", "ui_error",
          "weather_rain", "weather_thunder", "weather_thunder_2", "weather_thunder_3"]
MUSIC = ["battle", "battle_victory_concord", "battle_defeat"]


def copy_terrain(manifest: dict) -> None:
    out = os.path.join(PROJECT, "assets", "terrain")
    os.makedirs(out, exist_ok=True)
    t = manifest["terrain"]
    atlas = Image.open(os.path.join(MAIN, "assets", "atlases", "terrain.png")).convert("RGBA")
    size = t["tile_size"]
    for name in ["grass", "water"]:
        info = t["terrains"][name]
        col0 = info["field"]["column"]
        cw, ch = info["field"]["cells"]
        field = Image.new("RGBA", (cw * size, ch * size))
        for i in range(cw * ch):
            x = (col0 + i) * size
            y = info["row"] * size
            field.paste(atlas.crop((x, y, x + size, y + size)), ((i % cw) * size, (i // cw) * size))
        field.save(os.path.join(out, name + ".png"))
    deco = t["deco"]
    dw, dh = deco["cell"]
    img = Image.open(os.path.join(MAIN, "assets", "atlases", "deco.png")).convert("RGBA")
    kinds = ["boulders", "mossy_boulders"]
    n = deco["variants"]
    strip = Image.new("RGBA", (dw * n * len(kinds), dh))
    for k, kind in enumerate(kinds):
        row = deco["kinds"][kind]["row"]
        for v in range(n):
            strip.paste(img.crop((v * dw, row * dh, v * dw + dw, row * dh + dh)), ((k * n + v) * dw, 0))
    strip.save(os.path.join(out, "boulders.png"))


# Settlement centres: (source, sprite key or scenery file).
SETTLEMENT_ART = {
    "waystone": ("sprite", "place_lockstone"),
    "farmstead": ("scenery", "dwelling_windmill"),
    "hamlet": ("scenery", "settlement_concord_hamlet"),
    "village": ("scenery", "settlement_thornwood_hamlet"),
    "town": ("sprite", "town_forge"),
    "city": ("scenery", "landmark_shattered_citadel"),
}


def crop_sprite(manifest: dict, key: str, atlases: dict) -> Image.Image:
    info = manifest["sprites"][key]
    name = info["atlas"]
    if name not in atlases:
        atlases[name] = Image.open(os.path.join(MAIN, "assets", "atlases", name + ".png")).convert("RGBA")
    x, y, w, h = info["rect"]
    return atlases[name].crop((x, y, x + w, y + h))


def copy_map_objects(manifest: dict) -> dict:
    """Buildings (town-screen art, halved), settlement centres and resource piles."""
    atlases = {}
    economy = json.load(open(os.path.join(PROJECT, "data", "economy.json")))
    towns = json.load(open(os.path.join(MAIN, "data", "buildings.json")))["towns"]
    out_b = os.path.join(PROJECT, "assets", "buildings")
    os.makedirs(out_b, exist_ok=True)
    names = {}
    for fac, b in economy["buildings"].items():
        for key in [b["hall"], b["storehouse"]] + b["dwellings"]:
            src = MAIN_BUILDING_PREFIX.get(fac, "") + key[key.index("_"):] if fac in MAIN_BUILDING_PREFIX else key
            img = Image.open(os.path.join(MAIN, "assets", "towns", fac, src + ".png")).convert("RGBA")
            img = img.resize((img.width // 2, img.height // 2), Image.LANCZOS)
            img.save(os.path.join(out_b, key + ".png"))
            names[key] = towns[fac]["buildings"][src]["name"]
    out_s = os.path.join(PROJECT, "assets", "settlements")
    os.makedirs(out_s, exist_ok=True)
    for size, (src, key) in SETTLEMENT_ART.items():
        if src == "sprite":
            img = crop_sprite(manifest, key, atlases)
        else:
            img = Image.open(os.path.join(MAIN, "assets", "map_scenery", key + ".png")).convert("RGBA")
        img.save(os.path.join(out_s, size + ".png"))
    out_r = os.path.join(PROJECT, "assets", "resources")
    os.makedirs(out_r, exist_ok=True)
    for res in economy["node_resources"]:
        crop_sprite(manifest, "resource_" + res, atlases).save(os.path.join(out_r, res + ".png"))
    return names


def copy_units3d(ids) -> None:
    src = os.path.join(MAIN, "assets", "units3d")
    if not os.path.isdir(src):
        print("no assets/units3d in the main game yet; 3D view keeps sprites")
        return
    dst = os.path.join(PROJECT, "assets", "units3d")
    os.makedirs(dst, exist_ok=True)
    n = 0
    for i in sorted(set(ids)):
        f = os.path.join(src, i + ".glb")
        if os.path.exists(f):
            shutil.copyfile(f, os.path.join(dst, i + ".glb"))
            n += 1
    manifest = os.path.join(src, "units3d.json")
    if os.path.exists(manifest):
        shutil.copyfile(manifest, os.path.join(dst, "units3d.json"))
    loader = os.path.join(MAIN, "src", "ui", "live_unit.gd")
    if os.path.exists(loader):
        with open(loader) as fh:
            lines = fh.read().split("\n")
        lines.insert(1, "## Copied unchanged from the main game (src/ui/live_unit.gd); edit it there, not here.")
        with open(os.path.join(PROJECT, "src", "ui", "live_unit.gd"), "w") as fh:
            fh.write("\n".join(lines))
    print("copied %d 3D unit models" % n)


def copy_audio() -> None:
    for sub, names in [("sfx", SOUNDS), ("music", MUSIC)]:
        out = os.path.join(PROJECT, "assets", "audio", sub)
        os.makedirs(out, exist_ok=True)
        for n in names:
            shutil.copyfile(os.path.join(MAIN, "assets", "audio", sub, n + ".ogg"), os.path.join(out, n + ".ogg"))


# Missiles of the ranged units (CombatFx3D): arrow, bolt (crossbow), harpoon, stone, shell (bombard),
# orb (a straight glowing bolt) or lob (an arcing glowing glob). Not listed: an elemental shooter
# casts an orb, anything else shoots an arrow.
MISSILES = {"rivet_crossbowman": "bolt", "deserter_crossbows": "bolt", "fm_hookcaster": "harpoon",
            "crag_slinger": "stone", "thunder_bombard": "shell", "brimstone_hurler": "lob",
            "spore_lobber": "lob", "wyrdthorn_mother": "lob"}


def fx_element(cid: str, c: dict, listed: dict) -> str:
    """The main game's BattleFx.element_of: the battle_fx.json table, then the creature's data."""
    if cid in listed:
        return listed[cid]
    abilities = [a["id"] if isinstance(a, dict) else a for a in c.get("abilities", [])]
    if "poison" in abilities:
        return "poison"
    if "splash" in abilities:
        return "blast"
    if "caster" in c.get("tags", []):
        return "arcane"
    return ""


def fx_gore(c: dict) -> str:
    """The main game's BattleGore.kind_from."""
    tags = c.get("tags", [])
    if "spirit" in tags:
        return "wisp"
    if "undead" in tags:
        return "bone"
    if "construct" in tags or "siege" in tags:
        return "sparks"
    if "demon" in tags:
        return "ember"
    if any(t in tags for t in ("treant", "plant", "fungus")):
        return "sap"
    if "fishmen" in tags or c.get("faction") == "fishmen" or "insect" in tags:
        return "ichor"
    return "blood"


def write_combat_fx() -> None:
    units = json.load(open(os.path.join(PROJECT, "data", "units.json")))["units"]
    listed = json.load(open(os.path.join(MAIN, "assets", "battle_fx.json")))["creatures"]
    creatures = {}
    for fac in FACTIONS + ["wilds"]:
        creatures.update(json.load(open(os.path.join(MAIN, "data", "creatures", fac + ".json")))["creatures"])
    path = os.path.join(PROJECT, "data", "combat_fx.json")
    out = json.load(open(path)) if os.path.exists(path) else {}
    table = {}
    for uid in sorted(units):
        u = units[uid]
        if u["role"] == "worker":
            src = os.path.basename(u["sprite"])[:-4]  # the unit whose body it borrows
            table[uid] = {"element": "", "gore": fx_gore(creatures.get(src, {})), "missile": ""}
            continue
        c = creatures.get(uid, creatures.get("pike_militia"))
        element = fx_element(uid, c, listed)
        missile = ""
        if "ranged" in u["abilities"]:
            missile = MISSILES.get(uid, "orb" if element else "arrow")
        table[uid] = {"element": element, "gore": fx_gore(c), "missile": missile}
    out["units"] = table
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("wrote combat fx for %d units" % len(table))


def main() -> int:
    if sys.argv[1:] == ["fx"]:
        write_combat_fx()
        return 0
    units_only = sys.argv[1:] == ["units"]
    manifest = json.load(open(os.path.join(MAIN, "assets", "manifest.json")))
    # Each sprite lives in the atlas its manifest entry names (fish-men and dark elves have their own).
    atlases = {}
    units = {}
    for fac in FACTIONS:
        creatures = json.load(open(os.path.join(MAIN, "data", "creatures", fac + ".json")))["creatures"]
        for cid, c in creatures.items():
            if "upgrade_of" in c:
                continue
            units[cid] = convert(cid, c)
            if not units_only:
                crop_sprite(manifest, "creature_" + cid, atlases).save(os.path.join(PROJECT, "assets", "units", cid + ".png"))
        # Upgraded units: a dwelling trains them once its (permanent) upgrade is bought.
        for cid, c in creatures.items():
            if "upgrade_of" not in c:
                continue
            base = c["upgrade_of"]
            u = upgrade_convert(cid, c, base, creatures[base], units[base])
            units[base]["upgrade"] = cid
            units[cid] = u
            if not units_only:
                crop_sprite(manifest, "creature_" + cid, atlases).save(os.path.join(PROJECT, "assets", "units", cid + ".png"))
    if units_only:
        building_names = json.load(open(os.path.join(PROJECT, "data", "units.json")))["building_names"]
    else:
        copy_terrain(manifest)
        copy_audio()
        building_names = copy_map_objects(manifest)
        building_names.update(upgrade_building_names())
    balance_defenses(units)
    # People and neutral defenders. Workers gather and build; they barely fight.
    for fac in FACTIONS:
        wid = "worker_" + fac
        name, sprite = WORKERS[fac]
        units[wid] = {"id": wid, "name": name, "faction": fac, "tier": 0, "role": "worker", "hp": scaled_hp(60),
                      "armor_pct": 0.0, "damage": 2.0, "attack_interval": 1.5, "range": 0.0, "speed": 64,
                      "sight": 220.0, "radius": 7.0, "abilities": [], "cost": {},
                      "sprite": "res://assets/units/%s.png" % sprite}
        units[wid].update(PEOPLE_COMBAT)
    # Campaign townsfolk (story NPCs): neutral, harmless, with their own 3D bodies and sprite
    # sheets baked from them (main tools/assets/tripo_npcs.py, bake_hero_sprites.py --units).
    for nid, name in NPCS.items():
        units[nid] = {"id": nid, "name": name, "faction": "neutral", "tier": 0, "role": "worker", "hp": 60,
                      "armor_pct": 0.0, "damage": 2.0, "attack_interval": 1.5, "range": 0.0, "speed": 60,
                      "sight": 220.0, "radius": 7.0, "abilities": [], "cost": {},
                      "sprite": "res://assets/units/%s.png" % nid}
        units[nid].update(PEOPLE_COMBAT)
    # Wild creatures guard the map's lairs (MapGen, data/map_templates.json lair_guards).
    wilds = json.load(open(os.path.join(MAIN, "data", "creatures", "wilds.json")))["creatures"]
    for cid, c in wilds.items():
        if "upgrade_of" in c or cid in WILD_SKIP:
            continue
        w = convert(cid, c)
        w["faction"] = "neutral"
        w["cost"] = {}
        units[cid] = w
        if not units_only:
            crop_sprite(manifest, "creature_" + cid, atlases).save(os.path.join(PROJECT, "assets", "units", cid + ".png"))
    militia = json.loads(json.dumps(units["pike_militia"]))
    militia.update({"id": "militia", "name": "Militia", "faction": "neutral", "tier": 0,
                    "abilities": ["reach"], "cost": {}})
    militia.pop("upgrade", None)
    units["militia"] = militia
    out = {
        "_doc": "Generated by tools/sync_from_main.py from the main game's creatures. Tune the formulas there, not here.",
        "factions": FACTIONS + ["neutral"],
        "units": units,
        "building_names": building_names,
    }
    with open(os.path.join(PROJECT, "data", "units.json"), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("wrote %d units" % len(units))
    if units_only:
        return 0
    copy_units3d(os.path.basename(u["sprite"])[:-4] for u in units.values())
    write_combat_fx()
    return 0


if __name__ == "__main__":
    sys.exit(main())
