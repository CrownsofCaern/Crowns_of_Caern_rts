# Crowns of Caern: Warbound

A dark-fantasy real-time strategy game with RPG heroes and story campaigns, set in the world of the
turn-based game Crowns of Caern (github.com/CrownsofCaern/Crowns_of_Caern_4X). Made with Godot 4.5
(GDScript). Licence: code under MIT (`LICENSE`); art, story and third-party credits in `CREDITS.md`.

## Play

Install Godot 4.5.1 and run `godot --path .` in this folder (or open `project.godot` in the editor).
On a Mac you can double-click `tools/mac/Play Warbound.command`.

A skirmish is for 2 to 4 houses on a generated map. `src/sim/map_gen.gd` (`MapGen`) builds it from a
template in `data/map_templates.json`: zones (homes and settlements, mirrored for every player), links
(roads, trails, mountain passes, bridges, fords), features (sea, islands, lakes, rivers, ridges, woods)
and sites (monster lairs of tier 1-3 that guard loot, shrines, merchants), each dressed with set pieces
(CC0 ruins, temples, graveyards, siege wrecks, and landmarks modelled from the main game's encounter art,
in `assets/props3d`). The land rolls in hills; some places stand on plateaus ringed by cliffs (rock in the
sim) with ramps where the roads come in, and mountains rise where lakes used to be. Every zone takes a biome: homes their
house's, the wilds those of other houses. Two-player layouts include island maps, a river with two
bridges, highland passes, a crown lake, three lanes, a drowned delta, a winding serpent river, an open
steppe and three ridge valleys; three and four players play on corner maps (among them a drowned wheel). The setup screen picks a template or a random one (from the seed). Each sector has a centre:
a waystone or a settlement from farmstead to city. Stand next to a settlement with soldiers to take it
(beat its garrison first: one of some 35 groups in `data/map_templates.json` `garrisons`, often mixed and
themed by the land, such as cutthroats with crossbows, a fen coven or a giant's hall, scaled to the settlement's
size; campaign maps keep plain militia); after 60 s unsettled it pays gold and sends out workers. Workers run themselves and can't be selected. They gather the
resources your faction uses (grey piles are useless to you). Piles run dry: a timber pile holds 1200, ore 1000 and a rare 150 (rares are spent in tens, not thousands; piles at home half as much again, `economy.json` `pile_amounts`); a worked pile shows what is left and shrinks, an empty one is gone and its workers move on to other piles in your sectors, so you have to take new ground. Gold comes from settlements and never runs out. Workers also build dwellings (B opens the build menu; the nearest free worker goes by itself, and a building site's panel
sends another to help), and one worker is
drafted for every unit you train. The number beside each resource in the top bar (0x to 10x, left
click for more, right click for fewer) is its share of your gatherers: workers spread themselves over
what your sectors offer in that mix. Building sites and recruits come first and take the worker the mix
can best spare (`Economy.spare_worker`; defaults in `economy.json`, `gather_weights`). Raise the hall (click your home settlement) to unlock higher tiers. The hall defends itself: it shoots arrows at enemies within about 9 m (soldiers first, workers only
when no soldier is near), 2 a volley at level 1 and up to 5 heavier ones at level 4, so a base can ride out
an early push (`BaseDefense`; numbers in `economy.json`, `hall_defense` and `arrows` per hall level). A taken hall falls silent.
Lose every settlement and you lose. Tuning lives in `data/economy.json`.

Workers can also wall the land off (build menu: Wall; click where it starts and where it ends, Shift keeps
going). A wall is a line of 1 m cells that always touch by a side, and its ends reach on to rock, water, woods or
another wall within 3 m, so it can shut a pass or a bridge between islands without a gap. It is cut into 3 m pieces
that workers build one after another. Ground units cannot pass: a soldier on attack-move with nobody to fight
breaks the wall in its way (paths are planned through walls when there is no way round, so they walk up to it),
and the hole stays open. Flyers ignore walls. A finished piece can become a gate (it opens while one of your units
is close, so an enemy right there can slip in) or a tower (sturdier; select up to 2 ranged units and right click it
to send them up: they shoot farther, and only ranged and flying foes can hurt them until the tower falls). The
computer breaks walls but does not build them yet. Code: `src/sim/fortifications.gd` (`Fortifications`; numbers
in `economy.json` "forts"); the wall and tower models are Tripo (`assets/forts3d`); stills: `tools/fort_shots.gd`.

The battlefield is 3D (Tab, F3 or the map button by the ? opens the flat tactical map): a heightmap terrain with roads, ponds,
woods, rock outcrops and mountains around the map, under a fixed RTS camera (wheel zooms, arrows,
screen edge or middle drag scroll). Units are the main game's animated battle sprites standing in
the 3D world (see below). Buildings and settlements are still sprites until their
3D models arrive (`assets/buildings3d/<key>.glb`, `assets/settlements3d/<size>.glb` are picked up
automatically).

Units are drawn with the main game's animated
battle sprites (idle, walk, attack, death) as billboards that always face the camera and mirror to the side
they walk or strike towards (`SpriteUnit`, `src/ui/sprite_unit.gd`). A shader lights them with the scene's sun, ambient
light and fog (`sprite_unit.gdshader`), and a soft blob shadow grounds them. The sheets are cut from the main game's
battle atlases by `python3 tools/sync_unit_anims.py` into `assets/unit_anims/<sprite>.png` and
`data/unit_anims.json`. Heroes have their own class sheets (`hero_<class>`), baked from their 3D bodies with
their weapons by `python3 tools/bake_hero_sprites.py` (renders through `tools/render_hero_sprites.gd`, then the main
game's palette and outline); a class without a sheet shows its stand-in unit.

The light is dark and gothic: a low, red sun under a blood-red sky, fog and dark corners. Now and then
the weather turns: grey cloud, rain, or a thunderstorm with lightning flashes and thunder (snow fields
get snow and ash lands falling ash with red lightning). It is purely visual and seeded by the map.
F6 steps through the weather; Settings can switch it off. The light follows the biome under the camera (frost light over snow, a burning sky over ash), and a final colour grade (`ColorGrade`, a small 3D lookup texture) gives every frame the main game's split of warm golden light and cool slate shadows. The fog of war has a soft, slowly drifting edge. In skirmish, land never explored is shown greyed out rather than black (never who holds it or what stands on it); the campaign keeps it black. The minimap always shows the sector borders. Stills for art review: `tools/look_shots.gd -- <dir> [zoom]`. Code: `src/world3d/atmosphere_3d.gd`
(rain is one MultiMesh moved by `precipitation.gdshader`, so it stays cheap on phones); the thunder
and rain sounds come from the main game's `tools/audio/synth.py`. Look: `tools/world3d_shots.gd -- <dir> 101 weather`.
On top of that, `LookFx3D` (`src/ui/look/`) adds two looks that Settings can switch off one by one.
**Ink outlines** draws dark contour lines wherever the depth jumps or bends, puts a one-texel ink outline
round every battle sprite and gives the frame a punchier grade. **Living land** adds cloud shadows drifting
over the fields, mist in the low ground, and motes that suit the biome: pollen, fireflies, spores, ice
glitter, violet sparks or rising embers. Both are full-screen passes that read the depth buffer and draw
before the fog of war. A building under construction gets scaffolding, rises out of the ground as the work
goes on, and throws up dust and wood chips while builders are at it (`ConstructionFx3D`). In a fight, a
melee blow leaves a bright arc, a struck figure flashes white and then red, and heavy fighters throw up
dust. Clips: `tools/visual_shots.gd` (run it with `--fixed-fps 12`).
Imported models (units, heroes, buildings, props) lose their glossy PBR look: `MatteMaterials` swaps in a rough,
non-metallic copy of each material with little specular, so they read as cloth, leather and old iron rather than
plastic (`tools/world3d_shots.gd -- <dir> 101 materials` shows before and after).

Every blow is melee, ranged or magic (`damage_type` in `data/units.json`), and every unit has a defence against
each (`defense`): shields and plate stop arrows, robed casters and the holy resist spells, arrows pass through bone
while holy light breaks it, spirits shrug off steel and fear magic, riders and flyers are big targets for archers.
Witches, shamans, healers, spirits and mystic heroes strike with magic, and hero spells are magic too. Against a building,
wall, gate or tower a unit deals its `building_damage` instead: colossi, giants, treants, engines and bombards several
times their damage, archers and flyers well under it. Some blows keep hurting (`rules.json` "dots"): poison (through
armour), burn (Ashen and Forge fire; met by magic defence, and buildings burn too), bleed (slashers; not the
undead, spirits, constructs or plants) and frost (Frostmarch; the target slows). The values come from body tags in
`tools/sync_from_main.py` (`DEFENSE_TAGS`, `SIEGE_TAGS`, `DOTS`; `sync_from_main.py units` rewrites only the unit table);
the unit card shows damage and type, the three defences and building damage. `tools/combat_parity.gd` fights the
factions' armies against each other and times how fast each role razes a building.

Fights show what each blow does (`src/ui/combat_fx_3d.gd`, `CombatFx3D`): archers' arrows, crossbow bolts,
harpoons, axes, sling stones and bombard shells fly in an arc to their target, casters fire a glowing orb
in their element (fire, frost, shadow, poison...) that lights up the ground where it bursts, every wound
spurts what the unit is made of (blood, ichor, bone dust, sparks, embers, sap) and the fallen leave a pool.
Healers send motes of light, and hero skills strike, burst, ring out or rain arrows in their element.
The table is `data/combat_fx.json`: its `units` part comes from the main game's `assets/battle_fx.json`
and creature tags (`python3 tools/sync_from_main.py fx`), hero classes and skills are set there by hand.
Effects are capped (bursts and lights) and skipped in the fog, so big fights stay cheap. Look:
`tools/combat_fx_shots.gd -- <dir>` (run with `--fixed-fps 30`).

Controls are listed on screen (F1 hides them). Left click or drag to select, right click to move or
attack, A + click to attack-move, S stop, H hold, Ctrl+1-9 / 1-9 groups, P pause, M sound, R new battle.
Right click a settlement that isn't yours (or T + click) to capture it: the soldiers march there ready to
fight, beat its defenders and stand in it until it is yours (SimWorld.command_capture, order CAPTURE).
Hold shift with any order to queue it: waypoints, attack-moves, attacks, captures, gathering, building
(shift + placing lays out sites that the workers build one after another). A queued group goes on to its
next step once every member is done (SimWorld.queue_command / plans); any order without shift drops the
queue. The queue of the selection shows as a dashed line. The cursor shows what a right click would do
(CommandCursor, Warbound's own dark fantasy cursor set with a hammer for building and a flag for capturing; tools/command_probe.gd checks it).
The unit panel selects one type per click; the minimap looks (left) or sends the selection (right).

**Tactical map.** Tab (or F3, or the map button left of the ?) swaps the 3D world for the flat 2D
map with the 2D sprites (units, towns, halls, dwellings, piles). It opens showing the whole map between the
HUD bars, and sprites are drawn up to 2.4x larger when zoomed out so they stay readable. Over the fog it adds
every sector's border and, under each settlement's name, the resource piles in its sector (icon and count;
greyed when your faction can't use them). The wheel zooms in on the mouse; opening it again resets to the
whole map. Back in 3D the camera returns where it was, or looks where you moved the map.
Code: `src/ui/tactical_map.gd` (overlay) and `Skirmish._draw_world`; stills: `tools/tactical_shots.gd -- <dir> [seconds] [template]`.

## Menus

The game opens on the title screen (Skirmish, Online, Campaign, Settings, Quit), in the main game's look:
its painted backdrops, wordmark, Cinzel/Lora fonts, framed faction panels and UI sounds. Skirmish
setup picks your house and the computer's (or Random), the victory rule and the seed, with a preview
of the generated sector map; the last choices are remembered. Campaign opens a house's campaign
(see Campaigns below; Concord's campaign, The Last Light, is playable end to end). In battle, Esc (when nothing is selected) or F10 opens the
pause menu (resume, restart, new map, settings, main menu); the end of a battle shows a victory or
defeat card. Code: `src/menu/` (`SkirmishSetup` is the plain hand-over to `skirmish.gd`;
`HudSkin` restyles the battle HUD and adds the resource bar). Art and sounds come from
`tools/sync_ui_from_main.py`; screenshots: `tools/menu_shots.gd`.

## Computer players

Five levels (setup screen, per computer row): Easy, Normal, Hard, Very hard and Brutal. `EconomyAi`
(`src/sim/economy_ai.gd`) plays with the same commands as a person; the levels differ only in the
numbers under `ai_difficulty` in `data/economy.json`. From Normal up it weighs armies by strength rather
than head count (`EconomyAi.power_of`: damage per second times blows it can take, veteran ranks, wounds and
statuses included; a hall's arrows count too), so it never sends a wave into a stronger garrison and
storms a capital only with a clear edge over the whole rival army. It sends small squads out at once to
take the free settlements on its own half of the map (strong enough for the guards there, nearest and
richest first, land with a resource its next hall level lacks first of all), calls a wave back to the
capital when it is losing the fight, falls back on its hall when raiders are too strong to meet in the
field, and pulls hurt veterans (rank 3 and up on Hard and above) out of a fight to rest at home, beside a
healing building when the house has one, until they are fit again. It steers its gatherers away from a rare
once it has a stock of it and keeps training while the rival army is stronger instead of saving for the
hall. Very hard thinks every half second and plays fair; Brutal is the same player with 30% more from every
load and every settlement. Soldiers resting idle at their own capital mend slowly (`rules.json` rest_heal,
0.4% of their health a second); the healing buildings of three houses are the quick way.

Measure one level against another, or against an older AI script:

    git show origin/main:spinoff/warbound/src/sim/economy_ai.gd | sed 's/^class_name EconomyAi$//' > /tmp/old_ai.gd
    godot --headless --path . --script res://tools/ai_duel.gd -- 8 30 very_hard old:hard concord,hollow,forge /tmp/old_ai.gd

## Online

Online (title screen) plays a skirmish against other people: one player clicks **Host a match**, the
others type the host's address and click **Join** (port 24690; an address may carry its own port,
`host:port`). In the lobby everyone picks a house and hero (or Random); the host picks the map and may add
up to two computer players, then starts. Two to four players. On the same network the host's local
address works; from afar both install Tailscale (free) and join with the host's Tailscale address
(100.x.y.z), so nobody has to open ports on a router. Both computers need the same build: the lobby
compares the game version and a fingerprint of `data/*.json` and turns a different build away.

How it works: lockstep. Every computer runs the whole simulation; only the players' commands travel.
Every change a player makes is a plain command (`WorldCommands`, `src/sim/world_commands.gd`: orders,
building, training, hero skills and gear, gather mix...), which `Skirmish.act()` applies at once
alone at the keyboard. Online `Lockstep` (`src/sim/lockstep.gd`) schedules it 0.2 s ahead (2 turns of
0.1 s), sends each turn's commands to the others, and runs a turn only when every player's commands
for it are in, so every computer applies the same commands before the same tick. Computer players
run on every computer. A command only ever moves the sender's own units and spends their own
resources. Once a second the computers compare a fingerprint of their worlds. If they differ, the
drift is repaired: the host names a turn just ahead that nobody can have reached yet, everyone stops
there, the host sends a `WorldSnapshot` (`src/sim/world_snapshot.gd`: every plain value of the world,
its units, buildings, settlements, players, heroes and the computer players, compressed) and the
others copy it; the screen says "Re-syncing with the host..." for a moment. Only when the worlds hold
different units, or after 5 repairs, does the match stop with "Out of sync". The lobby shows each
player's kind of computer and warns when they differ (Mac and Windows may round some maths
differently, which is what repairs are for). `NetSession` (`src/net/net_session.gd`) is the ENet connection
(clients talk to the host, which passes game messages on); `OnlineGame` holds a running match;
`OnlineScreen` is the lobby. Online there is no pause, no F2/F4/F5, and the menu leaves the match.
If a player leaves, their house stands idle and the others play on; if the host leaves, the match
ends. Two copies on one computer: `tools/online_selftest.gd` (see Checks).

## Heroes

Each player has one hero. At the start of a
match you pick one of your faction's 4 classes; the computer picks one from the map seed. A hero levels
from 1 to 10 within the match (XP for every enemy that dies within 12 m of it, and for settlements
taken) and has a fixed kit: 3 skills with 3 ranks (Q W E) and an ultimate (R) from
level 6. A skill point waits 10 s for your choice (click the "+"), then auto-learn spends it. Skills
autocast unless you switch that off (right click the skill). A fallen hero returns at the hall after
15 s + 3 s per level, for 50 gold per level. Data: `data/heroes.json` (archetypes, classes, skills),
checked by `HeroCatalog.validate()`; rules: `src/sim/hero_system.gd`; UI: `src/ui/hero_bar.gd`.
All six factions have 4 classes, one per archetype they use. Each class has its own
empty-handed 3D body (`assets/heroes3d/<class>.glb`, Tripo models of the project's hero reference images with Mixamo
clips); `HeroGear3D` puts the class's weapons (`assets/weapons3d`, CC0) on its hand bones. In battle the body is
shown as a baked sprite sheet (`assets/unit_anims/hero_<class>.png`); the campaign journey map walks the 3D body.
The tactical map (Tab) still uses the stand-in unit sprite.

**Gear (skirmish loot).** Each neutral settlement drops one item and a potion the first time it is taken;
the hero picks loot up by walking over it. Items follow a classic loot ladder (common, magic, rare, set,
unique) on 7 slots (weapon, armour, helm, off-hand, boots, charm, banner); banners and some uniques give
army auras. The hero bar shows the potions (click to drink), the worn slots (click to take off) and a
6-slot bag (click to wear, right click to drop). Gear stays through death and ends with the match. Data:
`data/items.json` (`ItemCatalog`, with validation); rules: `src/sim/hero_gear.gd`.
The base items are the minor and major designs of the main game's equipment artwork library, its relics
are uniques, and its elemental legendaries are the top drops (item level 8+): poison, fire, frost and
lightning sets, and void, sunlight and blood uniques. Every item shows its painted icon in the hero bar,
its tooltip and on the ground. Icons live in `assets/items/<id>.png`; after changing the items, run
`python3 tools/sync_item_icons.py` (copies them from the main game).

**Story skill trees (campaigns).** A story hero levels slowly to 40 and
spends a point per level in three trees: its archetype's two and its faction's (`data/skill_trees.json`,
20 trees of 8 nodes in 4 rows that open at 0/2/5/8 points spent in the tree). Each tree has a theme
(Slaughter = bloodletting, Bulwark = unkillable, Grace = healing and Resurrection, Siphon = the fallen rise,
Oath = brotherhood...), 3 actives and 5 passives. Passives are talents with a real mechanic
(`StoryTrees.TALENTS`: lifesteal, thorns, cheat death, every Nth blow stuns, army regeneration, the fallen
rise as yours...; `HeroSystem` carries them out, `SimWorld` calls its hooks) or army auras; there are no
plain attribute nodes. Actives teach skills, and 3 basic skills plus 1 ultimate go on Q W E R. `StoryHero`
holds the progress (saveable with `to_dict`/`from_dict`, respec for gold; loading refunds points in nodes
that no longer exist); `HeroSystem.spawn_story_hero()` brings it into a battle. In a campaign K opens the
trees (`src/ui/skill_tree_panel.gd`).

## Campaigns

Each house plays the story of its campaign in
the main game, chapter by chapter (`data/campaigns/campaigns.json`), on handcrafted maps. Chapters alternate
between **hero chapters** (the campaign hero, e.g. Aldous Wren, and a few companions; no economy; NPCs,
dialogue with choices, quests, lairs, shrines and a merchant) and **war chapters** (the RTS with story goals). The hero, its story level and trees, gear, marks (the hero's coin), named companions and every choice (flags)
carry from chapter to chapter (`CampaignProgress`, saved to `user://warbound_campaign_<id>.json`).

A chapter is one mission file, `data/campaigns/<chapter>.json` (the pilot is `ll_harvest.json`, The Last
Light 1, Greyhold Harvest): a map in the skirmish template format but for one fixed layout (`symmetry` none,
`jitter` 0, zones with an `owner` and a `name`, lairs with fixed `guards`; built by `MapGen.build_layout`),
the players, the hero's start, `npcs` (passive units with talk entries and ! / ? marks), `groups` (enemy or
wild bands, guarding a spot or spawned later), `quests` (steps with a done condition, rewards),
`dialogues` (lines, speakers, answers with conditions and actions), `triggers` and the intro and outro
texts. Conditions and actions are a small vocabulary (`StoryMission.CONDITIONS` / `ACTIONS`);
`CampaignCatalog.validate()` checks every mission. Rules: `src/sim/campaign/` (`StoryMission` runs a chapter
on top of `SimWorld`); view: `src/ui/campaign_hud.gd` (quest log, dialogue, intro and outro cards).
On hero maps the hero gets the chapter's `hero_boost`, the band heals out of a fight, and a fallen hero
wakes at the last shrine it touched for a tenth of its marks.

The Last Light 3, Lanterns in the Fen (`ll_lanterns.json`), is the second hero chapter: Sister Edda Vey joins (or
stays), Wren puts out Father Corvin Mire's three lanterns and takes Fenlight; it reads chapter 2's choices
(the refugees, what Grue said). Lair guards in hero chapters should not all fly: a knight cannot hit flyers.

All ten chapters of The Last Light are written (`ll_*.json`): hero chapters 1, 3, 5, 7, 9 and war chapters
2, 4, 6, 8, 10. Choices carry: the refugees (2) bring Ama to chapter 3; Edda, Hrodna's grain (7), Hessa's
debt (5), the Heartwood oath (6) and the Margraves (9) decide who stands with you at the gate in chapter 10.
Companions carried in from an earlier chapter may speak through the mission's `"speakers"` (short id ->
name). Hero chapters: keep relentless units (berserkers, flayers) to one or two per band, since several of
them stagger a lone hero so often that it never swings.

All ten chapters of The Pale Inheritance (Hollow, `ph_*.json`) are written. Ysmay Vane, the
Unburied Regent, leads it, with Sir Orrin Wren from chapter 1 and Father Corvin Mire from chapter 3. On hero
maps a named companion who falls gets back up beside the hero once the fight is over (`RISE_SECONDS`), so the
story's companions are not lost to one bad fight. A mission's `"absent"` lists companions who sit that
chapter out (Orrin, after he falls at Saint Orrin's Rest); they are dropped unless they join again.
Choices that carry to the finale, The Pale Crown (a 1 v 2 against two Ashen broods that also fight each
other): Lady Hesk (2), King Ossric (7), the tombs kept from the fire (8) and the Drowned Cantor spared (3)
bring allies; the Rotwing raised in chapter 9 arrives as a companion. Twice Dead (5) has a dawn timer
(`lose` at 20 minutes, 25 if the bell is silenced).

A war chapter (`"kind": "war"`, e.g. `ll_barrow_roads.json`, The Last Light 2) runs the skirmish economy:
each player has a `home` zone (its hall, workers and resources), settlements can be taken, every enemy
owner gets an `EconomyAi` of the chapter's `ai` difficulty and `max_tier` caps what halls can train. The
story still drives the enemy: groups (and their heroes) are `scripted` units the enemy AI leaves alone,
`"waves": true` groups come again each time a `"repeat"` trigger fires, and a lair with a `keeper` is that
player's (its guards fight for it and it never claims its own lair). Conditions `held` (a zone's owner),
`holds` ([player, settlements]) and `companion`; action `res` (resources for the war chest). A war chapter is
lost when the player holds no settlement; there is no hero respawn or heal between fights.

The campaign screen is the main game's journey screen: a campaign picker, the campaign's journey painting
with a numbered stop per chapter, and a side panel with the chapter's picture and story. The campaign's
hero walks the routes as its live 3D model (`src/menu/journey_map.gd`, a small SubViewport). The paintings
and chapter pictures are the main game's, copied as WebP into `assets/campaign_art/` together with the
journey stops (`data/campaigns/journeys.json`) by `python3 tools/campaign/sync_campaign_art.py`; the intro
and outro cards show the chapter's picture too.

    godot --headless --path . --script res://tools/campaign_probe.gd -- ll_harvest [join|hang|free] [level]   # balance run (ll_lanterns: level 10, ph_living_shore: 10)
    godot --headless --path . --script res://tools/campaign_war_probe.gd -- ll_barrow_roads normal 30 [flag,flag]  # war chapter: a bot plays it
    xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/campaign_shots.gd -- /tmp/camp

## Layout

- `src/sim/`: headless rules (no Nodes). `SimWorld` runs fixed 20 Hz ticks; all randomness goes
  through `GameRng` (copied from the main game); units are processed in id order, so a seed plus the
  same commands always gives the same battle.
- `src/sim/economy.gd`: sectors, capture, workers, gathering, drafting, buildings, hall levels.
  `economy_ai.gd`: the computer player (same commands as a human). `skirmish_scenario.gd`:
  `build_skirmish()` makes a skirmish on a generated map (`map_gen.gd`, `data/map_templates.json`;
  `world.map_info` carries roads, bridges, set pieces, biome regions and sites to the views);
  `build()` is the M1 battle-only field.
- `src/ui/`: the view. It reads `SimWorld` state and only changes it through `Skirmish.act()`
  (`WorldCommands`, also what travels online).
  `skirmish.gd` owns input, HUD and orders; `skirmish_view_3d.gd` draws the 3D world, picks units and
  ground under the mouse, and draws bars and names on an overlay.
- `src/world3d/`: the shared 3D world layer, also meant for the main game's 3D battles.
  `TerrainField` is plain data (heights, a splat map: dirt/rock/forest floor/ash, decoration densities),
  built from a skirmish map (`build_from_sim`) or as a battle field (`build_battlefield`).
  `MapScene3D.create(field, seed)` turns it into chunked terrain, water, seeded trees/rocks/bushes
  (MultiMesh) and the dark red sky. 1 sim cell (32 px) = 1 m; a soldier is 1.8 m tall.
- `data/units.json`: generated by `tools/sync_from_main.py` from the main game's creatures (tune the
  formulas there). `data/rules.json`: counters and combat constants.
- `assets/`: the main game's unit sprites, 3D unit models (`units3d`, with `src/ui/live_unit.gd`),
  grass/water fields, boulders and battle sounds, copied by `tools/sync_from_main.py`. CC0 terrain
  textures and nature models are listed in `assets/LICENSES.md`; all credits are in `CREDITS.md`.
- `art-source/`: raw art inputs (hero reference images, UI and NPC art sheets, Tripo task records) and
  the scripts that made the 3D models. Godot ignores it (`.gdignore`).
- `tools/sync_*.py`: refresh content copied from the main game; set `CAERN_MAIN` to a checkout of it.

## Checks

    ./run_tests.sh [filter]                                   # headless tests
    godot --headless --path . --script res://tools/online_selftest.gd -- host 24690 300 &   # two copies play online;
    godot --headless --path . --script res://tools/online_selftest.gd -- join 24690 300     # both print RESULT ok
    godot --headless --path . --script res://tools/perf.gd    # 300-unit speed check
    xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- /tmp/shots
    xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/hero_shots.gd -- /tmp/hero [class]
    xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/world3d_shots.gd -- /tmp/w3d [seed] [skirmish|battle]
    godot --headless --path . --script res://tools/map_sheet.gd -- /tmp/maps [seeds] [template|all] [players]   # top-down map pictures
    xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/map3d_shots.gd -- /tmp/m3d <template> [seed] [factions]
    xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
        --write-movie /tmp/warbound.avi --fixed-fps 30 --script res://tools/record.gd   # clip (M1 director, needs an M2 update)
