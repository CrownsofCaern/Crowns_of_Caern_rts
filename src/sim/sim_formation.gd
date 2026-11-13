class_name SimFormation
extends RefCounted
## A melee block: foot soldiers given one order together keep their ranks while they fight.
## Plain data; SimWorld runs the rules (see SimWorld._step_formations and _think_block).
##
## Learned from the 3D battle screen (playtests): fights look best when each side's
## melee stands in a block and the blocks grind into each other. The front row fights,
## the rows behind wait in their places and step up as the front falls. Cavalry, flyers
## and heroes stay free, and any unit given its own order leaves its block.

## Roles that stand in a block. Ranged and support take the back rows when the group
## also has melee foot; a group with no melee foot forms no block.
const MELEE_ROLES := ["heavy", "infantry"]
const BACK_ROLES := ["ranged", "support"]
## Fewer melee foot than this fight loose (a hero's escort, a few raiders).
const MIN_MELEE := 4

var id: int = 0
var owner: int = 0
## Members, front rank first (melee before ranged, then by id). Dead ones are dropped
## each tick by SimWorld.
var members: Array[int] = []
## The order the block carries out: MOVE, ATTACK_MOVE, IDLE or HOLD (SimUnit.Order).
var mode: int = SimUnit.Order.IDLE
## Where the order sends the block, and where an idle block returns after a fight.
var dest: Vector2 = Vector2.ZERO
var anchor: Vector2 = Vector2.ZERO
## While fighting: the block's middle, and the way its front faces.
var center: Vector2 = Vector2.ZERO
var fwd: Vector2 = Vector2.RIGHT
## Figures per row at the start; rows shrink in depth, not width, as the block loses men.
var cols: int = 1
## Distance between neighbouring places (px).
var step: float = 30.0
## The slowest member's speed (px/s): the block marches at this pace.
var pace: float = 60.0
## Each member's place relative to `center`: unit id -> offset.
var slots: Dictionary = {}
var slotted_count: int = -1

## The enemy the block closes on (-1 = none) and whether it fights right now.
var foe_id: int = -1
var last_foe: int = -1
var engaged: bool = false
## Fallback: the foe is behind rocks or water, so members fight one by one.
var loose: bool = false
var acquire_timer: float = 0.0
## Seconds since the block last saw a foe (a short grace keeps it formed between blows).
var calm: float = 0.0
## Set by members during a tick when one of them has a foe within reach.
var contact: bool = false
var contact_prev: bool = false


func slot_of(unit_id: int) -> Vector2:
	return center + slots.get(unit_id, Vector2.ZERO)


## Distance from the middle to the front row.
func front_depth() -> float:
	var rows := int(ceil(float(members.size()) / float(maxi(1, mini(cols, members.size())))))
	return float(rows - 1) * 0.5 * step


## Sorting key: melee foot first, then ranged and support, then by id.
static func rank_of(u: SimUnit) -> int:
	var r := u.role()
	if r == "heavy":
		return 0
	if r == "infantry":
		return 1
	if r == "ranged":
		return 2
	return 3


## Whether this unit takes a place in a block (cavalry, flyers, heroes, workers and
## campaign NPCs keep moving freely).
static func can_join(u: SimUnit) -> bool:
	if u.is_flying() or u.is_hero() or u.is_worker() or u.passive or u.guard_radius > 0.0:
		return false
	return u.role() in MELEE_ROLES or u.role() in BACK_ROLES


static func is_melee_foot(u: SimUnit) -> bool:
	return not u.is_flying() and not u.is_hero() and u.role() in MELEE_ROLES and not u.is_ranged()
