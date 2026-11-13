#!/usr/bin/env python3
"""Turns raw Tripo GLBs of map landmarks into Warbound props (assets/props3d/<id>.glb).

The landmarks are image-to-3D models made with Tripo from the main game's own encounter
and place paintings (assets/source/generated, assets/source/map-expansion-001), so they
match its art. This script keeps the mesh, centres it, puts its lowest point at y = 0,
scales it to a footprint width in metres, keeps only the colour texture (1024 px JPEG,
matte, no metal) and drops the normal / metal / roughness maps to keep the files small.

  python3 tools/props/convert_landmarks.py <dir with raw lm_*.glb> [id ...]
"""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "assets" / "props3d"
## id -> footprint width (the larger of x and z) in metres; 1 m is one sim cell.
WIDTH = {
    "lm_cindermaw_gate": 10.0,
    "lm_hall_of_echoes": 11.0,
    "lm_thornwolf_den": 7.5,
    "lm_pyrehold": 11.0,
    "lm_drowned_chapel": 7.5,
    "lm_shattered_citadel": 13.0,
    "lm_ashen_saint_shrine": 6.5,
    "lm_barrow_camp": 9.0,
    "lm_lockstone": 5.0,
    "lm_saint_orrins_rest": 8.0,
    "lm_trader_stall": 6.5,
    "lm_obelisk": 4.0,
}
TEX = 1024


def read_glb(data: bytes) -> tuple[dict, bytes]:
    magic, _, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    off = 12
    doc, binary = None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(chunk)
        elif ctype == 0x004E4942:
            binary = chunk
        off += 8 + clen
    return doc, binary


def write_glb(doc: dict, binary: bytes) -> bytes:
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def convert(src: Path, uid: str) -> Path:
    doc, binary = read_glb(src.read_bytes())
    views = doc["bufferViews"]

    def view_bytes(i: int) -> bytes:
        v = views[i]
        return binary[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]

    # Bounds of every mesh position accessor (Tripo writes one mesh at the origin).
    lo, hi = [1e9] * 3, [-1e9] * 3
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    size = [h - l for h, l in zip(hi, lo)]
    scale = WIDTH[uid] / max(size[0], size[2])
    centre = [(hi[0] + lo[0]) * 0.5, lo[1], (hi[2] + lo[2]) * 0.5]
    # Only the colour texture stays: re-encode it smaller, drop the rest.
    keep_tex = set()
    for mat in doc.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr:
            keep_tex.add(pbr["baseColorTexture"]["index"])
        pbr.pop("metallicRoughnessTexture", None)
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.92
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            mat.pop(k, None)
    # Rebuild the binary: every buffer view as it was, except images (re-encoded or dropped).
    new_bin = bytearray()
    new_views = []
    remap = {}
    image_of_view = {img["bufferView"]: n for n, img in enumerate(doc.get("images", [])) if "bufferView" in img}
    keep_img = {doc["textures"][t]["source"] for t in keep_tex}
    for i, v in enumerate(views):
        if i in image_of_view:
            n = image_of_view[i]
            if n not in keep_img:
                continue
            im = Image.open(io.BytesIO(view_bytes(i))).convert("RGB")
            im = im.resize((TEX, TEX), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=88)
            chunk = buf.getvalue()
            doc["images"][n]["mimeType"] = "image/jpeg"
        else:
            chunk = view_bytes(i)
        new_bin += b"\0" * (-len(new_bin) % 4)
        nv = {k: val for k, val in v.items() if k not in ("byteOffset", "byteLength")}
        nv.update({"buffer": 0, "byteOffset": len(new_bin), "byteLength": len(chunk)})
        remap[i] = len(new_views)
        new_views.append(nv)
        new_bin += chunk
    doc["bufferViews"] = new_views
    for acc in doc["accessors"]:
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    # Drop unused images and textures, renumbering the survivors.
    img_map, images = {}, []
    for n, img in enumerate(doc.get("images", [])):
        if n in keep_img:
            img["bufferView"] = remap[img["bufferView"]]
            img_map[n] = len(images)
            images.append(img)
    tex_map, textures = {}, []
    for n, tex in enumerate(doc.get("textures", [])):
        if n in keep_tex:
            tex["source"] = img_map[tex["source"]]
            tex_map[n] = len(textures)
            textures.append(tex)
    doc["images"], doc["textures"] = images, textures
    for mat in doc.get("materials", []):
        bct = mat["pbrMetallicRoughness"].get("baseColorTexture")
        if bct:
            bct["index"] = tex_map[bct["index"]]
    doc["buffers"] = [{"byteLength": len(new_bin)}]
    # One root node that centres and scales the mesh nodes.
    roots = doc["scenes"][doc.get("scene", 0)]["nodes"]
    doc["nodes"].append({"name": uid, "children": list(roots), "scale": [scale] * 3,
                         "translation": [-centre[0] * scale, -centre[1] * scale, -centre[2] * scale]})
    doc["scenes"][doc.get("scene", 0)]["nodes"] = [len(doc["nodes"]) - 1]
    out = OUT / f"{uid}.glb"
    out.write_bytes(write_glb(doc, bytes(new_bin)))
    print(f"{uid}: {src.stat().st_size // 1024} KB -> {out.stat().st_size // 1024} KB, "
          f"{size[0] * scale:.1f} x {size[1] * scale:.1f} x {size[2] * scale:.1f} m")
    return out


def main(argv: list[str]) -> None:
    src = Path(argv[0])
    ids = argv[1:] or [p.stem for p in sorted(src.glob("lm_*.glb"))]
    for uid in ids:
        convert(src / f"{uid}.glb", uid)


if __name__ == "__main__":
    main(sys.argv[1:])
