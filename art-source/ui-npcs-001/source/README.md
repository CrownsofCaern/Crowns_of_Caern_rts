# Warbound UI and NPC artwork

55 final PNGs: 27 UI images and 28 full-body NPC references. The UI images include 72 active skill icons, 18 passive icons, HUD/tree/equipment materials and eight class portraits. The NPCs include seven original generic references plus three civilians for each of seven other factions.

`ui/` retains the requested drop-in filenames; `npc_ref/` contains individual square modelling references. `manifest.json` records dimensions, prompts, style references, generated-source filenames and checksums. External hero-ref references identify the existing modelling images supplied locally; they are not new artwork from this batch.

This is a source-art handoff; sheets remain unsliced and the batch is not wired into runtime code. Source images are excluded from Godot import by the parent `.gdignore`. See [review report](../../../../docs/art/WARBOUND_UI_NPC_ART_REPORT.md) for previews and known finishing work.
