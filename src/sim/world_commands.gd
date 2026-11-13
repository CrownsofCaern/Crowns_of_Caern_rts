class_name WorldCommands
extends RefCounted
## Every change a player makes to a running skirmish, as plain data.
##
## The skirmish view never changes the world itself: it builds a command
## dictionary ({"t": kind, ...}) and hands it to `apply` (alone at the keyboard)
## or to Lockstep (online), which applies the same commands on every computer at
## the same tick. Commands hold only ints, floats, strings, bools, Vector2 and
## arrays of ints, so they cross the network unchanged (var_to_bytes).
##
## `player` is who sent the command. Whatever the command says, it only ever
## moves that player's units and spends that player's resources, so a broken or
## hostile packet can't order someone else's army.

## Every command kind apply knows. Anything else is ignored.
const KINDS := ["order", "garrison_now", "stop", "hold", "retreat", "rally", "gather", "help_build", "build", "wall",
	"train", "refit", "gather_upgrade", "special", "fort_upgrade", "fort_release", "grow", "hall", "buy",
	"weight", "cast", "learn", "autocast", "drink", "equip", "unequip", "drop"]
## The order types run_command / queue_command take.
const ORDER_TYPES := ["move", "attack_move", "attack", "capture", "gather", "build", "garrison"]


## Carries out one command for `player`. True when it did something (the
## economy's own refusals leave a notice for that player, as before).
static func apply(w: SimWorld, player: int, c: Dictionary) -> bool:
	var kind := String(c.get("t", ""))
	match kind:
		"order":
			var ids := own_ids(w, player, c.get("ids"))
			var cmd: Variant = c.get("cmd")
			if ids.is_empty() or not cmd is Dictionary or not ORDER_TYPES.has(String((cmd as Dictionary).get("type", ""))):
				return false
			if bool(c.get("queued", false)):
				w.queue_command(ids, cmd)
			else:
				w.drop_plans(ids)
				w.run_command(ids, cmd)
			return true
		"garrison_now":
			# Right click on your tower: up they go, or walk there when it is full.
			var ids := own_ids(w, player, c.get("ids"))
			if ids.is_empty():
				return false
			w.drop_plans(ids)
			if w.forts.command_garrison(ids, _int(c, "fort")) == 0:
				w.run_command(ids, {"type": "move", "point": _vec(c, "point")})
			return true
		"stop":
			w.command_stop(own_ids(w, player, c.get("ids")))
			return true
		"hold":
			w.command_hold(own_ids(w, player, c.get("ids")))
			return true
		"retreat":
			var ids := own_ids(w, player, c.get("ids"))
			w.drop_plans(ids)
			return w.command_retreat(ids) > 0
		"rally":
			w.economy.command_rally(player, _int(c, "building"), _vec(c, "point"))
			return true
		"gather":
			w.economy.command_gather(own_ids(w, player, c.get("ids")), _int(c, "node"))
			return true
		"help_build":
			var b := w.economy.building(_int(c, "building"))
			if b == null or b.owner != player:
				return false
			w.economy.command_help_build(own_ids(w, player, c.get("ids")), b.id)
			return true
		"build":
			# keep (shift): the workers queue this site after the ones they already have.
			var ids := own_ids(w, player, c.get("ids"))
			var keep := bool(c.get("keep", false))
			var b := w.economy.command_build([] if keep else ids, player, String(c.get("kind", "")), _int(c, "tier"),
				_vec(c, "point"), String(c.get("special", "")))
			if b == null:
				return false
			if keep:
				w.queue_command(ids, {"type": "build", "building": b.id})
			else:
				w.drop_plans(ids)
			return true
		"wall":
			return not w.forts.command_build_wall(own_ids(w, player, c.get("ids")), player, _vec(c, "a"), _vec(c, "b")).is_empty()
		"train":
			return w.economy.command_train(player, _int(c, "building"), _int(c, "tier"))
		"refit":
			return w.economy.command_upgrade_dwelling(player, _int(c, "building"), _int(c, "tier"))
		"gather_upgrade":
			return w.economy.command_gather_upgrade(player, _int(c, "building"), String(c.get("res", "")))
		"special":
			return w.specials.use(player, _int(c, "building"), String(c.get("arg", "")))
		"fort_upgrade":
			return w.forts.command_upgrade(player, _int(c, "building"), String(c.get("kind", "")))
		"fort_release":
			w.forts.command_release(player, _int(c, "building"))
			return true
		"grow":
			return w.economy.command_upgrade_settlement(player, _int(c, "sector"))
		"hall":
			return w.economy.command_upgrade_hall(player)
		"buy":
			var what: Variant = c.get("what")
			if not (what is int or what is String):
				return false
			return w.sites.command_buy(player, _int(c, "site"), what)
		"weight":
			var r := String(c.get("res", ""))
			w.economy.set_gather_weight(player, r, _int(c, "weight"))
			return true
		"cast":
			return w.heroes.command_cast(player, _int(c, "slot"), int(c.get("target", -1)), _vec(c, "point"))
		"learn":
			var h := w.heroes.hero_of(player)
			if h == null or not w.heroes.can_learn(h, _int(c, "slot")):
				return false
			return w.heroes.command_learn(player, _int(c, "slot"))
		"autocast":
			w.heroes.command_set_autocast(player, _int(c, "slot"), bool(c.get("on", false)))
			return true
		"drink":
			return w.heroes.gear.command_drink(player, String(c.get("kind", "")))
		"equip":
			return w.heroes.gear.command_equip(player, _int(c, "index"))
		"unequip":
			return w.heroes.gear.command_unequip(player, String(c.get("slot", "")))
		"drop":
			return w.heroes.gear.command_drop(player, _int(c, "index"))
	return false


## The ids in `raw` that are this player's living units, ascending (anything else is dropped).
static func own_ids(w: SimWorld, player: int, raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for v: Variant in raw:
		if not (v is int or v is float):
			continue
		var u := w.get_unit(int(v))
		if u != null and u.owner == player and not out.has(u.id):
			out.append(u.id)
	out.sort()
	return out


## True when the dictionary is a command apply knows (the network drops anything else).
static func is_command(c: Variant) -> bool:
	return c is Dictionary and KINDS.has(String((c as Dictionary).get("t", "")))


static func _int(c: Dictionary, key: String) -> int:
	var v: Variant = c.get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func _vec(c: Dictionary, key: String) -> Vector2:
	var v: Variant = c.get(key, Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO
