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
var asphalt: StandardMaterial3D
var pbr_cache: Dictionary = {}
var activity_nodes: Dictionary = {}
var staff_nodes: Dictionary = {}
var capture_orbit = true
var surface_cache:Dictionary = {}
var first_person_frame = true

func _ready() -> void:
	name="WorldView"
	var model = World.new(); model.create_world(); preview=model.data
	_build_city()
	_build_animations()
	camera = Camera3D.new(); camera.fov=58; camera.near=0.15; camera.far=560
	add_child(camera); camera.current=true
	camera.position=focus+Vector3(8,12,16); camera.look_at(focus+Vector3.UP)
	Session.entered.connect(func(): first_person_frame=true)

func material(color: Color, glow: float = 0.0, metal: float = 0.0) -> StandardMaterial3D:
	var key=str(color)+str(glow)+str(metal)
	if surface_cache.has(key):return surface_cache[key]
	var m = StandardMaterial3D.new();surface_cache[key]=m; m.albedo_color=color; m.roughness=0.75; m.metallic=metal
	if glow>0:
		m.emission_enabled=true; m.emission=color; m.emission_energy_multiplier=glow
	return m
func pbr(name: String, scale_uv: float=0.25) -> StandardMaterial3D:
	var key=name+str(scale_uv)
	if pbr_cache.has(key):return pbr_cache[key]
	var m=StandardMaterial3D.new()
	m.albedo_texture=load("res://assets/hd/"+name+"_albedo.jpg")
	m.normal_enabled=true;m.normal_texture=load("res://assets/hd/"+name+"_normal.jpg");m.normal_scale=0.4
	m.roughness_texture=load("res://assets/hd/"+name+"_roughness.jpg");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar=true;m.uv1_world_triplanar=true;m.uv1_scale=Vector3.ONE*scale_uv
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color=Color("818b93") if name=="asphalt_02" else Color("c5c9ca")
	pbr_cache[key]=m;return m
func detailed(parent: Node3D,size: Vector3,pos: Vector3,surface: String,scale_uv: float=0.25) -> MeshInstance3D:
	var mesh=box(parent,size,pos,Color.WHITE);mesh.material_override=pbr(surface,scale_uv);return mesh
func cull(n: Node, reach: float) -> void:
	if n is GeometryInstance3D:n.visibility_range_end=reach;n.visibility_range_end_margin=15
	for child in n.get_children():cull(child,reach)
func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var m=MeshInstance3D.new(); var mesh=BoxMesh.new(); mesh.size=size
	m.mesh=mesh; m.material_override=material(color,glow); m.position=pos; parent.add_child(m)
	return m
func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, glow: float=0.0) -> MeshInstance3D:
	var m=MeshInstance3D.new(); var mesh=CylinderMesh.new(); mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=24
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
	if pack=="city-kit-suburban" and file.begins_with("tree-"):return _tree_detail(parent,pos,size.y,int(pos.x*7+pos.z*13))
	var path="res://assets/"+pack+"/"+file
	if not scene_cache.has(path): scene_cache[path]=load(path)
	var n=scene_cache[path].instantiate()
	var wrapper=Node3D.new(); parent.add_child(wrapper);wrapper.add_child(n)
	var b=bounds(n)
	if size!=Vector3.ZERO:
		n.scale=size/b.size
		n.position=-Vector3(b.get_center().x,b.position.y,b.get_center().z)*n.scale
	wrapper.position=pos
	cull(wrapper,230)
	return wrapper
func light(parent: Node3D,pos:Vector3,color:Color,energy:float,reach:float) -> OmniLight3D:
	var l=OmniLight3D.new();l.position=pos;l.light_color=color;l.light_energy=energy;l.omni_range=reach;l.omni_attenuation=1.8
	l.distance_fade_enabled=true;l.distance_fade_begin=45;l.distance_fade_length=20;parent.add_child(l);return l

func _build_city() -> void:
	environment=Environment.new();environment.background_mode=Environment.BG_SKY
	var sky=Sky.new();var sky_mat=ShaderMaterial.new();var sky_shader=Shader.new()
	# Use the unobstructed upper sky of the panorama; exclude photographed foreground buildings.
	sky_shader.code="shader_type sky; uniform sampler2D clouds:source_color,filter_linear; void sky(){vec2 uv=vec2(SKY_COORDS.x,clamp(SKY_COORDS.y*.56,.025,.28));vec3 c=texture(clouds,uv).rgb;float h=pow(clamp(SKY_COORDS.y*2.,0.,1.),3.);COLOR=mix(mix(vec3(.08,.16,.30),vec3(.55,.32,.20),h),c*.35,.25);}"
	sky_mat.shader=sky_shader;sky_mat.set_shader_parameter("clouds",load("res://assets/hd/twilight_sunset.hdr"))
	sky.sky_material=sky_mat;sky.radiance_size=Sky.RADIANCE_SIZE_256;environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("adbed1");environment.ambient_light_energy=0.42
	environment.background_energy_multiplier=1.0
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.tonemap_exposure=0.9
	environment.fog_enabled=true;environment.fog_light_color=Color("637882");environment.fog_density=0.0013;environment.fog_sky_affect=0.45
	var env=WorldEnvironment.new();env.environment=environment;add_child(env)
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-28,-45,0);sun.light_color=Color("dfc4b4");sun.light_energy=0.32;sun.shadow_enabled=Profile.shadows;sun.directional_shadow_max_distance=90;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;add_child(sun)
	get_viewport().msaa_3d=Viewport.MSAA_4X if Profile.shadows else Viewport.MSAA_DISABLED
	box(self,Vector3(650,0.5,560),Vector3(-105,-0.5,0),Color("344d42"))
	var ground=detailed(self,Vector3(394,0.15,302),Vector3(-14,-0.06,0),"asphalt_02",0.18)
	asphalt=ground.material_override
	_build_water()
	# Pavements, raised curbs and road paint establish a readable street network.
	for x in [-28.0,28.0]:
		for z in [-19.0,19.0]:
			box(self,Vector3(46,0.24,28),Vector3(x,0.04,z),Color("819193"))
			box(self,Vector3(43.8,0.04,25.8),Vector3(x,0.18,z),Color("6e8083"))
	for z in Layout.ROAD_Z:
		for x in range(-206,179,6):
			if absf(fposmod(x+28,56)-28)<6: continue
			box(self,Vector3(2.8,0.025,0.13),Vector3(x,0.035,z),Color("d2bd84"))
	for x in Layout.ROAD_X:
		for z in range(-146,147,6):
			if absf(fposmod(z+19,38)-19)<6: continue
			box(self,Vector3(0.13,0.025,2.8),Vector3(x,0.04,z),Color("d2bd84"))
		for z in [-114.0,-38.0,38.0,114.0]:
			for offset in [-7.0,7.0]:
				for stripe in range(-3,4): box(self,Vector3(0.65,0.026,2.2),Vector3(x+stripe,0.035,z+offset),Color("c0c8c0"))
	for building in Layout.BUILDINGS:
		var rect:Rect2=building[1];var center=rect.get_center();var h:float=building[2]
		box(self,Vector3(rect.size.x+1,0.2,rect.size.y+1),Vector3(center.x,0.03,center.y),Color("99a49c"))
		var facade=asset(self,building[4] if building.size()>4 else "city-kit-commercial",building[0]+".glb",Vector3(center.x,0.13,center.y),Vector3(rect.size.x,h,rect.size.y))
		var palette=[Color("72909b"),Color("b89483"),Color("818e8b"),Color("b2a18d"),Color("7895a5")]
		for mesh in facade.get_child(0).get_children():
			if mesh is MeshInstance3D:
				var mat=mesh.get_active_material(0).duplicate();mat.albedo_color=palette[absi(int(center.x+center.y))%5];mesh.material_override=mat
		# Real material detail on the plinth; original model windows and roof remain intact.
		for side in [-1.0,1.0]:
			detailed(self,Vector3(rect.size.x,h-.4,.12),Vector3(center.x,h/2,center.y+side*rect.size.y/2),"brick_wall_003",0.22)
			detailed(self,Vector3(.12,h-.4,rect.size.y),Vector3(center.x+side*rect.size.x/2,h/2,center.y),"brick_wall_003",0.22)
		detailed(self,Vector3(rect.size.x+3,0.09,rect.size.y+3),Vector3(center.x,0.08,center.y),"brick_pavement",0.2)
		# Additional illuminated storefront at the visible entrance.
		var front=rect.end.y+0.12 if center.y<0 else rect.position.y-0.12
		var facing=0.0 if center.y<0 else PI
		var sign=Node3D.new();add_child(sign);sign.position=Vector3(center.x,0,front);sign.rotation.y=facing
		_front_detail(sign,rect,h,absi(int(center.x+center.y)))
		var title=label3(sign,building[3],Vector3(0,3,.32),30,GOLD);title.pixel_size=minf(.006,rect.size.x*.75/maxi(1,building[3].length())/26)
		light(self,Vector3(center.x,3.3,front+(2 if center.y<0 else -2)),GOLD,1.4,10)
	var horizon=Node3D.new();add_child(horizon);horizon.set_meta("keep_static",true)
	for i in range(18):
		var angle=i*TAU/18;var pos=Vector3(sin(angle)*310,0,cos(angle)*260);var height=22+i%5*9
		box(horizon,Vector3(15,height,15),pos+Vector3.UP*height/2,Color("667580"))
		box(horizon,Vector3(11,2,11),pos+Vector3.UP*(height+1),Color("526574"))
	cull(horizon,540)
	_build_garage()
	_build_districts()
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
	_bake_static()

func _build_garage() -> void:
	detailed(self,Vector3(26,0.12,22),Vector3(-37.5,0.18,20),"concrete_floor_worn_02",0.22)
	for wall in Layout.GARAGE_WALLS:
		detailed(self,Vector3(wall.size.x,4.8,wall.size.y),Vector3(wall.get_center().x,2.4,wall.get_center().y),"brick_wall_003",0.22)
	detailed(self,Vector3(25.5,.25,11),Vector3(-37.5,4.95,14.5),"concrete_floor_worn_02",.25)
	for x in [-48.0,-42.0,-36.0,-30.0]:box(self,Vector3(.18,.3,11),Vector3(x,4.65,14.5),Color("344349"))
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
	var source=animation_library.get_animation("run");var idle=animation_library.get_animation("idle")
	var walk=source.duplicate();walk.length=1.05
	for track in range(walk.get_track_count()):
		var path=walk.track_get_path(track);var base=idle.find_track(path,walk.track_get_type(track))
		for key in range(walk.track_get_key_count(track)):
			walk.track_set_key_time(track,key,source.track_get_key_time(track,key)*1.05/source.length)
			if base<0:continue
			var neutral=idle.track_get_key_value(base,0);var value=source.track_get_key_value(track,key)
			var amount=.48 if "Leg" in str(path) or "Foot" in str(path) or "Toe" in str(path) else .3
			if value is Quaternion:walk.track_set_key_value(track,key,neutral.slerp(value,amount))
			elif value is Vector3:walk.track_set_key_value(track,key,neutral.lerp(value,.18))
	animation_library.add_animation("walk",walk)
func _character(parent: Node3D, variant: int) -> Node3D:
	var character=asset(parent,"characters","characterMedium.fbx",Vector3.ZERO)
	character.scale=Vector3.ONE*0.49
	var model=character.get_child(0)
	var mesh=model.find_child("characterMedium",true,false)
	var m=material(Color.WHITE);m.albedo_texture=load("res://assets/characters/"+["skaterMaleA","skaterFemaleA","criminalMaleA","cyborgFemaleA"][variant%4]+".png");mesh.material_override=m
	var player=AnimationPlayer.new();model.add_child(player);player.add_animation_library("",animation_library);player.play("idle")
	parent.set_meta("animation",player)
	return character
func _vehicle(parent: Node3D, vid: String="van_01") -> void:
	var body=Node3D.new();parent.add_child(body)
	var spec=World.FLEET[vid]
	body.scale=Vector3(float(spec.width)/2.5,0.82 if vid=="courier_02" else (1.2 if vid=="truck_03" else 1.0),float(spec.length)/5.4)
	parent=body
	var paint=Color("d18343") if vid=="courier_02" else (Color("596b94") if vid=="truck_03" else TEAL)
	var base=asset(parent,"car-kit","delivery-flat.glb",Vector3.ZERO,Vector3(2.5,2.0,5.4));base.name="Chassis"
	box(parent,Vector3(2.45,0.15,3.1),Vector3(0,0.9,-0.9),Color("3a4b54"))
	for x in [-1.2,1.2]:box(parent,Vector3(0.12,1.9,3.0),Vector3(x,1.9,-0.95),paint)
	box(parent,Vector3(2.5,0.16,3.1),Vector3(0,2.85,-0.95),paint)
	box(parent,Vector3(2.45,1.9,0.12),Vector3(0,1.9,0.6),paint)
	for side in [-1,1]:
		var pivot=Node3D.new();pivot.name="RearLeft" if side<0 else "RearRight";parent.add_child(pivot);pivot.position=Vector3(side*1.2,1.9,-2.48)
		box(pivot,Vector3(1.18,1.9,0.12),Vector3(-side*0.59,0,0),paint)
		box(pivot,Vector3(0.05,0.4,0.05),Vector3(-side*1.06,-0.05,-0.09),Color("b7c6bd"))
		box(parent,Vector3(0.25,0.15,0.05),Vector3(side*0.92,0.85,-2.65),Color("ff5543"),1.8)
		var logo=label3(parent,"AH / "+("EXPRESS" if vid=="courier_02" else "CARGO" if vid=="truck_03" else "COURIER"),Vector3(side*1.28,2.15,-0.8),38,GOLD);logo.rotation.y=side*PI/2
		light(parent,Vector3(side*0.8,1,2.6),Color("ffdfad"),0.7,7)
	label3(parent,"AH  024",Vector3(0,0.72,-2.76),22,Color("f6e6c1")).rotation.y=PI
func _parcel(parent: Node3D, kind: String) -> void:
	var hint=label3(parent,"ЗАКАЗ [E]",Vector3(0,1.5,0),21,GOLD,true);hint.name="PickupHint"
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
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(30,distance+1)
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
					"vehicles": _vehicle(n,id)
					"items": _parcel(n,record.kind)
					"police":asset(n,"car-kit","police.glb",Vector3.ZERO,Vector3(2,1.7,4.3))
			var n:Node3D=entities[key]
			var target=World.vec(record.pos);var target_yaw=float(record.get("yaw",0))
			n.visible=true
			if domain=="players": n.visible=record.connected and record.alive and record.vehicle==""
			if domain=="items":
				n.visible=not record.delivered
				n.get_node("PickupHint").visible=record.holder=="" and record.container==""
				if record.holder!="":
					var p=s.players[record.holder];target_yaw=p.yaw
					target=World.vec(p.pos)+Vector3(0,0.8 if record.kind!="heavy" else 0.0,0.9).rotated(Vector3.UP,target_yaw)
					n.visible=n.visible and p.connected
				elif record.container!="":
					var v=s.vehicles[record.container];var idx=v.cargo.find(id)
					var spec=World.vehicle_spec(v)
					target_yaw=v.yaw;target=World.vec(v.pos)+Vector3(-0.48+(idx%2)*0.96,0.95+floori(idx/6.0)*0.5,(-1.8+(idx%6/2)*0.75)*float(spec.length)/5.4).rotated(Vector3.UP,target_yaw)
					# Roof is faded out while accessing the cargo through its open doors.
					n.visible=n.visible and v.door_open
			var previous:Vector3=n.position
			if n.position.distance_to(target)>8: n.position=target
			else: n.position=n.position.lerp(target,1-exp(-16*dt))
			n.rotation.y=lerp_angle(n.rotation.y,target_yaw,1-exp(-14*dt))
			if n.has_meta("animation"):
				var measured=n.position.distance_to(previous)/maxf(dt,.001)
				var speed=lerpf(float(n.get_meta("speed",0.0)),measured,1-exp(-6*dt))
				if domain=="npcs":speed=float(record.get("speed",1.25))
				n.set_meta("speed",speed)
				var anim:AnimationPlayer=n.get_meta("animation");var wanted=("run" if speed>3 else "walk") if speed>.15 else "idle"
				if anim.current_animation!=wanted: anim.play(wanted,0.16)
				anim.speed_scale=clampf(speed/(4.4 if wanted=="run" else 1.35),.55,1.6) if wanted!="idle" else 1.0
			if domain=="vehicles":
				for side in [-1,1]:
					var door=n.get_child(0).get_node("RearLeft" if side<0 else "RearRight")
					door.rotation.y=lerp_angle(door.rotation.y,side*2.15 if record.door_open else 0.0,dt*8)
				for wheel in n.get_child(0).get_node("Chassis").get_child(0).get_children():
					if str(wheel.name).begins_with("wheel"): wheel.rotation.x+=float(record.speed)*dt*1.2
	for key in entities.keys():
		if not live.has(key): entities[key].queue_free();entities.erase(key)
	gate.position.y=lerpf(gate.position.y,4.3 if s.doors.gate_01.open else 1.5,dt*4)
	gate.scale.y=lerpf(gate.scale.y,0.12 if s.doors.gate_01.open else 1.0,dt*4)
	roadworks.visible=s.economy.weather.road_closed;garage_extension.visible=int(s.economy.company.garage)>0
	asphalt.roughness=0.32 if s.economy.weather.rain else 1.0
	asphalt.metallic=0.22 if s.economy.weather.rain else 0.0
	asphalt.albedo_color=Color("556d7b") if s.economy.weather.rain else Color("818b93")
	_update_activities(s)
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
			for wall in Layout.GARAGE_WALLS+Layout.WORKSHOP_WALLS+Layout.DEALER_WALLS:
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

func _lamp(pos: Vector3) -> void:
	var n=Node3D.new();add_child(n);n.position=pos
	cylinder(n,0.085,6.8,Vector3(0,3.4,0),Color("293e49"))
	box(n,Vector3(1.8,0.12,0.12),Vector3(0.8,6.7,0),Color("344d59"))
	box(n,Vector3(0.8,0.1,0.4),Vector3(1.3,6.65,0),GOLD,2)
	light(n,Vector3(1.3,6.35,0),Color("ffe0b6"),2.4,17)
	cull(n,130)
func _build_water() -> void:
	var water=box(self,Vector3(350,0.12,650),Vector3(358,-0.26,0),Color("345767"))
	var sh=Shader.new();sh.code="shader_type spatial; varying vec3 world_pos; void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;VERTEX.y+=sin(world_pos.x*.7+TIME*.9)*.04+sin(world_pos.z*.43-TIME*1.2)*.025;} void fragment(){float waves=sin(world_pos.x*1.6+TIME*1.2+sin(world_pos.z*.45))*sin(world_pos.z*.65-TIME*.5); ALBEDO=mix(vec3(.035,.09,.13),vec3(.14,.28,.32),waves*.5+.5);ROUGHNESS=.19;METALLIC=.65;NORMAL_MAP=normalize(vec3(waves*.12,.12*sin(world_pos.x+TIME),1.))*0.5+0.5;}"
	var m=ShaderMaterial.new();m.shader=sh;water.material_override=m
	for pier in Layout.PIERS:
		detailed(self,Vector3(pier.size.x,0.6,pier.size.y),Vector3(pier.get_center().x,-0.23,pier.get_center().y),"concrete_floor_worn_02",0.22)
		for x in range(184,209,6):
			for z in [-3.5,3.5]:
				cylinder(self,0.16,1.0,Vector3(x,0.5,pier.get_center().y+z),Color("293f47"))
	for z in range(-144,146,12):
		if absf(fposmod(z+19,38)-19)<6:continue
		box(self,Vector3(0.3,1.15,6),Vector3(182,0.6,z),Color("50656b"))
		box(self,Vector3(0.45,0.14,6),Vector3(182,1.22,z),Color("a7b4b4"))
	# Two moored boats, with hull, cabin, rails and mast.
	for z in [-60.0,67.0]:
		var boat=Node3D.new();add_child(boat);boat.position=Vector3(201,-0.22,z)
		box(boat,Vector3(8,1.5,19),Vector3(0,0.2,0),Color("264856"))
		box(boat,Vector3(7.5,0.2,18),Vector3(0,1.0,0),Color("9ea39b"))
		box(boat,Vector3(5.5,3.4,6),Vector3(0,2.75,3),Color("d2cab4"))
		box(boat,Vector3(5.7,1.1,0.12),Vector3(0,3.0,6.1),Color("2d566c"))
		cylinder(boat,0.09,8,Vector3(0,6,2),Color("c5c2b2"))
		light(boat,Vector3(0,4,6),GOLD,1.5,15)
		cull(boat,280)
func _build_districts() -> void:
	# Streets remain open: buildings, destinations and collision share WorldLayout.
	for x in [-174.0,-106.0,106.0,174.0]:
		for z in [-108.0,-32.0,44.0,120.0]:_lamp(Vector3(x,0,z))
	for x in [-62.0,50.0]:
		for z in [-108.0,82.0,120.0]:_lamp(Vector3(x,0,z))
	# Northern public garden, paths, planted beds, benches and a fountain.
	box(self,Vector3(108,0.2,24),Vector3(0,0.08,-95),Color("395d48"))
	detailed(self,Vector3(109,0.05,3),Vector3(0,0.22,-94),"brick_pavement",0.2)
	for x in range(-46,51,12):
		for z in [-105.0,-84.0]:asset(self,"city-kit-suburban","tree-large.glb",Vector3(x,0.16,z),Vector3(5.4,8.2,5.4))
		box(self,Vector3(2.3,0.16,0.7),Vector3(x,0.8,-98),Color("966f50"))
		box(self,Vector3(2.3,0.6,0.12),Vector3(x,1.1,-98.3),Color("966f50"))
	cylinder(self,4,0.5,Vector3(22,0.25,-94),Color("7d9393"))
	cylinder(self,3.5,0.12,Vector3(22,0.57,-94),Color("77b9bd"),0.2)
	cylinder(self,0.4,3.2,Vector3(22,1.6,-94),Color("a7b7ae"))
	label3(self,"NORTH GARDENS",Vector3(-2,3,-79),54,GOLD,true)
	# Residential trees, hedges, mailboxes and garden fences.
	for b in Layout.BUILDINGS:
		if b.size()<5 or b[4]!="city-kit-suburban":continue
		var r:Rect2=b[1]
		for offset in [-3.0,3.0]:
			asset(self,"city-kit-suburban","tree-small.glb",Vector3(r.get_center().x+offset*3,0,r.end.y+3),Vector3(3,4.5,3))
		box(self,Vector3(0.8,0.65,0.4),Vector3(r.get_center().x+5,1.3,r.end.y+1.8),Color("9d7563"))
		for x in range(int(r.position.x),int(r.end.x),2):box(self,Vector3(1.8,0.6,0.25),Vector3(x,0.5,r.position.y-1),Color("819b8b"))
	# Enterable, roofless workshops keep third-person camera and controls legible.
	for walls in [Layout.WORKSHOP_WALLS,Layout.DEALER_WALLS]:
		for wall in walls:detailed(self,Vector3(wall.size.x,4.6,wall.size.y),Vector3(wall.get_center().x,2.3,wall.get_center().y),"brick_wall_003",0.22)
	detailed(self,Vector3(32,0.15,22),Vector3(84,0.03,96),"concrete_floor_worn_02",0.22)
	detailed(self,Vector3(31,0.15,22),Vector3(-144,0.03,58),"concrete_floor_worn_02",0.22)
	label3(self,"ATLAS / GARAGE & PARTS",Vector3(84,4.3,85.6),62,GOLD)
	label3(self,"WESTERN MOTORS / AUTOPARK",Vector3(-144,4.3,46.6),56,GOLD)
	for pos in [Layout.WORKSHOP,Layout.DEALER]:
		box(self,Vector3(1.6,0.9,0.7),pos+Vector3(0,0.5,-1.2),Color("365c67"))
		box(self,Vector3(0.9,0.55,0.06),pos+Vector3(0,1.35,-1.2),Color("6adccc"),1)
		label3(self,"[E] ТЕРМИНАЛ",pos+Vector3(0,2.4,-1.2),27,GOLD,true)
		light(self,pos+Vector3(0,4,0),Color("b4e3df"),2,18)
	for i in range(3):asset(self,"factory-kit","machine.glb",Vector3(72+i*4,0,88),Vector3(2.5,2.6,2))
	asset(self,"factory-kit","conveyor-long.glb",Vector3(95,0,93),Vector3(2,0.9,6))
	asset(self,"factory-kit","box-large.glb",Vector3(95,0.9,94),Vector3(1,1,1))
	asset(self,"factory-kit","catwalk-stairs.glb",Vector3(97,0,88),Vector3(2,2.8,4))
	# Docks and industrial landmarks.
	for i in range(12):
		var x=158 if i<6 else 175;var z=-135+(i%6)*22.0
		asset(self,"city-kit-industrial","shipping-container-"+("a" if i%2==0 else "b")+".glb",Vector3(x,0,z),Vector3(3.1,2.9,8))
	for x in [-141.0,-84.0,139.0]:
		asset(self,"city-kit-industrial","chimney-large.glb",Vector3(x,10.0,135),Vector3(3.5,15,3.5))
	asset(self,"city-kit-industrial","water-tower.glb",Vector3(-188,10,133),Vector3(8,13,8))
	asset(self,"city-kit-industrial","detail-tank-large.glb",Vector3(-137,12,92),Vector3(9,5,8))
	for z in [-95.0,90.0]:
		for x in [176.0,182.0]:box(self,Vector3(0.55,17,0.55),Vector3(x,8.5,z),Color("b18b58"))
		box(self,Vector3(31,0.8,1),Vector3(188,17,z),Color("c59d62"))
		cylinder(self,0.06,12,Vector3(201,11,z),Color("33434b"))
	# Static activity scenery. Only the tiny state changes are replicated.
	for aid in preview.activities:
		var a=preview.activities[aid];var n=Node3D.new();add_child(n);n.position=World.vec(a.pos);activity_nodes[aid]=n
		if a.kind=="parts":
			box(n,Vector3(0.9,0.65,0.7),Vector3(0,0.35,0),Color("577e73"))
			box(n,Vector3(0.92,0.09,0.72),Vector3(0,0.72,0),Color("97c9af"))
			label3(n,"ДЕТАЛИ [E]",Vector3(0,1.8,0),23,Color("9bf4cf"),true)
		else:
			asset(n,"car-kit","sedan.glb",Vector3.ZERO,Vector3(2.0,1.6,4.3))
			for x in [-1.3,1.3]:asset(n,"car-kit","cone.glb",Vector3(x,0,-3),Vector3(0.5,0.7,0.5))
			label3(n,"ПОМОЩЬ [E] / $420",Vector3(0,3,0),25,GOLD,true)
		cull(n,70)
	for sid in World.STAFF:
		var n=Node3D.new();add_child(n);n.position=Vector3(89,0,89) if sid=="mechanic" else Vector3(-39,0,16);staff_nodes[sid]=n
	# Building-animation resources are loaded afterwards in _ready.
func _update_activities(s: Dictionary) -> void:
	for aid in activity_nodes:
		var n:Node3D=activity_nodes[aid];var a=s.activities[aid]
		n.visible=a.status!="completed"
		if a.kind=="parts":n.rotation.y=sin(elapsed*0.7)*0.13
	for sid in staff_nodes:
		var n:Node3D=staff_nodes[sid]
		if n.get_child_count()==0:
			_character(n,2 if sid=="mechanic" else 0);label3(n,World.STAFF[sid].name,Vector3(0,2.5,0),25,Color("9bf4cf"),true)
		n.visible=s.employees[sid].hired

func _window_detail(parent:Node3D,x:float,y:float,width:float,height:float,warm:bool,shop:bool=false) -> void:
	var n=Node3D.new();parent.add_child(n);n.position=Vector3(x,y,.24)
	var trim=Color("293940")
	box(n,Vector3(width+.18,height+.18,.15),Vector3.ZERO,trim)
	box(n,Vector3(width,height,.025),Vector3(0,0,.09),Color("746044") if warm else Color("294251"),.12 if warm else 0)
	if shop:
		for shelf in [-.45,.2]:
			box(n,Vector3(width*.9,.04,.15),Vector3(0,shelf,.17),Color("927154"))
			for item in range(4):box(n,Vector3(width*.13,.23,.07),Vector3((item-1.5)*width*.21,shelf+.14,.20),[Color("c6aa70"),Color("718d85"),Color("ae6e50"),Color("bdb2a3")][item])
	box(n,Vector3(.045,height,.03),Vector3(0,0,.30),trim)
	box(n,Vector3(width,.04,.03),Vector3(0,height*.18,.30),trim)
	box(n,Vector3(width+.28,.1,.4),Vector3(0,-height/2-.1,.08),Color("a1a09a"))
func _front_detail(sign:Node3D,rect:Rect2,height:float,seed:int) -> void:
	var width=rect.size.x
	for x in [-width*.35,-width*.18,width*.18,width*.35]:_window_detail(sign,x,1.52,minf(2,width*.13),1.6,true,true)
	box(sign,Vector3(1.4,2.55,.22),Vector3(0,1.35,.15),Color("afb4ae"))
	box(sign,Vector3(1.15,2.35,.08),Vector3(0,1.28,.29),Color("243d48"))
	box(sign,Vector3(.055,.34,.055),Vector3(-.38,1.18,.36),Color("d1c19e"))
	box(sign,Vector3(width*.8,.52,.28),Vector3(0,3,.13),Color("183c45"))
	box(sign,Vector3(width*.85,.12,1.25),Vector3(0,2.63,.65),Color("416867")).rotation.x=-.09
	var columns=maxi(2,floori(width/2.8))
	for row in range(1,int(height/3)):
		for column in range(columns):_window_detail(sign,(column-(columns-1)*.5)*2.65,3+row*2.55,1.2,1.45,posmod(column+row+seed,4)==0)
	for y in [3.7,height-.15]:box(sign,Vector3(width+.12,.17,.28),Vector3(0,y,.12),Color("9e9c92"))
	cylinder(sign,.065,height-.8,Vector3(width*.47,(height-.8)/2,.28),Color("566467"))
	box(sign,Vector3(.5,.55,.2),Vector3(-width*.45,1.65,.27),Color("78817b"))
	box(sign,Vector3(1.05,.58,.38),Vector3(width*.34,3.85,.38),Color("a2a7a0"))
	for i in range(6):box(sign,Vector3(.65,.027,.02),Vector3(width*.34,3.65+i*.07,.58),Color("566164"))
func _tree_detail(parent:Node3D,pos:Vector3,height:float,seed:int) -> Node3D:
	var n=Node3D.new();parent.add_child(n);n.position=pos
	cylinder(n,height*.035,height*.65,Vector3(0,height*.325,0),Color("594c3d"))
	var rng=RandomNumberGenerator.new();rng.seed=seed
	var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true
	var mesh=SphereMesh.new();mesh.radial_segments=10;mesh.rings=5;mesh.radius=1;mesh.height=2
	var leaf=material(Color("597544")).duplicate();leaf.vertex_color_use_as_albedo=true;mesh.material=leaf;mm.mesh=mesh;mm.instance_count=65
	for i in range(mm.instance_count):
		var a=rng.randf()*TAU;var r=height*.25*sqrt(rng.randf());var radius=height*rng.randf_range(.06,.11)
		var center=Vector3(sin(a)*r,height*.71+rng.randf_range(-.1,.12)*height,cos(a)*r)
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3(radius,radius*.8,radius)),center));mm.set_instance_color(i,Color.WHITE.darkened(rng.randf_range(0,.3)))
	var leaves=MultiMeshInstance3D.new();leaves.multimesh=mm;n.add_child(leaves);cull(n,180);return n
func _bake_static() -> void:
	var groups={};var removed:Array[Node]=[]
	_gather_static(self,groups,removed)
	for key in groups:
		var g=groups[key];var n=MeshInstance3D.new();n.mesh=g.surface.commit();n.material_override=g.material;n.position=g.origin;add_child(n)
	for n in removed:n.queue_free()
func _gather_static(parent:Node,groups:Dictionary,removed:Array[Node]) -> void:
	for n in parent.get_children():
		if n in [gate,roadworks,garage_extension,rain] or n in markers.values() or n in activity_nodes.values() or n in staff_nodes.values() or n.has_meta("keep_static"):continue
		if n is MeshInstance3D and n.mesh is PrimitiveMesh and not n.material_override is ShaderMaterial:
			var mat=n.get_active_material(0)
			if mat is StandardMaterial3D and mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
			var tile=Vector2i(floori(n.global_position.x/32),floori(n.global_position.z/32));var key=str(tile)+str(mat.get_instance_id())
			if not groups.has(key):
				var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);groups[key]={"surface":st,"material":mat,"origin":Vector3(tile.x*32,0,tile.y*32)}
			var transform=n.global_transform;transform.origin-=groups[key].origin
			groups[key].surface.append_from(n.mesh,0,transform);removed.append(n)
		else:_gather_static(n,groups,removed)
