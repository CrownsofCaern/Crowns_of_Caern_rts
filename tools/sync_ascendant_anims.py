#!/usr/bin/env python3
"""Copy the main game's level-five (Ascendant) clips into Warbound's sprite unit sheets.

Run from anywhere:  python3 spinoff/warbound/tools/sync_ascendant_anims.py

The main game draws an upgraded creature at veteran level 5 with its own art
(assets/build/veteran_animations/<upgraded id>/move.png and attack.png, four 320x256
frames each, made by tools/assets/prepare_veteran_animations.py). For every upgraded unit
in data/units.json that has them, this cuts the frames to their shared box like
sync_unit_anims.py does and writes assets/unit_anims/asc_<id>.png with an "asc_<id>"
entry in data/unit_anims.json (rows: move, attack; no idle or death: a standing
Ascendant holds its first stride and the view dissolves it in light when it falls).
"""
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.path.abspath(os.path.join(PROJECT, "..", ".."))
SRC = os.path.join(MAIN, "assets", "build", "veteran_animations")
OUT_DIR = os.path.join(PROJECT, "assets", "unit_anims")
OUT_JSON = os.path.join(PROJECT, "data", "unit_anims.json")
ACTIONS = ["move", "attack"]
PAD = 2
PREFIX = "asc_"


def main() -> None:
    manifest = json.load(open(os.path.join(SRC, "manifest.json")))
    fw, fh = manifest["frame_size"]
    anchor = manifest["anchor"]
    units = json.load(open(os.path.join(PROJECT, "data", "units.json")))["units"]
    out = json.load(open(OUT_JSON))
    for k in [k for k in out["units"] if k.startswith(PREFIX)]:
        del out["units"][k]
    made, missing = [], []
    for uid in sorted(u for u, d in units.items() if "upgrade_of" in d):
        sid = os.path.splitext(os.path.basename(units[uid]["sprite"]))[0]
        entry = manifest["units"].get(sid)
        if entry is None:
            missing.append(uid)
            continue
        clips = {}
        for action in ACTIONS:
            c = entry["actions"].get(action)
            if not c:
                continue
            strip = Image.open(os.path.join(MAIN, c["path"])).convert("RGBA")
            frames = [strip.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(int(c["frame_count"]))]
            clips[action] = (c, frames)
        box = None
        for _, frames in clips.values():
            for f in frames:
                b = f.getbbox()
                if b is not None:
                    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        if box is None:
            missing.append(uid)
            continue
        box = (max(0, box[0] - PAD), max(0, box[1] - PAD), min(fw, box[2] + PAD), min(fh, box[3] + PAD))
        w, h = box[2] - box[0], box[3] - box[1]
        cols = max(len(f) for _, f in clips.values())
        sheet = Image.new("RGBA", (w * cols, h * len(clips)), (0, 0, 0, 0))
        actions = {}
        for row, action in enumerate(a for a in ACTIONS if a in clips):
            c, frames = clips[action]
            for col, f in enumerate(frames):
                sheet.paste(f.crop(box), (col * w, row * h))
            e = {"row": row, "frames": len(frames), "ms": [int(x) for x in c["durations_ms"]], "loop": bool(c.get("loop", False))}
            for ev in c.get("events", []):
                if ev["name"] == "impact":
                    e["impact_ms"] = int(ev["time_ms"])
            actions[action] = e
        sheet.save(os.path.join(OUT_DIR, PREFIX + sid + ".png"), optimize=True)
        out["units"][PREFIX + sid] = {"size": [w, h], "anchor": [anchor[0] - box[0], anchor[1] - box[1]], "actions": actions}
        made.append(sid)
    with open(OUT_JSON, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print("ascendant sheets: %d, without art: %s" % (len(made), missing))


if __name__ == "__main__":
    main()
