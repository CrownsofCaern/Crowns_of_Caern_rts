#!/usr/bin/env python3
"""Recolours Concord town art for neutral Warbound settlement pieces: blue slate roofs and banners
turn to weathered brown-red, everything else stays.  python3 tools/assets/neutral_recolor.py SRC.png OUT.png"""
import sys

import numpy as np
from PIL import Image


def recolor(img: Image.Image) -> Image.Image:
    rgba = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    hsv = np.asarray(img.convert("RGB").convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    blue = (h > 0.52) & (h < 0.75) & (s > 0.18)
    weight = np.clip((s - 0.18) / 0.15, 0.0, 1.0) * blue
    h2 = np.where(weight > 0, 0.03, h)       # rust-brown
    s2 = np.where(weight > 0, s * 0.55, s)
    v2 = np.where(weight > 0, v * 0.95, v)
    out = Image.merge("HSV", [Image.fromarray((c * 255).astype(np.uint8)) for c in (h2, s2, v2)]).convert("RGB")
    out = np.asarray(out).astype(np.float32) / 255.0
    mixed = rgba[..., :3] * (1 - weight[..., None]) + out * weight[..., None]
    res = np.concatenate([mixed, rgba[..., 3:]], axis=-1)
    return Image.fromarray((res * 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    recolor(Image.open(sys.argv[1])).save(sys.argv[2])
