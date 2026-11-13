#!/usr/bin/env python3
"""3D hero models for Warbound from the hero reference images (hero-ref/<id>.png), through Tripo:
image_to_model, then the Mixamo-compatible biped rig (animations come from the Mixamo retarget pipeline).

  python3 tools/assets/tripo_heroes.py model ID [ID ...]   # paid: model + rig per hero
  python3 tools/assets/tripo_heroes.py redo ID [ID ...]    # paid again: new model + rig
  python3 tools/assets/tripo_heroes.py list

Spec: assets/source/heroes3d/heroes.json (task ids saved before waiting, so reruns never pay twice).
GLBs (git-ignored, large): assets/source/heroes3d/<id>/<id>_model.glb and <id>_rigged.glb.
Kept separate from assets/specs/creature_models.json, which the unit pipeline writes.
"""
from __future__ import annotations

import io
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tripo  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "assets/source/heroes3d/heroes.json"
OUT = ROOT / "assets/source/heroes3d"
REF_DIR = Path(os.environ.get("HERO_REF_DIR", ROOT / "hero-ref"))
IN_FLIGHT = 4
KEY = "heroes"  # top-level key of the spec; tripo_workers.py reuses this module with its own spec
TRIPO_FIELDS = ("model_task", "rig_task", "model", "rigged", "rejected")


def load() -> dict:
    return json.loads(SPEC.read_text())


def save(spec: dict, ids: list[str] | None = None) -> None:
    """Writes back only the Tripo fields of the entries this run touches, so two runs can share the spec."""
    current = load() if SPEC.is_file() else spec
    for key, entry in spec[KEY].items():
        if ids is not None and key not in ids:
            continue
        target = current[KEY].setdefault(key, dict(entry))
        for field in TRIPO_FIELDS:
            if field in entry:
                target[field] = entry[field]
            else:
                target.pop(field, None)
    SPEC.write_text(json.dumps(current, indent=1) + "\n")


def source_png(hid: str) -> bytes:
    img = Image.open(REF_DIR / f"{hid}.png").convert("RGB")
    buffer = io.BytesIO()
    img.save(buffer, "PNG")
    return buffer.getvalue()


def submit_model(spec: dict, hid: str, client: tripo.Client) -> None:
    entry = spec[KEY][hid]
    if entry.get("model_task"):
        return
    if entry.get("prompt"):
        request = {"type": "text_to_model", "prompt": entry["prompt"]}
        if entry.get("negative_prompt"):
            request["negative_prompt"] = entry["negative_prompt"]
    else:
        token = client.upload(source_png(hid))
        request = {"type": "image_to_model", "file": {"type": "png", "file_token": token}}
    request.update({"texture": True, "pbr": True, "texture_quality": "detailed"})
    entry["model_task"] = client.create(request)
    save(spec, [hid])
    print(f"{hid}: model task {entry['model_task']}", flush=True)


def fetch(spec: dict, hid: str, client: tripo.Client, field: str, task_field: str, name: str) -> None:
    entry = spec[KEY][hid]
    if entry.get(field) and (ROOT / entry[field]).is_file():
        return
    for attempt in range(4):
        try:
            task = client.wait(entry[task_field])
            path = tripo.download(tripo.model_url(task), OUT / hid / f"{hid}_{name}.glb")
            break
        except tripo.TripoError as error:
            if attempt == 3 or "download" not in str(error):
                raise
            print(f"{hid}: {error}; retrying", flush=True)
    entry[field] = str(path.relative_to(ROOT))
    save(spec, [hid])
    print(f"{hid}: {entry[field]} ({path.stat().st_size // 1024} KB)", flush=True)


def rig(spec: dict, hid: str, client: tripo.Client) -> None:
    entry = spec[KEY][hid]
    if not entry.get("rig_task"):
        entry["rig_task"] = client.create({"type": "animate_rig", "original_model_task_id": entry["model_task"],
                                           "out_format": "glb", "rig_type": "biped", "spec": "mixamo"})
        save(spec, [hid])
    fetch(spec, hid, client, "rigged", "rig_task", "rigged")


def run(spec: dict, ids: list[str], client: tripo.Client) -> None:
    done = 0
    for n, hid in enumerate(ids):
        while n - done >= IN_FLIGHT:
            finish(spec, ids[done], client)
            done += 1
        submit_model(spec, hid, client)
    for hid in ids[done:]:
        finish(spec, hid, client)


def finish(spec: dict, hid: str, client: tripo.Client) -> None:
    fetch(spec, hid, client, "model", "model_task", "model")
    rig(spec, hid, client)


def main(argv: list[str]) -> None:
    if not argv:
        print(__doc__)
        return
    client = tripo.Client(os.environ.get("TRIPO_API_KEY", ""))
    spec = load()
    if argv[0] == "list":
        for hid, e in spec[KEY].items():
            print(f"{hid:18} {e.get('faction', ''):11} {e.get('rigged', '-')}")
    elif argv[0] == "redo":
        for hid in argv[1:]:
            e = spec[KEY][hid]
            e.setdefault("rejected", []).append([e.pop("model_task", None), e.pop("rig_task", None)])
            e.pop("model", None)
            e.pop("rigged", None)
        save(spec, argv[1:])
        run(load(), argv[1:], client)
    elif argv[0] == "model":
        run(spec, argv[1:], client)
    else:
        raise SystemExit(f"unknown command {argv[0]}")


if __name__ == "__main__":
    main(sys.argv[1:])
