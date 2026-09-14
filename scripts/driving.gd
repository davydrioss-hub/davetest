extends RefCounted
## +Z is the nose; viewed from the driver's seat, right is local -X.
static func forward(heading: float) -> Vector3:
	return Vector3(sin(heading),0,cos(heading))
static func walk_axis(axis: Vector2, heading: float) -> Vector2:
	var world=Vector3(-axis.x,0,-axis.y).rotated(Vector3.UP,heading)
	return Vector2(world.x,world.z).limit_length()
static func bearing(delta: Vector3, heading: float) -> float:
	return wrapf(heading-atan2(delta.x,delta.z),-PI,PI)
static func step(v: Dictionary, axis: Vector2, top: float, length: float, dt: float) -> void:
	var throttle=clampf(-axis.y,-1,1)
	var speed=float(v.speed)
	var goal=throttle*(top if throttle>=0 else minf(5.0,top))
	var rate=7.0 if throttle>=0 else 4.2
	if throttle*speed<0:rate=13.0
	if absf(throttle)<0.01:rate=2.2
	if v.brake:goal=0;rate=24.0
	if top<=0:goal=0;rate=16.0
	v.speed=move_toward(speed,goal,rate*dt)
	v.steer=move_toward(float(v.get("steer",0)),clampf(axis.x,-1,1),dt*3.2)
	var angle=float(v.steer)*0.56/(1.0+absf(v.speed)*0.045)
	v.yaw=wrapf(float(v.yaw)-tan(angle)*float(v.speed)/maxf(2.2,length*0.56)*dt,-PI,PI)
