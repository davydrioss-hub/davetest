extends RefCounted
const Layout=preload("res://scripts/world_layout.gd")
static func clear(a:Vector3,b:Vector3,closed:bool) -> bool:
	var steps=ceili(a.distance_to(b)/1.5)
	for i in range(steps+1):
		if Layout.blocked(a.lerp(b,float(i)/maxi(steps,1)),.65,closed):return false
	return true
static func path(origin:Vector3,goal:Vector3,closed:bool) -> PackedVector3Array:
	origin.y=0;goal.y=0
	if origin.distance_to(goal)<12 and clear(origin,goal,closed):return PackedVector3Array([origin,goal])
	var nodes:Array[Vector3]=[]
	for x in Layout.ROAD_X:
		for z in Layout.ROAD_Z:nodes.append(Vector3(x,0,z))
	for endpoint in [origin,goal]:
		for x in Layout.ROAD_X:
			var p=Vector3(x,0,endpoint.z)
			if not p in nodes:nodes.append(p)
		for z in Layout.ROAD_Z:
			var p=Vector3(endpoint.x,0,z)
			if not p in nodes:nodes.append(p)
	var graph=AStar3D.new()
	for i in range(nodes.size()):graph.add_point(i,nodes[i])
	for i in range(nodes.size()):
		for j in range(i+1,nodes.size()):
			var a=nodes[i];var b=nodes[j]
			var road=(is_equal_approx(a.x,b.x) and a.x in Layout.ROAD_X) or (is_equal_approx(a.z,b.z) and a.z in Layout.ROAD_Z)
			if road and a.distance_to(b)<=56.1 and clear(a,b,closed):graph.connect_points(i,j)
	var first=nodes.size();var last=first+1
	graph.add_point(first,origin);graph.add_point(last,goal)
	for i in range(nodes.size()):
		if origin.distance_to(nodes[i])<65 and clear(origin,nodes[i],closed):graph.connect_points(first,i)
		if goal.distance_to(nodes[i])<65 and clear(goal,nodes[i],closed):graph.connect_points(last,i)
	var raw=graph.get_point_path(first,last);var result=PackedVector3Array()
	for i in range(raw.size()):
		if i>0 and i<raw.size()-1 and (raw[i]-raw[i-1]).normalized().dot((raw[i+1]-raw[i]).normalized())>.995:continue
		result.append(raw[i])
	return result
