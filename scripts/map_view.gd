extends Control
const Layout=preload("res://scripts/world_layout.gd")
const World=preload("res://scripts/world_state.gd")
func _ready() -> void:
	custom_minimum_size=Vector2(640,510)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func point(pos: Vector3) -> Vector2:
	return Vector2((pos.x+80)/160*size.x,(pos.z+64)/128*size.y)
func _process(_dt: float) -> void: queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("182e39"))
	for z in [-38,0,38]:draw_line(point(Vector3(-80,0,z)),point(Vector3(80,0,z)),Color("425967"),29)
	for x in [-56,0,56]:draw_line(point(Vector3(x,0,-64)),point(Vector3(x,0,64)),Color("425967"),29)
	for b in Layout.BUILDINGS:
		var r:Rect2=b[1];draw_rect(Rect2(point(Vector3(r.position.x,0,r.position.y)),r.size/Vector2(160,128)*size),Color("6a898b"))
	var font=ThemeDB.fallback_font
	var garage=point(Layout.GARAGE);draw_circle(garage,8,Color("72d6bf"));draw_string(font,garage+Vector2(12,5),"ГАРАЖ",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("aee8d7"))
	if not Session.active:return
	var s=Session.state()
	if s.economy.weather.road_closed:draw_line(point(Vector3(18,0,-4)),point(Vector3(18,0,4)),Color("ed7c59"),8)
	for o in s.orders.values():
		if o.status!="active":continue
		var d=World.destination(o);var p=point(World.vec(d.pos))
		draw_circle(p,9,Color("f3bd77"));draw_string(font,p+Vector2(12,5),d.name,HORIZONTAL_ALIGNMENT_LEFT,170,14,Color("f3bd77"))
	var van=point(World.vec(s.vehicles.van_01.pos));draw_rect(Rect2(van-Vector2(5,8),Vector2(10,16)),Color("f1be7b"))
	for id in s.players:
		var p=s.players[id]
		if not p.connected:continue
		var at=point(World.vec(p.pos));var color=Color("e9f6e9") if id==Profile.player_id else Color("62cbe8")
		draw_circle(at,5,color)
		draw_line(at,at+Vector2(sin(p.yaw),cos(p.yaw))*13,color,2)
