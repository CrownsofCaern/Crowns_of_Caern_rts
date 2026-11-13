#!/usr/bin/env python3
"""3D building models for Warbound from the game's 2D building art, through Tripo's image-to-model API.

  python3 tools/assets/tripo_buildings.py balance
  python3 tools/assets/tripo_buildings.py model KEY [KEY ...]   # paid: one image_to_model task per key
  python3 tools/assets/tripo_buildings.py redo KEY [KEY ...]    # paid: new task for a rejected model
  python3 tools/assets/tripo_buildings.py list

The plan lives in assets/source/buildings3d/buildings.json: one entry per building key (the RTS's sprite key,
e.g. c_dw1 or a settlement size) with its source image and, once made, its Tripo task id. A task id is saved
before waiting, so a rerun resumes instead of paying twice. Raw GLBs go to assets/source/buildings3d/<key>/
(git-ignored, large); tools/assets/export_buildings.gd slims them into assets/buildings3d/<key>.glb.

This keeps its own spec on purpose: tripo.py writes assets/specs/creature_models.json (units).
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tripo  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assets/source/buildings3d/buildings.json"
OUT = ROOT / "assets/source/buildings3d"
# Tripo works best on a clean image about 1k px across; the town art is 200-450 px.
TARGET_PX = 1024
IN_FLIGHT = 4


def load() -> dict:
    return json.loads(SPEC.read_text())


TRIPO_FIELDS = ("task", "raw", "credits", "rejected")


def save(spec: dict) -> None:
    # Merge only the Tripo bookkeeping into the file as it is now, so hand edits made while a
    # long batch runs (yaw, tint, layouts) are not overwritten.
    current = load() if SPEC.is_file() else spec
    for key, entry in spec["buildings"].items():
        target = current["buildings"].setdefault(key, dict(entry))
        for field in TRIPO_FIELDS:
            if field in entry:
                target[field] = entry[field]
            else:
                target.pop(field, None)
    SPEC.write_text(json.dumps(current, indent=1) + "\n")


def source_png(entry: dict) -> bytes:
    img = Image.open(ROOT / entry["image"]).convert("RGBA")
    if entry.get("crop"):
        img = img.crop(tuple(entry["crop"]))
    img = img.crop(img.getbbox())
    scale = TARGET_PX / max(img.size)
    if scale > 1.0:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
    pad = Image.new("RGBA", (img.width + 64, img.height + 64), (0, 0, 0, 0))
    pad.paste(img, (32, 32), img)
    buffer = io.BytesIO()
    pad.save(buffer, "PNG")
    return buffer.getvalue()


def submit(spec: dict, key: str, client: tripo.Client) -> None:
    entry = spec["buildings"][key]
    if not entry.get("task"):
        token = client.upload(source_png(entry))
        body = {"type": "image_to_model", "file": {"type": "png", "file_token": token},
                "texture": True, "pbr": True, "texture_quality": "detailed"}
        entry["task"] = client.create(body)
        save(spec)
        print(f"{key}: task {entry['task']}", flush=True)


def fetch(spec: dict, key: str, client: tripo.Client) -> None:
    entry = spec["buildings"][key]
    if entry.get("raw") and (ROOT / entry["raw"]).is_file():
        return
    for attempt in range(4):
        # The download CDN sometimes resets the connection; the task itself is paid and kept.
        try:
            task = client.wait(entry["task"])
            path = tripo.download(tripo.model_url(task), OUT / key / f"{key}_model.glb")
            break
        except tripo.TripoError as error:
            if attempt == 3 or "download" not in str(error):
                raise
            print(f"{key}: {error}; retrying", flush=True)
    entry["raw"] = str(path.relative_to(ROOT))
    if "consumed_credit" in task:
        entry["credits"] = task["consumed_credit"]
    save(spec)
    print(f"{key}: {entry['raw']} ({path.stat().st_size // 1024} KB) credits={task.get('consumed_credit', '?')}")


def main(argv: list[str]) -> None:
    if not argv:
        print(__doc__)
        return
    client = tripo.Client(__import__("os").environ.get("TRIPO_API_KEY", ""))
    if argv[0] == "balance":
        print(client.balance())
    elif argv[0] == "list":
        for key, entry in load()["buildings"].items():
            print(f"{key:16} {entry['image']:52} {entry.get('task', '-')}")
    elif argv[0] == "redo":
        # Paid again: a rejected model keeps its old task id in "rejected" for the record.
        spec = load()
        for key in argv[1:]:
            entry = spec["buildings"][key]
            entry.setdefault("rejected", []).append(entry.pop("task"))
            entry.pop("raw", None)
        save(spec)
        main(["model"] + argv[1:])
    elif argv[0] == "model":
        spec = load()
        # Keep at most IN_FLIGHT tasks queued: Tripo runs them in parallel but refuses (429) past an
        # account-wide limit, which the units' jobs share.
        keys = argv[1:]
        done = 0
        for n, key in enumerate(keys):
            while n - done >= IN_FLIGHT:
                fetch(spec, keys[done], client)
                done += 1
            submit(spec, key, client)
        for key in keys[done:]:
            fetch(spec, key, client)
    else:
        raise SystemExit(f"unknown command {argv[0]}")


if __name__ == "__main__":
    main(sys.argv[1:])
