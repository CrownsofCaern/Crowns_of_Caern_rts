#!/usr/bin/env python3
"""Copy the main game's menu art, fonts, UI frames and UI sounds into Warbound.

Run from anywhere:  python3 tools/sync_ui_from_main.py

Separate from sync_from_main.py (units, terrain, battle audio), so the menu and
the gameplay content can be refreshed independently.

* assets/ui/menu_<id>.jpg: the title, setup and campaign backdrops (JPEG, same size).
* assets/ui/wordmark.png, emblem.png: the game's wordmark and crest (alpha cropped).
* assets/ui/panel_<faction>.png, panel.png, button*.png, slot.png, divider.png:
  framed UI pieces cut from the main game's ui atlas; their nine-slice margins go
  into data/ui.json.
* assets/ui/res_<resource>.png: resource icons.
* assets/ui/emblems/<faction>.png: the detailed faction crests (main game assets/emblems/*.tres).
* assets/ui/heroes/<class>.png, assets/ui/icons/: hero portraits and UI icons (sync_hero_ui.py).
* assets/fonts/: Cinzel (display) and Lora (body), with their OFL licences.
* assets/audio/sfx/ui_*.ogg and music/menu.ogg: menu sounds and the menu theme.
* data/ui.json: faction palettes, names and colours, sprite nine-slices.
"""
import json
import os
import re
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")

BACKDROPS = ["title", "setup", "campaign"]
UI_SPRITES = {
    "panel": "ui_panel",
    "button": "ui_button",
    "button_hover": "ui_button_hover",
    "button_pressed": "ui_button_pressed",
    "button_disabled": "ui_button_disabled",
    "slot": "ui_slot",
    "divider": "ui_divider",
}
RESOURCES = ["gold", "wood", "ore", "mercury", "sulfur", "crystal", "gems"]
UI_SOUNDS = ["ui_click.ogg", "ui_click_2.ogg", "ui_click_3.ogg", "ui_open.ogg", "ui_close.ogg", "ui_error.ogg"]


def main_path(*parts: str) -> str:
    return os.path.join(MAIN, *parts)


def out_path(*parts: str) -> str:
    p = os.path.join(PROJECT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def crop_sprite(manifest: dict, atlases: dict, sprite_id: str, dest: str) -> dict:
    s = manifest["sprites"][sprite_id]
    atlas_id = s["atlas"]
    if atlas_id not in atlases:
        rel = manifest["atlases"][atlas_id]["path"].replace("res://", "")
        atlases[atlas_id] = Image.open(main_path(rel)).convert("RGBA")
    x, y, w, h = s["rect"]
    atlases[atlas_id].crop((x, y, x + w, y + h)).save(dest)
    return {"nine_slice": s.get("nine_slice", [0, 0, 0, 0]), "size": [w, h]}


def crest_emblem(fid: str, dest: str) -> None:
    """The detailed faction crest: the cell of factions_detailed.png that the
    main game's assets/emblems/<faction>.tres points at, resized to 256 px."""
    tres = open(main_path("assets", "emblems", "%s.tres" % fid)).read()
    m = re.search(r"region = Rect2\(([^)]*)\)", tres)
    x, y, w, h = [float(v) for v in m.group(1).split(",")]
    sheet = Image.open(main_path("assets", "emblems", "factions_detailed.png")).convert("RGBA")
    cell = sheet.crop((round(x), round(y), round(x + w), round(y + h)))
    cell.resize((256, 256), Image.LANCZOS).save(dest, optimize=True)


def main() -> None:
    manifest = json.load(open(main_path("assets", "manifest.json")))
    atlases: dict = {}
    sprites: dict = {}

    for b in BACKDROPS:
        im = Image.open(main_path("assets", "menus", "menu_%s.png" % b)).convert("RGB")
        im.save(out_path("assets", "ui", "menu_%s.jpg" % b), quality=88, optimize=True)
    for name, width in [("wordmark", 1200), ("emblem", 512)]:
        im = Image.open(main_path("assets", "menus", "menu_%s.png" % name)).convert("RGBA")
        im = im.crop(im.getbbox())
        if im.width > width:
            im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        im.save(out_path("assets", "ui", "%s.png" % name), optimize=True)

    faction_ui = json.load(open(main_path("assets", "specs", "faction_ui.json")))
    factions_main = json.load(open(main_path("data", "factions.json")))["factions"]
    factions: dict = {}
    for fid in sorted(faction_ui.keys()):
        if fid not in factions_main:
            continue
        f = factions_main[fid]
        pal = faction_ui[fid]
        factions[fid] = {
            "name": f["name"],
            "adjective": f.get("adjective", f["name"]),
            "color": f.get("color", "#c9a24a"),
            "roster": f.get("roster", ""),
            "background": pal["background"],
            "panel": pal["panel"],
            "raised": pal["raised"],
            "accent": pal["accent"],
        }
        panel_id = "ui_panel_" + fid
        if panel_id in manifest["sprites"]:
            sprites["panel_" + fid] = crop_sprite(manifest, atlases, panel_id, out_path("assets", "ui", "panel_%s.png" % fid))
        crest_emblem(fid, out_path("assets", "ui", "emblems", "%s.png" % fid))

    for name, sid in UI_SPRITES.items():
        sprites[name] = crop_sprite(manifest, atlases, sid, out_path("assets", "ui", "%s.png" % name))
    for r in RESOURCES:
        crop_sprite(manifest, atlases, "ui_resource_" + r, out_path("assets", "ui", "res_%s.png" % r))

    for f in ["Cinzel.ttf", "Cinzel-OFL.txt", "Lora.ttf", "Lora-OFL.txt"]:
        shutil.copyfile(main_path("assets", "fonts", f), out_path("assets", "fonts", f))
    for f in UI_SOUNDS:
        shutil.copyfile(main_path("assets", "audio", "sfx", f), out_path("assets", "audio", "sfx", f))
    shutil.copyfile(main_path("assets", "audio", "music", "menu.ogg"), out_path("assets", "audio", "music", "menu.ogg"))

    # Hero class portraits (256 px) and the main game's UI icons: tools/sync_hero_ui.py.
    sys.path.insert(0, HERE)
    import sync_hero_ui
    portraits = sync_hero_ui.sync()

    data = {
        "_doc": "Menu and UI data, generated by tools/sync_ui_from_main.py from the main game. Do not edit by hand.",
        "factions": factions,
        "sprites": sprites,
        "resources": RESOURCES,
        "hero_portraits": portraits,
    }
    with open(out_path("data", "ui.json"), "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print("synced %d factions, %d sprites" % (len(factions), len(sprites)))


if __name__ == "__main__":
    main()
