extends Control
signal chosen(title: String, pos: Vector3)
const Layout=preload("res://scripts/world_layout.gd")
const World=preload("res://scripts/world_state.gd")
var targets: Array=[]
func _ready() -> void:
	custom_minimum_size=Vector2(950,490)
	mouse_filter=Control.MOUSE_FILTER_STOP
func point(pos: Vector3) -> Vector2:
	return Vector2((pos.x+Layout.LIMIT.x)/(Layout.LIMIT.x*2)*size.x,(pos.z+Layout.LIMIT.y)/(Layout.LIMIT.y*2)*size.y)
func _process(_dt: float) -> void: queue_redraw()
func marker(title: String,pos: Vector3,color: Color,radius: float=6,label: bool=true) -> void:
	var at=point(pos);draw_circle(at,radius+2,Color("142634"));draw_circle(at,radius,color)
	if label:draw_string(ThemeDB.fallback_font,at+Vector2(10,4),title,HORIZONTAL_ALIGNMENT_LEFT,190,13,color)
	targets.append({"name":title,"pos":pos,"at":at})
func _draw() -> void:
	targets.clear();draw_rect(Rect2(Vector2.ZERO,size),Color("193542"))
	for d in Layout.DISTRICTS:
		var r:Rect2=d.rect;var top=point(Vector3(r.position.x,0,r.position.y));draw_rect(Rect2(top,r.size/(Layout.LIMIT*2)*size),d.color)
	for z in Layout.ROAD_Z:draw_line(point(Vector3(-211,0,z)),point(Vector3(182,0,z)),Color("7a8583"),10)
	for x in Layout.ROAD_X:draw_line(point(Vector3(x,0,-151)),point(Vector3(x,0,151)),Color("7a8583"),10)
	for r in Layout.PIERS:draw_rect(Rect2(point(Vector3(r.position.x,0,r.position.y)),r.size/(Layout.LIMIT*2)*size),Color("7a8583"))
	for b in Layout.BUILDINGS:
		var r:Rect2=b[1];draw_rect(Rect2(point(Vector3(r.position.x,0,r.position.y)),r.size/(Layout.LIMIT*2)*size),Color("91a3a1"))
	for d in Layout.DISTRICTS:
		var r:Rect2=d.rect;draw_string(ThemeDB.fallback_font,point(Vector3(r.position.x+4,0,r.position.y+9)),d.name,HORIZONTAL_ALIGNMENT_LEFT,290,12,Color("d4e0d6"))
	marker("ГАРАЖ",Layout.GARAGE,Color("80dfc0"))
	marker("АВТОСАЛОН",Layout.DEALER,Color("94cdfa"))
	marker("МАСТЕРСКАЯ",Layout.WORKSHOP,Color("94cdfa"))
	if not Session.active:return
	var s=Session.state()
	if s.economy.weather.road_closed:draw_line(point(Vector3(18,0,-4)),point(Vector3(18,0,4)),Color("ed7c59"),6)
	for a in s.activities.values():
		if a.status=="completed":continue
		marker(a.title,World.vec(a.pos),Color("8ddea7") if a.kind=="parts" else Color("f5a86e"),3 if a.kind=="parts" else 5,false)
	for o in s.orders.values():
		if o.status!="active":continue
		var d=World.destination(o);marker(d.name,World.vec(d.pos),Color("f3bd77"),7)
	for vid in s.vehicles:
		var v=s.vehicles[vid]
		if not v.owned:continue
		var at=point(World.vec(v.pos));draw_rect(Rect2(at-Vector2(3,5),Vector2(6,10)),Color("6fbaff"))
		targets.append({"name":World.vehicle_spec(v).name,"pos":World.vec(v.pos),"at":at})
	for id in s.players:
		var p=s.players[id]
		if not p.connected:continue
		var at=point(World.vec(p.pos));var color=Color("ffffff") if id==Profile.player_id else Color("62cbe8")
		draw_circle(at,4,color);draw_line(at,at+Vector2(sin(p.yaw),cos(p.yaw))*12,color,2)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var best=20.0;var selected={}
		for target in targets:
			var d=event.position.distance_to(target.at)
			if d<best:best=d;selected=target
		if not selected.is_empty():chosen.emit(selected.name,selected.pos)
