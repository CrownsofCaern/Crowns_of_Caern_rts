#!/usr/bin/env python3
"""Imports the painted UI art sheets into Warbound.

    python3 spinoff/warbound/tools/import_ui_art.py <folder with the delivered PNGs>

Every piece is optional: the game draws a stand-in for anything missing (src/ui/hud_art.gd).
Sheets are cut into equal cells; each cell's background (transparent, or the flat colour of its
corners) is removed and the icon is centred on a square. A cell left empty is skipped, so its stand-in stays. The order of the sheets below is the
order of the prompts in the art list, so keep the two in step.

* skills_1..10.png (3 x 3) and skills_11.png (2 x 1) -> assets/ui/skills/<skill id>.png (128 px)
* passives_1..2.png (3 x 3) -> assets/ui/passives/<stat>.png (128 px)
* potions.png (2 x 1) -> assets/ui/hud/potion_health.png, potion_mana.png
* tree_nodes.png (2 x 2) -> assets/ui/hud/node_active, node_passive, node_ultimate, node_signature
* bar_fills.png (3 strips) -> assets/ui/hud/fill_health, fill_mana, fill_xp
* bar_frame, skill_slot, tree_connector, portrait_frame -> assets/ui/hud/<name>.png (background removed,
  scaled); the openings of the frames go into assets/ui/hud/frames.json
* tree_backdrop, paper_doll -> assets/ui/hud/<name>.jpg (kept opaque)
* portrait_<class>.png -> assets/ui/heroes/<class>.png (256 px)
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
UI = os.path.join(PROJECT, "assets", "ui")

SKILL_SHEETS = [
 [
  "cleave",
  "leap",
  "red_harvest",
  "shield_bash",
  "defend_aura",
  "last_stand",
  "power_shot",
  "volley",
  "arrow_storm"
 ],
 [
  "binding",
  "arcane_bolt",
  "cataclysm",
  "mend",
  "blessing_aura",
  "revival",
  "summon_minions",
  "drain",
  "legion"
 ],
 [
  "rallying_oath",
  "pinning_shafts",
  "lantern_of_mending",
  "judgement",
  "warcry",
  "cinderfall",
  "brand_of_agony",
  "slag_shield",
  "knit_the_fallen"
 ],
 [
  "bone_bulwark",
  "rot_cloud",
  "grave_cleave",
  "bramble_wall",
  "called_shot",
  "sap_of_renewal",
  "feral_howl",
  "anvil_blow",
  "bombard"
 ],
 [
  "spark_lattice",
  "riveted_aegis",
  "undertow",
  "tidal_rally",
  "called_harpoon",
  "pearl_of_mending",
  "whirlwind_of_steel",
  "unbroken_line",
  "hail_of_shafts"
 ],
 [
  "unmaking",
  "sanctuary",
  "soul_harvest",
  "shield_wall",
  "dawn_charge",
  "ember_burst",
  "firestorm",
  "grasp_of_the_dead",
  "raise_the_barrow"
 ],
 [
  "entangle",
  "wrath_of_the_grove",
  "overcharge",
  "iron_tide",
  "brine_spray",
  "drowning_tide",
  "veiled_strike",
  "venom_shot",
  "veil_of_shadows"
 ],
 [
  "silk_snare",
  "horn_of_the_hold",
  "hail_of_axes",
  "frostbite",
  "feast_fire",
  "shadowstep",
  "night_without_end",
  "glacial_shards",
  "call_of_the_giants"
 ],
 [
  "reaping_blow",
  "sunder",
  "challenge",
  "call_to_arms",
  "hunters_mark",
  "caltrops",
  "chain_lightning",
  "withering_hex",
  "resurrection"
 ],
 [
  "purify",
  "bind_champion",
  "raise_dead",
  "dawnbreak",
  "blood_price",
  "bone_burst",
  "call_the_pack",
  "steam_blast",
  "riptide"
 ],
 [
  "venom_blades",
  "rime_shell"
 ]
]
PASSIVE_SHEETS = [["hp", "defense", "skill_pct", "hp_regen", "damage_pct", "damage", "power", "aura_might", "mana"], ["cooldown_pct", "mana_regen", "attack_speed", "knowledge", "aura_ward", "attack", "move_pct", "aura_haste", "marks"]]
NODES = ["node_active", "node_passive", "node_ultimate", "node_signature"]
FRAMES = ["bar_frame", "skill_slot", "tree_connector", "portrait_frame"]
FRAME_HEIGHT = {"bar_frame": 96, "skill_slot": 256, "tree_connector": 24, "portrait_frame": 512}
OPAQUE = {"tree_backdrop": (1536, 1024), "paper_doll": (768, 1152)}


def _bg(im: Image.Image) -> tuple:
    w, h = im.size
    px = [im.getpixel(p) for p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]]
    return tuple(sum(c[i] for c in px) // 4 for i in range(3))


def cut_out(im: Image.Image, tol: int = 38) -> Image.Image:
    """Removes a flat background (if the image has no transparency yet), soft at the edge."""
    im = im.convert("RGBA")
    if im.getextrema()[3][0] < 250:
        return im
    bg = _bg(im)
    data = []
    for r, g, b, a in im.getdata():
        d = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
        data.append((r, g, b, 0 if d < tol else (a if d > tol * 2 else int(a * (d - tol) / tol))))
    im.putdata(data)
    return im


def blank(im: Image.Image) -> bool:
    """An empty cell (left blank on purpose: the stand-in stays)."""
    box = solid_bbox(im)
    return box is None or (box[2] - box[0]) * (box[3] - box[1]) < im.width * im.height * 0.01


def solid_bbox(im: Image.Image, t: int = 40):
    """The bounding box of what is really drawn (faint shadows and haze don't count)."""
    return im.getchannel("A").point(lambda v: 255 if v > t else 0).getbbox()


def main_block(im: Image.Image, t: int = 40) -> Image.Image:
    """Crops to the largest run of drawn rows and columns, dropping bits of neighbouring cells."""
    a = im.getchannel("A").point(lambda v: 255 if v > t else 0)

    def longest(flags: list) -> tuple:
        best, start = (0, len(flags)), None
        for i, f in enumerate(flags + [False]):
            if f and start is None:
                start = i
            elif not f and start is not None:
                if i - start > best[1] - best[0] or best == (0, len(flags)):
                    best = (start, i)
                start = None
        return best

    w, h = a.size
    rows = [a.crop((0, y, w, y + 1)).getbbox() is not None for y in range(h)]
    y0, y1 = longest(rows)
    cols = [a.crop((x, y0, x + 1, y1)).getbbox() is not None for x in range(w)]
    x0, x1 = longest(cols)
    return im.crop((x0, y0, x1, y1))


def opening(im: Image.Image, dark: bool = False) -> list:
    """The inside of a frame as shares of its size [left, top, right, bottom]: walks out from the
    centre while the pixels are transparent (or, for a bar with a painted channel, dark)."""
    w, h = im.size
    px = im.load()

    def inside(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return (a > 200 and r + g + b < 150) if dark else a < 60

    cx, cy = w // 2, h // 2
    x0 = cx
    while x0 > 0 and inside(x0 - 1, cy):
        x0 -= 1
    x1 = cx
    while x1 < w - 1 and inside(x1 + 1, cy):
        x1 += 1
    y0 = cy
    while y0 > 0 and inside(cx, y0 - 1):
        y0 -= 1
    y1 = cy
    while y1 < h - 1 and inside(cx, y1 + 1):
        y1 += 1
    return [round(x0 / w, 4), round(y0 / h, 4), round((x1 + 1) / w, 4), round((y1 + 1) / h, 4)]


def square(im: Image.Image, px: int, pad: float = 0.04) -> Image.Image:
    box = solid_bbox(im) or (0, 0, im.width, im.height)
    im = im.crop(box)
    side = int(max(im.size) * (1.0 + pad * 2))
    out = Image.new("RGBA", (side, side))
    out.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return out.resize((px, px), Image.LANCZOS)


def cells(im: Image.Image, cols: int, rows: int) -> list:
    w, h = im.size
    return [im.crop((c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows))
            for r in range(rows) for c in range(cols)]


def save(im: Image.Image, *parts: str) -> None:
    p = os.path.join(UI, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if p.endswith(".jpg"):
        im.convert("RGB").save(p, quality=90, optimize=True)
    else:
        im.save(p, optimize=True)
    print("  ", os.path.relpath(p, PROJECT))


def main(src: str) -> None:
    def have(name: str) -> str:
        p = os.path.join(src, name)
        return p if os.path.exists(p) else ""

    for i, ids in enumerate(SKILL_SHEETS):
        if p := have("skills_%d.png" % (i + 1)):
            # A full sheet is a 3 x 3 grid; a shorter one is a single row.
            grid = (3, 3) if len(ids) == 9 else (len(ids), 1)
            for sid, cell in zip(ids, cells(Image.open(p), *grid)):
                icon = cut_out(cell)
                if not blank(icon):
                    save(square(icon, 128), "skills", sid + ".png")
    for i, ids in enumerate(PASSIVE_SHEETS):
        if p := have("passives_%d.png" % (i + 1)):
            for sid, cell in zip(ids, cells(Image.open(p), 3, 3)):
                icon = cut_out(cell)
                if not blank(icon):
                    save(square(icon, 128), "passives", sid + ".png")
    if p := have("potions.png"):
        for kind, cell in zip(["health", "mana"], cells(Image.open(p), 2, 1)):
            save(square(cut_out(cell), 128), "hud", "potion_%s.png" % kind)
    if p := have("tree_nodes.png"):
        for name, cell in zip(NODES, cells(Image.open(p), 2, 2)):
            save(square(main_block(cut_out(cell)), 160, 0.0), "hud", name + ".png")
    if p := have("bar_fills.png"):
        im = Image.open(p).convert("RGB")
        for kind, cell in zip(["health", "mana", "xp"], cells(im, 1, 3)):
            strip = cut_out(cell)
            strip = strip.crop(solid_bbox(strip) or (0, 0, cell.width, cell.height))
            save(strip.resize((512, 32), Image.LANCZOS), "hud", "fill_%s.png" % kind)
    # Frames: cut to what is drawn, scaled to a sane size, and their openings recorded in
    # assets/ui/hud/frames.json (HudArt fits the content into the opening).
    openings = {}
    for name in FRAMES:
        if p := have(name + ".png"):
            im = cut_out(Image.open(p))
            im = main_block(im)
            target_h = FRAME_HEIGHT[name]
            im = im.resize((max(1, round(im.width * target_h / im.height)), target_h), Image.LANCZOS)
            if name != "tree_connector":
                openings[name] = opening(im, dark=name == "bar_frame")
            save(im, "hud", name + ".png")
    for name in NODES:
        p = os.path.join(UI, "hud", name + ".png")
        if os.path.exists(p):
            openings[name] = opening(Image.open(p).convert("RGBA"))
    if openings:
        fp = os.path.join(UI, "hud", "frames.json")
        old = json.load(open(fp)) if os.path.exists(fp) else {}
        old.update(openings)
        with open(fp, "w") as fh:
            json.dump(old, fh, indent=1, sort_keys=True)
            fh.write("\n")
        print("  ", os.path.relpath(fp, PROJECT))
    for name, px in OPAQUE.items():
        if p := have(name + ".png"):
            save(Image.open(p).convert("RGB").resize(px, Image.LANCZOS), "hud", name + ".jpg")
    for f in sorted(os.listdir(src)):
        if f.startswith("portrait_") and f.endswith(".png") and f != "portrait_frame.png":
            im = Image.open(os.path.join(src, f)).convert("RGB")
            side = min(im.size)
            im = im.crop(((im.width - side) // 2, 0, (im.width + side) // 2, side))
            save(im.resize((256, 256), Image.LANCZOS), "heroes", f[len("portrait_"):])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
