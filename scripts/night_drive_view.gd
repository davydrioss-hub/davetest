extends "res://scripts/world_view.gd"
const Controls=preload("res://scripts/driving.gd")
var pitch=0.0
var car_look=0.0
var last_seat=""
var cab:Node3D
var cab_wheel:Node3D
var cab_speed:Label3D
var cab_wiper:Node3D
var bob_phase=0.0
func _ready() -> void:
	super._ready()
	camera.near=.045;camera.fov=Profile.fov
	yaw=PI
	Session.entered.connect(func():yaw=PI;pitch=0;last_seat="")
	_cab()
	environment.ambient_light_energy=.5
	environment.tonemap_exposure=1.05
	sun.light_energy=.5;sun.light_angular_distance=.8
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		environment.ssao_enabled=Profile.shadows;environment.ssao_radius=1.4;environment.ssao_intensity=1.3
		environment.ssil_enabled=Profile.shadows;environment.ssil_radius=4;environment.ssil_intensity=.7
		environment.ssr_enabled=Profile.shadows
		environment.glow_enabled=true;environment.glow_intensity=.5
func _input(event:InputEvent) -> void:
	if not Session.active or not capture_orbit:return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		var seated=Session.state().players.get(Profile.player_id,{}).get("vehicle","")!=""
		if seated:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				car_look=clampf(car_look-event.relative.x*Profile.sensitivity,-1.3,1.3)
				pitch=clampf(pitch-event.relative.y*Profile.sensitivity,-.65,.65)
		else:
			yaw=wrapf(yaw-event.relative.x*Profile.sensitivity,-PI,PI)
			pitch=clampf(pitch-event.relative.y*Profile.sensitivity,-1.25,1.25)
func movement(axis:Vector2) -> Vector2:
	return Controls.walk_axis(axis,yaw)
func heading() -> float:
	if Session.active:
		var p=Session.state().players.get(Profile.player_id,{})
		if p.get("vehicle","")!="":return float(Session.state().vehicles[p.vehicle].yaw)
	return yaw
func _process(dt:float) -> void:
	super._process(dt)
	if not is_instance_valid(cab):return
	cab.visible=false
	if not Session.active:return
	var s=Session.state()
	if not s.players.has(Profile.player_id):return
	var p=s.players[Profile.player_id]
	var target=World.vec(p.pos)+Vector3.UP*1.68
	var look=yaw
	var own=entities.get("players/"+Profile.player_id)
	if own:own.visible=false
	if p.vehicle!="":
		var v=s.vehicles[p.vehicle];var car:Node3D=entities["vehicles/"+p.vehicle]
		car.visible=false
		cab.visible=true;cab.position=car.position;cab.rotation.y=car.rotation.y;cab.scale=car.get_child(0).scale
		var seat=v.passengers.find(Profile.player_id)
		target=car.position+(Vector3(.5 if seat%2==0 else -.5,1.78,1.12 if seat<2 else .35)*cab.scale).rotated(Vector3.UP,car.rotation.y)
		if last_seat!=p.vehicle:car_look=0;pitch=-.09;first_person_frame=true
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):car_look=lerpf(car_look,0,1-exp(-6*dt));pitch=lerpf(pitch,-.09,1-exp(-6*dt))
		look=car.rotation.y+car_look;yaw=wrapf(car.rotation.y,-PI,PI)
		cab_wheel.rotation.y=-float(v.get("steer",0))*1.6
		cab_speed.text="%02d km/h"%roundi(absf(v.speed)*3.6)
		cab_wiper.rotation.z=-.55+sin(elapsed*5)*.8 if s.economy.weather.rain else -1.38
	elif last_seat!="":first_person_frame=true;pitch=0
	last_seat=p.vehicle
	# Use a separate first-person position; the inherited overview camera cannot feed back into it.
	var old=camera.get_meta("eye",target)
	if first_person_frame or old.distance_to(target)>7:old=target;first_person_frame=false
	var eye:Vector3=old.lerp(target,1-exp(-22*dt)) if p.vehicle=="" else target
	camera.set_meta("eye",eye)
	bob_phase+=old.distance_to(eye)
	var bob=sin(bob_phase*7)*.012 if Profile.head_bob and p.vehicle=="" else 0.0
	camera.position=eye+Vector3.UP*bob;camera.rotation=Vector3(pitch,look+PI,0);camera.fov=Profile.fov
	for vid in s.vehicles:
		var vehicle_node:Node3D=entities["vehicles/"+vid]
		var bulbs=vehicle_node.get_node_or_null("Signals")
		if not bulbs:
			bulbs=Node3D.new();bulbs.name="Signals";vehicle_node.add_child(bulbs)
			var spec=World.vehicle_spec(s.vehicles[vid])
			for side in [-1,1]:
				for z in [-1,1]:
					var light=box(bulbs,Vector3(.17,.13,.06),Vector3(side*(float(spec.width)*.42),1.1,z*(float(spec.length)/2+.04)),Color("59391a"))
					light.set_meta("side","left" if side>0 else "right")
		var blinking=fposmod(s.time,.9)<.45
		for bulb in bulbs.get_children():
			var on=blinking and s.vehicles[vid].get("indicator","off") in [bulb.get_meta("side"),"hazard"]
			bulb.material_override=_signal_material(on)
func _signal_material(on:bool) -> StandardMaterial3D:
	var key="signal_on" if on else "signal_off"
	if not pbr_cache.has(key):pbr_cache[key]=material(Color("ffa52a") if on else Color("59391a"),2 if on else 0)
	return pbr_cache[key]
func _cab() -> void:
	cab=Node3D.new();add_child(cab)
	var trim=Color("202e38");var paint=Color("356c73")
	box(cab,Vector3(2.3,.16,2.7),Vector3(0,.94,1.1),trim)
	box(cab,Vector3(2.4,.12,2.7),Vector3(0,2.47,1.1),paint)
	box(cab,Vector3(2.3,.12,.6),Vector3(0,1.4,2.0),trim)
	box(cab,Vector3(2.35,.18,.65),Vector3(0,1.2,2.35),paint)
	for side in [-1,1]:
		box(cab,Vector3(.09,1.12,.1),Vector3(side*1.12,1.95,2.25),paint)
		box(cab,Vector3(.1,1.1,.12),Vector3(side*1.12,1.94,.1),paint)
		box(cab,Vector3(.12,.5,2.1),Vector3(side*1.12,1.2,1.2),trim)
		box(cab,Vector3(.2,.36,.15),Vector3(side*1.4,1.75,1.94),trim)
		box(cab,Vector3(.16,.3,.02),Vector3(side*1.4,1.75,1.85),Color("637a87"))
		box(cab,Vector3(.66,.55,.12),Vector3(side*.5,1.3,.55),Color("30444d"))
		box(cab,Vector3(.35,.23,.14),Vector3(side*.5,1.63,.53),trim)
		for i in range(5):box(cab,Vector3(.15,.012,.025),Vector3(side*.84,1.33+i*.03,1.68),Color("738689"))
	cab_wheel=Node3D.new();cab.add_child(cab_wheel);cab_wheel.position=Vector3(.5,1.42,1.52);cab_wheel.rotation.x=deg_to_rad(70)
	var rim=MeshInstance3D.new();var torus=TorusMesh.new();torus.inner_radius=.19;torus.outer_radius=.24;torus.rings=32;torus.ring_segments=12
	rim.mesh=torus;rim.material_override=material(trim);cab_wheel.add_child(rim)
	box(cab_wheel,Vector3(.4,.045,.06),Vector3.ZERO,Color("687d85"))
	box(cab_wheel,Vector3(.1,.065,.14),Vector3.ZERO,trim)
	box(cab,Vector3(.5,.24,.06),Vector3(.5,1.38,1.7),Color("101a22"))
	cab_speed=label3(cab,"00 km/h",Vector3(.5,1.38,1.657),18,Color("9de4ce"));cab_speed.pixel_size=.005;cab_speed.rotation.y=PI;cab_speed.outline_size=0
	var radio=label3(cab,"AH / FM",Vector3(-.15,1.35,1.67),16,Color("86c8bb"));radio.rotation.y=PI;radio.pixel_size=.005
	cab_wiper=box(cab,Vector3(.025,.6,.025),Vector3(.58,1.59,2.26),trim)
	box(cab,Vector3(2.28,1.8,.1),Vector3(0,1.85,-.18),Color("405258"))
