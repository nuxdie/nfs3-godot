class_name MakerMap
extends MapBrowser
## The dealership's makers on the world map, each where it builds its cars (Porsche and
## Mercedes both in Stuttgart, Detroit's four together). The items are indices into
## `makers` (set_makers()); the dealership draws the header and searches cars itself, so
## typing goes on up to it.

## The regions and what each frames: [south, west, north, east] in degrees.
const REGIONS := [["WORLD", [-42.0, -128.0, 60.0, 150.0]], ["EUROPE", [43.5, -4.5, 54.5, 13.5]],
	["NORTH AMERICA", [34.0, -137.0, 53.0, -72.0]], ["JAPAN", [32.5, 129.5, 37.5, 141.5]]]
## Places: [name, where, latitude, longitude, region].
const PLACES := {
	"stuttgart": ["Stuttgart", "Zuffenhausen and Untertürkheim, Stuttgart, Germany", 48.8, 9.19, 1],
	"munich": ["Munich", "Munich, Germany", 48.18, 11.56, 1],
	"russelsheim": ["Rüsselsheim", "Rüsselsheim, Germany", 49.99, 8.41, 1],
	"motorvalley": ["Motor Valley", "Maranello and Sant'Agata Bolognese, Italy", 44.6, 11.0, 1],
	"turin": ["Turin", "Moncalieri, Turin, Italy", 45.0, 7.68, 1],
	"coventry": ["Coventry", "Coventry, England", 52.41, -1.51, 1],
	"newportpagnell": ["Newport Pagnell", "Newport Pagnell, England", 52.09, -0.72, 1],
	"luton": ["Luton", "Luton, England", 51.88, -0.42, 1],
	"hethel": ["Hethel", "Hethel, Norfolk, England", 52.56, 1.17, 1],
	"woking": ["Woking", "Woking, Surrey, England", 51.32, -0.56, 1],
	"cambridge": ["Cambridge", "Cambridge, England", 52.2, 0.12, 1],
	"spectre": ["Spectre", "England", 51.1, -1.3, 1],
	"detroit": ["Detroit", "Detroit, Michigan, USA", 42.33, -83.05, 2],
	"burnaby": ["EA Canada", "Burnaby, Canada: where the games were made", 49.25, -122.98, 2],
	"melbourne": ["Melbourne", "Clayton, Melbourne, Australia", -37.92, 145.12, 0],
	"yokohama": ["Yokohama", "Yokohama, Japan", 35.45, 139.64, 3],
	# (Gran Turismo 2's makers.)
	"ingolstadt": ["Ingolstadt", "Ingolstadt, Germany", 48.77, 11.42, 1],
	"wolfsburg": ["Wolfsburg", "Wolfsburg, Germany", 52.42, 10.79, 1],
	"pfaffenhausen": ["Pfaffenhausen", "Pfaffenhausen, Bavaria, Germany", 48.12, 10.46, 1],
	"milan": ["Milan", "Arese, Milan, Italy", 45.55, 9.05, 1],
	"paris": ["Paris", "Paris, France", 48.86, 2.35, 1],
	"monaco": ["Monaco", "Monaco", 43.73, 7.42, 1],
	"birmingham": ["Birmingham", "Longbridge, Birmingham, England", 52.39, -1.98, 1],
	"blackpool": ["Blackpool", "Blackpool, England", 53.8, -3.05, 1],
	"lasvegas": ["Las Vegas", "Las Vegas, Nevada, USA", 36.1, -115.2, 2],
	"losangeles": ["Los Angeles", "Wilmington, Los Angeles, USA", 34.0, -118.3, 2],
	"tokyo": ["Tokyo", "Tokyo, Japan", 35.68, 139.75, 3],
	"gunma": ["Gunma", "Ota, Gunma, Japan", 36.29, 139.38, 3],
	"hamamatsu": ["Hamamatsu", "Hamamatsu, Japan", 34.71, 137.73, 3],
	"toyota": ["Toyota City", "Toyota, Aichi, Japan", 35.08, 137.16, 3],
	"kyoto": ["Kyoto", "Kyoto, Japan", 35.0, 135.77, 3],
	"osaka": ["Osaka", "Ikeda, Osaka, Japan", 34.82, 135.43, 3],
	"hiroshima": ["Hiroshima", "Hiroshima, Japan", 34.39, 132.46, 3],
	"elsewhere": ["Elsewhere", "Makers from add-on cars", 30.0, -40.0, 0],
}
## Each maker's place, and its chip there where the place has several.
const MAKER_PLACES := {
	"Porsche": ["stuttgart", "PORSCHE"], "Mercedes": ["stuttgart", "MERCEDES"], "BMW": ["munich", ""],
	"Opel": ["russelsheim", ""], "Ferrari": ["motorvalley", "FERRARI"], "Lamborghini": ["motorvalley", "LAMBORGHINI"],
	"Italdesign": ["turin", "ITALDESIGN"], "Jaguar": ["coventry", ""], "Aston Martin": ["newportpagnell", ""],
	"Vauxhall": ["luton", ""], "Lotus": ["hethel", ""], "McLaren": ["woking", ""], "Lister": ["cambridge", ""],
	"Spectre": ["spectre", ""], "Chevrolet": ["detroit", "CHEVROLET"], "Ford": ["detroit", "FORD"],
	"Dodge": ["detroit", "DODGE"], "Pontiac": ["detroit", "PONTIAC"], "EA": ["burnaby", "EA"],
	"Police": ["burnaby", "POLICE"], "Generated": ["burnaby", "GENERATED"], "HSV": ["melbourne", ""], "Nissan": ["yokohama", ""],
	# (Gran Turismo 2's makers.)
	"Audi": ["ingolstadt", ""], "Volkswagen": ["wolfsburg", ""], "RUF": ["pfaffenhausen", ""],
	"Alfa Romeo": ["milan", ""], "Fiat": ["turin", "FIAT"], "Lancia": ["turin", "LANCIA"],
	"Citroen": ["paris", "CITROEN"], "Peugeot": ["paris", "PEUGEOT"], "Renault": ["paris", "RENAULT"],
	"Venturi": ["monaco", ""], "Rover": ["birmingham", ""], "TVR": ["blackpool", ""],
	"Plymouth": ["detroit", "PLYMOUTH"], "Shelby": ["lasvegas", ""], "Vector": ["losangeles", ""],
	"Honda": ["tokyo", "HONDA"], "Acura": ["tokyo", "ACURA"], "Mitsubishi": ["tokyo", "MITSUBISHI"],
	"Isuzu": ["tokyo", "ISUZU"], "Subaru": ["gunma", ""], "Suzuki": ["hamamatsu", ""], "Toyota": ["toyota", ""],
	"Tommykaira": ["kyoto", ""], "Daihatsu": ["osaka", ""], "Mazda": ["hiroshima", ""],
}

## [{brand, cars: Array (car indices), in_use: bool, tag: String}]
var makers: Array = []


func _init() -> void:
	super()
	noun = "makers"
	head_h = 0.0
	map_top = 34.0
	chips_y = 0.0
	# The car on its turntable beside the map reaches over its right edge: pins keep clear.
	side_w = 90.0
	set_regions(REGIONS)


func set_makers(m: Array) -> void:
	makers = m
	total = m.size()
	# (What was laid out was of the makers before.)
	entries.clear()
	focus = -1
	_places.clear()
	_place_order.clear()


## Where maker `brand` is: "Stuttgart, Germany".
static func where(brand: String) -> String:
	return PLACES[MAKER_PLACES.get(brand, ["elsewhere"])[0]][1]


func hints() -> Array:
	return [["←→↑↓", "MAKER"], ["TAB", "REGION"], ["ENTER", "VISIT"]]


# ------------------------------------------------------------------ the map's hooks

func _place_table() -> Dictionary:
	return PLACES


func _item_ids() -> Array:
	return range(makers.size())


func _item_place(item: int) -> Array:
	var b: String = makers[item].brand
	return MAKER_PLACES.get(b, ["elsewhere", b.to_upper()])


func _item_text(item: int) -> String:
	return makers[item].brand


func _item_tag(item: int) -> String:
	return makers[item].tag


func _item_hay(item: int) -> String:
	return makers[item].brand


func _item_marked(item: int) -> bool:
	return item >= 0 and item < makers.size() and makers[item].in_use


func _place_faint(key: String) -> bool:
	return key == "elsewhere"


# ------------------------------------------------------------------ input, drawing

## Typing goes on up to the dealership (it searches every car), and so do the career's
## letters.
func _unhandled_input(e: InputEvent) -> void:
	var key := e as InputEventKey
	if key and key.pressed and not key.ctrl_pressed and not key.alt_pressed \
			and (key.unicode >= 32 or key.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]):
		return
	super(e)


## (The dealership draws the title and search over the map.)
func _draw() -> void:
	pass
