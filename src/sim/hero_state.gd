class_name HeroState
extends RefCounted
## A hero's progress: survives death and respawn (the SimUnit does not). Plain data.

var class_id: String = ""
var owner: int = 0
var level: int = 1
var xp: int = 0
var points: int = 0  ## unspent skill points
var unspent_time: float = 0.0  ## seconds a point has waited (auto-learn after a delay)
var auto_learn: bool = true
## The 4 skills on the bar (Q W E, R = ultimate): the class kit in a skirmish, the chosen
## slots for a story hero ("" = empty slot).
var kit: Array = []
var story: bool = false  ## a campaign hero: levels and skills come from its StoryHero
var ranks: Array[int] = [0, 0, 0, 0]  ## per kit slot (slot 3 = ultimate)
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var autocast: Array[bool] = [true, true, true, false]
var mana: float = 0.0
var max_mana: float = 0.0
var mana_regen: float = 0.0
var power_factor: float = 1.0  ## skill strength multiplier from Power
var attributes: Dictionary = {}  ## attack, defense, power, knowledge (floats)
var unit_id: int = -1  ## the living SimUnit, -1 while dead
var respawn: float = 0.0  ## seconds left until revival (only while dead)
var deaths: int = 0
var aura_timer: float = 0.0
var autocast_timer: float = 0.0
## The cast in progress: walking into range of a target. slot -1 = none.
var cast_slot: int = -1
var cast_target: int = -1
var cast_point: Vector2 = Vector2.ZERO
## Gear: slot -> item (see ItemCatalog), the bag, potions, and the summed item mods.
var worn: Dictionary = {}
var bag: Array[Dictionary] = []
var potions: Dictionary = {"health": 0, "mana": 0}
var potion_cd: float = 0.0
## The hero's own coin (merchants), apart from the army's gold. See heroes.json rules "coin".
var marks: int = 0
var gear: Dictionary = {}  ## stat -> value from worn items, set bonuses and bonus
var bonus: Dictionary = {}  ## stat -> value from story passives
## Story talents (StoryTrees.TALENTS type -> value), empty for a skirmish hero.
var talents: Dictionary = {}
## Counters for the "every Nth" talents: blows swung, blows landed, blows aimed at the hero,
## skills cast and enemies fallen near the hero.
var swings: int = 0
var landed: int = 0
var struck: int = 0
var casts: int = 0
var enemies_fallen: int = 0
## Talent waits (seconds): the hero's own escape from death, a soldier's, the cleansing pulse.
var undying_cd: float = 0.0
var ally_undying_cd: float = 0.0
var cleanse_timer: float = 0.0
