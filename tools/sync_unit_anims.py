#!/usr/bin/env python3
"""Copy the main game's animated battle sprites into the spinoff (sprite unit mode).

Run from anywhere:  python3 tools/sync_unit_anims.py

For every sprite the skirmish units use (data/units.json "sprite", res://assets/units/<id>.png),
the main game's battle clips (assets/animations.json, unit "creature_<id>") are cut out of the
320x256 atlas frames, cropped to the box all frames of that unit share, and packed into
assets/unit_anims/<id>.png: one row per action (idle, move, attack, death), one column per frame.
data/unit_anims.json says where each clip sits, its frame times, whether it loops, when the blow
lands (impact) and where the feet are (anchor, in pixels of the cropped frame).

The figures keep the main game's native scale (a man is about 128 px tall), so the 3D view can
draw every unit with one pixel size and the art keeps its relative sizes. Like the main game,
the art faces right; the view mirrors it.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")
ACTIONS = ["idle", "move", "attack", "death"]
OUT_DIR = os.path.join(PROJECT, "assets", "unit_anims")
OUT_JSON = os.path.join(PROJECT, "data", "unit_anims.json")
PAD = 2  # transparent pixels kept round the shared box (no bleeding between frames)


def res(path: str) -> str:
    return os.path.join(MAIN, path.replace("res://", ""))


def sprite_ids() -> list:
    units = json.load(open(os.path.join(PROJECT, "data", "units.json")))["units"]
    ids = set()
    for u in units.values():
        ids.add(os.path.splitext(os.path.basename(u["sprite"]))[0])
    # Wild lair guards are listed in their own file when the sync made one.
    wild = os.path.join(PROJECT, "data", "wilds.json")
    if os.path.exists(wild):
        for u in json.load(open(wild)).get("units", {}).values():
            ids.add(os.path.splitext(os.path.basename(u["sprite"]))[0])
    return sorted(ids)


def main() -> None:
    manifest = json.load(open(os.path.join(MAIN, "assets", "animations.json")))
    atlases = {}

    def atlas(name):
        if name not in atlases:
            atlases[name] = Image.open(res(manifest["atlases"][name]["path"])).convert("RGBA")
        return atlases[name]

    anchor = manifest["anchor"]
    os.makedirs(OUT_DIR, exist_ok=True)
    out = {"_doc": "Made by tools/sync_unit_anims.py from the main game's assets/animations.json "
                   "(hero_* and worker_* entries by tools/bake_hero_sprites.py). Do not edit.",
           "units": {}}
    # Ascendant sheets come from tools/sync_ascendant_anims.py.
    # Hero class and worker sheets are baked from the 3D bodies by tools/bake_hero_sprites.py: keep them.
    if os.path.exists(OUT_JSON):
        for k, v in json.load(open(OUT_JSON)).get("units", {}).items():
            if k.startswith("hero_") or k.startswith("worker_") or k.startswith("asc_"):
                out["units"][k] = v
    missing = []
    for sid in sprite_ids():
        unit = manifest["units"].get("creature_" + sid)
        if unit is None:
            missing.append(sid)
            continue
        clips = {}
        for action in ACTIONS:
            c = unit["actions"].get(action)
            if not c:
                continue
            frames = []
            for i, r in enumerate(c["frames"]):
                name = c.get("atlas", unit["atlas"])
                per = c.get("frame_atlases", [])
                if i < len(per):
                    name = per[i]
                frames.append(atlas(name).crop((r[0], r[1], r[0] + r[2], r[1] + r[3])))
            clips[action] = (c, frames)
        box = None
        for _, frames in clips.values():
            for f in frames:
                b = f.getbbox()
                if b is None:
                    continue
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        if box is None:
            missing.append(sid)
            continue
        box = (max(0, box[0] - PAD), max(0, box[1] - PAD), box[2] + PAD, box[3] + PAD)
        w, h = box[2] - box[0], box[3] - box[1]
        cols = max(len(f) for _, f in clips.values())
        sheet = Image.new("RGBA", (w * cols, h * len(clips)), (0, 0, 0, 0))
        actions = {}
        for row, action in enumerate(a for a in ACTIONS if a in clips):
            c, frames = clips[action]
            for col, f in enumerate(frames):
                sheet.paste(f.crop(box), (col * w, row * h))
            entry = {"row": row, "frames": len(frames), "ms": [int(x) for x in c["durations_ms"]],
                     "loop": bool(c.get("loop", False))}
            for ev in c.get("events", []):
                if ev["name"] == "impact":
                    entry["impact_ms"] = int(ev["time_ms"])
            actions[action] = entry
        sheet.save(os.path.join(OUT_DIR, sid + ".png"), optimize=True)
        out["units"][sid] = {"size": [w, h], "anchor": [anchor[0] - box[0], anchor[1] - box[1]], "actions": actions}
    with open(OUT_JSON, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print("unit_anims: %d units, missing %s" % (len(out["units"]), missing))


if __name__ == "__main__":
    main()
