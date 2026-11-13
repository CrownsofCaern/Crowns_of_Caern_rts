#!/usr/bin/env python3
"""Mixamo clips + live-unit export for the Tripo hero and worker bodies (Warbound).

  UNITS3D_TOOLS=/path/to/checkout python3 tools/assets/heroes3d_export.py heroes|workers|npcs ID [ID ...]

Runs mixamo_set.py and export_live_units.gd from a checkout that has them (the 3D units branch,
PR #191) and writes UNITS3D_TOOLS/build3d/<kind>/<id>.glb + units3d.json, which go into
spinoff/warbound/assets/heroes3d/ (heroes, by Warbound class id: de_/fm_ ref prefixes dropped) or
spinoff/warbound/assets/units3d/ (workers). Clip class per hero follows its Warbound weapons;
workers use the worker set (club swing as the gather animation, a plain run to walk); campaign NPCs
(npcs, also into spinoff/warbound/assets/units3d/) use the unarmed npc set. Spec written there: assets/source/<kind>3d/<kind>_models.json
(a copy is kept here as hero_models.json / worker_models.json)."""
import json, os, shutil, subprocess, sys
from pathlib import Path
MAIN = Path(__file__).resolve().parents[2]; WT = Path(os.environ.get("UNITS3D_TOOLS", MAIN))
CLASS = {"knight":"sword_shield","ranger":"bow","oracle":"caster","templar":"heavy","warlord":"club","warlock":"caster_2h",
 "tormentor":"club","brandguard":"sword_shield","necromancer":"caster_2h","gravewarden":"sword_shield","blightcaller":"caster_2h",
 "barrow_lord":"heavy","grovewarden":"sword_shield","huntmaster":"bow","thornspeaker":"caster","beastcaller":"caster",
 "anvilbreaker":"heavy","ironmarshal":"sword_shield","runesmith":"caster_2h","artificer":"club","brine_champion":"heavy",
 "fm_tidemarshal":"sword_shield","fm_reef_hunter":"thrower","fm_deep_oracle":"caster","de_dreadmarshal":"heavy",
 "de_nightstalker":"bow","de_veilseer":"caster_2h","broodbinder":"caster","thane":"club","reaver":"thrower",
 "frostcaller":"caster_2h","hearthkeeper":"club"}
HEIGHT = {"brine_champion":1.95,"anvilbreaker":1.6,"ironmarshal":1.6,"runesmith":1.6,"artificer":1.6,"barrow_lord":1.95,"templar":1.9}
kind, ids = sys.argv[1], sys.argv[2:]
src_spec = json.loads((MAIN/f"assets/source/{kind}3d/{kind}.json").read_text())[kind]
spec_path = WT/f"assets/source/{kind}3d/{kind}_models.json"
spec_path.parent.mkdir(parents=True, exist_ok=True)
spec = json.loads(spec_path.read_text()) if spec_path.exists() else {"units": []}
out = f"res://build3d/{kind}/"
(WT/f"build3d/{kind}").mkdir(parents=True, exist_ok=True)
for i in ids:
    e = src_spec[i]
    wid = i.removeprefix("de_").removeprefix("fm_")
    dst = WT/f"assets/source/{kind}3d/{i}/{i}_rigged.glb"; dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists() or dst.stat().st_size != (MAIN/e["rigged"]).stat().st_size:
        shutil.copy(MAIN/e["rigged"], dst)
    spec = json.loads(spec_path.read_text()) if spec_path.exists() else {"units": []}
    old = next((u for u in spec["units"] if u["id"] == wid), {})
    spec["units"] = [u for u in spec["units"] if u["id"] != wid]
    spec["units"].append({"id": wid, "model": str(dst.relative_to(WT)), "height": e.get("height", HEIGHT.get(i, 1.85))})
    if old.get("clips") and all((WT/c["model"]).exists() for c in old["clips"].values()):
        spec["units"][-1]["clips"] = old["clips"]; spec["units"][-1].update({k: v for k, v in old.items() if k not in ("clips",)})
        spec_path.write_text(json.dumps(spec, indent=1)+"\n"); continue
    spec_path.write_text(json.dumps(spec, indent=1)+"\n")
    cls = {"workers": "worker", "npcs": "npc"}.get(kind) or CLASS[i]
    subprocess.run(["python3","tools/assets/mixamo_set.py",wid,cls,"--fbx-dir",os.environ["MIXAMO_DIR"],"--spec",str(spec_path.relative_to(WT))],cwd=WT,check=True)
subprocess.run(["godot","--headless","--path",".","--script","res://tools/assets/export_live_units.gd","--","--spec",str(spec_path.relative_to(WT)),"--out",out,"--tris","8000","--tex","1024"]+[i.removeprefix("de_").removeprefix("fm_") for i in ids],cwd=WT,check=True)
