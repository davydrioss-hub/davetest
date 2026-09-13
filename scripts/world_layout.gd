class_name WorldLayout
extends RefCounted
const SPAWN = Vector3(-43, 0, 28)
const GARAGE = Vector3(-43, 0, 16)
const VAN = Vector3(-34, 0, 29)
const REPAIR = Vector3(-30, 0, 24)
const LIMIT = Vector2(211, 151)
const DEALER = Vector3(-141, 0, 56)
const WORKSHOP = Vector3(84, 0, 94)
const ROAD_X = [-168.0, -112.0, -56.0, 0.0, 56.0, 112.0, 168.0]
const ROAD_Z = [-114.0, -76.0, -38.0, 0.0, 38.0, 76.0, 114.0]
const DISTRICTS = [
	{"name":"СТАРЫЙ ЦЕНТР", "rect":Rect2(-82,-70,166,140), "color":Color("334c59")},
	{"name":"СОСНОВЫЙ КВАРТАЛ", "rect":Rect2(-211,-151,126,225), "color":Color("3e5955")},
	{"name":"СЕВЕРНЫЙ ПАРК", "rect":Rect2(-82,-151,194,77), "color":Color("31594d")},
	{"name":"ПРОМЫШЛЕННАЯ ЗОНА", "rect":Rect2(-211,77,379,74), "color":Color("595052")},
	{"name":"ВОСТОЧНЫЙ ПОРТ", "rect":Rect2(85,-151,126,226), "color":Color("304d64")}
]
static func district(pos: Vector3) -> String:
	for d in DISTRICTS:
		if d.rect.has_point(Vector2(pos.x,pos.z)): return d.name
	return "ГОРОДСКАЯ МАГИСТРАЛЬ"
# Each footprint is used by both the server's collision and the rendered district.
const BUILDINGS = [
	["building-a", Rect2(-47,-29,18,17), 11.0, "WEST APARTMENTS"],
	["building-c", Rect2(-24,-29,16,17), 10.0, "CORNER COFFEE"],
	["building-e", Rect2(9,-30,17,18), 15.0, "OFFICES"],
	["building-g", Rect2(31,-29,17,17), 12.0, "NIGHT MARKET"],
	["building-j", Rect2(9,14,17,16), 11.0, "RIVERSIDE CLINIC"],
	["building-m", Rect2(-51,-60,20,13), 13.0, "NORTH RESIDENCE"],
	["building-c", Rect2(-22,-60,15,13), 10.0, "BOOKS & RECORDS"],
	["building-a", Rect2(9,-60,17,13), 14.0, "HOTEL 24"],
	["building-e", Rect2(32,-60,18,13), 12.0, "RIVER STUDIOS"],
	["building-g", Rect2(31,49,18,12), 9.0, "LANTERN BISTRO"],
	["building-j", Rect2(9,49,16,12), 14.0, "CITY WORKS"],
	["building-a", Rect2(-24,49,16,12), 11.0, "LAUNDROMAT"],
	["building-m", Rect2(-50,49,21,12), 13.0, "SOUTH APARTMENTS"],
	["building-c", Rect2(-76,-28,12,16), 9.0, "BAKERY"],
	["building-g", Rect2(-76,12,12,18), 14.0, "WAREHOUSE"],
	["building-e", Rect2(64,-28,13,16), 12.0, "ARCADE"],
	["building-j", Rect2(64,12,13,18), 11.0, "STATION"],
	["building-type-a",Rect2(-200,-104,21,18),9.0,"PINE HOUSE 01","city-kit-suburban"],
	["building-type-g",Rect2(-155,-104,26,17),12.0,"PINE HOUSE 02","city-kit-suburban"],
	["building-type-g",Rect2(-202,-66,24,18),11.0,"PINE HOUSE 03","city-kit-suburban"],
	["building-type-a",Rect2(-155,-66,22,18),10.0,"PINE HOUSE 04","city-kit-suburban"],
	["building-type-a",Rect2(-202,-28,24,18),9.0,"GARDEN VILLA","city-kit-suburban"],
	["building-c",Rect2(-154,-28,24,18),10.0,"PINE CAFE"],
	["building-type-g",Rect2(-201,12,23,17),11.0,"HILLSIDE HOME","city-kit-suburban"],
	["building-type-a",Rect2(-153,12,23,17),9.0,"PINE HOUSE 05","city-kit-suburban"],
	["building-g",Rect2(-202,49,24,17),10.0,"WESTERN STORES"],
	["building-m",Rect2(-100,-104,20,18),13.0,"NORTH SCHOOL"],
	["building-a",Rect2(-98,-66,16,18),12.0,"WEST TOWER"],
	["building-e",Rect2(-98,49,16,17),14.0,"WEST OFFICES"],
	["building-c",Rect2(-48,-141,28,17),11.0,"BOTANICAL CENTER"],
	["building-m",Rect2(10,-141,28,17),17.0,"OBSERVATORY"],
	["building-g",Rect2(69,-141,27,17),12.0,"HILLTOP HOTEL"],
	["building-a",Rect2(-202,87,24,17),10.0,"WEST LOGISTICS","city-kit-industrial"],
	["building-d",Rect2(-154,86,28,18),13.0,"POWER STATION","city-kit-industrial"],
	["building-f",Rect2(-101,86,34,18),11.0,"STEELWORKS","city-kit-industrial"],
	["building-h",Rect2(-47,86,34,18),14.0,"NIGHT PRINT","city-kit-industrial"],
	["building-b",Rect2(9,87,37,18),10.0,"CITY DISTRIBUTION","city-kit-industrial"],
	["building-f",Rect2(-201,124,24,18),12.0,"COLD STORAGE","city-kit-industrial"],
	["building-a",Rect2(-152,124,29,18),13.0,"TIMBER YARD","city-kit-industrial"],
	["building-d",Rect2(-99,124,32,18),14.0,"RECYCLING","city-kit-industrial"],
	["building-h",Rect2(-47,124,34,18),12.0,"ASSEMBLY 04","city-kit-industrial"],
	["building-b",Rect2(10,124,35,18),11.0,"CARGO TERMINAL","city-kit-industrial"],
	["building-a",Rect2(70,124,26,18),14.0,"TECH LAB","city-kit-industrial"],
	["building-d",Rect2(124,87,29,18),16.0,"DOCK FACTORY","city-kit-industrial"],
	["building-f",Rect2(125,124,28,18),12.0,"SHIP SERVICE","city-kit-industrial"],
	["building-e",Rect2(123,-141,30,18),18.0,"PORT AUTHORITY"],
	["building-a",Rect2(123,-103,29,18),12.0,"EAST WAREHOUSE","city-kit-industrial"],
	["building-g",Rect2(70,-103,28,18),11.0,"PARK RESTAURANT"],
	["building-m",Rect2(85,-65,17,18),16.0,"EAST HOTEL"],
	["building-b",Rect2(124,-65,29,18),12.0,"DOCK 01","city-kit-industrial"],
	["building-h",Rect2(123,-28,30,18),12.0,"MARINE SUPPLY","city-kit-industrial"],
	["building-a",Rect2(86,11,16,19),14.0,"EAST RESIDENCE"],
	["building-d",Rect2(124,11,28,19),13.0,"FISH MARKET","city-kit-industrial"],
	["building-j",Rect2(70,48,28,19),13.0,"RIVER MUSEUM"],
	["building-c",Rect2(124,48,29,19),11.0,"HARBOUR CAFE"]
]
const DESTINATIONS = [
	{"name":"Corner Coffee", "pos":[-16.0,0.0,-8.0]},
	{"name":"Night Market", "pos":[39.0,0.0,-8.0]},
	{"name":"North Residence", "pos":[-41.0,0.0,-43.0]},
	{"name":"Riverside Clinic", "pos":[17.0,0.0,9.0]},
	{"name":"Lantern Bistro", "pos":[40.0,0.0,45.0]},
	{"name":"Pine House 01", "pos":[-188.0,0.0,-82.0]},
	{"name":"Pine House 02", "pos":[-142.0,0.0,-82.0]},
	{"name":"Garden Villa", "pos":[-191.0,0.0,-6.0]},
	{"name":"Pine Cafe", "pos":[-143.0,0.0,-6.0]},
	{"name":"Western Stores", "pos":[-190.0,0.0,45.0]},
	{"name":"North School", "pos":[-91.0,0.0,-82.0]},
	{"name":"Botanical Center", "pos":[-35.0,0.0,-120.0]},
	{"name":"Observatory", "pos":[23.0,0.0,-120.0]},
	{"name":"Hilltop Hotel", "pos":[82.0,0.0,-120.0]},
	{"name":"Steelworks", "pos":[-84.0,0.0,82.0]},
	{"name":"Night Print", "pos":[-31.0,0.0,82.0]},
	{"name":"Cold Storage", "pos":[-189.0,0.0,120.0]},
	{"name":"Cargo Terminal", "pos":[26.0,0.0,120.0]},
	{"name":"Tech Lab", "pos":[83.0,0.0,120.0]},
	{"name":"Port Authority", "pos":[139.0,0.0,-120.0]},
	{"name":"Dock 01", "pos":[139.0,0.0,-43.0]},
	{"name":"Marine Supply", "pos":[139.0,0.0,-6.0]},
	{"name":"Fish Market", "pos":[139.0,0.0,7.0]},
	{"name":"River Museum", "pos":[84.0,0.0,44.0]},
	{"name":"Pier 03", "pos":[199.0,0.0,38.0]}
]
const GARAGE_WALLS = [Rect2(-50,9,25,1), Rect2(-50,9,1,11), Rect2(-26,9,1,11)]
const WORKSHOP_WALLS = [Rect2(68,85,33,1),Rect2(68,85,1,21),Rect2(100,85,1,21)]
const DEALER_WALLS = [Rect2(-159,46,31,1),Rect2(-159,46,1,19),Rect2(-129,46,1,19)]
const WATER = Rect2(183,-151,29,302)
const PIERS = [Rect2(177,-42,34,8),Rect2(177,-4,34,8),Rect2(177,34,34,8),Rect2(177,110,34,8)]
const ROADBLOCK = Rect2(16,-3.8,5,7.6)
static func blocked(pos: Vector3, radius: float, closed_road: bool = false) -> bool:
	if absf(pos.x) > LIMIT.x-radius or absf(pos.z) > LIMIT.y-radius: return true
	var point = Vector2(pos.x,pos.z)
	for building in BUILDINGS:
		if building[1].grow(radius).has_point(point): return true
	for wall in GARAGE_WALLS:
		if wall.grow(radius).has_point(point): return true
	for wall in WORKSHOP_WALLS + DEALER_WALLS:
		if wall.grow(radius).has_point(point): return true
	if WATER.grow(radius).has_point(point):
		var on_pier = false
		for pier in PIERS:
			if pier.grow(-radius).has_point(point): on_pier = true
		if not on_pier: return true
	if closed_road and ROADBLOCK.grow(radius).has_point(point): return true
	return false
