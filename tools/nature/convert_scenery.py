#!/usr/bin/env python3
"""Biome scenery for Warbound (assets/nature/<id>.glb), all Quaternius CC0.

Sources (downloaded into a cache folder, nothing else is fetched):
  un  Quaternius "Ultimate Nature Pack" GLBs, mirrored at github.com/trebeljahr/quaternius-showcase
      (public/glb/nature_pack). Flat colours, no textures.
  snm Quaternius "Stylized Nature MegaKit" and
  ru  Quaternius "Ultimate Modular Ruins" (monster lair dressing, written to assets/props3d), as USDA in github.com/chibifire-stages/quaternius-stage
      (models/<pack>/S_<name>.usda, textures beside them). Converted to GLB here (needs usd-core).

Colours are pulled toward the art bible: darker, colder, less saturated; snow turns from lilac to a
cold white, bark loses its red, and a few ids get a tone of their own (charred wood for the ash lands,
violet leaves for the dark elf crags).

  pip install usd-core numpy pillow
  python3 tools/nature/convert_scenery.py <cache dir> [ids...]
"""
import io
import json
import os
import struct
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "nature"))
PROPS = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "props3d"))
UN = "https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/HEAD/public/glb/nature_pack/%s.glb"
STAGE = "https://raw.githubusercontent.com/chibifire-stages/quaternius-stage/HEAD/models/%s/%s"

## id -> [source, source name, tone]
PICK = {
	# Frostmarch snow
	"sn_pine_1": ["un", "PineTree_Snow_1", "snow"], "sn_pine_2": ["un", "PineTree_Snow_2", "snow"],
	"sn_pine_3": ["un", "PineTree_Snow_3", "snow"], "sn_pine_4": ["un", "PineTree_Snow_4", "snow"],
	"sn_pine_5": ["un", "PineTree_Snow_5", "snow"],
	"sn_dead_1": ["un", "CommonTree_Dead_Snow_1", "snow"], "sn_dead_2": ["un", "CommonTree_Dead_Snow_2", "snow"],
	"sn_dead_3": ["un", "CommonTree_Dead_Snow_3", "snow"],
	"sn_bush_1": ["un", "Bush_Snow_1", "snow"], "sn_bush_2": ["un", "Bush_Snow_2", "snow"],
	"sn_rock_1": ["un", "Rock_Snow_1", "snow"], "sn_rock_2": ["un", "Rock_Snow_2", "snow"],
	"sn_rock_3": ["un", "Rock_Snow_3", "snow"], "sn_rock_4": ["un", "Rock_Snow_6", "snow"],
	"sn_stump": ["un", "TreeStump_Snow", "snow"],
	# Fens: willows, drowned trees, lily pads, moss
	"fn_willow_1": ["un", "Willow_1", "fen"], "fn_willow_2": ["un", "Willow_2", "fen"],
	"fn_willow_3": ["un", "Willow_3", "fen"], "fn_willow_4": ["un", "Willow_4", "fen"],
	"fn_willow_dead_1": ["un", "Willow_Dead_1", "fen"], "fn_willow_dead_2": ["un", "Willow_Dead_2", "fen"],
	"fn_willow_dead_3": ["un", "Willow_Dead_4", "fen"], "fn_lilypad": ["un", "Lilypad", "fen"],
	"mo_rock_1": ["un", "Rock_Moss_2", "fen"], "mo_rock_2": ["un", "Rock_Moss_3", "fen"],
	"mo_rock_3": ["un", "Rock_Moss_5", "fen"], "mo_rock_4": ["un", "Rock_Moss_6", "fen"],
	"mo_stump": ["un", "TreeStump_Moss", "fen"], "mo_log": ["un", "WoodLog_Moss", "fen"],
	# Plain wood for the meadow and deep woods, and charred for the ash lands
	"stump": ["un", "TreeStump", "plain"], "log": ["un", "WoodLog", "plain"],
	"ch_stump": ["un", "TreeStump", "charred"], "ch_log": ["un", "WoodLog", "charred"],
	"ch_tree_1": ["un", "CommonTree_Dead_1", "charred"], "ch_tree_2": ["un", "CommonTree_Dead_3", "charred"],
	"ch_tree_3": ["un", "CommonTree_Dead_5", "charred"],
	# Woodland floor (Stylized Nature MegaKit)
	"fern": ["snm", "Fern_1", "wood"], "mushrooms": ["snm", "MushroomCommon", "wood"],
	"shelf_fungus": ["snm", "MushroomLaetiporus", "wood"], "reeds": ["snm", "GrassWispyTall", "fen"],
	"twisted_tree_1": ["snm", "TwistedTree_1", "wood"], "twisted_tree_2": ["snm", "TwistedTree_3", "wood"],
	"twisted_tree_3": ["snm", "TwistedTree_5", "wood"],
	# Dark elf crags: twisted trees with violet leaves, pale fungus
	"gl_tree_1": ["snm", "TwistedTree_2", "gloom"], "gl_tree_2": ["snm", "TwistedTree_4", "gloom"],
	"gl_fungus": ["snm", "MushroomLaetiporus", "gloom"], "gl_mushrooms": ["snm", "MushroomCommon", "gloom"],
	# Monster lair dressing (Ultimate Modular Ruins) -> assets/props3d
	"ru_arch": ["ru", "ArchGothic", "ruin"], "ru_wall_broken": ["ru", "WallBroken", "ruin"],
	"ru_wall_ivy": ["ru", "WallArchRoundOvergrownBroken", "ruin"], "ru_column": ["ru", "ColumnRoundShort", "ruin"],
	"ru_statue_stag": ["ru", "StatueStag", "ruin"], "ru_torch": ["ru", "Torch", "ruin"],
	"ru_bear_trap": ["ru", "BearTrapOpen", "ruin"], "ru_bricks": ["ru", "Bricks", "ruin"],
}
## Colours (linear) for USDA materials whose Blender colour did not survive (they read 0.8 grey).
FLAT = {"ruin": {"Leaf_Texture": [0.04, 0.06, 0.03], "Green": [0.035, 0.055, 0.028], "Bark": [0.07, 0.05, 0.04],
	"Fire": [0.9, 0.35, 0.06]}}
## Textures per USDA pack (diffuse only; normal maps are dropped).
TEXTURES = {"snm": ["T_BarkTwistedTree_D", "T_LeavesTwistedTreeC_D", "T_Leaves_D", "T_Mushrooms_D", "T_Grass_D"]}
PACKS = {"snm": "StylizedNatureMegaKit", "ru": "UltimateModularRuins"}

## Flat colours (linear) by material name, per tone. Missing names keep their colour, darkened a little.
BASE = {
	"Wood": [0.075, 0.052, 0.042], "LightWood": [0.13, 0.085, 0.062], "Green": [0.055, 0.085, 0.042],
	"DarkGreen": [0.035, 0.055, 0.03], "Rock": [0.15, 0.155, 0.165], "Rock.001": [0.15, 0.155, 0.165],
	"Snow": [0.27, 0.29, 0.33], "Snow.001": [0.27, 0.29, 0.33], "Mushroom_Top": [0.09, 0.07, 0.06],
	"Mushroom_Bottom": [0.2, 0.16, 0.13], "Pink": [0.22, 0.09, 0.14],
}
TONES = {
	"fen": {"Green": [0.05, 0.072, 0.036], "DarkGreen": [0.034, 0.05, 0.028], "Wood": [0.06, 0.048, 0.036]},
	"charred": {"Wood": [0.022, 0.019, 0.018], "LightWood": [0.05, 0.03, 0.022], "Green": [0.03, 0.028, 0.026],
		"Mushroom_Top": [0.03, 0.026, 0.024], "Mushroom_Bottom": [0.07, 0.04, 0.03]},
}
## Texture multipliers (sRGB) per tone for the textured MegaKit pieces.
TEX_TINT = {
	"wood": {"Leaves_TwistedTree": (0.62, 0.66, 0.5), "Bark_TwistedTree": (0.6, 0.55, 0.52), "Mushrooms": "pale",
		"Leaves": (0.3, 0.34, 0.22), "Grass": (0.5, 0.5, 0.36)},
	"fen": {"Grass": (0.48, 0.48, 0.34), "Leaves": (0.3, 0.34, 0.22)},
	"gloom": {"Leaves_TwistedTree": "violet", "Bark_TwistedTree": (0.45, 0.42, 0.48), "Mushrooms": "dusk"},
}


def fetch(url: str, path: str) -> str:
	if not os.path.exists(path):
		os.makedirs(os.path.dirname(path), exist_ok=True)
		with urllib.request.urlopen(url) as r, open(path, "wb") as f:
			f.write(r.read())
	return path


def read_glb(path: str):
	b = open(path, "rb").read()
	n = struct.unpack("<I", b[12:16])[0]
	j = json.loads(b[20:20 + n])
	rest = b[20 + n:]
	bn = struct.unpack("<I", rest[0:4])[0]
	return j, bytearray(rest[8:8 + bn])


def write_glb(path: str, j: dict, blob: bytearray) -> None:
	while len(blob) % 4:
		blob.append(0)
	j["buffers"] = [{"byteLength": len(blob)}]
	js = json.dumps(j, separators=(",", ":")).encode()
	while len(js) % 4:
		js += b" "
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A))
		f.write(js)
		f.write(struct.pack("<II", len(blob), 0x004E4942))
		f.write(blob)


def recolour_flat(j: dict, tone: str) -> None:
	table = dict(BASE)
	table.update(TONES.get(tone, {}))
	for m in j.get("materials", []):
		pbr = m.setdefault("pbrMetallicRoughness", {})
		old = pbr.get("baseColorFactor", [1, 1, 1, 1])
		col = table.get(m.get("name", ""), [c * 0.75 for c in old[:3]])
		pbr["baseColorFactor"] = list(col) + [1.0]
		pbr["metallicFactor"] = 0.0
		pbr["roughnessFactor"] = 1.0


def tint_texture(png: bytes, tint) -> bytes:
	from PIL import Image
	im = Image.open(io.BytesIO(png)).convert("RGBA")
	if im.width > 512:
		im = im.resize((512, 512 * im.height // im.width), Image.LANCZOS)
	a = np.asarray(im).astype(np.float32) / 255.0
	if tint == "violet":
		# Red leaves -> dusky violet: keep the light, swap the hue.
		lum = a[..., :3] @ np.array([0.3, 0.55, 0.15], dtype=np.float32)
		a[..., 0] = lum * 0.55 + a[..., 0] * 0.12
		a[..., 1] = lum * 0.42
		a[..., 2] = lum * 0.78 + a[..., 0] * 0.1
	elif tint == "dusk":
		# Fungus of the crags: a dim, greyish violet that glints without glowing.
		lum = a[..., :3] @ np.array([0.3, 0.55, 0.15], dtype=np.float32)
		a[..., :3] = lum[..., None] * np.array([0.4, 0.34, 0.5], dtype=np.float32)
	elif tint == "pale":
		# Bright orange fungus -> pale, dull ochre.
		lum = a[..., :3] @ np.array([0.3, 0.55, 0.15], dtype=np.float32)
		a[..., :3] = (lum[..., None] * np.array([0.62, 0.55, 0.45], dtype=np.float32) + a[..., :3] * 0.12)
	else:
		a[..., :3] *= np.array(tint, dtype=np.float32)
	out = io.BytesIO()
	Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(out, "PNG", optimize=True)
	return out.getvalue()


def usd_to_glb(src: str, tex_dir: str, tone: str, name: str):
	"""Triangulated GLB (json, blob) from a Quaternius USDA: one primitive per material subset."""
	from pxr import Usd, UsdGeom, UsdShade
	stage = Usd.Stage.Open(src)
	mpu = UsdGeom.GetStageMetersPerUnit(stage) or 1.0
	cache = UsdGeom.XformCache()
	prims, mats = [], {}

	def mat_info(m):
		if not m:
			return "none", None, [0.5, 0.5, 0.5]
		key = m.GetPath().name
		tex, col = None, [0.6, 0.6, 0.6]
		for sh in Usd.PrimRange(m.GetPrim()):
			s = UsdShade.Shader(sh)
			if not s:
				continue
			sid = s.GetIdAttr().Get()
			if sid == "UsdUVTexture" and tex is None:
				f = s.GetInput("file").Get()
				if f is not None and not os.path.basename(f.path).endswith("_N.png"):
					tex = os.path.basename(f.path)
			if sid == "UsdPreviewSurface":
				d = s.GetInput("diffuseColor")
				if d and d.Get() is not None:
					col = list(d.Get())
		return key, tex, col

	for prim in stage.Traverse():
		if not prim.IsA(UsdGeom.Mesh):
			continue
		mesh = UsdGeom.Mesh(prim)
		xf = np.array(cache.GetLocalToWorldTransform(prim), dtype=np.float64)
		pts = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
		pts = (np.c_[pts, np.ones(len(pts))] @ xf)[:, :3] * mpu
		counts = np.array(mesh.GetFaceVertexCountsAttr().Get())
		idx = np.array(mesh.GetFaceVertexIndicesAttr().Get())
		st = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
		uvs = None
		if st:
			uvs = np.array(st.ComputeFlattened(), dtype=np.float64)
			if st.GetInterpolation() == "vertex":
				uvs = uvs[idx]
		na = mesh.GetNormalsAttr().Get()
		nrms = None
		if na is not None and len(na):
			nrms = np.array(na, dtype=np.float64)
			if len(nrms) == len(pts) and len(nrms) != len(idx):
				nrms = nrms[idx]
			nrms = nrms @ xf[:3, :3]
		starts = np.r_[0, np.cumsum(counts)[:-1]]
		assigned = np.full(len(counts), -1)
		groups = {}
		for gi, sub in enumerate(UsdGeom.Subset.GetAllGeomSubsets(mesh)):
			info = mat_info(UsdShade.MaterialBindingAPI(sub.GetPrim()).ComputeBoundMaterial()[0])
			mats[info[0]] = info[1:]
			for f in sub.GetIndicesAttr().Get():
				assigned[f] = gi
			groups[gi] = info[0]
		info = mat_info(UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0])
		mats[info[0]] = info[1:]
		groups[-1] = info[0]
		for g, key in groups.items():
			faces = np.where(assigned == g)[0]
			if len(faces) == 0:
				continue
			corners = []
			for f in faces:
				s, c = starts[f], counts[f]
				for k in range(1, c - 1):
					corners += [s, s + k + 1, s + k]
			corners = np.array(corners)
			P = pts[idx[corners]]
			U = uvs[corners] if uvs is not None and len(uvs) == len(idx) else np.zeros((len(corners), 2))
			tri = P.reshape(-1, 3, 3)
			fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
			N = nrms[corners] if nrms is not None and len(nrms) == len(idx) else np.repeat(fn, 3, axis=0)
			N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
			flip = (fn * N.reshape(-1, 3, 3).mean(axis=1)).sum(axis=1) < 0
			P, N, U = P.reshape(-1, 3, 3), N.reshape(-1, 3, 3), U.reshape(-1, 3, 2)
			P[flip], N[flip], U[flip] = P[flip][:, ::-1], N[flip][:, ::-1], U[flip][:, ::-1]
			prims.append((key, P.reshape(-1, 3), N.reshape(-1, 3), U.reshape(-1, 2)))

	blob = bytearray()
	views, accs, materials, images, textures, mat_index, out_prims = [], [], [], [], [], {}, []

	def view(data, target=None):
		while len(blob) % 4:
			blob.append(0)
		v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
		blob.extend(data)
		if target:
			v["target"] = target
		views.append(v)
		return len(views) - 1

	def acc(arr, typ):
		arr = np.ascontiguousarray(arr, dtype=np.float32)
		a = {"bufferView": view(arr.tobytes(), 34962), "componentType": 5126, "count": len(arr), "type": typ}
		if typ == "VEC3":
			a["min"], a["max"] = arr.min(axis=0).tolist(), arr.max(axis=0).tolist()
		accs.append(a)
		return len(accs) - 1

	tints = TEX_TINT.get(tone, {})
	for key, (tex, col) in mats.items():
		col = FLAT.get(tone, {}).get(key, [c * 0.7 for c in col])
		m = {"name": key, "pbrMetallicRoughness": {"baseColorFactor": list(col) + [1.0],
			"metallicFactor": 0.0, "roughnessFactor": 1.0}}
		path = os.path.join(tex_dir, tex) if tex else ""
		if tex and os.path.exists(path):
			data = tint_texture(open(path, "rb").read(), tints.get(key, (0.7, 0.7, 0.66)))
			images.append({"bufferView": view(data), "mimeType": "image/png", "name": key})
			textures.append({"source": len(images) - 1})
			m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(textures) - 1}
			m["pbrMetallicRoughness"]["baseColorFactor"] = [1, 1, 1, 1]
			if key.startswith("Leaves") or key in ("Grass", "Flowers"):
				m["alphaMode"], m["alphaCutoff"], m["doubleSided"] = "MASK", 0.5, True
		if key == "Fire":
			m["emissiveFactor"] = [1.0, 0.42, 0.08]
		mat_index[key] = len(materials)
		materials.append(m)
	for key, P, N, U in prims:
		U2 = U.copy()
		U2[:, 1] = 1.0 - U2[:, 1]
		# Share identical corners (position, normal, uv) through an index buffer.
		rows = np.round(np.c_[P, N, U2], 5).astype(np.float32)
		uniq, inv = np.unique(rows, axis=0, return_inverse=True)
		ind = np.ascontiguousarray(inv.reshape(-1), dtype=np.uint32)
		accs.append({"bufferView": view(ind.tobytes(), 34963), "componentType": 5125, "count": len(ind), "type": "SCALAR"})
		ia = len(accs) - 1
		out_prims.append({"attributes": {"POSITION": acc(uniq[:, 0:3], "VEC3"), "NORMAL": acc(uniq[:, 3:6], "VEC3"),
			"TEXCOORD_0": acc(uniq[:, 6:8], "VEC2")}, "indices": ia, "material": mat_index[key]})
	j = {"asset": {"version": "2.0", "generator": "convert_scenery.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": out_prims}],
		"materials": materials, "bufferViews": views, "accessors": accs}
	if images:
		j["images"], j["textures"] = images, textures
	return j, blob


def main() -> None:
	cache = sys.argv[1]
	ids = sys.argv[2:] or list(PICK)
	for i in ids:
		src, name, tone = PICK[i]
		out = os.path.join(PROPS if i.startswith("ru_") else OUT, i + ".glb")
		if src == "un":
			j, blob = read_glb(fetch(UN % name, os.path.join(cache, "un", name + ".glb")))
			recolour_flat(j, tone)
			for n in j.get("nodes", []):
				n.pop("name", None)
			write_glb(out, j, blob)
		else:
			pack = PACKS[src]
			usda = fetch(STAGE % (pack, "S_%s.usda" % name), os.path.join(cache, src, "S_%s.usda" % name))
			tex_dir = os.path.join(cache, src, "textures")
			for t in TEXTURES.get(src, []):
				fetch(STAGE % (pack, "textures/%s.png" % t), os.path.join(tex_dir, t + ".png"))
			j, blob = usd_to_glb(usda, tex_dir, tone, i)
			write_glb(out, j, blob)
		print("wrote", out)


if __name__ == "__main__":
	main()
