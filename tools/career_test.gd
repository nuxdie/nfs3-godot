extends Node
## Plays High Stakes' tournaments (then NFS3's and Porsche Unleashed's) through without racing, finishing orders made up, and
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
	_other_series(g)
	print("careertest: %d failures" % fails)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.career_path))
	get_tree().quit()


## NFS3's Tournament and Knockout, Porsche Unleashed's eras: a career each, with its own
## money and garage, kept apart from High Stakes'.
func _other_series(g) -> void:
	var hs_money: int = g.career_money
	print("series: ", g.career_series_list())
	if "nfs3" in g.career_series_list():
		g.set_career_series("nfs3")
		var c = g.career_data()
		check(g.career_series == "nfs3" and c.series == "nfs3", "over to NFS3's")
		print("nfs3: money ", g.career_money, " cars ", g.garage_cars().map(func(i): return g.cars[i].name), " dealer ", g.dealer_cars().size())
		check(not g.garage_cars().is_empty() and g.dealer_cars().is_empty(), "NFS3's cars all yours, no dealer")
		var t = c.tournaments[0]
		var cid = t.circuits[0]
		g.car_index = g.garage_cars()[0]
		check(g.start_circuit(t, cid) == "", "enter NFS3's beginner tournament")
		check(g.track_id == "trk000" and g.laps == 2, "on Hometown, 2 laps")
		var n: int = g.circuit_run.field.size()
		print("  field ", g.circuit_run.field.map(func(f): return g.cars[f.car].name))
		check(n == 7, "seven rivals")
		var o
		while true:
			o = g.circuit_race_done(["you"] + range(n))
			if o.done:
				break
			g.next_circuit_race()
		print("  won: ", o.message, " award ", g.cars[o.award].name if o.award >= 0 else "none")
		check(o.place == 1 and o.award >= 0 and g.owns(o.award), "the XJR-15 is yours")
		g.circuit_run = {}
		# The knockout: seven races, one out each.
		var kt = c.tournaments[1]
		check(g.start_circuit(kt, kt.circuits[0]) == "", "enter NFS3's beginner knockout")
		var races := 0
		while true:
			var rivals = g.circuit_rivals().map(func(r): return r.key)
			o = g.circuit_race_done(["you"] + rivals)
			races += 1
			if o.done:
				break
			g.next_circuit_race()
		print("  knockout: ", races, " races, place ", o.place, " opened ", o.opened)
		check(races == 7 and o.place == 1 and "Empire City" in o.opened, "knockout won in 7, Empire City")
		g.circuit_run = {}
	if "pu" in g.career_series_list():
		g.set_career_series("pu")
		var c = g.career_data()
		print("pu: money ", g.career_money, " eras ", c.tournaments.map(func(t): return "%s %s" % [t.name, t.circuits]))
		check(g.career_money == PuCareer.START_MONEY, "Evolution's starting money")
		for t in c.tournaments:
			for cid in t.circuits:
				var e = c.circuits[cid]
				print("  #%d %s [%s] fee %d races %s rally=%s traffic=%s award=%s prize1 %d" % [cid, e.name, e.only, e.fee,
					e.races.map(func(r): return "%s%s%s" % [r.id.trim_prefix("pu_"), "(r)" if r.reverse else "", "x%d" % r.laps if r.laps > 1 else ""]),
					e.rally, e.traffic, e.award_id, e.prizes[0]])
				check(e.races.all(func(r): return HsCareer.race_track(r) != ""), "event %d's tracks installed" % cid)
				check(e.cars.all(func(id): return g._car_by_id_ci(id) >= 0), "event %d's cars installed" % cid)
		var dealer = g.dealer_cars()
		print("  dealer ", dealer.size(), " cheapest ", g.cars[dealer[0]].name, " $", g.career_price(dealer[0]))
		var t = c.tournaments[0]
		var first = c.circuits[t.circuits[0]]
		var ok = dealer.filter(func(i): return g.circuit_allows(first, i))
		check(not ok.is_empty() and g.career_price(ok[0]) <= g.career_money, "a car for the first event is affordable")
		g.car_index = ok[0]
		check(g.buy_car(ok[0]) == "", "bought " + g.cars[ok[0]].name)
		var before: int = g.career_money
		check(g.start_circuit(t, first.id) == "", "enter " + first.name)
		print("  field ", g.circuit_run.field.map(func(f): return g.cars[f.car].name))
		var n: int = g.circuit_run.field.size()
		var o = g.circuit_race_done(["you"] + range(n))
		check(o.race_prize == int(first.races[0].prizes[0]) and g.career_money == before - int(first.fee) + o.race_prize,
			"the race's own prize")
		g.next_circuit_race()
		while not o.done:
			o = g.circuit_race_done(["you"] + range(n))
			if not o.done:
				g.next_circuit_race()
		print("  ", first.name, ": place ", o.place, " prize ", o.prize, " money ", g.career_money)
		check(o.place == 1 and o.prize == int(first.prizes[0]), "event won, its prize")
		g.circuit_run = {}
		# A rally goes by the total time.
		for cid in t.circuits:
			var e = c.circuits[cid]
			if e.rally and g.circuit_run.is_empty():
				g.career_money = 10000000
				var cars_ok = dealer.filter(func(i): return g.circuit_allows(e, i))
				g.car_index = cars_ok[0]
				g.buy_car(cars_ok[0])
				check(g.start_circuit(t, cid) == "", "enter rally " + e.name)
				n = g.circuit_run.field.size()
				# You finish last every stage but by a whisker; rival 0 wins each stage by a mile... once.
				var times := {"you": 300.0}
				for k in n:
					times[k] = 299.0
				times[0] = 200.0
				o = g.circuit_race_done(range(n) + ["you"], times)
				times[0] = 400.0
				g.next_circuit_race()
				while not o.done:
					o = g.circuit_race_done(range(n) + ["you"], times)
					if not o.done:
						g.next_circuit_race()
				print("  rally: ", o.standings.map(func(s): return "%s %.0f" % [g.circuit_name(s.key), s.total]))
				check(o.standings[0].key is int and o.standings[0].key == 0 or o.standings[0].total <= o.standings[1].total,
					"rally standings by total time")
				g.circuit_run = {}
		# The bonus race waits for the rest of the era.
		var bonus = c.circuits[t.circuits[-1]]
		check(bonus.type == HsCareer.TYPE_CAR_RACE and not g.circuit_open(bonus), "the bonus race is locked")
	g.set_career_series("hs")
	check(g.career_money == hs_money, "High Stakes' money kept apart")
