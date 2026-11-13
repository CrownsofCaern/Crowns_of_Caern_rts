#!/usr/bin/env python3
"""Bake the hero classes' 3D bodies into battle sprites for the sprite unit view.

  python3 tools/bake_hero_sprites.py [class,...] [--frames DIR] [--keep]
  python3 tools/bake_hero_sprites.py --units worker_concord,worker_hollow,...

--units bakes live units from assets/units3d (the workers' own bodies) as assets/unit_anims/<id>.png
under their own id, instead of hero classes as hero_<class>, and cuts each one's still sprite
(icons, training queue, 2D view) from its first idle frame: assets/units/<id>.png, 128x128 like
the units synced from the main game, trimmed, feet on the bottom edge, centred.
--stills ID,... only cuts the still sprites again from the sheets already baked.

Renders every hero class (assets/heroes3d/<class>.glb with its weapons) through
tools/render_hero_sprites.gd under Godot (GODOT, default `godot`; xvfb-run when there is
no display), then turns the frames into pixel art the way the main game bakes its 3D
models (tools/assets/bake_models.py there): one scale for the whole hero, the rest pose's
feet on the battle anchor, box downscale, hard alpha, the master palette and the 1 px
outline. The result is assets/unit_anims/hero_<class>.png with its entry in
data/unit_anims.json, in the same format as tools/sync_unit_anims.py writes for units.
--frames reuses frames already rendered there (no Godot run).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MAIN = os.environ.get("CAERN_MAIN") or sys.exit(
    "Set CAERN_MAIN to a checkout of the main game (github.com/CrownsofCaern/Crowns_of_Caern_4X).")
sys.path.insert(0, os.path.join(MAIN, "tools", "assets"))
from crowns_of_cinder_assets.palette import Palette  # noqa: E402
from crowns_of_cinder_assets.postprocess import outline  # noqa: E402

sys.path.insert(0, HERE)
from sync_unit_anims import ACTIONS, OUT_DIR, OUT_JSON, PAD  # noqa: E402

SIZE = (320, 256)
ANCHOR = (160, 207)
RENDER_SCALE = 0.25  # frames are rendered at 4x
ALPHA_CUT = 110
TIMING = {"idle": (160, True), "move": (110, True), "attack": (90, False), "death": (110, False)}
IMPACT_FRAME = 4  # the attack frame the blow lands on (frames are spread evenly over the clip)
STILL = 128  # still sprites (assets/units/<id>.png) are this square
UNITS_DIR = os.path.join(PROJECT, "assets", "units")


def render(frames_dir: str, classes: list, units: bool = False) -> None:
    godot = os.environ.get("GODOT", "godot")
    cmd = [godot, "--path", PROJECT, "--rendering-driver", "opengl3",
           "--script", "res://tools/render_hero_sprites.gd", "--", frames_dir]
    if classes:
        cmd.append(",".join(classes))
    if units:
        cmd.append("--units")
    if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a"] + cmd
    subprocess.run(cmd, check=True)


def visible_box(img: Image.Image):
    return img.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0).getbbox()


def pixelate(raw: Image.Image, dx: int, dy: int, palette: Palette) -> Image.Image:
    w, h = round(raw.width * RENDER_SCALE), round(raw.height * RENDER_SCALE)
    small = raw.convert("RGBA").resize((w, h), Image.Resampling.BOX)
    cell = Image.new("RGBA", SIZE)
    cell.paste(small, (dx, dy))
    alpha = cell.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
    solid = Image.new("RGBA", SIZE)
    solid.paste(cell.convert("RGB"), (0, 0), alpha)
    return outline(palette.quantize(solid), palette.outline)


def bake(cls: str, src: str, palette: Palette, key: str = "") -> dict:
    info = json.load(open(os.path.join(src, "info.json")))
    clips = {}
    for action in ACTIONS:
        n = info["clips"].get(action, {}).get("frames", 0)
        if n:
            clips[action] = [Image.open(os.path.join(src, "%s_%d.png" % (action, i))).convert("RGBA") for i in range(n)]
    rest = clips.get("idle", clips.get("move"))[0]
    box = visible_box(rest)
    # The rest pose's feet on the anchor, its middle on the anchor column.
    dx = round(ANCHOR[0] - (box[0] + box[2]) / 2 * RENDER_SCALE)
    dy = round(ANCHOR[1] - box[3] * RENDER_SCALE)
    cells = {a: [pixelate(f, dx, dy, palette) for f in fs] for a, fs in clips.items()}
    union = None
    for fs in cells.values():
        for f in fs:
            b = f.getbbox()
            if b:
                union = b if union is None else (min(union[0], b[0]), min(union[1], b[1]), max(union[2], b[2]), max(union[3], b[3]))
    union = (max(0, union[0] - PAD), max(0, union[1] - PAD), min(SIZE[0], union[2] + PAD), min(SIZE[1], union[3] + PAD))
    w, h = union[2] - union[0], union[3] - union[1]
    order = [a for a in ACTIONS if a in cells]
    sheet = Image.new("RGBA", (w * max(len(cells[a]) for a in order), h * len(order)))
    actions = {}
    for row, action in enumerate(order):
        for col, f in enumerate(cells[action]):
            sheet.paste(f.crop(union), (col * w, row * h))
        ms, loop = TIMING[action]
        entry = {"row": row, "frames": len(cells[action]), "ms": [ms] * len(cells[action]), "loop": loop}
        if action == "attack":
            entry["impact_ms"] = ms * IMPACT_FRAME
        actions[action] = entry
    sheet.save(os.path.join(OUT_DIR, "%s.png" % (key or "hero_" + cls)), optimize=True)
    return {"size": [w, h], "anchor": [ANCHOR[0] - union[0], ANCHOR[1] - union[1]], "actions": actions}


def still(key: str, entry: dict) -> None:
    """assets/units/<key>.png from the first idle frame of the baked sheet: trimmed, scaled
    (nearest, to keep the pixel art hard) to fit the square, feet on the bottom, centred."""
    sheet = Image.open(os.path.join(OUT_DIR, key + ".png")).convert("RGBA")
    w, h = entry["size"]
    action = entry["actions"].get("idle", entry["actions"].get("move"))
    cell = sheet.crop((0, action["row"] * h, w, action["row"] * h + h))
    fig = cell.crop(cell.getbbox())
    k = min(STILL / fig.width, STILL / fig.height)
    fig = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (STILL, STILL))
    out.paste(fig, ((STILL - fig.width) // 2, STILL - fig.height))
    out.save(os.path.join(UNITS_DIR, key + ".png"), optimize=True)


def main(argv: list) -> None:
    if "--stills" in argv:
        data = json.load(open(OUT_JSON))
        ids = [c for c in argv[argv.index("--stills") + 1].split(",") if c]
        for key in ids:
            still(key, data["units"][key])
        print("still sprites: %s" % ", ".join(ids))
        return
    frames = None
    keep = "--keep" in argv
    units = "--units" in argv
    classes = []
    i = 0
    while i < len(argv):
        if argv[i] == "--frames":
            frames = argv[i + 1]
            i += 1
        elif argv[i] not in ("--keep", "--units"):
            classes += [c for c in argv[i].split(",") if c]
        i += 1
    tmp = None
    if frames is None:
        tmp = tempfile.mkdtemp(prefix="hero_frames_")
        frames = tmp
        render(frames, classes, units)
    palette = Palette.load(os.path.join(MAIN, "assets", "specs", "palette.json"))
    data = json.load(open(OUT_JSON))
    done = []
    for cls in sorted(os.listdir(frames)):
        src = os.path.join(frames, cls)
        if classes and cls not in classes or not os.path.isfile(os.path.join(src, "info.json")):
            continue
        key = cls if units else "hero_" + cls
        data["units"][key] = bake(cls, src, palette, key)
        if units:
            still(key, data["units"][key])
        done.append(cls)
    with open(OUT_JSON, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
    if tmp and not keep:
        shutil.rmtree(tmp)
    print("hero sprites: %d baked (%s)" % (len(done), ", ".join(done)))


if __name__ == "__main__":
    main(sys.argv[1:])
