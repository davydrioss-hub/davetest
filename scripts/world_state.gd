class_name WorldState
extends RefCounted
## Pure authoritative rules. Both single player and a listen server use this.
const SPEED = 5.0
const INTERACT_RANGE = 2.8
const RESPAWN_DELAY = 3.0
const SPAWN = Vector3(0, 0, 5)
const DELIVERY = Vector3(12, 0, -6)
const BLOCKERS = [Rect2(-20, -19, 40, 5), Rect2(-20, -14, 3, 28), Rect2(17, -14, 3, 28)]
var data: Dictionary = {}
var events: Array = []
var npc_clock = 0.0
var employee_clock = 0.0

static func vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func arr(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func create_world() -> void:
	data = {"world_id": Crypto.new().generate_random_bytes(16).hex_encode(), "time": 18.0 * 3600.0, "tick": 0, "revision": 0,
		"players": {}, "items": {}, "vehicles": {"van_01": {"pos": [6.0, 0.0, 5.0], "yaw": 0.0, "driver": "", "speed": 0.0}},
		"npcs": {"worker_01": {"pos": [-10.0, 0.0, -8.0], "phase": 0.0}},
		"police": {"patrol_01": {"pos": [14.0, 0.0, 8.0], "phase": 1.0}},
		"orders": {}, "properties": {"depot_01": {"pos": [-12.0, 0.0, 5.0], "owner": "", "price": 600}},
		"employees": {"employee_01": {"pos": [-12.0, 0.0, 9.0], "owner": "", "price": 150, "earnings": 0, "accrued": 0.0}},
		"doors": {"gate_01": {"pos": [0.0, 0.0, -9.0], "open": false}},
		"containers": {"supply_01": {"pos": [-7.0, 0.0, 5.0], "inventory": {"supplies": 12}}},
		"economy": {"ledger": {"paid_orders": 0, "employee_wages": 0}}}
	for i in range(8):
		var item_id = "parcel_%02d" % (i + 1)
		data.items[item_id] = {"pos": [-8.0 + (i % 4) * 2.0, 0.0, -3.0 - (i / 4) * 2.0], "holder": "", "delivered": false}
		data.orders["order_%02d" % (i + 1)] = {"item": item_id, "reward": 250, "completed_by": "", "status": "open"}

func load_world(snapshot: Dictionary) -> void:
	data = snapshot.duplicate(true)
	for p in data.players.values():
		p.connected = false
		p.vehicle = ""
	for v in data.vehicles.values():
		v.driver = ""
		v.speed = 0.0

func patch(domain: String, id: String, fields: Dictionary, inv: Dictionary = {}, stats: Dictionary = {}) -> void:
	data.revision += 1
	var event = {"revision": data.revision, "tick": data.tick, "d": domain, "id": id, "fields": fields.duplicate(true), "inv": inv.duplicate(true), "stats": stats.duplicate(true)}
	apply_event(data, event)
	events.append(event)

static func apply_event(state: Dictionary, event: Dictionary) -> void:
	var domain = event.d
	var id = event.id
	if not state[domain].has(id):
		state[domain][id] = {}
	var record = state[domain][id]
	record.merge(event.fields, true)
	if not event.inv.is_empty():
		if not record.has("inventory"):
			record.inventory = {}
		for item in event.inv:
			if int(event.inv[item]) <= 0:
				record.inventory.erase(item)
			else:
				record.inventory[item] = event.inv[item]
	if not event.stats.is_empty():
		record.stats.merge(event.stats, true)
	state.revision = event.revision

func drain_events() -> Array:
	var result = events
	events = []
	return result

func join_player(id: String, nick: String) -> void:
	if not data.players.has(id):
		patch("players", id, {"nickname": nick, "pos": arr(SPAWN + Vector3(data.players.size() % 4, 0, 0)), "yaw": 0.0,
			"money": 300, "inventory": {}, "owned": {}, "stats": {"deliveries": 0, "deaths": 0},
			"alive": true, "dead_until": 0.0, "vehicle": "", "connected": true})
	else:
		patch("players", id, {"nickname": nick, "connected": true})

func leave_player(id: String) -> void:
	if not data.players.has(id):
		return
	var p = data.players[id]
	if not p.vehicle.is_empty():
		exit_vehicle(id)
	patch("players", id, {"connected": false})

func near(id: String, location: Array, distance: float = INTERACT_RANGE) -> bool:
	return vec(data.players[id].pos).distance_to(vec(location)) <= distance

func command(id: String, action: String, target: String) -> String:
	if not data.players.has(id) or not data.players[id].connected:
		return "Player is not connected."
	var p = data.players[id]
	if action == "respawn":
		if p.alive or data.time < p.dead_until:
			return "Respawn is not ready."
		patch("players", id, {"alive": true, "pos": arr(SPAWN), "vehicle": ""})
		return ""
	if not p.alive:
		return "Press R to respawn."
	if not p.vehicle.is_empty():
		if action == "vehicle":
			return exit_vehicle(id)
		return "Exit the van first."
	match action:
		"pickup":
			if not data.items.has(target): return "Unknown parcel."
			var box = data.items[target]
			if box.delivered or not box.holder.is_empty() or not near(id, box.pos): return "Parcel is unavailable or too far away."
			if p.inventory.size() >= 10: return "Inventory is full."
			patch("items", target, {"holder": id})
			patch("players", id, {}, {target: 1})
		"drop":
			if not data.items.has(target) or data.items[target].holder != id or not p.inventory.has(target): return "You do not own that parcel."
			patch("items", target, {"holder": "", "pos": p.pos.duplicate()})
			patch("players", id, {}, {target: 0})
		"complete_order":
			if not data.orders.has(target): return "Unknown order."
			var order = data.orders[target]
			if order.status != "open": return "Order already completed."
			if not near(id, arr(DELIVERY)): return "Bring the parcel to Dispatch."
			if not p.inventory.has(order.item) or data.items[order.item].holder != id: return "You need the matching parcel."
			patch("orders", target, {"status": "completed", "completed_by": id})
			patch("items", order.item, {"holder": "", "delivered": true})
			patch("players", id, {"money": p.money + order.reward}, {order.item: 0}, {"deliveries": p.stats.deliveries + 1})
			patch("economy", "ledger", {"paid_orders": data.economy.ledger.paid_orders + order.reward})
		"door":
			if not data.doors.has(target) or not near(id, data.doors[target].pos): return "Door is too far away."
			var door = data.doors[target]
			if door.open:
				for player in data.players.values():
					if player.connected and vec(player.pos).distance_to(vec(door.pos)) < 1.5: return "Someone is in the doorway."
			patch("doors", target, {"open": not door.open})
		"take_supply", "store_supply":
			if not data.containers.has(target) or not near(id, data.containers[target].pos): return "Container is too far away."
			var container = data.containers[target]
			var available = int(container.inventory.get("supplies", 0))
			var held = int(p.inventory.get("supplies", 0))
			var amount = 1 if action == "take_supply" else -1
			if amount > 0 and (available <= 0 or (p.inventory.size() >= 10 and held == 0)): return "No space or no supplies left."
			if amount < 0 and held <= 0: return "You have no supplies to store."
			patch("containers", target, {}, {"supplies": available - amount})
			patch("players", id, {}, {"supplies": held + amount})
		"vehicle":
			if not data.vehicles.has(target): return "Unknown vehicle."
			var van = data.vehicles[target]
			if not van.driver.is_empty() or not near(id, van.pos, 3.5): return "Van is occupied or too far away."
			patch("vehicles", target, {"driver": id, "speed": 0.0})
			patch("players", id, {"vehicle": target, "pos": van.pos.duplicate()})
		"buy_property":
			if not data.properties.has(target): return "Unknown property."
			var property = data.properties[target]
			if not near(id, property.pos) or not property.owner.is_empty() or p.money < property.price: return "Depot unavailable. Price: $600."
			var owned = p.owned.duplicate()
			owned[target] = true
			patch("properties", target, {"owner": id})
			patch("players", id, {"money": p.money - property.price, "owned": owned})
		"hire":
			if not data.employees.has(target): return "Unknown employee."
			var employee = data.employees[target]
			if not near(id, employee.pos) or not employee.owner.is_empty() or p.money < employee.price or data.properties.depot_01.owner != id: return "Own the depot and pay $150 to hire."
			patch("employees", target, {"owner": id})
			patch("players", id, {"money": p.money - employee.price})
		_:
			return "Unknown action."
	return ""

func exit_vehicle(id: String) -> String:
	var p = data.players[id]
	var vehicle_id = p.vehicle
	if vehicle_id.is_empty(): return "You are not in a vehicle."
	var v = data.vehicles[vehicle_id]
	var position = vec(v.pos) + Vector3(2, 0, 0)
	if blocked(position, 0.4): position = vec(v.pos) + Vector3(-2, 0, 0)
	if blocked(position, 0.4): position = SPAWN
	patch("vehicles", vehicle_id, {"driver": "", "speed": 0.0, "pos": v.pos.duplicate(), "yaw": v.yaw})
	patch("players", id, {"vehicle": "", "pos": arr(position)})
	return ""

func blocked(position: Vector3, radius: float) -> bool:
	if absf(position.x) > 16.5 - radius or absf(position.z) > 13.5 - radius: return true
	var point = Vector2(position.x, position.z)
	for rect in BLOCKERS:
		if rect.grow(radius).has_point(point): return true
	# Fence leaves a real collision-controlled passage at the gate.
	if absf(position.z + 9.0) < 0.18 + radius:
		if absf(position.x) > 1.5 - radius or not data.doors.gate_01.open: return true
	return false

func advance(dt: float, inputs: Dictionary) -> void:
	data.tick += 1
	data.time += dt
	for id in data.players:
		var p = data.players[id]
		if not p.connected or not p.alive: continue
		var axis: Vector2 = inputs.get(id, Vector2.ZERO)
		if not p.vehicle.is_empty():
			var van = data.vehicles[p.vehicle]
			van.yaw += axis.x * dt * 1.8
			van.speed = move_toward(float(van.speed), -axis.y * 9.0, dt * 12.0)
			var position = vec(van.pos) + Vector3(sin(van.yaw), 0, cos(van.yaw)) * van.speed * dt
			if not blocked(position, 1.1): van.pos = arr(position)
			else: van.speed = 0.0
			p.pos = van.pos.duplicate()
			p.yaw = van.yaw
			continue
		var position = vec(p.pos)
		var velocity = Vector3(axis.x, 0, axis.y) * SPEED * dt
		if not blocked(position + Vector3(velocity.x, 0, 0), 0.4): position.x += velocity.x
		if not blocked(position + Vector3(0, 0, velocity.z), 0.4): position.z += velocity.z
		p.pos = arr(position)
		if axis.length_squared() > 0.01: p.yaw = atan2(axis.x, axis.y)
		if position.distance_to(Vector3(10, 0, 10)) < 1.4:
			patch("players", id, {"alive": false, "dead_until": data.time + RESPAWN_DELAY}, {}, {"deaths": p.stats.deaths + 1})
	# NPC movement is server-only: nearby 5 Hz; far-away 1 Hz.
	npc_clock += dt
	if npc_clock >= 0.2:
		var elapsed = npc_clock
		npc_clock = 0.0
		for domain in ["npcs", "police"]:
			for actor in data[domain].values():
				actor.phase += elapsed * 0.3
				var nearby = false
				for p in data.players.values():
					if p.connected and vec(p.pos).distance_to(vec(actor.pos)) < 18: nearby = true
				if nearby or int(data.tick) % 60 < 12:
					var center = Vector3(-10, 0, -6) if domain == "npcs" else Vector3(12, 0, 6)
					actor.pos = arr(center + Vector3(sin(actor.phase) * 2.0, 0, cos(actor.phase) * 2.0))
	for id in data.employees:
		var employee = data.employees[id]
		if employee.owner.is_empty(): continue
		employee.accrued += dt
		if employee.accrued >= 30:
			employee.accrued -= 30
			var owner = data.players[employee.owner]
			patch("players", employee.owner, {"money": owner.money + 25})
			patch("employees", id, {"earnings": employee.earnings + 25})
			patch("economy", "ledger", {"employee_wages": data.economy.ledger.employee_wages + 25})
