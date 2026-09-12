class_name WorldLayout
extends RefCounted
const SPAWN = Vector3(-43, 0, 28)
const GARAGE = Vector3(-43, 0, 16)
const VAN = Vector3(-34, 0, 29)
const REPAIR = Vector3(-30, 0, 24)
const LIMIT = Vector2(77, 61)
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
	["building-j", Rect2(64,12,13,18), 11.0, "STATION"]
]
const DESTINATIONS = [
	{"name":"Corner Coffee", "pos":[-16.0,0.0,-8.0]},
	{"name":"Night Market", "pos":[39.0,0.0,-8.0]},
	{"name":"North Residence", "pos":[-41.0,0.0,-43.0]},
	{"name":"Riverside Clinic", "pos":[17.0,0.0,9.0]},
	{"name":"Lantern Bistro", "pos":[40.0,0.0,45.0]}
]
const GARAGE_WALLS = [Rect2(-50,9,25,1), Rect2(-50,9,1,11), Rect2(-26,9,1,11)]
const ROADBLOCK = Rect2(16,-3.8,5,7.6)
static func blocked(pos: Vector3, radius: float, closed_road: bool = false) -> bool:
	if absf(pos.x) > LIMIT.x-radius or absf(pos.z) > LIMIT.y-radius: return true
	var point = Vector2(pos.x,pos.z)
	for building in BUILDINGS:
		if building[1].grow(radius).has_point(point): return true
	for wall in GARAGE_WALLS:
		if wall.grow(radius).has_point(point): return true
	if closed_road and ROADBLOCK.grow(radius).has_point(point): return true
	return false
