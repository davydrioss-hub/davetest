extends RefCounted
const LOOPS=[Rect2(-51,-34,46,27),Rect2(5,-34,47,27),Rect2(-54,-65,107,22),Rect2(-174,-71,57,28),Rect2(118,-70,43,27),Rect2(-52,81,45,28),Rect2(-50,-103,100,17)]
const RADIUS=2.0
static func route(index: int) -> PackedVector3Array:
	var r:Rect2=LOOPS[posmod(index,LOOPS.size())]
	var points=PackedVector3Array()
	var centers=[Vector2(r.end.x-RADIUS,r.position.y+RADIUS),r.end-Vector2.ONE*RADIUS,Vector2(r.position.x+RADIUS,r.end.y-RADIUS),r.position+Vector2.ONE*RADIUS]
	for corner in range(4):
		for step in range(9):
			var angle=-PI/2+corner*PI/2+step*PI/16
			var p:Vector2=centers[corner]+Vector2(cos(angle),sin(angle))*RADIUS
			points.append(Vector3(p.x,0,p.y))
	return points
static func length(points: PackedVector3Array) -> float:
	var total=0.0
	for i in range(points.size()):total+=points[i].distance_to(points[(i+1)%points.size()])
	return total
static func sample(points: PackedVector3Array, distance: float) -> Dictionary:
	var remaining=fposmod(distance,length(points))
	for i in range(points.size()):
		var a=points[i];var b=points[(i+1)%points.size()];var span=a.distance_to(b)
		if remaining<=span:
			var d=(b-a).normalized()
			return {"position":a.lerp(b,remaining/span),"yaw":atan2(d.x,d.z)}
		remaining-=span
	return {"position":points[0],"yaw":0.0}
