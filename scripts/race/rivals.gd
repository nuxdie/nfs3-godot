class_name Rivals
## The AI racers' drivers: a name, a signature colour (their car's paint and their chip in
## the timing tower) and a way of driving, which AIController.set_driver() turns into how it
## brakes, passes, defends, starts, slips up and paces itself over a race.
##
## Traits (1.0 / 0.0 the plain AI):
##   pace    - the share of the tyres' grip it corners on (AIController.skill)
##   brakes  - how hard it counts on braking into a bend (0.6 the AI's own)
##   room    - how much space it leaves passing (x the AI's margin; under 1 squeezes by)
##   defend  - 0..1, how far it moves over to cover a car right behind
##   launch  - s it's slow away off the line
##   errors  - slips a minute: a few seconds off its line and its pace, a lock-up or a run wide
##   line    - m it drives off the racing line (+ right), its own way round
##   form    - pace gained (+) or lost (-) by the last lap
##   quips   - what it says passing you

const ROSTER := [
	{"name": "Vic Moreau", "short": "Moreau", "tag": "Viper", "style": "The Aggressor",
		"about": "Brakes last, leaves you no room and leans on you through the turn.",
		"color": Color(0.88, 0.12, 0.14),
		"pace": 1.01, "brakes": 0.69, "room": 0.6, "defend": 0.8, "launch": 0.1, "errors": 0.6, "line": 0.0, "form": 0.0,
		"quips": ["Out of my way.", "Too slow.", "Mirrors, rookie."]},
	{"name": "Kenji Arakawa", "short": "Arakawa", "tag": "Professor", "style": "The Technician",
		"about": "Every apex, every lap, to the tenth. Rarely puts a wheel wrong.",
		"color": Color(0.9, 0.91, 0.93),
		"pace": 1.03, "brakes": 0.62, "room": 1.0, "defend": 0.3, "launch": 0.15, "errors": 0.05, "line": 0.0, "form": 0.0,
		"quips": ["Late apex. Textbook.", "Efficient.", "As calculated."]},
	{"name": "Rosa Delgado", "short": "Delgado", "tag": "Closer", "style": "The Charger",
		"about": "Bogs down off the line, then hunts the field down lap after lap.",
		"color": Color(1.0, 0.47, 0.08),
		"pace": 0.99, "brakes": 0.63, "room": 0.9, "defend": 0.2, "launch": 0.5, "errors": 0.25, "line": 0.0, "form": 0.05,
		"quips": ["Here I come.", "Just warming up.", "Saved the best for last."]},
	{"name": "Dutch van der Berg", "short": "Van der Berg", "tag": "The Wall", "style": "The Blocker",
		"about": "Not the quickest, but good luck finding a way past.",
		"color": Color(0.96, 0.78, 0.0),
		"pace": 0.99, "brakes": 0.6, "room": 1.1, "defend": 1.0, "launch": 0.2, "errors": 0.2, "line": 0.0, "form": 0.0,
		"quips": ["My road.", "Nowhere to go, friend.", "You'll have to wait."]},
	{"name": "Lena Kowalski", "short": "Kowalski", "tag": "Rocket", "style": "The Sprinter",
		"about": "Lightning off the line and quick early on; fades as the tyres go.",
		"color": Color(0.12, 0.42, 1.0),
		"pace": 1.04, "brakes": 0.64, "room": 0.9, "defend": 0.4, "launch": 0.0, "errors": 0.3, "line": 0.0, "form": -0.04,
		"quips": ["Catch me if you can!", "See you at the finish.", "Bye!"]},
	{"name": "Marcus Okafor", "short": "Okafor", "tag": "Ice", "style": "The Cool Head",
		"about": "Smooth, patient, never panics. Passes clean and keeps it on the road.",
		"color": Color(0.1, 0.78, 0.78),
		"pace": 1.0, "brakes": 0.58, "room": 1.25, "defend": 0.25, "launch": 0.2, "errors": 0.0, "line": 0.0, "form": 0.015,
		"quips": ["Easy does it.", "Patience pays.", "Stay cool."]},
	{"name": "Sasha Volkova", "short": "Volkova", "tag": "Wildcard", "style": "The Daredevil",
		"about": "Blindingly fast when it sticks. Often it doesn't.",
		"color": Color(0.56, 0.24, 1.0),
		"pace": 1.06, "brakes": 0.71, "room": 0.75, "defend": 0.5, "launch": 0.05, "errors": 1.3, "line": 0.0, "form": 0.0,
		"quips": ["Hold on to something!", "Ha! Full send.", "Whoops — still here!"]},
	{"name": "Tommy Reyes", "short": "Reyes", "tag": "Rookie", "style": "The Rookie",
		"about": "Eager and timid at once: gives everyone room and gets flustered.",
		"color": Color(0.5, 0.84, 0.12),
		"pace": 0.96, "brakes": 0.56, "room": 1.45, "defend": 0.0, "launch": 0.55, "errors": 0.9, "line": 0.0, "form": 0.02,
		"quips": ["Did I just pass you?!", "Sorry! Sorry!", "Woo!"]},
	{"name": "Harland Price", "short": "Price", "tag": "Veteran", "style": "The Veteran",
		"about": "Thirty years of racing. Saves the car early and knows when to push.",
		"color": Color(0.1, 0.1, 0.12),
		"pace": 1.0, "brakes": 0.6, "room": 1.0, "defend": 0.6, "launch": 0.25, "errors": 0.1, "line": 0.0, "form": 0.03,
		"quips": ["Seen it all, kid.", "Experience.", "Not my first race."]},
	{"name": "Nico Benedetti", "short": "Benedetti", "tag": "Showman", "style": "The Showman",
		"about": "Takes the long way round in style: wide lines, big moves, for the cameras.",
		"color": Color(1.0, 0.25, 0.64),
		"pace": 1.0, "brakes": 0.66, "room": 0.8, "defend": 0.3, "launch": 0.15, "errors": 0.55, "line": 1.2, "form": 0.0,
		"quips": ["Smile for the cameras!", "Bellissimo.", "Ciao!"]},
	{"name": "Ingrid Solberg", "short": "Solberg", "tag": "Gentle", "style": "The Sportswoman",
		"about": "Fast and scrupulously fair. Never blocks, always leaves a car's width.",
		"color": Color(0.06, 0.45, 0.24),
		"pace": 1.02, "brakes": 0.61, "room": 1.5, "defend": 0.0, "launch": 0.15, "errors": 0.1, "line": -0.4, "form": 0.0,
		"quips": ["Good race.", "After you — oh, never mind.", "Clean pass."]},
	{"name": "Dmitri Orlov", "short": "Orlov", "tag": "Tank", "style": "The Bully",
		"about": "Drives through gaps that aren't there and doesn't mind the paint.",
		"color": Color(0.42, 0.5, 0.6),
		"pace": 0.98, "brakes": 0.67, "room": 0.5, "defend": 0.9, "launch": 0.2, "errors": 0.4, "line": 0.0, "form": 0.0,
		"quips": ["Move.", "Bump.", "I don't brake for you."]},
]


## `n` different drivers (indices into ROSTER) for a single race, in random order.
static func pick(n: int) -> Array:
	var idx: Array = range(ROSTER.size())
	idx.shuffle()
	var out := []
	for k in n:
		out.append(idx[k % idx.size()])
	return out


static func get_driver(i: int) -> Dictionary:
	return ROSTER[posmod(i, ROSTER.size())]
