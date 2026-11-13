class_name EconomyAi
extends RefCounted
## A computer player for the sector skirmish. It only uses the same commands a human has:
## build dwellings, upgrade the hall, train, attack-move, capture, retreat.
##
## How well it plays comes from data/economy.json ai_difficulty: besides its pace, the smarter
## levels send small squads to take free settlements at once (expand), weigh armies by their
## strength rather than their head count before they attack (attack_edge), call a losing wave
## back to the capital (regroup_ratio), and pull hurt veterans out of a fight to rest until
## they are fit again (protect_rank, retreat_hp, rejoin_hp). The hardest levels gather more
## (income_bonus).

const DIFFICULTIES := ["easy", "normal", "hard", "very_hard", "brutal"]
const SHORT_PILES := 1.5  ## below this many full piles' worth of timber or ore left, it expands for more

var owner: int = 1
var enabled: bool = true
var difficulty: String = "normal"  ## data/economy.json ai_difficulty
var think_every: float = 2.0
var army_to_attack: int = 12  ## grows after each wave
var wave_growth: int = 4
var expand: int = 0  ## capture squads out at once (0 = settlements wait for the waves)
var attack_edge: float = 0.0  ## strength ratio a wave needs over its target (0 = count heads)
var regroup_ratio: float = 0.0  ## a wave holding less than this share of the foe's strength falls back (0 = never)
var protect_rank: int = 0  ## veterans of this rank or more retreat when hurt (0 = never)
var retreat_hp: float = 0.3  ## the health share below which they go
var rejoin_hp: float = 0.8  ## and the share at which they fight again
var hall_army: int = 6  ## soldiers it keeps before raising the hall (plus 2 per hall level)
var income_bonus: float = 0.0  ## extra share of every load and of settlement gold
var _timer: float = 0.0
var _wave_target: int = -1
var _errand: int = -1  ## the lair the hero and its escort are clearing (-1 = none)
var _refit: int = -1  ## the dwelling being emptied for its upgrade (-1 = none)
var _refit_tier: int = 0  ## and the tier it upgrades
var _squads: Dictionary = {}  ## sector id -> ids of the units sent to take it
var _resting: Dictionary = {}  ## id -> true: hurt veterans sent home to mend
var _calm_until: int = 0  ## world tick before which no new wave sets out (after a call-back)


func _init(p_owner: int = 1, p_difficulty: String = "normal") -> void:
	owner = p_owner
	difficulty = p_difficulty if p_difficulty in DIFFICULTIES else "normal"
	var d: Dictionary = UnitCatalog.get_default().economy.get("ai_difficulty", {}).get(difficulty, {})
	think_every = float(d.get("think_every", think_every))
	army_to_attack = int(d.get("first_wave", army_to_attack))
	wave_growth = int(d.get("wave_growth", wave_growth))
	expand = int(d.get("expand", expand))
	attack_edge = float(d.get("attack_edge", attack_edge))
	regroup_ratio = float(d.get("regroup_ratio", regroup_ratio))
	protect_rank = int(d.get("protect_rank", protect_rank))
	retreat_hp = float(d.get("retreat_hp", retreat_hp))
	rejoin_hp = float(d.get("rejoin_hp", rejoin_hp))
	hall_army = int(d.get("hall_army", hall_army))
	income_bonus = float(d.get("income_bonus", income_bonus))


func update(world: SimWorld) -> void:
	if not enabled:
		return
	_timer -= world.dt
	if _timer > 0.0:
		return
	_timer = think_every
	var eco := world.economy
	var pl := eco.player(owner)
	if pl == null:
		return
	pl.income_bonus = income_bonus
	var home := eco.hall_of(owner)
	if home == null:
		return
	_build(world, eco, home)
	if pl.hall_upgrading <= 0.0 and (_has_all_dwellings(eco) or _army_units(world).size() >= hall_army + 2 * eco.player(owner).hall_level):
		eco.command_upgrade_hall(owner)
	_upgrade_dwellings(eco)
	_worker_upgrades(eco, home)
	_faction_buildings(world, eco, home)
	_train(world, eco)
	_develop(world, eco)
	_rebalance_gatherers(world, eco)
	if expand > 0:
		_tune_gather(eco)
	_hero_errands(world, eco)
	_army(world, eco, home)


func _has_all_dwellings(eco: Economy) -> bool:
	for t in range(1, eco.max_tier(owner) + 1):
		if _dwelling(eco, t) == null:
			return false
	return true


func _dwelling(eco: Economy, tier: int) -> Building:
	return eco.dwelling_of(owner, tier)


func _build(world: SimWorld, eco: Economy, home: Sector) -> void:
	for b in eco.buildings:
		if b.owner == owner and not b.done():
			# Keep a builder on every site.
			var busy := false
			for u in eco.workers_of(owner):
				if u.order == SimUnit.Order.BUILD and u.job == b.id:
					busy = true
					break
			if not busy and eco.sector_at(b.pos).owner == owner:
				var ws := _nearest_workers(eco, b.pos, 1)
				if not ws.is_empty():
					eco.command_help_build(ws, b.id)
			if b.kind == "dwelling":
				return  # one dwelling at a time
	for t in range(1, eco.max_tier(owner) + 1):
		if _dwelling(eco, t) != null:
			continue
		if not eco.player(owner).can_pay(eco.dwelling_cost(t)):
			return
		var spot := find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
		if spot == Vector2.INF:
			return
		var builders := _nearest_workers(eco, spot, 2)
		if builders.is_empty():
			return
		eco.command_build(builders, owner, "dwelling", t, spot)
		return


## Rings around the settlement centre; the first free spot wins.
static func find_spot(eco: Economy, s: Sector, radius: float) -> Vector2:
	var d0 := float(eco.e.get("settlement_clearance", 110.0)) + radius + 10.0
	for ring in range(0, 6):
		var d := d0 + ring * (radius * 1.6 + 20.0)
		var steps := 10 + ring * 4
		for i in steps:
			var a := float(i) / float(steps) * TAU + ring * 0.37
			var p := s.center + Vector2(cos(a), sin(a)) * d
			if eco.can_place(s.owner, p, radius):
				return p
	return Vector2.INF


func _nearest_workers(eco: Economy, p: Vector2, n: int) -> Array:
	var ws := eco.workers_of(owner)
	ws.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var da := a.pos.distance_squared_to(p)
		var db := b.pos.distance_squared_to(p)
		return da < db if da != db else a.id < b.id)
	var out: Array = []
	for u in ws:
		if u.order == SimUnit.Order.DRAFT:
			continue
		out.append(u.id)
		if out.size() >= n:
			break
	return out


func _army_units(world: SimWorld) -> Array:
	var army: Array = []
	for u in world.units:
		if u.owner == owner and not u.is_worker() and not u.scripted:
			army.append(u)
	return army


func _train(world: SimWorld, eco: Economy) -> void:
	# Keep enough workers gathering; draft the rest.
	var free_workers := 0
	for u in eco.workers_of(owner):
		if u.order != SimUnit.Order.DRAFT:
			free_workers += 1
	var queued := 0
	for b in eco.buildings:
		if b.owner == owner:
			queued += b.queue.size()
	var keep := 4 + eco.sectors_of(owner)
	# Save up for the next hall level once the army can hold the line.
	if _saving_for_hall(world, eco):
		return
	if free_workers - queued <= keep:
		# Still train what needs no worker (the Hollow raise their dead), but only
		# while it is free of workers: past the cap they would cost a gatherer.
		for t in eco.twist(owner, "no_worker_tiers", []):
			var b := _dwelling(eco, int(t))
			if b != null and b.done() and b.queue.size() < 2 and eco.raises_without_worker(owner, int(t)):
				eco.command_train(owner, b.id, int(t))
		return
	# Highest tier first.
	for t in range(eco.max_tier(owner), 0, -1):
		var b := _dwelling(eco, t)
		if b != null and b.done() and b.queue.size() < 2 and b.id != _refit and b.refit_left <= 0.0:
			eco.command_train(owner, b.id, t)


## True while it holds back its spending for the next hall level: once every dwelling stands and
## the army can hold the line. The smart levels (expand > 0) don't wait for a resource none of
## their land yields (they go and take some instead, see _wanted).
func _saving_for_hall(world: SimWorld, eco: Economy) -> bool:
	var pl := eco.player(owner)
	var cost := eco.hall_upgrade_cost(owner)
	if pl.hall_upgrading > 0.0 or cost.is_empty() or not _has_all_dwellings(eco):
		return false
	var army := _army_units(world)
	if army.size() < 6 or pl.can_pay(cost):
		return false
	if expand <= 0:
		return true
	# The smart levels keep training while the rival army is the stronger, and never wait for
	# a resource none of their land yields.
	return power_of(army) >= power_of(_rival_army(world)) * 0.9 and _missing(eco, cost).is_empty()


## The resources of a cost it can neither pay nor gather on its own land (gold always flows).
func _missing(eco: Economy, cost: Dictionary) -> Array:
	var pl := eco.player(owner)
	var out: Array = []
	for r: String in cost:
		if r == "gold" or pl.amount(r) >= int(cost[r]):
			continue
		var has := false
		for n in eco.nodes:
			if n.resource == r and eco.sectors[n.sector].owner == owner:
				has = true
				break
		if not has:
			out.append(r)
	return out


## Resources the next hall level needs that none of its land yields: land with them is worth more.
func _wanted(eco: Economy) -> Array:
	var cost := eco.hall_upgrade_cost(owner)
	return [] if cost.is_empty() else _missing(eco, cost)


## Buys dwelling upgrades once the hall is past level II (or at its top, or rising): the highest
## tier it can pay for. The chosen dwelling stops taking orders until its queue runs out.
func _upgrade_dwellings(eco: Economy) -> void:
	var pl := eco.player(owner)
	if _refit >= 0:
		var b := eco.building(_refit)
		if b == null or not eco.can_upgrade_dwelling(b, _refit_tier):
			_refit = -1
		elif b.queue.is_empty() and not b.has_recruit:
			if eco.command_upgrade_dwelling(owner, b.id, _refit_tier) \
					or not pl.can_pay(eco.dwelling_upgrade_cost(owner, _refit_tier)):
				_refit = -1
		return
	var hall_done := eco.hall_upgrade_cost(owner).is_empty()
	if pl.hall_level < 3 and not hall_done:
		return
	if pl.hall_upgrading <= 0.0 and not hall_done and pl.can_pay(eco.hall_upgrade_cost(owner)):
		return  # the hall comes first
	for t in range(eco.max_tier(owner), 0, -1):
		var b := _dwelling(eco, t)
		if b != null and eco.can_upgrade_dwelling(b, t) and pl.can_pay(eco.dwelling_upgrade_cost(owner, t)):
			_refit = b.id
			_refit_tier = t
			return


## The smart levels steer their gatherers (the same mix a player sets in the top bar): a rare
## stays at one share until a stock of RARE_STOCK lies in store, then none, so the hands go
## to timber and ore, which every unit and building needs by the hundred.
const RARE_STOCK := 60


func _tune_gather(eco: Economy) -> void:
	var pl := eco.player(owner)
	for r in eco.gather_resources(owner):
		if r == "wood" or r == "ore" or r == "gold":
			continue
		var want := 1 if pl.amount(r) < RARE_STOCK else 0
		if eco.gather_weight(owner, r) != want:
			eco.set_gather_weight(owner, r, want)


## Moves a gatherer from timber to ore (or back) when one pile of stock is far bigger.
func _rebalance_gatherers(world: SimWorld, eco: Economy) -> void:
	var pl := eco.player(owner)
	var wood := pl.amount("wood")
	var ore := pl.amount("ore")
	var short := ""
	var rich := ""
	if wood > ore * 2 + 100:
		short = "ore"
		rich = "wood"
	elif ore > wood * 2 + 100:
		short = "wood"
		rich = "ore"
	else:
		return
	for u in eco.workers_of(owner):
		if u.order == SimUnit.Order.GATHER and eco.node(u.job) != null and eco.node(u.job).resource == rich:
			var best: ResNode = null
			for n in eco.nodes:
				if n.resource == short and eco.sectors[n.sector].owner == owner and not n.depleted():
					if best == null or n.pos.distance_to(u.pos) < best.pos.distance_to(u.pos):
						best = n
			if best != null:
				eco.command_gather([u.id], best.id)
			return


## Worker upgrades: from hall level 2 it keeps a storehouse at home, and buys the next level of
## a resource's upgrade there whenever it could pay for it twice over (common goods first; easy
## computers stop after the first level). Training always comes first: twice over leaves enough.
func _worker_upgrades(eco: Economy, home: Sector) -> void:
	var pl := eco.player(owner)
	if pl.hall_level < 2:
		return
	var stores: Array[Building] = []
	for b in eco.buildings:
		if b.owner == owner and b.kind == "storehouse":
			stores.append(b)
	if stores.is_empty():
		var c: Dictionary = eco.e["storehouse"]["cost"]
		var doubled := {}
		for r in c:
			doubled[r] = int(c[r]) * 2
		if pl.can_pay(doubled):
			var spot := find_spot(eco, home, float(eco.e["storehouse"]["radius"]))
			var ws := _nearest_workers(eco, home.center, 1)
			if spot != Vector2.INF and not ws.is_empty():
				eco.command_build(ws, owner, "storehouse", 0, spot)
		return
	var cap := 1 if difficulty == "easy" else eco.gather_levels_max()
	for r in eco.gather_resources(owner):
		if eco.gather_level(owner, r) >= cap:
			continue
		var cost := eco.gather_upgrade_cost(owner, r)
		var doubled := {}
		for k in cost:
			doubled[k] = int(cost[k]) * 2
		if not pl.can_pay(doubled):
			continue
		for b in stores:
			if eco.gather_upgrade_lock(owner, b.id, r) == "":
				eco.command_gather_upgrade(owner, b.id, r)
				return


## Grows a settlement when gold piles up, and builds storehouses in waystone sectors with piles.
func _develop(world: SimWorld, eco: Economy) -> void:
	var pl := eco.player(owner)
	for s in eco.sectors:
		if s.owner != owner or s.unsettled > 0.0:
			continue
		if s.size == "waystone":
			var has_store := false
			for b in eco.buildings:
				if b.owner == owner and b.kind == "storehouse" and eco.sector_at(b.pos) == s:
					has_store = true
			var piles := 0
			for n in eco.nodes:
				if n.sector == s.id and eco.uses(owner, n.resource) and not n.depleted():
					piles += 1
			if not has_store and piles > 0 and pl.can_pay(eco.e["storehouse"]["cost"]):
				var spot := find_spot(eco, s, float(eco.e["storehouse"]["radius"]))
				var ws := _nearest_workers(eco, s.center, 2)
				if spot != Vector2.INF and not ws.is_empty():
					eco.command_build(ws, owner, "storehouse", 0, spot)
					return
			continue
		var cost := eco.settlement_upgrade_cost(s)
		if s.growing <= 0.0 and not cost.is_empty() and pl.hall_level >= 2 and not (expand > 0 and _saving_for_hall(world, eco)):
			var doubled := {}
			for r in cost:
				doubled[r] = int(cost[r]) * 2
			if pl.can_pay(doubled):
				eco.command_upgrade_settlement(owner, s.id)
				return


## Timber or ore (what every army is built from) when the piles in our sectors are nearly gone:
## less than SHORT_PILES full piles' worth left. Endless piles never run short.
func _running_short(eco: Economy) -> Array[String]:
	var out: Array[String] = []
	var left := eco.remaining(owner)
	for r: String in ["wood", "ore"]:
		if not eco.uses(owner, r):
			continue
		var have := int(left.get(r, 0))
		var pile := eco.pile_amount(r)
		if have >= 0 and pile > 0 and have < int(SHORT_PILES * pile):
			out.append(r)
	return out



# --- Strength --------------------------------------------------------------------------

## A group's fighting strength: the square root of its damage per second times the blows it
## can take (Lanchester's square law, so twice the troops count about twice). Veteran ranks,
## auras and curses are in through the units' own factors; hurt units count for less.
static func power_of(units: Array) -> float:
	var dps := 0.0
	var ehp := 0.0
	for u: SimUnit in units:
		if u.is_worker() or not u.alive:
			continue
		dps += float(u.def["damage"]) / maxf(0.1, float(u.def["attack_interval"])) * u.damage_factor()
		ehp += u.hp / maxf(0.2, 1.0 - float(u.def["armor_pct"])) / maxf(0.2, u.taken_factor())
	return sqrt(dps * ehp)


## The arrows and walls of a hall standing in this sector, as a power like power_of's.
static func hall_power(world: SimWorld, s: Sector) -> float:
	var a := world.defense.arrows_of(s)
	if a.is_empty():
		return 0.0
	var dps := float(a.get("count", 0)) * float(a.get("damage", 0.0)) / maxf(0.1, float(a.get("interval", 1.0)))
	var hall := world.defense.hall_structure(s)
	var hp := hall.hp / maxf(0.2, 1.0 - float(hall.def["armor_pct"])) if hall != null else 0.0
	return sqrt(dps * hp)


## Soldiers of anyone but `owner` near a point (militia and lair guards included).
func _foes_near(world: SimWorld, p: Vector2, radius: float) -> Array:
	var out: Array = []
	for u: SimUnit in world.nearby(p, radius):
		if u.owner != owner and not u.is_worker() and not u.is_structure() and not u.passive:
			out.append(u)
	return out


## Soldiers of rival players (not neutrals) near a point.
func _rivals_near(world: SimWorld, p: Vector2, radius: float) -> Array:
	var out: Array = []
	for u: SimUnit in _foes_near(world, p, radius):
		if u.owner != Economy.NEUTRAL:
			out.append(u)
	return out


func _rival_army(world: SimWorld) -> Array:
	var out: Array = []
	for u in world.units:
		if u.owner != owner and u.owner != Economy.NEUTRAL and not u.is_worker() and not u.scripted \
				and not u.passive and u.alive:
			out.append(u)
	return out


static func _centroid(units: Array) -> Vector2:
	var c := Vector2.ZERO
	for u: SimUnit in units:
		c += u.pos
	return c / maxf(1.0, float(units.size()))


# --- Threats at home -------------------------------------------------------------------

## Enemy soldiers inside one of our sectors (near its centre or our buildings): where the
## most stand, or INF.
func _threat(world: SimWorld, eco: Economy) -> Vector2:
	var best := Vector2.INF
	var best_n := 0
	for s in eco.sectors:
		if s.owner != owner:
			continue
		var foes := _rivals_near(world, s.center, 520.0 if s.home_of != owner else 680.0)
		if foes.size() > best_n:
			best_n = foes.size()
			best = _centroid(foes)
	return best


# --- The army ------------------------------------------------------------------------

func _army(world: SimWorld, eco: Economy, home: Sector) -> void:
	var army := _army_units(world)
	_tidy(world, eco)
	if army.is_empty():
		return
	if protect_rank > 0:
		_care_for_veterans(world, eco, army, home)
	var hero := world.heroes.hero_unit(owner)
	var free: Array = []  ## not resting, not on a capture errand
	for u: SimUnit in army:
		if not _resting.has(u.id) and not _in_squad(u.id):
			free.append(u)
	var threat := _threat(world, eco)
	if threat != Vector2.INF:
		_defend(world, eco, army, free, threat, home)
		return
	if regroup_ratio > 0.0 and _wave_target >= 0 and _losing(world, eco, free):
		return
	if expand > 0:
		_expand(world, eco, free, hero, home)
		free = free.filter(func(u: SimUnit) -> bool: return not _in_squad(u.id))
	_wave(world, eco, free)


## Sends everyone who can help against raiders in our land. With the smart levels a squad
## far off finishes its errand, hurt veterans help only at home, and an army that cannot win
## in the field falls back to the hall, which shoots for it.
func _defend(world: SimWorld, eco: Economy, army: Array, free: Array, threat: Vector2, home: Sector) -> void:
	var ids: Array = []
	var foes := _rivals_near(world, threat, 600.0)
	var need := power_of(foes) * 1.3
	var helpers: Array = []
	for u: SimUnit in army:
		if _resting.has(u.id) and u.pos.distance_to(threat) > 700.0:
			continue  # a hurt veteran only fights on its doorstep
		if _in_squad(u.id) and u.pos.distance_to(threat) > 1500.0:
			continue  # a squad far off finishes its errand
		helpers.append(u)
	var at_home := threat.distance_to(home.center) < 700.0
	if regroup_ratio > 0.0 and not at_home and power_of(helpers) < need * regroup_ratio / 1.3:
		# Too many of them out there: gather at the hall and let its arrows help.
		var out: Array = []
		for u: SimUnit in helpers:
			if u.pos.distance_to(home.center) > 400.0 and u.order != SimUnit.Order.RETREAT:
				out.append(u.id)
		if not out.is_empty():
			world.command_retreat(out)
		_wave_target = -1
		return
	for u: SimUnit in helpers:
		_leave_squad(u.id)
		if u.order != SimUnit.Order.ATTACK_MOVE or u.order_point.distance_to(threat) > 300.0:
			ids.append(u.id)
	if not ids.is_empty():
		world.command_attack_move(ids, threat)
	_wave_target = -1


## Seconds a called-back army gathers at home before the next wave.
const REGROUP_SECONDS := 45


## True (and the wave is called back) when the units out on a wave stand in a fight they
## are losing badly: they run for the capital, picking no fights on the way, and the next
## wave waits until the army has grown.
func _losing(world: SimWorld, eco: Economy, free: Array) -> bool:
	var out: Array = []
	for u: SimUnit in free:
		if u.order in [SimUnit.Order.ATTACK_MOVE, SimUnit.Order.ATTACK, SimUnit.Order.CAPTURE]:
			out.append(u)
	if out.is_empty():
		return false
	var c := _centroid(out)
	var foes := _foes_near(world, c, 560.0)
	if foes.is_empty():
		return false
	var near: Array = []
	for u: SimUnit in out:
		if u.pos.distance_to(c) < 480.0:
			near.append(u)
	var theirs := power_of(foes)
	var s := eco.sector_at(c)
	if s != null and s.owner != owner and s.center.distance_to(c) < 450.0:
		theirs += hall_power(world, s)
	if power_of(near) >= theirs * regroup_ratio:
		return false
	var ids: Array = []
	for u: SimUnit in out:
		ids.append(u.id)
	world.command_retreat(ids)
	_wave_target = -1
	army_to_attack = mini(army_to_attack + wave_growth, 40)
	_calm_until = world.tick + REGROUP_SECONDS * world.tick_rate
	return true


## Starts or steers a wave: the cheapest sector by distance, worth more if it pays well or
## holds our rares, and never one whose defenders are stronger than the wave.
func _wave(world: SimWorld, eco: Economy, army: Array) -> void:
	if army.is_empty():
		return
	if _wave_target >= 0 and eco.sectors[_wave_target].owner == owner:
		_wave_target = -1
		army_to_attack = mini(army_to_attack + wave_growth, 40)
	var short := _running_short(eco)
	var mine := power_of(army)
	var rivals := _rival_army(world)
	var theirs := power_of(rivals)
	var early := false  # a smaller wave sent out because timber or ore runs dry at home
	if _wave_target < 0:
		if world.tick < _calm_until:
			return
		var ready := army.size() >= army_to_attack
		if attack_edge > 0.0 and army.size() >= 6 and mine >= theirs * attack_edge * 1.5:
			ready = true  # a clear edge: no need to wait for the full count
		if not ready:
			# Piles running dry at home: a smaller force goes out early to take ground that still has them.
			early = not short.is_empty() and army.size() >= maxi(4, army_to_attack / 2)
			if not early:
				return
	var centroid := _centroid(army)
	var wanted := _wanted(eco) if expand > 0 else []
	var best: Sector = null
	var best_score := INF
	for s in eco.sectors:
		if s.owner == owner or (not eco.can_capture(owner, s) and not _is_capital(eco, s)):
			continue
		if _squads.has(s.id):
			continue
		var held := _foes_near(world, s.center, 420.0)
		var defence := power_of(held) + hall_power(world, s)
		if attack_edge > 0.0:
			if defence * attack_edge > mine:
				continue
		elif held.size() > army.size():
			continue
		var value := 1.0 + float(eco.settlement(s)["gold_per_min"]) / 60.0
		var feeds_short := false
		for n in eco.nodes:
			if n.sector != s.id or n.depleted() or not eco.uses(owner, n.resource):
				continue
			if n.resource in short:
				value += 1.5 * n.fraction()  # what we are running out of counts most
				feeds_short = true
			elif n.resource != "wood" and n.resource != "ore":
				value += (3.0 if n.resource in wanted else 1.0) * n.fraction()
		if early and not feeds_short:
			continue  # an early wave only goes for the piles we lack
		if s.owner >= 0 and s.owner != Economy.NEUTRAL:
			value += 1.0  # taking from the enemy counts twice
			if s.home_of == s.owner:
				# Only storm a home with a clear edge over the house's whole army.
				if attack_edge > 0.0:
					if mine < (theirs + hall_power(world, s)) * attack_edge * 1.2:
						continue
					value += 2.0  # the capital ends the game
				elif army.size() < rivals.size() * 1.3:
					continue
		var score := s.center.distance_to(centroid) / value
		if score < best_score:
			best_score = score
			best = s
	if best == null:
		return
	var ids: Array = []
	for u: SimUnit in army:
		if u.order == SimUnit.Order.IDLE or best.id != _wave_target:
			ids.append(u.id)
	if ids.is_empty():
		return
	if best.id != _wave_target:
		_feast(world, eco)  # a new wave sets out: hold the feast now
	_wave_target = best.id
	world.command_attack_move(ids, best.center)


func _is_capital(eco: Economy, s: Sector) -> bool:
	return s.home_of >= 0 and s.owner == s.home_of and s.owner != owner


# --- Taking the land fast ---------------------------------------------------------------

## Small squads go out at once to take the free settlements and waystones around, nearest
## and richest first, each just strong enough for the militia or guards there. Up to
## `expand` squads at a time; a squad that wins waits in its new settlement for the wave.
func _expand(world: SimWorld, eco: Economy, free: Array, hero: SimUnit, home: Sector) -> void:
	if _squads.size() >= expand:
		return
	var pool: Array = []
	for u: SimUnit in free:
		if u != hero and u.order == SimUnit.Order.IDLE:
			pool.append(u)
	if pool.is_empty():
		return
	var wanted := _wanted(eco)
	var rivals := _rival_army(world)
	var bold := power_of(free) >= power_of(rivals) * maxf(1.0, attack_edge)
	var spots: Array = []  ## [score, id]
	for s in eco.sectors:
		if s.owner != -1 or not eco.can_capture(owner, s) or _squads.has(s.id):
			continue
		if not bold and _rival_home_dist(eco, s.center) < s.center.distance_to(home.center):
			continue  # on their half: only with an army that can stand up to theirs
		if not _rivals_near(world, s.center, 900.0).is_empty():
			continue  # contested: that is the wave's job
		var value := 1.0 + float(eco.settlement(s)["gold_per_min"]) / 60.0
		for n in eco.nodes:
			if n.sector == s.id and eco.uses(owner, n.resource):
				value += 3.0 if n.resource in wanted else 0.5
		spots.append([s.center.distance_to(home.center) / value, s.id])
	spots.sort()
	for sp: Array in spots:
		if _squads.size() >= expand or pool.is_empty():
			return
		var s := eco.sector_by_id(int(sp[1]))
		var need := power_of(_foes_near(world, s.center, 400.0)) * 2.2
		pool.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
			var da := a.pos.distance_squared_to(s.center)
			var db := b.pos.distance_squared_to(s.center)
			return da < db if da != db else a.id < b.id)
		var group: Array = []
		for u: SimUnit in pool:
			group.append(u)
			if power_of(group) >= need and group.size() >= (1 if need <= 0.0 else 2):
				break
		if power_of(group) < need or group.size() > 10:
			continue  # not strong enough yet: try a softer one
		var ids: Array = []
		for u: SimUnit in group:
			ids.append(u.id)
			pool.erase(u)
		if world.command_capture(ids, s.id):
			_squads[s.id] = ids


## How far the nearest rival capital is from a point (INF: none).
func _rival_home_dist(eco: Economy, p: Vector2) -> float:
	var best := INF
	for s in eco.sectors:
		if s.home_of >= 0 and s.home_of != owner and s.owner == s.home_of:
			best = minf(best, s.center.distance_to(p))
	return best


func _in_squad(id: int) -> bool:
	for k in _squads:
		if id in _squads[k]:
			return true
	return false


func _leave_squad(id: int) -> void:
	for k in _squads.keys():
		var ids: Array = _squads[k]
		ids.erase(id)
		if ids.is_empty():
			_squads.erase(k)


## Forgets squads whose settlement fell to us (or can't be taken), the dead, and veterans
## healed enough to fight again.
func _tidy(world: SimWorld, eco: Economy) -> void:
	for k in _squads.keys():
		var s := eco.sector_by_id(int(k))
		var alive: Array = []
		for id in _squads[k]:
			var u := world.get_unit(int(id))
			if u != null and u.alive and u.order == SimUnit.Order.CAPTURE:
				alive.append(id)
		if s == null or s.owner == owner or alive.is_empty():
			_squads.erase(k)
		else:
			_squads[k] = alive
	for id in _resting.keys():
		var u := world.get_unit(int(id))
		if u == null or not u.alive or u.hp_ratio() >= rejoin_hp:
			_resting.erase(id)


# --- Veterans ------------------------------------------------------------------------

## A unit of protect_rank or more that is badly hurt runs home before it dies (its rank is
## worth more than one fight), and rests there, by a healing building when the house has
## one, until it is fit again. Ascendants go a little sooner.
func _care_for_veterans(world: SimWorld, eco: Economy, army: Array, home: Sector) -> void:
	var out: Array = []
	for u: SimUnit in army:
		if u.is_hero() or u.veteran < protect_rank or _resting.has(u.id):
			continue
		var limit := retreat_hp + (0.1 if u.is_ascendant() else 0.0)
		if u.hp_ratio() < limit and u.pos.distance_to(home.center) > 450.0:
			out.append(u.id)
	if not out.is_empty():
		for id in out:
			_leave_squad(int(id))
			_resting[id] = true
		world.command_retreat(out)
	var mend := _mending_spot(eco)
	if mend == Vector2.INF:
		return
	var go: Array = []
	for id in _resting:
		var u := world.get_unit(int(id))
		if u != null and u.order == SimUnit.Order.IDLE and u.pos.distance_to(mend) > 90.0:
			go.append(u.id)
	if not go.is_empty():
		world.command_move(go, mend)


## Beside our first finished building that heals the troops around it (INF: none).
func _mending_spot(eco: Economy) -> Vector2:
	for b in eco.buildings:
		if b.owner == owner and b.kind == "special" and b.done():
			var fx: Dictionary = eco.def_of(b)["effect"]
			if fx.has("own") and (fx["own"] as Dictionary).has("heal"):
				return b.pos + Vector2(0, float(eco.e["dwelling"]["radius"]) * 0.5)
	return Vector2.INF


# --- Faction buildings ---------------------------------------------------------------

## Once every dwelling it may have stands, it builds its house buildings (one of each; towers two)
## and uses the ones with buttons: research at once, trade and the market when a stock runs short.
func _faction_buildings(world: SimWorld, eco: Economy, home: Sector) -> void:
	var pl := eco.player(owner)
	if not _has_all_dwellings(eco):
		return
	for b in eco.buildings:
		if b.owner == owner and not b.done():
			return  # one site at a time
	for d: Dictionary in eco.special_defs(pl.faction):
		var want := 2 if d["effect"]["kind"] == "tower" else 1
		if eco.special_count(owner, d["id"]) >= mini(want, int(d["limit"])) or eco.special_lock_text(owner, d["id"]) != "":
			continue
		if not pl.can_pay(d["cost"]):
			continue
		var spot := find_spot(eco, home, float(eco.e["dwelling"]["radius"]))
		var builders := _nearest_workers(eco, spot, 2)
		if spot == Vector2.INF or builders.is_empty():
			return
		eco.command_build(builders, owner, "special", 0, spot, d["id"])
		return
	var sp := world.specials
	for b in eco.buildings:
		if b.owner != owner or b.kind != "special" or not b.done():
			continue
		var fx: Dictionary = eco.def_of(b)["effect"]
		match String(fx["kind"]):
			"research":
				if sp.can_use(owner, b.id) == "":
					sp.use(owner, b.id)
			"trade":
				var short := false
				for r in fx["take"]:
					short = short or pl.amount(r) < 10
				if short and eco.workers_of(owner).size() > 8 and sp.can_use(owner, b.id) == "":
					sp.use(owner, b.id)
			"market":
				if pl.amount("gold") < 600:
					continue
				for r in pl.res:
					if r != "gold" and pl.amount(r) < (40 if r in FactionBuildings.COMMON else 4):
						var arg := "gold>%s" % r
						if sp.can_use(owner, b.id, arg) == "":
							sp.use(owner, b.id, arg)
							break


func _feast(world: SimWorld, eco: Economy) -> void:
	for b in eco.buildings:
		if b.owner == owner and b.kind == "special" and b.done() and eco.def_of(b)["effect"]["kind"] == "feast" \
				and world.specials.can_use(owner, b.id) == "":
			world.specials.use(owner, b.id)


# --- Hero errands: lairs, shrines, merchants --------------------------------------

## Between waves the hero takes an escort to clear a lair it can handle, heals at a ready
## shrine when hurt and buys potions and better gear at a merchant.
func _hero_errands(world: SimWorld, eco: Economy) -> void:
	var h := world.heroes.hero_of(owner)
	var hu := world.heroes.hero_unit(owner)
	if h == null or hu == null or hu.scripted or world.sites.all.is_empty():
		return
	var sites := world.sites
	_shop(world, h)
	if _threat(world, eco) != Vector2.INF:
		_errand = -1
		return
	# Hurt: a ready shrine close enough.
	if hu.hp < hu.max_hp * 0.45:
		for s in sites.of_kind("shrine"):
			if float(s["ready_in"]) <= 0.0 and hu.pos.distance_to(s["pos"]) < 1800.0:
				world.command_move([hu.id], s["pos"])
				return
	# Gold to spend: the nearest merchant.
	var pl := eco.player(owner)
	if h.marks >= 80 and int(h.potions.get("health", 0)) < 2 and hu.order == SimUnit.Order.IDLE:
		for s in sites.of_kind("merchant"):
			if hu.pos.distance_to(s["pos"]) < 1600.0:
				world.command_move([hu.id], s["pos"])
				return
	if _errand >= 0:
		var cur := sites.get_site(_errand)
		if cur.is_empty() or cur["cleared"]:
			_errand = -1
		elif hu.order == SimUnit.Order.IDLE and hu.pos.distance_to(cur["pos"]) > 700.0:
			_errand = -1  # beaten back (or fallen and risen at the hall): gather a new escort
		else:
			return
	if _wave_target >= 0:
		return
	# The nearest lair this hero can take: tier 1 from the start, tier 2 at level 4, tier 3 at 7.
	var best: Dictionary = {}
	for s in sites.of_kind("lair"):
		if s["cleared"] or int(s["tier"]) > 1 + (h.level - 1) / 3 or int(s.get("keeper", -1)) >= 0:
			continue
		if best.is_empty() or hu.pos.distance_to(s["pos"]) < hu.pos.distance_to(best["pos"]):
			best = s
	if best.is_empty():
		return
	var want := 3 + 3 * int(best["tier"])
	var ids: Array = [hu.id]
	var army := _army_units(world)
	army.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		return a.pos.distance_to(best["pos"]) < b.pos.distance_to(best["pos"]) or \
			(a.pos.distance_to(best["pos"]) == b.pos.distance_to(best["pos"]) and a.id < b.id))
	for u: SimUnit in army:
		if ids.size() > want:
			break
		if u.id != hu.id and u.order == SimUnit.Order.IDLE:
			ids.append(u.id)
	if ids.size() < want / 2 + 1:
		return  # not enough of an escort yet
	_errand = best["id"]
	world.command_attack_move(ids, best["pos"])


func _shop(world: SimWorld, h: HeroState) -> void:
	var s := world.sites.merchant_near(owner)
	if s.is_empty():
		return
	for k in ["health", "health", "mana"]:
		if int(h.potions.get(k, 0)) < 3:
			world.sites.command_buy(owner, s["id"], k)
	var gear := world.heroes.gear
	for i in range(s["stock"].size() - 1, -1, -1):
		var item: Dictionary = s["stock"][i]
		var worn: Dictionary = h.worn.get(item["slot"], {})
		var better := worn.is_empty() or gear.icat.score(item) > gear.icat.score(worn)
		if better and gear.icat.can_wear(gear.archetype(h), item) \
				and h.marks >= world.sites.item_price(item) + 60:
			world.sites.command_buy(owner, s["id"], i)
