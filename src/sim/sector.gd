class_name Sector
extends RefCounted
## One part of the map, owned through its centre (a settlement or a waystone).

var id: int = 0
var center: Vector2 = Vector2.ZERO
var size: String = "waystone"  ## key in economy.json settlements
var owner: int = -1  ## -1 = neutral
var home_of: int = -1  ## player whose home (hall) this is, or -1
var capture: float = 0.0  ## 0..1
var capturer: int = -1
var contested: bool = false
var unsettled: float = 0.0  ## seconds left before it gives workers and gold
var spawn_timer: float = 0.0
var label: String = ""  ## a campaign map's place name ("" = the settlement's kind)
var growing: float = 0.0  ## seconds left on a settlement upgrade (0 = none)
var hall_structure: int = -1  ## id of the structure SimUnit that carries a standing capital's hit points
