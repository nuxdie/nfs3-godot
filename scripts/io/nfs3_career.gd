class_name Nfs3Career
## Need for Speed III's Tournament and Knockout, as tournaments (HsCareer, series "nfs3").
##
## NFS3 keeps them in its program, not in a data file; what's here is what its menus say
## (FeData/Text/text.eng): a Tournament is "a series of eight races" for points, a Knockout
## "eight cars, seven races, last place car in each race is eliminated", each at Beginner
## and Expert. Beginner Tournament wins the Jaguar XJR-15, Expert the Mercedes CLK-GTR and
## the XJR-15; Beginner Knockout opens Empire City, Expert wins El Niño and opens it. The
## races go round its tracks in the game's order (Hometown to The Summit); the laps (2 at
## Beginner, 3 at Expert) and the rivals' pace are this game's choice. There's no money:
## every car of NFS3's but the bonus ones is yours to race, the bonus cars once won.

## The bonus cars (carmodel folders, lower case).
const XJR15 := "jxjr"
const CLK_GTR := "merc"
const EL_NINO := "elni"
const BONUS := [XJR15, CLK_GTR, EL_NINO]
const TRACKS := ["trk000", "trk001", "trk002", "trk003", "trk004", "trk005", "trk006", "trk007"]


static func build() -> HsCareer:
	var c := HsCareer.new()
	c.series = "nfs3"
	c.start_money = 0
	var t := 1
	var cid := 1
	for knockout in [false, true]:
		var ids := []
		for expert in [false, true]:
			var n := 7 if knockout else 8
			var races := []
			for k in n:
				races.append({"id": TRACKS[k], "laps": 3 if expert else 2, "reverse": false, "mirror": false,
					"night": false, "weather": false})
			var award := (EL_NINO if expert else "") if knockout else (CLK_GTR if expert else XJR15)
			# (Empire City is open here anyway; the line says what NFS3 opened.)
			var opens := "Opens Empire City" if knockout else ""
			var level := "Expert" if expert else "Beginner"
			c.circuits[cid] = {"id": cid, "type": HsCareer.TYPE_KNOCKOUT if knockout else HsCareer.TYPE_TOURNAMENT,
				"fee": 0.0, "races": races, "opponents": 7, "laps": 2, "restriction": HsCareer.OPEN, "value": 0,
				"prizes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "award": -1, "award_id": award,
				"also_award": [XJR15] if award == CLK_GTR else [], "opens": opens,
				"pace": 2.2 if expert else 0.9, "mam": [0, 0, 0], "name": level,
				"about": ("Eight cars, seven races: the last car in each race is out." if knockout
					else "Points for each of eight races, 10-8-6-5-4-3-2-1."), "needs": []}
			ids.append(cid)
			cid += 1
		c.tournaments.append({"id": t, "name": "Knockout" if knockout else "Tournament", "open": true, "circuits": ids,
			"unlocks": [], "about": "Beginner and Expert, as NFS III runs them"})
		t += 1
	return c
