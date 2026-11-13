#!/usr/bin/env python3
"""Hero UI art from the main game for Warbound's hero window, HUD and skill trees.

Run from anywhere:  python3 tools/sync_hero_ui.py [hero_ref_dir]

* assets/ui/heroes/<class>.png: the main game's painted class portraits at 256 px. Warbound class ids
  drop the main game's de_/fm_ prefixes. Classes the main game has no portrait for get a head-and-
  shoulders crop of the 3D hero reference image (hero_ref_dir/<id>.png, e.g.
  art-source/hero-ref) until a painted portrait arrives (see docs in
  tools/import_ui_art.py); an existing portrait is never replaced by a crop.
* assets/ui/icons/<name>.png: the main game's 48 px UI icons (attack, defense, power, knowledge, xp,
  the empty gear slot symbols, pack, move).

Also called by sync_ui_from_main.py.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")
PORTRAIT_PX = 256
UI_ICONS = ["armor", "attack", "banner", "charm", "defense", "hero", "knowledge", "move", "pack", "power", "xp"]


def main_portrait(cid: str) -> str:
    for prefix in ["", "de_", "fm_"]:
        p = os.path.join(MAIN, "assets", "hero_portraits", "classes", "%s%s.png" % (prefix, cid))
        if os.path.exists(p):
            return p
    return ""


def ref_crop(src: str) -> Image.Image:
    """Head and shoulders from a full-body reference on a flat background."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    bg = im.getpixel((4, 4))
    # The figure's top: the first row with pixels far from the background.
    top = 0
    for y in range(0, h, 4):
        row = [im.getpixel((x, y)) for x in range(0, w, 8)]
        if any(sum(abs(a - b) for a, b in zip(p, bg)) > 60 for p in row):
            top = y
            break
    side = int(h * 0.36)
    cx = w // 2
    box = (cx - side // 2, max(0, top - side // 12), cx + side // 2, max(0, top - side // 12) + side)
    out = im.crop(box).resize((PORTRAIT_PX, PORTRAIT_PX), Image.LANCZOS)
    # Darken towards the edges so the flat grey reads as a dim backdrop, like the painted portraits.
    shade = Image.radial_gradient("L").resize((PORTRAIT_PX, PORTRAIT_PX))
    dark = Image.new("RGB", out.size, (18, 14, 11))
    mask = shade.point(lambda v: min(255, int(v * 1.25)))
    return Image.composite(dark, out, mask)


def sync(hero_ref_dir: str = "") -> list:
    heroes = json.load(open(os.path.join(PROJECT, "data", "heroes.json")))["classes"]
    out_dir = os.path.join(PROJECT, "assets", "ui", "heroes")
    os.makedirs(out_dir, exist_ok=True)
    painted = []
    for cid in sorted(heroes):
        dest = os.path.join(out_dir, "%s.png" % cid)
        src = main_portrait(cid)
        if src:
            Image.open(src).convert("RGBA").resize((PORTRAIT_PX, PORTRAIT_PX), Image.LANCZOS).save(dest, optimize=True)
            painted.append(cid)
        elif hero_ref_dir and not os.path.exists(dest):
            ref = os.path.join(hero_ref_dir, "%s.png" % cid)
            if os.path.exists(ref):
                ref_crop(ref).save(dest, optimize=True)
                print("stand-in portrait from reference:", cid)
    manifest = json.load(open(os.path.join(MAIN, "assets", "manifest.json")))
    icon_dir = os.path.join(PROJECT, "assets", "ui", "icons")
    os.makedirs(icon_dir, exist_ok=True)
    atlases: dict = {}
    for name in UI_ICONS:
        s = manifest["sprites"]["ui_icon_" + name]
        aid = s["atlas"]
        if aid not in atlases:
            rel = manifest["atlases"][aid]["path"].replace("res://", "")
            atlases[aid] = Image.open(os.path.join(MAIN, rel)).convert("RGBA")
        x, y, w, h = s["rect"]
        atlases[aid].crop((x, y, x + w, y + h)).save(os.path.join(icon_dir, "%s.png" % name), optimize=True)
    return painted


if __name__ == "__main__":
    p = sync(sys.argv[1] if len(sys.argv) > 1 else "")
    print("%d painted portraits" % len(p))
