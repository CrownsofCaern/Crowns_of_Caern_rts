# Art sources

Raw art inputs behind `assets/` and the scripts that turned them into game files:

- `hero-ref/`: the 32 hero class reference images; the 3D hero bodies (`assets/heroes3d`) were made from them.
- `buildings3d/`, `heroes3d/`, `workers3d/`: records of the image-to-3D (Tripo) tasks.
- `ui-npcs-001/`: painted UI sheets and civilian NPC reference art, with prompts and a production report.
- `tools/`: the conversion scripts. They were written for the main game's repository layout and its
  `tools/assets` pipeline (github.com/CrownsofCaern/Crowns_of_Caern_4X); adjust paths before reusing them.

Godot ignores this folder (`.gdignore`).
