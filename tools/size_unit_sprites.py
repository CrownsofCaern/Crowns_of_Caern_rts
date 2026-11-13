#!/usr/bin/env python3
"""Give every animated unit sprite its real size (data/unit_sizes.json).

Run from anywhere, after sync_unit_anims.py or bake_hero_sprites.py:
    python3 spinoff/warbound/tools/size_unit_sprites.py [--root <main repo>]

The main game's battle art draws every creature at about the same height (a giant fills the
same frame as a pikeman), so one pixel size for all (SpriteUnit.M_PER_PX) makes a 5 m giant
as tall as a man. This tool measures how tall each sheet's figure stands (top of the idle
pose to the feet) and writes the factor that brings it to the unit's height in the main
game's one height table (assets/specs/creature_models.json, metres, a soldier is 1.8).

Big units follow the main game's 3D battles (BattleStage3D.size_factor): life size up to
2.2 m, and only half as fast above, so a giant towers over a soldier without hiding an army.
Long low bodies (serpents, wyrms) are measured by half their length, so they are not blown
up to the height of their rearing 3D pose. Hero classes and workers are baked from their 3D
bodies at their own size (bake_hero_sprites.py) and keep factor 1.
"""
import argparse
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
M_PER_PX = 1.8 / 125.0  # SpriteUnit.M_PER_PX
BIG_FROM = 2.2  # BattleStage3D.BIG_FROM
ALPHA = 40
K_MIN, K_MAX = 0.45, 2.6
KEEP = 0.12  # factors this close to 1 are drawing noise (raised weapons): the art is right
OUT = os.path.join(PROJECT, "data", "unit_sizes.json")


def size_factor(h: float) -> float:
    return 1.0 if h <= BIG_FROM else (BIG_FROM + (h - BIG_FROM) * 0.5) / h


def heights(main: str) -> dict:
    out = {}
    u3 = os.path.join(PROJECT, "assets", "units3d", "units3d.json")
    if os.path.exists(u3):
        for k, v in json.load(open(u3)).items():
            if v.get("height"):
                out[k] = float(v["height"])
    spec = os.path.join(main, "assets", "specs", "creature_models.json")
    if os.path.exists(spec):  # the main game's table wins (the Warbound copy can lag)
        for u in json.load(open(spec))["units"]:
            if u.get("height"):
                out[u["id"]] = float(u["height"])
    return out


def measure(sid: str, d: dict) -> tuple:
    """Figure height and width in metres at factor 1 (idle pose, tallest frame)."""
    im = Image.open(os.path.join(PROJECT, "assets", "unit_anims", sid + ".png")).convert("RGBA")
    w, h = d["size"]
    ay = d["anchor"][1]
    c = d["actions"].get("idle") or d["actions"].get("move")
    top, width = h, 0
    for i in range(int(c["frames"])):
        fr = im.crop((i * w, c["row"] * h, i * w + w, c["row"] * h + h))
        bb = fr.getchannel("A").point(lambda a: 255 if a > ALPHA else 0).getbbox()
        if bb:
            top = min(top, bb[1])
            width = max(width, bb[2] - bb[0])
    return (ay - top) * M_PER_PX, width * M_PER_PX


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.abspath(os.path.join(PROJECT, "..", "..")))
    args = ap.parse_args()
    anims = json.load(open(os.path.join(PROJECT, "data", "unit_anims.json")))["units"]
    table = heights(args.root)
    units, report = {}, {}
    for sid in sorted(anims):
        if sid.startswith(("hero_", "worker_")) or sid not in table:
            continue
        drawn_h, drawn_w = measure(sid, anims[sid])
        target = table[sid]
        shown = target * size_factor(target)
        k = shown / max(drawn_h, drawn_w * 0.5, 0.1)
        k = round(min(K_MAX, max(K_MIN, k)), 2)
        if abs(k - 1.0) < KEEP:
            k = 1.0
        else:
            units[sid] = k
        report[sid] = {"height": target, "drawn_m": round(drawn_h, 2), "shown_m": round(drawn_h * k, 2), "k": k}
    out = {"_doc": "Made by tools/size_unit_sprites.py: sprite id -> size factor on SpriteUnit.M_PER_PX, "
                   "so each unit stands at its height from the main game's creature_models.json "
                   "(big ones compressed like the 3D battles). Missing ids draw at 1. Do not edit.",
           "units": units}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    for sid, r in report.items():
        print(f"{sid:24s} table {r['height']:4.2f} m  drawn {r['drawn_m']:4.2f} m  -> {r['shown_m']:4.2f} m  (x{r['k']})")
    print(f"{len(units)} of {len(report)} sprites rescaled -> {os.path.relpath(OUT, PROJECT)}")


if __name__ == "__main__":
    main()
