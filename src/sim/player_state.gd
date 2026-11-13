class_name PlayerState
extends RefCounted
## One player's economy: stockpile, hall level, faction.

var owner: int = 0
var faction: String = "concord"
var res: Dictionary = {}
var hall_level: int = 1
var hall_upgrading: float = 0.0  ## seconds left (0 = none)
var defeated: bool = false  ## their capital fell: out of the game
var gold_frac: float = 0.0  ## gold income below 1 that has not been paid out yet
## Statistics for reports and balance runs (not rules).
var gathered: Dictionary = {}  ## resource -> amount brought in (gold: settlement income)
var spent: Dictionary = {}  ## resource -> amount paid
var trained: Dictionary = {}  ## unit type -> count
var hall_times: Array = []  ## game seconds when each hall level was reached (index 0 = level 2)
## Faction research (Armoury): the share of damage this player's units take, and what was researched.
var taken_factor: float = 1.0
var researched: Dictionary = {}
## A computer player's extra share of every load and of settlement gold (ai_difficulty income_bonus).
var income_bonus: float = 0.0
var gather_weights: Dictionary = {}  ## resource -> 0..10, the mix of gatherers (unset: economy.json default)
## Worker upgrades bought at a storehouse: resource -> levels done (economy.json worker_upgrades),
## and the share of a load below 1 not paid out yet, per resource.
var gather_levels: Dictionary = {}
var gather_frac: Dictionary = {}


func amount(r: String) -> int:
	return int(res.get(r, 0))


func can_pay(cost: Dictionary) -> bool:
	for r in cost:
		if amount(r) < int(cost[r]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for r in cost:
		res[r] = amount(r) - int(cost[r])
		spent[r] = int(spent.get(r, 0)) + int(cost[r])


func earn(r: String, n: int) -> void:
	res[r] = amount(r) + n
	gathered[r] = int(gathered.get(r, 0)) + n


func refund(cost: Dictionary) -> void:
	for r in cost:
		res[r] = amount(r) + int(cost[r])
		spent[r] = int(spent.get(r, 0)) - int(cost[r])
