# Third-party assets in Warbound

All of these are CC0 (public domain); no attribution is required, it is kept here for our records.

| Files | Source | Licence |
|---|---|---|
| `assets/terrain3d/rock023_*` | ambientCG Rock023, as packed (albedo+height, normal+roughness) in the Terrain3D demo (github.com/TokisanGames/Terrain3D) | CC0 1.0 (https://docs.ambientcg.com/license/) |
| `assets/terrain3d/ground003_*`, `ground022_*`, `ground047_*`, `ground068_*`, `gravel024_*`, `gravel040_*`, `rock022_*`, `rock026_*`, `rock028_*`, `rock030_*`, `rock033_*` | ambientCG Ground003, Ground022, Ground047, Ground068, Gravel024, Gravel040, Rock022, Rock026, Rock028, Rock030 and Rock033 (official 1K JPG sets), packed the same way (Color+Displacement, NormalGL+Roughness); the colour of each is nudged toward a common hue so the biome tints in data/biomes.json apply evenly | CC0 1.0 (https://docs.ambientcg.com/license/) |
| `assets/nature/*.glb` | Quaternius "Ultimate Stylized Nature" pack, via github.com/walterpalladino/godot-quaternius-ultimate-stylized-nature; converted by `tools/nature/convert_nature.gd` (512 px textures, darker tints) | CC0 1.0 |
| `assets/nature/` biome scenery: `sn_*`, `fn_*`, `mo_*`, `ch_*`, `stump`, `log` | Quaternius "Ultimate Nature Pack", GLBs as mirrored in github.com/trebeljahr/quaternius-showcase (`public/glb/nature_pack`); recoloured by `tools/nature/convert_scenery.py` | CC0 1.0 (quaternius.com) |
| `assets/nature/` `fern`, `mushrooms`, `shelf_fungus`, `reeds`, `twisted_tree_*`, `gl_*` | Quaternius "Stylized Nature MegaKit", from the USDA copies in github.com/chibifire-stages/quaternius-stage; converted to GLB and retinted by `tools/nature/convert_scenery.py` (512 px textures) | CC0 1.0 (quaternius.com) |
| `assets/props3d/ru_*.glb` (monster lair dressing) | Quaternius "Ultimate Modular Ruins Pack", from the same quaternius-stage USDA copies; converted by `tools/nature/convert_scenery.py` | CC0 1.0 (quaternius.com) |
| `assets/weapons3d/*.glb` | Quaternius "Medieval Weapons Pack" (Sept 2018) and "RPG Asset Pack" (May 2017, the staff), via github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius; converted by `tools/weapons/convert_weapons.gd` (one mesh per weapon kind, metres, grip at the origin, darker colours) | CC0 1.0 |
| `assets/props3d/*.glb` (map ruins, temples, graveyards, siege wrecks, towers) | Kenney "Graveyard Kit" 0.2 and "Castle Kit" 1.0; Quaternius "Modular Dungeon Pack" (Jan 2018), "Updated Modular Dungeon" (May 2019), "Modular Medieval Buildings" (Jul 2017) and "Civilization Buildings" (May 2018), all via github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius; converted by `tools/props/convert_props.gd` (one merged mesh per prop, metres, darker stone, blue paint turned blood red) | CC0 1.0 |

The landmarks `assets/props3d/lm_*.glb` are our own: image-to-3D models made with Tripo from the main
game's encounter and place paintings (`assets/source/generated`, `assets/source/map-expansion-001` in the
main repo), converted by `tools/props/convert_landmarks.py` (metres, 1024 px colour texture only).

Everything else in `assets/` comes from the sister turn-based game Crowns of Caern (`tools/sync_from_main.py`),
including the project's own 3D unit models in `assets/units3d/`.

`assets/fonts/Cinzel.ttf` and `assets/fonts/Lora.ttf` are under the SIL Open Font License 1.1 (texts next
to them), copied from the main game by `tools/sync_ui_from_main.py` with the menu art and UI sounds.
