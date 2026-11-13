extends SceneTree
## AI against AI: one computer level against another (or against an older AI script), on many
## seeds and every pairing of the factions you name, sides swapped every other game.
##   godot --headless --path . --script res://tools/ai_duel.gd -- games minutes level_a level_b [factions] [old_ai.gd] [out.md] [first_seed]
## level_b "old:<level>" plays the script given as old_ai.gd (an older economy_ai.gd with its
## class_name line removed) at that level, e.g. to measure a new AI against main's.
##   git show origin/main:spinoff/warbound/src/sim/economy_ai.gd | sed 's/^class_name EconomyAi$//' > /tmp/old_ai.gd

var games := 8
var minutes := 30.0
var level_a := "very_hard"
var level_b := "hard"
var factions: Array = ["concord", "hollow"]
var old_script: GDScript = null
var out := ""
var first_seed := 1000


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		games = int(args[0])
	if args.size() > 1:
		minutes = float(args[1])
	if args.size() > 2:
		level_a = args[2]
	if args.size() > 3:
		level_b = args[3]
	if args.size() > 4 and args[4] != "-":
		factions = Array(args[4].split(","))
	if args.size() > 5 and args[5] != "-":
		old_script = load(args[5])
	if args.size() > 6 and args[6] != "-":
		out = args[6]
	if args.size() > 7:
		first_seed = int(args[7])
	var wins := [0, 0, 0]  ## a, b, none
	var lines: Array = []
	var t0 := Time.get_ticks_msec()
	for g in games:
		var pair: Array = [factions[g / 2 % factions.size()], factions[(g / 2 + 1 + g / (2 * factions.size())) % factions.size()]]
		var a_side := g % 2  # a plays west on even games, east on odd ones
		var r := play(first_seed + g / 2, pair, a_side)
		var who: int = 2 if r["winner"] < 0 else (0 if r["winner"] == a_side else 1)
		wins[who] += 1
		var line := "game %d: %s (%s) vs %s (%s): %s after %.1f min, sectors %s, lost %s, veterans 3+ %s, retreats %s" % [g + 1,
			level_a, pair[a_side], level_b, pair[1 - a_side], [level_a, level_b, "nobody"][who], r["minutes"],
			r["sectors"], r["lost"], r["vets"], r["retreats"]]
		print(line)
		lines.append(line)
	var summary := "%s vs %s, %d games of at most %.0f min: %s won %d, %s won %d, undecided %d (%.0f s)" % [level_a,
		level_b, games, minutes, level_a, wins[0], level_b, wins[1], wins[2], (Time.get_ticks_msec() - t0) / 1000.0]
	print(summary)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n" + summary + "\n")
	quit()


func make_ai(level: String, owner: int) -> RefCounted:
	if level.begins_with("old:"):
		return old_script.new(owner, level.substr(4))
	return EconomyAi.new(owner, level)


## Plays one game; level_a sits on side a_side. Returns winner (owner), minutes, sectors, units
## lost, units of veteran rank 3+ alive at the end and retreat orders given, per owner.
func play(seed_value: int, pair: Array, a_side: int) -> Dictionary:
	var w := SkirmishScenario.build_skirmish(seed_value, pair)
	var ais: Array = [null, null]
	ais[a_side] = make_ai(level_a, a_side)
	ais[1 - a_side] = make_ai(level_b, 1 - a_side)
	var eco := w.economy
	var limit := int(minutes * 60.0 * w.tick_rate)
	var lost := [0, 0]
	var retreats := [0, 0]  ## units seen setting off home
	var running := {}
	var tick := 0
	while tick < limit and eco.winner() < 0:
		for ai in ais:
			ai.update(w)
		w.step()
		tick += 1
		for e in w.events:
			if e["type"] == "death" and int(e["owner"]) < 2:
				lost[int(e["owner"])] += 1
		if tick % 10 == 0:
			for u in w.units:
				if u.owner < 2 and u.order == SimUnit.Order.RETREAT and not running.has(u.id):
					retreats[u.owner] += 1
			running.clear()
			for u in w.units:
				if u.order == SimUnit.Order.RETREAT:
					running[u.id] = true
	var vets := [0, 0]
	for u in w.units:
		if u.owner < 2 and u.veteran >= 3:
			vets[u.owner] += 1
	return {"winner": eco.winner(), "minutes": tick / float(w.tick_rate) / 60.0,
		"sectors": [eco.sectors_of(0), eco.sectors_of(1)], "lost": lost, "vets": vets, "retreats": retreats}
