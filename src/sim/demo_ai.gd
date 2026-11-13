class_name DemoAi
extends RefCounted
## Placeholder opponent for the M1 battle: waits, then attack-moves toward the
## enemy's centre of mass, re-aiming every few seconds. Uses the same commands
## as the player. The real skirmish AI comes in M4.

var owner: int = 1
var start_delay: float = 20.0
var reissue_every: float = 4.0
var enabled: bool = true
var _timer: float = 0.0
var _started: bool = false


func _init(p_owner: int = 1, delay: float = 20.0) -> void:
	owner = p_owner
	start_delay = delay


func update(world: SimWorld) -> void:
	if not enabled:
		return
	_timer += world.dt
	if not _started:
		var hurt := false
		for u in world.units:
			if u.owner == owner and u.hp < u.max_hp:
				hurt = true
				break
		if _timer < start_delay and not hurt:
			return
		_started = true
		_timer = reissue_every
	if _timer < reissue_every:
		return
	_timer = 0.0
	var enemy_c := Vector2.ZERO
	var n := 0
	var idle: Array = []
	for u in world.units:
		if u.owner != owner:
			enemy_c += u.pos
			n += 1
		elif u.target_id == -1:
			idle.append(u.id)
	if n == 0 or idle.is_empty():
		return
	world.command_attack_move(idle, enemy_c / n)
