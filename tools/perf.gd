extends SceneTree
## Headless speed check: a full 300-unit battle, ticks per second.
##   godot --headless --path . --script res://tools/perf.gd
## The game needs 20 ticks per second; more headroom means room for rendering.

func _init() -> void:
	var w := SkirmishScenario.build(3)
	var ai := DemoAi.new(1, 0.0)
	var ids: Array = []
	for u in w.units:
		if u.owner == 0:
			ids.append(u.id)
	w.command_attack_move(ids, Vector2(3000, 1150))
	var worst := 0
	var worst_at := 0
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in 20 * 90:
		var t := Time.get_ticks_usec()
		ai.update(w)
		w.step()
		var dt_us := Time.get_ticks_usec() - t
		if dt_us > worst and i > 0:
			worst = dt_us
			worst_at = i
		n += 1
		if w.count_alive(0) == 0 or w.count_alive(1) == 0:
			break
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("%d ticks (%.0f s of game) in %.2f s: %.0f ticks/s, worst tick %.1f ms (tick %d); left: %d vs %d" % [
		n, n / 20.0, secs, n / secs, worst / 1000.0, worst_at, w.count_alive(0), w.count_alive(1)])
	quit()
