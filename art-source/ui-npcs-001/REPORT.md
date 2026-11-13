# Warbound UI and NPC artwork handoff

This batch supplies 55 final PNGs for the Warbound hero-window, skill-tree and
campaign NPC artwork requests: 27 UI images and 28 full-body NPC references.
It is a source-art handoff. Runtime UI slicing and wiring, dialogue portraits,
3D generation and rigging remain separate work.

## Files and provenance

- Final images: [`assets/source/batches/warbound-ui-npcs-001/`](../../assets/source/batches/warbound-ui-npcs-001/).
- Portable manifest, prompts, dimensions, source filenames and SHA-256 hashes:
  [`manifest.json`](../../assets/source/batches/warbound-ui-npcs-001/manifest.json).
- Batch specification: [`warbound-ui-npcs-001.json`](../../assets/specs/batches/warbound-ui-npcs-001.json).
- Preview sheets: [`production/warbound-ui-npcs-001/`](production/warbound-ui-npcs-001/).

All images were generated with built-in `image_gen`. The requested game item and
class references supplied the painted style; existing modelling references supplied
faction anatomy and class identity. References marked `external:hero-ref/` identify
the existing locally supplied modelling images, rather than new deliverables.
NPC faces, civilian clothing and roles are new designs. Source images inherit the
parent `assets/source/.gdignore`, so they do not create runtime texture imports.

## UI images

The requested filenames are retained in `ui/`:

| Group | Files | Content |
| --- | --- | --- |
| Active skills | `skills_1.png` through `skills_8.png` | 72 icons, nine per 3×3 sheet |
| Passive skills | `passives_1.png`, `passives_2.png` | 18 icons, nine per 3×3 sheet |
| HUD | `bar_frame.png`, `bar_fills.png`, `potions.png`, `skill_slot.png` | Bar materials, two potion icons, empty skill frame |
| Skill tree | `tree_nodes.png`, `tree_backdrop.png`, `tree_connector.png` | Four node frames, dark backdrop and chain strip |
| Hero window | `paper_doll.png`, `portrait_frame.png` | Dark equipment alcove and empty portrait frame |
| Class portraits | Eight `portrait_<class>.png` images | Templar, Brandguard, Barrow Lord, Beastcaller, Anvilbreaker, Hearthkeeper, Broodbinder, Brine Champion |

![UI materials](production/warbound-ui-npcs-001/ui-contact.jpg)

![Class portraits](production/warbound-ui-npcs-001/class_portrait-contact.jpg)

## NPC references

`npc_ref/` contains seven original generic campaign NPCs: peddler, priest, elder,
woman, child, risen neighbour and noble. Twenty-one additional references give
each other faction three civilian roles:

| Faction | Roles |
| --- | --- |
| Ashen | Slag broker, pit steward, ash-shrine keeper |
| Hollow | Bone factor, shroud mender, tomb archivist |
| Thornwood | Resin trader, coppice elder, herb keeper |
| Forge | Tool broker, gem assayer, clan recordkeeper |
| Frostmarch | Fur trader, hall steward, hearth healer |
| Dark elves | Silk factor, cavern apothecary, house steward |
| Fish-men | Shell trader, net mender, tide-shrine keeper |

All individual NPC references are square and at least 1024 pixels, with full bodies,
separated legs, arms held away from the torso, a three-quarter view facing slightly
right, empty hands, even lighting and a plain grey background. Age, build, clothing,
materials and small belt tools distinguish their roles and faction identities.

![Original NPCs](production/warbound-ui-npcs-001/npc_reference-contact.jpg)

![Additional faction NPCs](production/warbound-ui-npcs-001/all-factions-contact.jpg)

## Review and finishing work

The images were visually reviewed individually and on contact sheets. PNG decoding,
minimum dimensions, ten 1536×1536 icon sheets, manifest paths and hashes are checked
for the handoff. The transparent UI assets have actual alpha; the skill-slot and
portrait-frame centres are transparent.

The ten icon sheets were mechanically enlarged from 1254×1254 generated sources
to the requested 1536×1536 export dimensions. This does not add new source detail.
The manifest records both dimensions.

`bar_fills.png` and `tree_connector.png` were refined for repeating patterns, but
their opposite-edge samples still differ. Finish those seams before relying on
exact seamless runtime tiling. Sheets remain unsliced, and no generated NPC models
or optional named-character dialogue portraits are included.
