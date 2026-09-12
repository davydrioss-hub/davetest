extends Node3D
## Presentation only. Entity state and collisions belong to WorldState on the host.
const World = preload("res://scripts/world_state.gd")
const Layout = preload("res://scripts/world_layout.gd")
const TEAL = Color("377e7e")
const GOLD = Color("f3bb72")
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var entities: Dictionary = {}
var markers: Dictionary = {}
var scene_cache: Dictionary = {}
var animation_library: AnimationLibrary
var preview: Dictionary
var yaw = 0.25
var distance = 10.5
var elevation = 0.46
var focus = Layout.SPAWN
var elapsed = 0.0
var rain: MultiMeshInstance3D
var gate: Node3D
var roadworks: Node3D
var garage_extension: Node3D
var asphalt: ShaderMaterial
var capture_orbit = true
var first_person_frame = true

func _ready() -> void:
	name="WorldView"
	var model = World.new(); model.create_world(); preview=model.data
	_build_city()
	_build_animations()
	camera = Camera3D.new(); camera.fov=58; camera.near=0.15; camera.far=280
	add_child(camera); camera.current=true
	camera.position=focus+Vector3(8,12,16); camera.look_at(focus+Vector3.UP)
	Session.entered.connect(func(): first_person_frame=true)

func material(color: Color, glow: float = 0.0, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new(); m.albedo_color=color; m.roughness=0.75; m.metallic=metal
	if glow>0:
		m.emission_enabled=true; m.emission=color; m.emission_energy_multiplier=glow
	return m
func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var m=MeshInstance3D.new(); var mesh=BoxMesh.new(); mesh.size=size
	m.mesh=mesh; m.material_override=material(color,glow); m.position=pos; parent.add_child(m)
	return m
func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, glow: float=0.0) -> MeshInstance3D:
	var m=MeshInstance3D.new(); var mesh=CylinderMesh.new(); mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=12
	m.mesh=mesh;m.material_override=material(color,glow);m.position=pos;parent.add_child(m)
	return m
func label3(parent: Node3D, title: String, pos: Vector3, size: int, color: Color, billboard: bool=false) -> Label3D:
	var l=Label3D.new(); l.text=title;l.font_size=size;l.pixel_size=0.008;l.modulate=color;l.outline_size=6;l.outline_modulate=Color("10212b");l.position=pos
	l.no_depth_test=false
	if billboard: l.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l);return l
func bounds(n: Node3D, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var combined = transform*n.transform
	var result=AABB()
	if n is MeshInstance3D: result=combined*n.mesh.get_aabb()
	for c in n.get_children():
		if c is Node3D:
			var next=bounds(c,combined)
			if next.size!=Vector3.ZERO: result=next if result.size==Vector3.ZERO else result.merge(next)
	return result
func asset(parent: Node3D, pack: String, file: String, pos: Vector3, size: Vector3=Vector3.ZERO) -> Node3D:
	var path="res://assets/"+pack+"/"+file
	if not scene_cache.has(path): scene_cache[path]=load(path)
	var n=scene_cache[path].instantiate()
	var wrapper=Node3D.new(); parent.add_child(wrapper);wrapper.add_child(n)
	var b=bounds(n)
	if size!=Vector3.ZERO:
		n.scale=size/b.size
		n.position=-Vector3(b.get_center().x,b.position.y,b.get_center().z)*n.scale
	wrapper.position=pos
	return wrapper
func light(parent: Node3D,pos:Vector3,color:Color,energy:float,reach:float) -> OmniLight3D:
	var l=OmniLight3D.new();l.position=pos;l.light_color=color;l.light_energy=energy;l.omni_range=reach;l.omni_attenuation=1.8
	l.distance_fade_enabled=true;l.distance_fade_begin=45;l.distance_fade_length=20;parent.add_child(l);return l

func _build_city() -> void:
	environment=Environment.new();environment.background_mode=Environment.BG_SKY
	var sky=Sky.new();var sky_mat=ProceduralSkyMaterial.new()
	sky_mat.sky_top_color=Color("152637");sky_mat.sky_horizon_color=Color("a37876");sky_mat.ground_bottom_color=Color("162c32");sky_mat.ground_horizon_color=Color("a37876");sky_mat.sky_curve=0.35
	sky.sky_material=sky_mat;environment.sky=sky;environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("afc9d0");environment.ambient_light_energy=0.38
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.tonemap_exposure=0.9
	environment.fog_enabled=true;environment.fog_light_color=Color("637882");environment.fog_density=0.0018;environment.fog_sky_affect=0.45
	var env=WorldEnvironment.new();env.environment=environment;add_child(env)
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-28,-45,0);sun.light_color=Color("ffd4aa");sun.light_energy=0.25;sun.shadow_enabled=Profile.shadows;sun.directional_shadow_max_distance=90;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;add_child(sun)
	get_viewport().msaa_3d=Viewport.MSAA_2X if Profile.shadows else Viewport.MSAA_DISABLED
	box(self,Vector3(450,0.5,450),Vector3(0,-0.4,0),Color("25484b"))
	var ground=box(self,Vector3(158,0.15,126),Vector3(0,-0.06,0),Color("263740"))
	var shader=Shader.new();shader.code="shader_type spatial; uniform bool wet=false; void fragment(){ vec2 p=UV*vec2(158.,126.); float n=fract(sin(dot(floor(p*24.),vec2(12.9898,78.233)))*43758.5453); ALBEDO=mix(vec3(.13,.18,.21),vec3(.20,.25,.27),n*.35); ROUGHNESS=wet?.32:.9; METALLIC=wet?.2:0.; }"
	asphalt=ShaderMaterial.new();asphalt.shader=shader;ground.material_override=asphalt
	# Pavements, raised curbs and road paint establish a readable street network.
	for x in [-28.0,28.0]:
		for z in [-19.0,19.0]:
			box(self,Vector3(46,0.24,28),Vector3(x,0.04,z),Color("819193"))
			box(self,Vector3(43.8,0.04,25.8),Vector3(x,0.18,z),Color("6e8083"))
	for z in [-38.0,0.0,38.0]:
		for x in range(-74,76,6):
			if absf(x)<6 or absf(absf(x)-56)<6: continue
			box(self,Vector3(2.8,0.025,0.13),Vector3(x,0.035,z),Color("d2bd84"))
	for x in [-56.0,0.0,56.0]:
		for z in range(-56,59,6):
			if absf(z)<6 or absf(absf(z)-38)<6: continue
			box(self,Vector3(0.13,0.025,2.8),Vector3(x,0.04,z),Color("d2bd84"))
		for z in [-38.0,0.0,38.0]:
			for offset in [-7.0,7.0]:
				for stripe in range(-3,4): box(self,Vector3(0.65,0.026,2.2),Vector3(x+stripe,0.035,z+offset),Color("c0c8c0"))
	for building in Layout.BUILDINGS:
		var rect:Rect2=building[1];var center=rect.get_center();var h:float=building[2]
		box(self,Vector3(rect.size.x+1,0.2,rect.size.y+1),Vector3(center.x,0.03,center.y),Color("99a49c"))
		var facade=asset(self,"city-kit-commercial",building[0]+".glb",Vector3(center.x,0.13,center.y),Vector3(rect.size.x,h,rect.size.y))
		var palette=[Color("72909b"),Color("b89483"),Color("818e8b"),Color("b2a18d"),Color("7895a5")]
		for mesh in facade.get_child(0).get_children():
			if mesh is MeshInstance3D:
				var mat=mesh.get_active_material(0).duplicate();mat.albedo_color=palette[absi(int(center.x+center.y))%5];mesh.material_override=mat
		# Additional illuminated storefront at the visible entrance.
		var front=rect.end.y+0.12 if center.y<0 else rect.position.y-0.12
		var facing=0.0 if center.y<0 else PI
		var sign=Node3D.new();add_child(sign);sign.position=Vector3(center.x,0,front);sign.rotation.y=facing
		box(sign,Vector3(rect.size.x*0.72,0.82,0.16),Vector3(0,3.0,0),Color("174e57"))
		label3(sign,building[3],Vector3(0,3.0,0.11),38,GOLD)
		for wx in [-3.8,-1.9,1.9,3.8]:
			box(sign,Vector3(1.55,1.65,0.07),Vector3(wx,1.6,0.13),Color("d4a971"),0.8)
		box(sign,Vector3(1.3,2.35,0.12),Vector3(0,1.3,0.14),Color("2b4f59"))
		for row in range(1,int(h/3)):
			for column in range(-2,3):
				var lit=posmod(column+row+int(center.x),3)!=0
				box(sign,Vector3(1.25,1.55,0.06),Vector3(column*2.55,3.0+row*2.6,0.15),Color("e9bc80") if lit else Color("344d5d"),0.45 if lit else 0.0)
		light(self,Vector3(center.x,3.3,front+(2 if center.y<0 else -2)),GOLD,1.4,10)
	# Skyline is decorative, outside the playable map.
	for i in range(18):
		var angle=i*TAU/18;var pos=Vector3(sin(angle)*145,0,cos(angle)*135)
		asset(self,"city-kit-commercial","building-skyscraper-a.glb",pos,Vector3(12,24+i%5*8,12))
	_build_garage()
	for x in [-51.0,5.0,51.0]:
		for z in [-33.0,6.0,33.0]:
			cylinder(self,0.1,5.8,Vector3(x,2.9,z),Color("253c45"))
			box(self,Vector3(1.8,0.12,0.12),Vector3(x+0.8,5.7,z),Color("33464c"))
			box(self,Vector3(0.9,0.1,0.45),Vector3(x+1.3,5.65,z),GOLD,2)
			light(self,Vector3(x+1.3,5.4,z),Color("ffcf95"),3,15)
	for i in range(22):
		var x = -50+i%11*10.0;var z=-6.5 if i<11 else 32.0
		if i>10 and x<-25: continue
		asset(self,"city-kit-suburban","tree-small.glb",Vector3(x,0.15,z),Vector3(2.4,4.5,2.4))
	# Pocket park, benches, planters and lamps.
	box(self,Vector3(18,0.12,19),Vector3(39,0.22,20),Color("456959"))
	box(self,Vector3(2.0,0.04,20),Vector3(39,0.3,20),Color("b3ada0"))
	for z in [13.0,24.0]:
		for x in [33.0,46.0]:
			asset(self,"city-kit-suburban","tree-large.glb",Vector3(x,0.25,z),Vector3(3.8,6,3.8))
			box(self,Vector3(2.1,0.18,0.6),Vector3(x,0.65,z+2.0),Color("a17657"))
			box(self,Vector3(2.1,0.6,0.14),Vector3(x,1.0,z+2.3),Color("a17657"))
	for i in range(7):
		var n=asset(self,"car-kit",["sedan.glb","taxi.glb","van.glb"][i%3],Vector3(-67+i*20,0,-34.7),Vector3(2.0,1.6,4.3));n.rotation.y=PI/2
	roadworks=Node3D.new();add_child(roadworks)
	for z in [-3.0,-1.5,0.0,1.5,3.0]:asset(roadworks,"car-kit","cone.glb",Vector3(18,0,z),Vector3(0.6,0.9,0.6))
	box(roadworks,Vector3(0.25,0.25,7),Vector3(18,1.1,0),GOLD)
	gate=box(self,Vector3(23,3.0,0.16),Vector3(-37.5,5.0,20),Color("437479"))
	for d in Layout.DESTINATIONS:
		var n=Node3D.new();n.position=World.vec(d.pos);add_child(n)
		cylinder(n,1.25,0.04,Vector3(0,0.08,0),TEAL,0.8)
		label3(n,d.name,Vector3(0,3.7,0),30,GOLD,true)
		markers[d.name]=n
	_build_rain()
	var grade=CanvasLayer.new();grade.layer=-1;add_child(grade)
	var screen=ColorRect.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.mouse_filter=Control.MOUSE_FILTER_IGNORE;grade.add_child(screen)
	var grading=Shader.new();grading.code="shader_type canvas_item; uniform sampler2D screen_tex:hint_screen_texture,filter_linear; void fragment(){vec2 uv=SCREEN_UV;vec3 c=texture(screen_tex,uv).rgb; float l=dot(c,vec3(.2126,.7152,.0722)); c=mix(vec3(l),c,1.1); c=mix(c,c*vec3(.90,1.01,1.07),.3*(1.-l)); float v=1.-.2*smoothstep(.18,.72,distance(uv,vec2(.5)));COLOR=vec4(c*v,1.);}"
	var gm=ShaderMaterial.new();gm.shader=grading;screen.material=gm

func _build_garage() -> void:
	box(self,Vector3(26,0.12,22),Vector3(-37.5,0.18,20),Color("777d78"))
	for wall in Layout.GARAGE_WALLS:
		box(self,Vector3(wall.size.x,4.8,wall.size.y),Vector3(wall.get_center().x,2.4,wall.get_center().y),Color("42626b"))
	# Open front and high clerestory keep the playable interior visible to the camera.
	box(self,Vector3(25.5,0.3,2.5),Vector3(-37.5,4.8,10),Color("253b48"))
	box(self,Vector3(25.5,0.6,0.5),Vector3(-37.5,4.6,20),Color("234a53"))
	label3(self,"AFTER HOURS  /  COURIER COMPANY",Vector3(-37.5,4.65,20.3),65,GOLD)
	for x in [-48.0,-38.0,-28.0]:
		box(self,Vector3(3.0,0.08,0.3),Vector3(x,4.0,12),Color("e3f9dc"),2)
		light(self,Vector3(x,3.6,15),Color("b9f4e4"),0.8,10)
	for y in [0.5,1.5,2.5]:
		box(self,Vector3(4,0.12,1.2),Vector3(-47,y,12),Color("bc8e5d"))
		for x in [-48.1,-47.0,-45.9]: box(self,Vector3(0.8,0.7,0.85),Vector3(x,y+0.4,12),Color("aa7c50"))
	for x in [-49.0,-45.0]: box(self,Vector3(0.1,3.0,1.4),Vector3(x,1.5,12),Color("354e56"))
	box(self,Vector3(2.2,0.9,0.9),Vector3(-43,0.65,16),Color("335760"))
	box(self,Vector3(1.0,0.65,0.1),Vector3(-43,1.5,15.85),Color("65d8c1"),1)
	label3(self,"[TAB]  ДИСПЕТЧЕРСКАЯ",Vector3(-43,2.5,16),26,GOLD,true)
	for i in range(8):
		var x=-45+i*2.0
		box(self,Vector3(1.7,0.025,1.9),Vector3(x,0.27,22),Color("426367"))
		box(self,Vector3(1.7,0.028,0.08),Vector3(x,0.30,23),GOLD)
	box(self,Vector3(6,0.025,7),Vector3(-31,0.28,28),Color("3b565e"))
	label3(self,"SERVICE",Vector3(-30,0.32,25),50,GOLD).rotation_degrees.x=-90
	box(self,Vector3(1.5,1.0,0.7),Vector3(-28,0.7,15),Color("bf6d55"))
	for i in range(4):cylinder(self,0.45,0.25,Vector3(-29,0.4+i*0.25,12),Color("243239"))
	garage_extension=Node3D.new();add_child(garage_extension)
	for i in range(4):box(garage_extension,Vector3(1.3,1.2,1.3),Vector3(-21,0.6,13+i*3),Color("748b83"))

func _build_animations() -> void:
	animation_library=AnimationLibrary.new()
	for file in ["idle","run"]:
		var n=load("res://assets/characters/"+file+".fbx").instantiate()
		var player=n.find_child("AnimationPlayer",true,false)
		var a=player.get_animation("Root|"+file.capitalize()).duplicate()
		a.loop_mode=Animation.LOOP_LINEAR;animation_library.add_animation(file,a);n.free()
func _character(parent: Node3D, variant: int) -> Node3D:
	var character=asset(parent,"characters","characterMedium.fbx",Vector3.ZERO)
	character.scale=Vector3.ONE*0.49
	var model=character.get_child(0)
	var mesh=model.find_child("characterMedium",true,false)
	var m=material(Color.WHITE);m.albedo_texture=load("res://assets/characters/"+["skaterMaleA","skaterFemaleA","criminalMaleA","cyborgFemaleA"][variant%4]+".png");mesh.material_override=m
	var player=AnimationPlayer.new();model.add_child(player);player.add_animation_library("",animation_library);player.play("idle")
	parent.set_meta("animation",player)
	return character
func _vehicle(parent: Node3D) -> void:
	var base=asset(parent,"car-kit","delivery-flat.glb",Vector3.ZERO,Vector3(2.5,2.0,5.4));base.name="Chassis"
	box(parent,Vector3(2.45,0.15,3.1),Vector3(0,0.9,-0.9),Color("3a4b54"))
	for x in [-1.2,1.2]:box(parent,Vector3(0.12,1.9,3.0),Vector3(x,1.9,-0.95),TEAL)
	box(parent,Vector3(2.5,0.16,3.1),Vector3(0,2.85,-0.95),TEAL)
	box(parent,Vector3(2.45,1.9,0.12),Vector3(0,1.9,0.6),TEAL)
	for side in [-1,1]:
		var pivot=Node3D.new();pivot.name="RearLeft" if side<0 else "RearRight";parent.add_child(pivot);pivot.position=Vector3(side*1.2,1.9,-2.48)
		box(pivot,Vector3(1.18,1.9,0.12),Vector3(-side*0.59,0,0),TEAL)
		box(pivot,Vector3(0.05,0.4,0.05),Vector3(-side*1.06,-0.05,-0.09),Color("b7c6bd"))
		box(parent,Vector3(0.25,0.15,0.05),Vector3(side*0.92,0.85,-2.65),Color("ff5543"),1.8)
		var logo=label3(parent,"AH / COURIER",Vector3(side*1.28,2.15,-0.8),38,GOLD);logo.rotation.y=side*PI/2
		light(parent,Vector3(side*0.8,1,2.6),Color("ffdfad"),0.7,7)
	label3(parent,"AH  024",Vector3(0,0.72,-2.76),22,Color("f6e6c1")).rotation.y=PI
func _parcel(parent: Node3D, kind: String) -> void:
	var large=kind=="heavy"
	box(parent,Vector3(1.5,0.85,0.9) if large else Vector3(0.65,0.6,0.55),Vector3(0,0.45 if large else 0.32,0),Color("b48b5b"))
	box(parent,Vector3(0.13,0.012,0.91 if large else 0.56),Vector3(0,0.89 if large else 0.627,0),Color("e2c38b"))
	box(parent,Vector3(0.32,0.18,0.015),Vector3(0,0.5,0.46 if large else 0.28),Color("e6e2cc"))
	if kind=="fragile": label3(parent,"↑ FRAGILE",Vector3(0,0.34,0.29),17,Color("813c32"))
	if large:
		box(parent,Vector3(1.65,0.12,1.05),Vector3(0,0.12,0),Color("43656d"))
		for x in [-0.6,0.6]:cylinder(parent,0.13,0.18,Vector3(x,0.1,0.35),Color("22353b")).rotation.z=PI/2
func _build_rain() -> void:
	rain=MultiMeshInstance3D.new();var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
	var mesh=BoxMesh.new();mesh.size=Vector3(0.016,0.42,0.016);mesh.material=material(Color("a5c6d1"),0.5);mm.mesh=mesh;mm.instance_count=260;rain.multimesh=mm;add_child(rain)

func _input(event: InputEvent) -> void:
	if not Session.active or not capture_orbit: return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw-=event.relative.x*0.006;elevation=clampf(elevation+event.relative.y*0.003,0.25,1.1)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(6,distance-1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(24,distance+1)
func movement(axis: Vector2) -> Vector2:
	return axis.rotated(-yaw)
func _process(dt: float) -> void:
	elapsed+=dt
	var s=Session.state() if Session.active else preview
	if s.is_empty(): return
	var live={}
	for domain in ["players","vehicles","items","npcs","police"]:
		for id in s[domain]:
			var record=s[domain][id];var key=domain+"/"+id;live[key]=true
			if not entities.has(key):
				var n=Node3D.new();add_child(n);entities[key]=n;n.position=World.vec(record.pos)
				match domain:
					"players", "npcs":
						_character(n,abs(id.hash()))
						if domain=="players":label3(n,record.nickname,Vector3(0,2.4,0),26,Color("c5efde"),true)
					"vehicles": _vehicle(n)
					"items": _parcel(n,record.kind)
					"police":asset(n,"car-kit","police.glb",Vector3.ZERO,Vector3(2,1.7,4.3))
			var n:Node3D=entities[key]
			var target=World.vec(record.pos);var target_yaw=float(record.get("yaw",0))
			n.visible=true
			if domain=="players": n.visible=record.connected and record.alive and record.vehicle==""
			if domain=="items":
				n.visible=not record.delivered
				if record.holder!="":
					var p=s.players[record.holder];target_yaw=p.yaw
					target=World.vec(p.pos)+Vector3(0,0.8 if record.kind!="heavy" else 0.0,0.9).rotated(Vector3.UP,target_yaw)
					n.visible=n.visible and p.connected
				elif record.container!="":
					var v=s.vehicles[record.container];var idx=v.cargo.find(id)
					target_yaw=v.yaw;target=World.vec(v.pos)+Vector3(-0.48+(idx%2)*0.96,1.0+floori(idx/6.0)*0.65,-1.8+(idx%6/2)*0.75).rotated(Vector3.UP,target_yaw)
					# Roof is faded out while accessing the cargo through its open doors.
					n.visible=n.visible and v.door_open
			var speed=n.position.distance_to(target)/maxf(dt,0.001)
			if n.position.distance_to(target)>8: n.position=target
			else: n.position=n.position.lerp(target,1-exp(-16*dt))
			n.rotation.y=lerp_angle(n.rotation.y,target_yaw,1-exp(-14*dt))
			if n.has_meta("animation"):
				var anim:AnimationPlayer=n.get_meta("animation");var wanted="run" if speed>0.45 else "idle"
				if anim.current_animation!=wanted: anim.play(wanted,0.16)
				anim.speed_scale=clampf(speed/4,0.45,1.35) if wanted=="run" else 1.0
			if domain=="vehicles":
				for side in [-1,1]:
					var door=n.get_node("RearLeft" if side<0 else "RearRight")
					door.rotation.y=lerp_angle(door.rotation.y,side*2.15 if record.door_open else 0.0,dt*8)
				for wheel in n.get_node("Chassis").get_child(0).get_children():
					if str(wheel.name).begins_with("wheel"): wheel.rotation.x+=float(record.speed)*dt*1.2
	for key in entities.keys():
		if not live.has(key): entities[key].queue_free();entities.erase(key)
	gate.position.y=lerpf(gate.position.y,4.3 if s.doors.gate_01.open else 1.5,dt*4)
	gate.scale.y=lerpf(gate.scale.y,0.12 if s.doors.gate_01.open else 1.0,dt*4)
	roadworks.visible=s.economy.weather.road_closed;garage_extension.visible=int(s.economy.company.garage)>0
	asphalt.set_shader_parameter("wet",s.economy.weather.rain)
	for d in Layout.DESTINATIONS:
		var needed=false
		for o in s.orders.values():
			if o.status=="active" and World.destination(o).name==d.name: needed=true
		var m:Node3D=markers[d.name];m.visible=needed
		if needed:m.get_child(0).scale=Vector3.ONE*(1.0+sin(elapsed*3)*0.1)
	if Session.active and s.players.has(Profile.player_id):
		var p=s.players[Profile.player_id];var target=World.vec(p.pos)+Vector3.UP*1.2
		if first_person_frame:focus=target;first_person_frame=false
		focus=focus.lerp(target,1-exp(-9*dt))
		var desired=focus+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
		# Camera line test against the same solid buildings, without trusting a client for gameplay.
		for step in range(1,31):
			var candidate=focus.lerp(desired,step/30.0)
			var occluded=false
			for b in Layout.BUILDINGS:
				if candidate.y<float(b[2])+0.5 and b[1].grow(0.25).has_point(Vector2(candidate.x,candidate.z)):occluded=true;break
			for wall in Layout.GARAGE_WALLS:
				if candidate.y<5.1 and wall.grow(0.3).has_point(Vector2(candidate.x,candidate.z)):occluded=true
			if candidate.y>3.9 and candidate.y<5.2 and Rect2(-50,19.4,25,1.2).has_point(Vector2(candidate.x,candidate.z)):occluded=true
			if occluded:desired=focus.lerp(desired,maxf(0.08,(step-1)/30.0));break
		camera.position=desired;camera.look_at(focus)
	else:
		focus=Vector3(-32,1,15);camera.position=focus+Vector3(19,10,29);camera.look_at(focus)
	rain.visible=s.economy.weather.rain
	if rain.visible:
		for i in range(rain.multimesh.instance_count):
			var pos=focus+Vector3(fposmod(i*7.21,32)-16,14-fposmod(elapsed*14+i*0.83,16),fposmod(i*3.71,32)-16)
			rain.multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.FORWARD,0.18),pos))
