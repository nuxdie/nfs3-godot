extends Node
## Plays High Stakes' tournaments through without racing, finishing orders made up, and
## prints what they pay and open (a scratch career file, deleted after):
##   godot --headless --path . -- --careertest
func _ready():
	await get_tree().process_frame
	var g = Game
	g.career_path = "user://career_selftest.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.career_path))
	var c = g.career_data()
	print("tournaments ", c.tournaments.size(), " circuits ", c.circuits.size(), " money ", g.career_money)
	for t in c.tournaments:
		print("  ", t.id, " ", t.name, " open=", t.open, " circuits=", t.circuits, " unlocks=", t.unlocks)
	var eu = c.tournaments[0]
	for cid in eu.circuits:
		var cc = c.circuits[cid]
		print("circuit ", cid, " type ", cc.type, " fee ", cc.fee, " opp ", cc.opponents, " laps ", cc.laps, " prizes ", cc.prizes, " races ", cc.races.map(func(r): return HsCareer.track_id(r.track)))
		g.car_index = 28
		print("  start: '", g.start_circuit(eu, cid), "' money ", g.career_money, " track ", g.track_id, " layout ", g.layout, " opp ", g.opponents)
		while true:
			var order := ["you"] + range(g.circuit_run.field.size())
			var o = g.circuit_race_done(order)
			print("  race done: done=", o.done, " place=", o.place, " prize=", o.prize, " standings=", o.standings.slice(0, 3), " next track ", g.track_id)
			if o.done:
				break
			g.next_circuit_race()
	print("money ", g.career_money, " won ", g.career_won, " open ", g.career_open)
	g.circuit_run = {}
	# a knockout
	for t in c.tournaments:
		for cid in t.circuits:
			if c.circuits[cid].type == 1 and g.circuit_run.is_empty():
				g.career_money = 999999
				g.car_index = range(g.cars.size()).filter(func(i): return g.circuit_allows(c.circuits[cid], i))[0]
				print("knockout ", cid, " '", g.start_circuit(t, cid), "' field ", g.circuit_run.field.size())
				var n := 0
				while n < 10:
					n += 1
					var rivals = g.circuit_rivals().map(func(r): return r.key)
					var o = g.circuit_race_done(rivals.slice(0, 1) + ["you"] + rivals.slice(1))
					print("  out=", g.circuit_run.get("out", []), " msg=", o.message, " done=", o.done, " place=", o.place)
					if o.done:
						g.circuit_run = {}
						break
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.career_path))
	get_tree().quit()
