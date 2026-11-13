class_name SimUnit
extends RefCounted
## One unit in the real-time simulation. Plain data; SimWorld runs the rules.

enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD, GATHER, BUILD, DRAFT, CAST, CAPTURE, RETREAT }

var id: int = 0
var owner: int = 0
var type_id: String = ""
var def: Dictionary = {}
var alive: bool = true

var hp: float = 0.0
var max_hp: float = 0.0
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var facing: float = 1.0  ## +1 faces right, -1 faces left (sprites are drawn facing right)

var order: int = Order.IDLE
var order_point: Vector2 = Vector2.ZERO
var anchor: Vector2 = Vector2.ZERO  ## where an idle unit returns to after chasing
var guard_radius: float = 0.0  ## > 0: a lair guard or village militia, roused only this close and chasing at most 1.5x as far
## A campaign NPC: never fights, is never targeted, never pushed (it is left out of the spatial
## grid) and only walks where its mission sends it.
var passive: bool = false
## A name shown over the unit (campaign NPCs, named enemies). "" = none.
var label: String = ""
## Moved by a campaign story (barrow guards, columns of the dead), never by its side's
## computer player.
var scripted: bool = false
var target_id: int = -1
## CAPTURE: the settlement (Sector id) this unit goes to take and stands in until it is taken.
var capture_sector: int = -1
## Shift-queued orders: the SimWorld plan this unit follows, -1 = none.
var plan_id: int = -1
## The last enemy that hurt this unit, and seconds left that an idle unit (or lair guard)
## goes after it even beyond its usual reach (so archers cannot pick it off from range).
var provoked_by: int = -1
var provoked_left: float = 0.0
var path: PackedVector2Array = PackedVector2Array()
var path_i: int = 0

var cooldown: float = 0.0
var acquire_timer: float = 0.0
var repath_timer: float = 0.0
var stuck_timer: float = 0.0
var stuck_ref: Vector2 = Vector2.ZERO
var charge_dist: float = 0.0
var cursed: float = 0.0  ## seconds left of a curse: deals less damage meanwhile
var poison_left: float = 0.0  ## seconds of venom left
var poison_dps: float = 0.0  ## venom damage per second (ignores armour)
var poison_by: int = -1  ## who poisoned it (credited with the kill)
## Other damage over time (rules.json "dots"): kind ("burn", "bleed") -> [seconds left, damage
## per second, attacker id]. A new dose keeps the stronger rate and restarts the clock.
var dots: Dictionary = {}
var group_speed: float = 0.0  ## while marching in a group: the slowest member's speed (0 = none)
var form_id: int = -1  ## the melee block (SimFormation) this unit stands in, -1 = none
var moving: bool = false
## A ranged unit inside a tower: the Building id (see Fortifications), -1 = none. It stands on
## the tower, shoots farther, and only ranged and flying foes can hurt it.
var garrison_of: int = -1

## Workers only.
var job: int = -1  ## resource node id (GATHER) or building id (BUILD, DRAFT)
var gather_timer: float = 0.0
var carry_amount: int = 0
var carry_type: String = ""
var home_sector: int = -1
var idle_time: float = 0.0

## Heroes only (null for every other unit); the rules live in HeroSystem.
var hero: HeroState = null
## Seconds until a summoned unit fades (0 = permanent).
var expires: float = 0.0

## Veteran rank (rules.json "veterans", run by SimWorld): xp counted in the unit's own hit
## points, and the level 1-5 it gives (5 = Ascendant).
var vet_xp: float = 0.0
var veteran: int = 1

## Timed effects from hero skills: kind -> [seconds left, strength]. Kinds: stun, slow,
## haste (attack speed), might (damage dealt), weak (less damage dealt), ward (less damage taken),
## exposed (more damage taken), venom (the unit's blows poison; read by HeroSystem).
## A new effect of the same kind keeps the stronger value and the longer time; they never stack.
var status: Dictionary = {}

## For the view only: seconds since the last attack and since the last hit taken.
var since_attack: float = 99.0
var since_hit: float = 99.0


func radius() -> float:
	return float(def["radius"])


## The game's pace (rules.speed_scale, set by SimWorld): scales walking, attack rate and arrows.
static var speed_scale: float = 1.0


func speed() -> float:
	return float(def["speed"]) * speed_scale


## Per veteran level (index 0 = level 1), set by SimWorld from rules.json "veterans".
static var vet_damage: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
static var vet_ward: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
static var vet_names: Array = ["", "", "", "", ""]


func is_ascendant() -> bool:
	return veteran >= 5


## The name shown for the unit: the Ascendant form carries the title.
func display_name() -> String:
	if label != "":
		return label
	return ("Ascendant " if is_ascendant() else "") + String(def["name"])


func rank_name() -> String:
	return String(vet_names[clampi(veteran, 1, 5) - 1])


func role() -> String:
	return def["role"]


func has_ability(a: String) -> bool:
	return a in def["abilities"]


func is_ranged() -> bool:
	return has_ability("ranged")


## What its blows deal: "melee", "ranged" or "magic" (units.json damage_type).
func damage_type() -> String:
	return UnitCatalog.damage_type_of(def)


## Share of damage of this type it shrugs off (units.json defense; armor_pct if it has none).
func defense(dtype: String) -> float:
	return UnitCatalog.defense_of(def, dtype)


## No blood to lose: undead, spirits, constructs, plants and every structure (bleeding skips them).
func bloodless() -> bool:
	return is_structure() or bool(def.get("bloodless", false))


func is_flying() -> bool:
	return has_ability("flying")


func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


## A wall, gate or tower (Fortifications): kept out of `units`, hit and broken like a unit.
func is_structure() -> bool:
	return def["role"] == "structure"


func is_worker() -> bool:
	return def["role"] == "worker"


func add_status(kind: String, seconds: float, value: float) -> void:
	var cur: Array = status.get(kind, [0.0, 0.0])
	status[kind] = [maxf(float(cur[0]), seconds), maxf(float(cur[1]), value)]


func status_value(kind: String) -> float:
	var cur: Array = status.get(kind, [])
	return float(cur[1]) if not cur.is_empty() else 0.0


func tick_status(dt: float) -> void:
	if status.is_empty():
		return
	for kind in status.keys():
		var cur: Array = status[kind]
		cur[0] = float(cur[0]) - dt
		if float(cur[0]) <= 0.0:
			status.erase(kind)


func stunned() -> bool:
	return status.has("stun")


func is_hero() -> bool:
	return hero != null


## Multipliers the combat rules apply (1.0 when nothing is active).
func damage_factor() -> float:
	return (1.0 + status_value("might")) * (1.0 - status_value("weak")) * (1.0 + float(vet_damage[veteran - 1]))


func taken_factor() -> float:
	return (1.0 - minf(0.8, status_value("ward"))) * (1.0 + status_value("exposed")) * (1.0 - float(vet_ward[veteran - 1]))


func attack_speed_factor() -> float:
	return 1.0 + status_value("haste")


func speed_factor() -> float:
	return 1.0 - minf(0.8, status_value("slow"))
