#!/usr/bin/env python3
"""Warbound worker bodies through Tripo text_to_model + Mixamo rig (no artwork exists for workers).
Same commands as tripo_heroes.py (model / redo / list); spec assets/source/workers3d/workers.json."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tripo_heroes as th  # noqa: E402

th.SPEC = th.ROOT / "assets/source/workers3d/workers.json"
th.OUT = th.ROOT / "assets/source/workers3d"
th.KEY = "workers"

if __name__ == "__main__":
    th.main(sys.argv[1:])
