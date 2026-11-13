#!/usr/bin/env python3
"""Copy the inventory icons of Warbound's hero gear from the main game.

Run from anywhere:  python3 tools/sync_item_icons.py

Every base item and unique in data/items.json gets assets/items/<id>.png (64x64): the
equipment artwork library (main game assets/equipment/expansion_002/64/, built by
tools/assets/build_equipment_expansion.py) or else the main game's artifact icon
(assets/artifacts/<id>.png). The main game's .import file comes along with its path
rewritten, so the icon keeps a stable uid. Icons of items no longer in the data are removed.
"""
import hashlib
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")
SOURCES = [os.path.join(MAIN, "assets/equipment/expansion_002/64"), os.path.join(MAIN, "assets/artifacts")]
DEST = os.path.join(PROJECT, "assets/items")


def import_text(main_import: str, res_path: str) -> str:
    """The main game's .import file pointed at the copy's res:// path."""
    name = os.path.basename(res_path)
    ctex = "res://.godot/imported/%s-%s.ctex" % (name, hashlib.md5(res_path.encode()).hexdigest())
    out = []
    for line in open(main_import).read().splitlines():
        if line.startswith("path="):
            line = 'path="%s"' % ctex
        elif line.startswith("source_file="):
            line = 'source_file="%s"' % res_path
        elif line.startswith("dest_files="):
            line = 'dest_files=["%s"]' % ctex
        out.append(line)
    return "\n".join(out) + "\n"


def main() -> int:
    data = json.load(open(os.path.join(PROJECT, "data/items.json")))
    ids = sorted(set(data["bases"]) | set(data["uniques"]))
    os.makedirs(DEST, exist_ok=True)
    missing = []
    for item_id in ids:
        src = next((os.path.join(s, item_id + ".png") for s in SOURCES
                    if os.path.isfile(os.path.join(s, item_id + ".png"))), None)
        if src is None:
            missing.append(item_id)
            continue
        dst = os.path.join(DEST, item_id + ".png")
        shutil.copyfile(src, dst)
        if os.path.isfile(src + ".import"):
            with open(dst + ".import", "w") as f:
                f.write(import_text(src + ".import", "res://assets/items/%s.png" % item_id))
    keep = {i + ".png" for i in ids} | {i + ".png.import" for i in ids}
    for f in sorted(os.listdir(DEST)):
        if f not in keep:
            os.remove(os.path.join(DEST, f))
    print("%d item icons in assets/items" % (len(ids) - len(missing)))
    if missing:
        print("no icon for: " + ", ".join(missing), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
