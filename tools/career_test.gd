extends Node
## Plays High Stakes' tournaments through without racing, finishing orders made up, and
## checks the money, the garage, the grid, the standings and the trophies (a scratch career
## file, deleted after):
##   godot --headless --path . -- --careertest
## Prints each step, "FAIL ..." for anything wrong and "careertest: N failures" at the end.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func _ready():
	await get_tree().process_frame
	var g = Game
	g.career_path = "user://career_selftest.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.career_path))
	var c = g.career_data()
	g.new_career()
	print("tournaments ", c.tournaments.size(), " circuits ", c.circuits.size(), " money ", g.career_money)
	for t in c.tournaments:
		print("  ", t.id, " ", t.name, " open=", t.open, " circuits=", t.circuits, " unlocks=", t.unlocks)
	# The dealer.
	var dealer = g.dealer_cars()
	print("dealer: ", dealer.map(func(i): return "%s $%d [%s]" % [g.cars[i].name, g.career_price(i),
		", ".join(range(1, 4).map(func(l): return str(g.upgrade_cost(i, l))))]))
	check(not dealer.is_empty(), "the dealer sells something")
	check(dealer.all(func(i): return not g.is_pursuit_car(i) and not g.car_serial(i) in g.BONUS_SERIALS), "no police or bonus cars for sale")
	var cheap: int = dealer[0]
	check(g.career_price(cheap) <= g.CAREER_START_MONEY, "the cheapest car is affordable at the start")
	check(g.buy_car(dealer[-1]) != "", "can't afford the dearest car")
	# Can't race what you don't own.
	var eu = c.tournaments[0]
	g.car_index = cheap
	check(g.start_circuit(eu, eu.circuits[0]) != "", "a circuit needs a car of yours")
	check(g.buy_car(cheap) == "", "buy the cheapest")
	check(g.owns(cheap) and g.career_money == g.CAREER_START_MONEY - g.career_price(cheap), "bought and paid")
	var before: int = g.career_money
	var up_err: String = g.upgrade_car(cheap)
	print("upgrade: '", up_err, "' level ", g.garage_upgrade(cheap), " money ", g.career_money)
	if up_err == "":
		check(g.career_money == before - g.upgrade_cost(cheap, 1), "upgrade paid")
	# Circuit 1: third in the first race, then winning; the grid follows the standings.
	var cid: int = eu.circuits[0]
	g.traffic = true
	var own: Dictionary = g._race_settings()
	check(g.start_circuit(eu, cid) == "", "enter circuit 1")
	check(not g.traffic, "no traffic in a circuit")
	var grid0: Array = g.circuit_grid()
	check(grid0[-1] == "you", "first race: you start at the back")
	var n: int = g.circuit_run.field.size()
	var o = g.circuit_race_done([0, 1, "you"] + range(2, n))
	print("race 1 standings: ", o.standings.map(func(s): return "%s %d (+%d, %s)" % [g.circuit_name(s.key), s.points, s.gained, s.race]))
	check(o.standings[2].key == "you" and o.standings[2].race == 3 and o.standings[2].gained == 6, "standings row for 3rd")
	var grid1: Array = g.circuit_grid()
	print("race 2 grid: ", grid1)
	check(grid1.find("you") == 2, "second race: you start where you stand (3rd)")
	check(grid1[0] == 0, "the leader on pole")
	# Damage carried and repaired.
	g.set_garage_damage(cheap, 0.4)
	var fix: int = g.repair_cost(cheap)
	print("repair 40%: $", fix)
	check(fix > 0 and fix < g.career_price(cheap), "a sensible repair bill")
	before = g.career_money
	check(g.repair_car(cheap) == "" and g.garage_damage(cheap) == 0.0 and g.career_money == before - fix, "repaired and paid")
	g.next_circuit_race()
	while true:
		o = g.circuit_race_done(["you"] + range(n))
		if o.done:
			break
		g.next_circuit_race()
	print("circuit 1: place ", o.place, " prize ", o.prize, " trophy ", o.trophy, " money ", g.career_money)
	check(o.place == 1 and o.trophy == 1 and o.prize == int(c.circuits[cid].prizes[0]), "circuit won: gold and the first prize")
	check(g.circuit_trophy(cid) == 1, "gold kept")
	g.circuit_run = {}
	check(g._race_settings() == own, "your own race settings back after the circuit")
	# Circuit 2 in 2nd: silver; every circuit not won, no tournament trophy.
	var cid2: int = eu.circuits[1]
	check(g.start_circuit(eu, cid2) == "", "enter circuit 2")
	n = g.circuit_run.field.size()
	while true:
		o = g.circuit_race_done([0, "you"] + range(1, n))
		if o.done:
			break
		g.next_circuit_race()
	check(o.place == 2 and o.trophy == 2 and o.tournament == "", "circuit 2 second: silver, no tournament trophy")
	g.circuit_run = {}
	check(g.start_circuit(eu, cid2) == "", "enter circuit 2 again")
	while true:
		o = g.circuit_race_done(["you"] + range(n))
		if o.done:
			break
		g.next_circuit_race()
	print("circuit 2 again: tournament '", o.tournament, "' opens ", o.opened)
	check(o.tournament == eu.name and not o.opened.is_empty(), "the tournament's trophy and what it opens")
	g.circuit_run = {}
	# A Pro Cup gives its car.
	for t in c.tournaments:
		for pc in t.circuits:
			var cc = c.circuits[pc]
			if cc.type == 0 and cc.award >= 0 and g.circuit_run.is_empty():
				var ok = range(g.cars.size()).filter(func(i): return g.circuit_allows(cc, i) and i in g.dealer_cars())
				print("pro cup ", pc, " award ", g.serial_name(cc.award), " eligible ", ok.map(func(i): return g.cars[i].name))
				if ok.is_empty():
					continue
				g.career_money = 10000000
				g.car_index = ok[0]
				g.buy_car(ok[0])
				check(g.start_circuit(t, pc) == "", "enter pro cup")
				n = g.circuit_run.field.size()
				while true:
					o = g.circuit_race_done(["you"] + range(n))
					if o.done:
						break
					g.next_circuit_race()
				print("  won: award ", g.cars[o.award].name if o.award >= 0 else "none", " prize ", o.prize)
				check(o.award >= 0 and g.owns(o.award), "the pro cup's car is yours")
				check(o.prize == 0, "and no $1 prize")
				g.circuit_run = {}
	# A knockout: the last one home goes; the standings list them last.
	for t in c.tournaments:
		for kc in t.circuits:
			if c.circuits[kc].type == 1 and g.circuit_run.is_empty():
				g.career_money = 10000000
				var ok = range(g.cars.size()).filter(func(i): return g.circuit_allows(c.circuits[kc], i) and i in g.dealer_cars())
				g.car_index = ok[0]
				g.buy_car(ok[0])
				print("knockout ", kc, " '", g.start_circuit(t, kc), "' field ", g.circuit_run.field.size())
				while true:
					var rivals = g.circuit_rivals().map(func(r): return r.key)
					o = g.circuit_race_done(rivals.slice(0, 1) + ["you"] + rivals.slice(1))
					print("  out=", g.circuit_run.out, " msg=", o.message, " done=", o.done, " place=", o.place,
						" standings=", o.standings.map(func(s): return "%s%s" % [g.circuit_name(s.key), " (out)" if s.out else ""]))
					var outs = o.standings.filter(func(s): return s.out)
					check(o.standings.slice(o.standings.size() - outs.size()).all(func(s): return s.out), "knocked out listed last")
					if o.done:
						break
					g.next_circuit_race()
				g.circuit_run = {}
	# Selling.
	before = g.career_money
	var val: int = g.resale_value(cheap)
	check(g.sell_car(cheap) == "" and not g.owns(cheap) and g.career_money == before + val, "sold at resale")
	# It all keeps.
	var money: int = g.career_money
	var garage: Dictionary = g.career_garage.duplicate(true)
	g._career_loaded = false
	g.career_garage = {}
	g.career_data()
	check(g.career_money == money and g.career_garage == garage, "saved and loaded")
	print("careertest: %d failures" % fails)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.career_path))
	get_tree().quit()
