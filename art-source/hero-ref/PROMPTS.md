# Hero reference images for Warbound (ChatGPT)

These images become the 3D hero models: one per class, 32 in total. Tripo turns each image into a rigged model, and the weapon is added in the game, so **the hands must be empty**. Do batch 1 first (12 heroes): Warbound already has those factions.

## How to use this

1. In ChatGPT, paste **one hero block** per image. Each block is complete on its own.
2. For the 24 existing classes, **attach the class portrait** so the hero keeps its look. The portraits are the game's class portraits (`assets/ui/heroes/<id>.png`) (for example `knight.png`). The 8 new classes (marked NEW) have no portrait: use the block alone, and attach one portrait of the same faction as a style reference if you like.
3. Save each result as `<id>.png` (for example `knight.png`), at least 1024 px, in `art-source/hero-ref/`.
4. Before you keep an image, check these six things (they are what Tripo needs):
   - the whole body is in frame, feet included;
   - the pose is upright and open: arms away from the body, a gap between the legs;
   - **both hands are empty** (no weapon, shield, staff, book or lantern in hand);
   - nothing hangs over or between the legs: capes, robes and tabards end above the knee;
   - the hero is on foot (no lizard, crab or horse);
   - plain flat background, no smoke, sparks or magic floating loose (glow *on* the body is fine).
5. If a result keeps adding a weapon, add this line at the end: `Again: the hands are completely empty.`

## All 32 heroes

| # | id | Class | Faction | Role | Portrait |
|---|---|---|---|---|---|
| 1 | knight | Knight | Concord | Guardian | knight.png |
| 2 | ranger | Ranger | Concord | Ranger | ranger.png |
| 3 | oracle | Oracle | Concord | Mender | oracle.png |
| 4 | templar | Templar | Concord | Warrior | NEW, no portrait |
| 5 | warlord | Warlord | Ashen | Warrior | warlord.png |
| 6 | warlock | Warlock | Ashen | Mystic | warlock.png |
| 7 | tormentor | Tormentor | Ashen | Summoner | tormentor.png |
| 8 | brandguard | Brandguard | Ashen | Guardian | NEW, no portrait |
| 9 | necromancer | Necromancer | Hollow | Summoner | necromancer.png |
| 10 | gravewarden | Gravewarden | Hollow | Guardian | gravewarden.png |
| 11 | blightcaller | Blightcaller | Hollow | Mystic | blightcaller.png |
| 12 | barrow_lord | Barrow Lord | Hollow | Warrior | NEW, no portrait |
| 13 | grovewarden | Grovewarden | Thornwood | Guardian | grovewarden.png |
| 14 | huntmaster | Huntmaster | Thornwood | Ranger | huntmaster.png |
| 15 | thornspeaker | Thornspeaker | Thornwood | Mender | thornspeaker.png |
| 16 | beastcaller | Beastcaller | Thornwood | Summoner | NEW, no portrait |
| 17 | artificer | Artificer | Forge | Summoner | artificer.png |
| 18 | ironmarshal | Ironmarshal | Forge | Guardian | ironmarshal.png |
| 19 | runesmith | Runesmith | Forge | Mystic | runesmith.png |
| 20 | anvilbreaker | Anvilbreaker | Forge | Warrior | NEW, no portrait |
| 21 | thane | Thane | Frostmarch | Warrior | thane.png |
| 22 | reaver | Reaver | Frostmarch | Ranger | reaver.png |
| 23 | frostcaller | Frostcaller | Frostmarch | Mystic | frostcaller.png |
| 24 | hearthkeeper | Hearthkeeper | Frostmarch | Mender | NEW, no portrait |
| 25 | de_dreadmarshal | Dreadmarshal | Dark elves | Warrior | de_dreadmarshal.png |
| 26 | de_veilseer | Veilseer | Dark elves | Mystic | de_veilseer.png |
| 27 | de_nightstalker | Nightstalker | Dark elves | Ranger | de_nightstalker.png |
| 28 | broodbinder | Broodbinder | Dark elves | Summoner | NEW, no portrait |
| 29 | fm_tidemarshal | Tidemarshal | Fishmen | Guardian | fm_tidemarshal.png |
| 30 | fm_deep_oracle | Deep Oracle | Fishmen | Mender | fm_deep_oracle.png |
| 31 | fm_reef_hunter | Reef Hunter | Fishmen | Ranger | fm_reef_hunter.png |
| 32 | brine_champion | Brine Champion | Fishmen | Warrior | NEW, no portrait |

## Batch 1: Concord, Ashen, Hollow (Warbound has these now)

### 1. knight (Knight, Concord)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Knight, a guardian hero of the Concord faction. Bearded veteran knight in a dented open-faced steel kettle helm, scarred plate armour over mail, a navy-blue surcoat with a gold tower emblem, short navy cape to mid-back. Colours: worn steel, navy blue, tarnished gold. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 2. ranger (Ranger, Concord)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Ranger, a ranger hero of the Concord faction. Grim bearded scout in a deep moss-green hood, a ragged brown leather cloak cut short at the hip, leather and mail over a dark tunic, a quiver of arrows on the back (no bow), bracers and soft boots. Colours: moss green, mud brown, dull iron. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 3. oracle (Oracle, Concord)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Oracle, a mender hero of the Concord faction. Pale woman with golden glowing eyes in a cream-white hood and robe embroidered with gold lantern motifs, a navy and steel breastplate under it, the robe shortened to above the knee over fitted dark trousers and boots, a small brass lantern hanging at the belt. Colours: cream white, navy, gold. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 4. templar (Templar, Concord) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Templar, a warrior hero of the Concord faction. NEW CLASS. A tall, broad Concord holy warrior who fights with a two-handed sword: a closed great-helm with a narrow cross-shaped visor and a small gold lantern crest, heavy scarred steel plate, a white tabard with a navy border and the gold tower emblem cut short at mid-thigh, a navy sash, chain skirt, plated boots. Grim and battered, not shiny. Colours: steel, off-white, navy blue, tarnished gold.
```

### 5. warlord (Warlord, Ashen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Warlord, a warrior hero of the Ashen faction. Huge brutal demon-touched warlord in blood-red spiked plate with ram-like horns on the helm, a skull trophy at the chest, scorched red cloth tatters at the waist ending above the knee. Colours: rust red, black iron, bone. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 6. warlock (Warlock, Ashen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Warlock, a mystic hero of the Ashen faction. Bearded pact-caster with two great curled horns growing through a ragged grey-brown hood, a tattered layered robe glowing with faint ember-orange runes, cut above the knee over dark wrapped trousers. Colours: ash grey, smoke brown, ember orange glow on the runes only. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 7. tormentor (Tormentor, Ashen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Tormentor, a summoner hero of the Ashen faction. Hulking masked torturer with a barred iron face-cage under a dark brown hood, one huge bare scarred arm, leather straps and hooks, a stained leather apron ending above the knee. Colours: dark leather brown, black iron, raw red skin. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 8. brandguard (Brandguard, Ashen) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Brandguard, a guardian hero of the Ashen faction. NEW CLASS. A massive shield-bearer of the Ashen Host: thick black-iron plate glowing with ember-orange seams like cooling slag, a heavy helm with two short forward horns and a slit visor, a chain-and-hook belt, scorched red cloth panels at the waist ending above the knee, very broad shoulders. Brutal and inhuman, not a knight. Colours: black iron, ember orange seams, dried-blood red.
```

### 9. necromancer (Necromancer, Hollow)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Necromancer, a summoner hero of the Hollow faction. Skeletal grave-scholar with a skull face and a long white beard under a deep violet hood, layered violet and grey robes cut above the knee over bone-wrapped legs, a coiled bronze brooch. Colours: faded violet, bone white, tarnished bronze. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 10. gravewarden (Gravewarden, Hollow)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Gravewarden, a guardian hero of the Hollow faction. Deathless sentinel in a closed great-helm topped by a spiked iron crown, corroded bronze-grey plate, a dark violet scarf and short cloth at the waist ending above the knee. Colours: corroded bronze, dark violet, grave grey. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 11. blightcaller (Blightcaller, Hollow)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Blightcaller, a mystic hero of the Hollow faction. Plague-priest in a long beaked plague-doctor mask under a rotting green hood, layered mossy rags, glass vials of yellow-green fluid on the belt, rags cut above the knee over wrapped legs. Colours: rot green, bile yellow, dirty leather. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 12. barrow_lord (Barrow Lord, Hollow) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Barrow Lord, a warrior hero of the Hollow faction. NEW CLASS. A risen ancient warrior-king who fights with a great axe: a gaunt dead face with sunken glowing pale-violet eyes under an old open bronze crown-helm, ancient corroded bronze scale armour over a ribcage that shows through gaps, a torn violet burial shroud as a short cape to mid-back, bone-and-bronze greaves. Colours: green-tarnished bronze, bone, faded violet.
```

## Batch 2: the other five factions

### 13. grovewarden (Grovewarden, Thornwood)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Grovewarden, a guardian hero of the Thornwood faction. Keeper of the old groves: bark-skinned gaunt warden in armour of grown wood and moss, a bramble crown. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 14. huntmaster (Huntmaster, Thornwood)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Huntmaster, a ranger hero of the Thornwood faction. Volley captain of the deep wood: lean bark-skinned hunter in leaf-and-leather armour, a quiver on the back (no bow). Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 15. thornspeaker (Thornspeaker, Thornwood)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Thornspeaker, a mender hero of the Thornwood faction. Druid voice of the green in robes of leaves and bark, cut above the knee. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 16. beastcaller (Beastcaller, Thornwood) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Beastcaller, a summoner hero of the Thornwood faction. NEW CLASS. A gaunt bark-skinned forest shaman who calls beasts: a wolf-skull headdress with antlers over a face of grey bark, a mantle of dark fur and moss on the shoulders, bone and claw charms on cords at the chest, a leather and woven-root kilt ending above the knee, bare bark-textured arms with green glowing rune scars. Colours: bark grey-brown, moss green, bone, faint green glow on the scars only.
```

### 17. artificer (Artificer, Forge)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Artificer, a summoner hero of the Forge faction. Soot-black deep-folk engineer with goggles, a leather apron and tool harness, riveted bracers. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 18. ironmarshal (Ironmarshal, Forge)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Ironmarshal, a guardian hero of the Forge faction. Siege commander of the deep folk in heavy riveted plate. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 19. runesmith (Runesmith, Forge)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Runesmith, a mystic hero of the Forge faction. Engraver of power-runes: deep-folk smith with glowing rune-etched armour pieces. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 20. anvilbreaker (Anvilbreaker, Forge) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Anvilbreaker, a warrior hero of the Forge faction. NEW CLASS. A short, very broad soot-black deep-folk smith-warrior who fights with a two-handed hammer: a thick braided black beard with iron rings, a heavy riveted iron helm with a glowing orange slit visor, a scorched leather smith's apron over chain mail, huge riveted iron gauntlets and boots, a coal-glow furnace plate on the chest. Colours: soot black, dark iron, brass rivets, orange furnace glow.
```

### 21. thane (Thane, Frostmarch)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Thane, a warrior hero of the Frostmarch faction. Bearded hold-lord in a dented steel nasal helm with a huge white fur mantle on the shoulders, mail and leather, a short fur-trimmed kilt above the knee. Colours: steel, white and grey fur, dark leather. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 22. reaver (Reaver, Frostmarch)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Reaver, a ranger hero of the Frostmarch faction. Fast northern raider who throws axes: fur and leather, a belt of throwing axes is NOT drawn (empty belt loops only). Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 23. frostcaller (Frostcaller, Frostmarch)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Frostcaller, a mystic hero of the Frostmarch faction. Rime-witch of the north in frost-white furs and pale blue cloth, cut above the knee. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 24. hearthkeeper (Hearthkeeper, Frostmarch) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Hearthkeeper, a mender hero of the Frostmarch faction. NEW CLASS. A stern grey-haired northern clan healer, a woman of about fifty with braided hair tied tight to the head and a band of bronze around the brow, a heavy white-and-grey fur mantle, a dark red wool dress over leather, cut above the knee over fur-wrapped boots, bronze amulets and small bundles of dried herbs at the belt. Colours: white and grey fur, dark red wool, bronze.
```

### 25. de_dreadmarshal (Dreadmarshal, Dark elves)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Dreadmarshal, a warrior hero of the Dark elves faction. Armoured dark elf commander in dark lacquered plate. ON FOOT: the portrait shows him on a cave lizard; leave the lizard out entirely. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 26. de_veilseer (Veilseer, Dark elves)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Veilseer, a mystic hero of the Dark elves faction. Hooded dark elf sorceress with long pale hair tied back, deep violet hood and layered robe cut above the knee. ON FOOT, no lizard. Colours: deep violet, black, silver. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 27. de_nightstalker (Nightstalker, Dark elves)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Nightstalker, a ranger hero of the Dark elves faction. Masked dark elf scout in fitted black leather. ON FOOT, no lizard, no crossbow in hand. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 28. broodbinder (Broodbinder, Dark elves) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Broodbinder, a summoner hero of the Dark elves faction. NEW CLASS. A slender dark elf beast-binder who commands cave lizards: pale grey skin, long silver-white hair tied in a high tail, a violet-lacquered half-mask over the lower face, a cape of black lizard hide with small spines along its edge, cut to mid-back, fitted black scale armour, a coiled whip hanging at the hip (not held), violet sash ending above the knee. Colours: black, deep violet, pale grey skin, silver.
```

### 29. fm_tidemarshal (Tidemarshal, Fishmen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Tidemarshal, a guardian hero of the Fishmen faction. Gilled fish-man commander with a finned crest, armour of coral-encrusted shell plates. ON FOOT on two legs, no crab mount. Colours: sea green, coral pink, shell bronze. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 30. fm_deep_oracle (Deep Oracle, Fishmen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Deep Oracle, a mender hero of the Fishmen faction. Robed anglerfish oracle with a small glowing lure on the brow, shell and pearl ornaments, robe cut above the knee. ON FOOT on two legs, no mount. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 31. fm_reef_hunter (Reef Hunter, Fishmen)
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Reef Hunter, a ranger hero of the Fishmen faction. Lean fish-man harpoon scout in light shell and net armour. ON FOOT on two legs, no crab, no harpoon in hand. Follow the attached portrait. Keep the face, helmet or hood, armour, colours and emblems of the attached portrait; invent the rest of the body to match it.
```

### 32. brine_champion (Brine Champion, Fishmen) NEW
```
Clean 3D-model reference image for a dark fantasy strategy game hero. One character only, full body from head to feet with a small margin. Plain flat light grey background, no ground, no shadow, no text, no scenery, no smoke, sparks, magic or particles floating free. Even soft lighting, matte painted look in the same gritty dark-fantasy painting style as the attached portrait (if one is attached), realistic adult proportions, not chibi, not cartoon. Square image, 1024 x 1024.

Pose: three-quarter front view, facing slightly right. Standing upright in a relaxed A-pose: feet apart at shoulder width, legs straight and clearly separated, both arms hanging down and held about 35 degrees away from the torso with a clear gap between each arm and the body. BOTH HANDS EMPTY: no weapon, no shield, no staff, no book, no lantern; hands as loose relaxed fists. Nothing hangs over the legs: any cape, cloak, robe or tabard ends above the knees and stays behind or beside the legs, not between them. No long loose hair, ribbons or chains hanging free. On foot, no mount.

Subject: Brine Champion, a warrior hero of the Fishmen faction. NEW CLASS. A huge, heavily muscled shark-headed fish-man who fights with a two-handed weapon: a wide shark mouth full of teeth, grey-blue rough skin with gill slits on the neck, heavy armour of barnacle-crusted bronze plates and big shell pauldrons, a net-and-kelp kilt ending above the knee, webbed clawed feet. Colours: storm grey-blue, tarnished sea-bronze, dark kelp green, bone-white teeth.
```
