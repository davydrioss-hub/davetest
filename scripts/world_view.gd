class_name WorldView
extends Node3D
## Procedural presentation only. Every interactive value comes from Session.
const World = preload("res://scripts/world_state.gd")
const CREAM = Color("e8e6d8")
const TEAL = Color("45857e")
const ORANGE = Color("e9ad52")
var camera: Camera3D
var entities: Dictionary = {}
var preview: Dictionary = {}
var active = false

func _ready() -> void:
	var sample = World.new()
	sample.create_world()
	preview = sample.data
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("15292d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9ab0ba")
	settings.ambient_light_energy = 0.3
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("ffdfaf")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(27, 26, 32)
	camera.fov = 46
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	_build_yard()

func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.86
	return m

func box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

func label(parent: Node3D, value: String, position: Vector3, size: int = 32, color: Color = CREAM) -> Label3D:
	var node = Label3D.new()
	node.text = value
	node.position = position
	node.font_size = size
	node.pixel_size = 0.012
	node.modulate = color
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = false
	node.outline_size = 6
	parent.add_child(node)
	return node

func _build_yard() -> void:
	box(self, Vector3(80, 0.2, 80), Vector3(0, -0.35, 0), Color("263d40"))
	box(self, Vector3(36, 0.2, 29), Vector3(0, -0.15, 0), Color("49585a"))
	box(self, Vector3(7, 0.02, 27), Vector3(5, -0.035, 0), Color("394448"))
	for z in range(-12, 13, 4):
		box(self, Vector3(0.12, 0.03, 1.8), Vector3(5, 0.0, z), Color("b5af8b"))
	for x in range(-16, 18, 3):
		box(self, Vector3(1.5, 0.03, 0.12), Vector3(x, 0, 12.5), CREAM)
	# Collision geometry is mirrored by WorldState.blocked() on the server.
	box(self, Vector3(40, 6, 5), Vector3(0, 3, -16.5), Color("3c5757"))
	box(self, Vector3(40.8, 0.25, 5.7), Vector3(0, 6.15, -16.5), Color("293d42"))
	for x in range(-15, 17, 5):
		box(self, Vector3(3.6, 2.7, 0.04), Vector3(x, 1.5, -13.97), Color("6d817a"))
		for y in range(1, 5):
			box(self, Vector3(3.6, 0.035, 0.055), Vector3(x, y * 0.5, -13.93), Color("435656"))
	label(self, "AFTER HOURS  /  FREIGHT DIVISION", Vector3(0, 5.2, -13.8), 45)
	box(self, Vector3(3, 3.8, 28), Vector3(-18.5, 1.9, 0), Color("3d5052"))
	box(self, Vector3(3, 3.0, 28), Vector3(18.5, 1.5, 0), Color("3d5052"))
	for x in [-9.0, 9.0]:
		box(self, Vector3(15, 1.5, 0.12), Vector3(x, 0.75, -9), Color("55716b"))
		for post in range(-7, 8, 2):
			box(self, Vector3(0.1, 1.8, 0.14), Vector3(x + post, 0.9, -9), Color("2d4244"))
	# Dispatch pad, depot office marker and a clearly marked respawn test hazard.
	box(self, Vector3(4.5, 0.05, 4.5), Vector3(12, 0, -6), Color("42766b"))
	label(self, "DISPATCH\n[F]  DELIVER", Vector3(12, 2.8, -6), 36, CREAM)
	for x in [-2, 2]:
		box(self, Vector3(0.15, 0.06, 4.4), Vector3(12 + x, 0.04, -6), ORANGE)
	box(self, Vector3(3, 0.06, 3), Vector3(10, 0.01, 10), Color("a9523f"))
	label(self, "DANGER\nRESPAWN TEST", Vector3(10, 0.8, 10), 22, Color("ffc4a5"))
	for point in [Vector3(-15, 0, -10), Vector3(15, 0, -10), Vector3(-15, 0, 11), Vector3(15, 0, 11)]:
		cylinder(self, 0.07, 5, point + Vector3(0, 2.5, 0), Color("253638"))
		box(self, Vector3(1.2, 0.1, 0.3), point + Vector3(0.4, 5, 0), ORANGE)
	for x in [-11, -9, -7, -5]:
		box(self, Vector3(1.8, 0.12, 3), Vector3(x, 0, -4), Color("695e4a"))

func _new_entity(domain: String, id: String) -> Node3D:
	var node = Node3D.new()
	add_child(node)
	match domain:
		"players", "npcs", "police", "employees":
			var color = [ORANGE, TEAL, Color("c58173"), Color("9aa5d0"), Color("b6c48e"), Color("bb92b8"), Color("8ba7bb"), Color("dbc78c")][posmod(id.hash(), 8)]
			if domain == "police": color = Color("6b86aa")
			if domain == "employees": color = Color("acb78b")
			cylinder(node, 0.34, 0.9, Vector3(0, 0.95, 0), color)
			cylinder(node, 0.27, 0.42, Vector3(0, 1.62, 0), Color("d7b69b"))
			box(node, Vector3(0.23, 0.55, 0.28), Vector3(-0.18, 0.28, 0), Color("29383c"))
			box(node, Vector3(0.23, 0.55, 0.28), Vector3(0.18, 0.28, 0), Color("29383c"))
			box(node, Vector3(0.38, 0.12, 0.2), Vector3(0, 1.66, 0.25), Color("34474a"))
			label(node, "", Vector3(0, 2.4, 0), 25).name = "Title"
		"items":
			box(node, Vector3(0.85, 0.7, 0.7), Vector3(0, 0.45, 0), Color("bd925d"))
			box(node, Vector3(0.16, 0.715, 0.715), Vector3(0, 0.45, 0), Color("e4c58b"))
			box(node, Vector3(0.25, 0.16, 0.02), Vector3(0.18, 0.5, 0.36), CREAM)
		"vehicles":
			box(node, Vector3(1.75, 1.25, 3.4), Vector3(0, 1.08, 0), TEAL)
			box(node, Vector3(1.78, 0.4, 1.0), Vector3(0, 1.91, 0.65), TEAL)
			box(node, Vector3(1.6, 0.63, 0.04), Vector3(0, 1.59, 1.72), Color("183e46"))
			box(node, Vector3(1.6, 0.12, 0.1), Vector3(0, 0.75, 1.72), CREAM)
			for x in [-0.65, 0.65]:
				box(node, Vector3(0.3, 0.22, 0.07), Vector3(x, 1.08, 1.72), Color("ffe1a0"))
			for x in [-0.9, 0.9]:
				for z in [-1.08, 1.05]:
					var wheel = cylinder(node, 0.43, 0.25, Vector3(x, 0.43, z), Color("1c282d"))
					wheel.rotation.z = PI / 2
			label(node, "CO-OP COURIER", Vector3(0, 2.9, 0), 23)
		"doors":
			var gate = Node3D.new()
			gate.name = "Gate"
			gate.position.x = -1.5
			node.add_child(gate)
			box(gate, Vector3(3, 1.5, 0.13), Vector3(1.5, 0.75, 0), ORANGE)
		"containers":
			box(node, Vector3(1.4, 0.9, 1.0), Vector3(0, 0.45, 0), Color("708578"))
			box(node, Vector3(1.5, 0.14, 1.1), Vector3(0, 0.97, 0), CREAM)
			label(node, "SUPPLIES\n[E] TAKE  /  [T] STORE", Vector3(0, 2.1, 0), 23)
		"properties":
			cylinder(node, 1.35, 0.07, Vector3.ZERO, Color("86784d"))
			label(node, "DEPOT\n[E] BUY  $600", Vector3(0, 2.2, 0), 28, ORANGE).name = "Title"
	return node

func _process(dt: float) -> void:
	var state = Session.state() if Session.active else preview
	if state.is_empty(): return
	var keep = {}
	for domain in ["players", "npcs", "police", "employees", "items", "vehicles", "doors", "containers", "properties"]:
		for id in state[domain]:
			var entity = state[domain][id]
			var tag = domain + "/" + id
			keep[tag] = true
			if not entities.has(tag):
				entities[tag] = _new_entity(domain, id)
				entities[tag].position = World.vec(entity.pos)
			var node: Node3D = entities[tag]
			var target = World.vec(entity.pos)
			node.position = node.position.lerp(target, 1.0 - exp(-dt * 16.0)) if node.position.distance_to(target) < 4 else target
			if domain in ["players", "npcs", "police", "vehicles"]:
				node.rotation.y = lerp_angle(node.rotation.y, float(entity.get("yaw", 0)), 1.0 - exp(-dt * 16))
			if domain == "players":
				node.visible = entity.connected and entity.vehicle.is_empty()
				node.get_node("Title").text = entity.nickname + ("  • YOU" if id == Profile.player_id else "")
				node.scale.y = 1.0 if entity.alive else 0.3
			elif domain == "items": node.visible = not entity.delivered and entity.holder.is_empty()
			elif domain == "doors": node.get_node("Gate").rotation.y = lerp_angle(node.get_node("Gate").rotation.y, -PI / 2 if entity.open else 0.0, minf(dt * 8, 1))
			elif domain == "properties": node.get_node("Title").text = "DEPOT\n" + ("OWNED" if not entity.owner.is_empty() else "[E] BUY  $600")
			elif domain == "employees": node.get_node("Title").text = "[E] HIRE  $150" if entity.owner.is_empty() else "ON THE CLOCK"
			elif domain == "police": node.get_node("Title").text = "PATROL"
			elif domain == "npcs": node.get_node("Title").text = "YARD CREW"
	for tag in entities.keys():
		if not keep.has(tag):
			entities[tag].queue_free()
			entities.erase(tag)
	if Session.active and state.players.has(Profile.player_id):
		var target = World.vec(state.players[Profile.player_id].pos)
		camera.position = camera.position.lerp(target + Vector3(0, 19, 19), 1.0 - exp(-dt * 5))
		camera.look_at(target)
	else:
		camera.position = camera.position.lerp(Vector3(27, 26, 32), 1.0 - exp(-dt * 2))
		camera.look_at(Vector3.ZERO)
