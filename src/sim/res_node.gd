class_name ResNode
extends RefCounted
## A resource pile workers gather from. It holds a fixed amount (economy.json pile_amounts) and
## runs dry: a worker takes up to one load at a time, and an empty pile is gone for good (it stays
## in Economy.nodes, so ids never shift). amount -1 means it never runs out.

var id: int = 0
var pos: Vector2 = Vector2.ZERO
var resource: String = "wood"
var sector: int = 0
var amount: int = -1  ## left in the pile (-1 = endless)
var full: int = -1  ## what it started with (-1 = endless)


func endless() -> bool:
	return amount < 0


func depleted() -> bool:
	return amount == 0


## What is left as a share of the start (1.0 for an endless pile).
func fraction() -> float:
	return 1.0 if amount < 0 or full <= 0 else float(amount) / float(full)


## Takes up to `want` from the pile and returns what was taken.
func take(want: int) -> int:
	if amount < 0:
		return want
	var got := mini(want, amount)
	amount -= got
	return got
