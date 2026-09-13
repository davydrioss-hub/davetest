class_name SaveStore
extends RefCounted
## One checksummed transaction contains every domain. Clients never call write().
const SCHEMA = 3
const DOMAINS = ["players", "items", "vehicles", "npcs", "police", "orders", "properties", "employees", "doors", "containers", "economy"]

static func valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 40:
		return false
	for ch in slot:
		if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func slots(root: String) -> Array:
	var result: Array = []
	var dir = DirAccess.open(root.path_join("Saves"))
	if dir:
		for name in dir.get_directories():
			if valid_slot(name) and FileAccess.file_exists(root.path_join("Saves").path_join(name).path_join("world.sav")):
				result.append(name)
	result.sort()
	return result

static func write(root: String, slot: String, world: Dictionary) -> String:
	if not valid_slot(slot):
		return "World name: use 1–40 letters, numbers, hyphens or underscores."
	var directory = root.path_join("Saves").path_join(slot)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Cannot create save directory."
	var snapshot = world.duplicate(true)
	for p in snapshot.players.values():
		p.connected = false
		p.vehicle = ""
	for v in snapshot.vehicles.values():
		v.driver = ""
		v.speed = 0.0
		if v.has("passengers"): v.passengers = []
	var payload = JSON.stringify(snapshot)
	var envelope = JSON.stringify({"schema": SCHEMA, "payload": payload, "sha256": payload.sha256_text()})
	var path = directory.path_join("world.sav")
	var temp = path + ".tmp"
	var f = FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return "Cannot write save: " + error_string(FileAccess.get_open_error())
	f.store_string(envelope)
	f.flush()
	var io_error = f.get_error()
	f.close()
	if io_error != OK:
		return "Save write failed: " + error_string(io_error)
	if FileAccess.file_exists(path):
		# Never replace a healthy backup with a damaged primary save.
		if read_file(path).get("ok", false):
			if DirAccess.copy_absolute(path, path + ".bak") != OK:
				return "Cannot create save backup. Previous save retained."
	var err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		return "Cannot commit save: " + error_string(err)
	return ""

static func read_world(root: String, slot: String) -> Dictionary:
	if not valid_slot(slot):
		return {"ok": false, "error": "Invalid world name."}
	var path = root.path_join("Saves").path_join(slot).path_join("world.sav")
	var result = read_file(path)
	if result.get("ok", false):
		return result
	var backup = read_file(path + ".bak")
	if backup.get("ok", false):
		backup["recovered"] = true
		return backup
	return result

static func read_file(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Save not found or unreadable."}
	if f.get_length() > 32 * 1024 * 1024:
		return {"ok": false, "error": "Save exceeds the supported size."}
	var parser = JSON.new()
	if parser.parse(f.get_as_text()) != OK:
		return {"ok": false, "error": "Save contains invalid JSON."}
	var envelope = parser.data
	if not envelope is Dictionary or not (envelope.get("schema") is float or envelope.get("schema") is int) or not int(envelope.get("schema",0)) in [1,2,SCHEMA]:
		return {"ok": false, "error": "Unsupported or damaged save. No new world was created."}
	var payload = envelope.get("payload", "")
	if not payload is String or payload.sha256_text() != envelope.get("sha256", ""):
		return {"ok": false, "error": "Save checksum failed."}
	if parser.parse(payload) != OK:
		return {"ok": false, "error": "Invalid world data."}
	var world = parser.data
	if not valid_world(world):
		return {"ok": false, "error": "Invalid world data."}
	return {"ok": true, "world": world}

static func valid_world(world: Variant) -> bool:
	if not world is Dictionary or not world.get("world_id") is String:
		return false
	for field in ["time", "tick", "revision"]:
		if not (world.get(field) is float or world.get(field) is int) or not is_finite(float(world[field])):
			return false
	for domain in DOMAINS:
		if not world.get(domain) is Dictionary:
			return false
		for record in world[domain].values():
			if not record is Dictionary:
				return false
	for p in world.players.values():
		for field in ["inventory", "stats", "owned"]:
			if not p.get(field) is Dictionary:
				return false
		if not p.get("pos") is Array or p.pos.size() != 3 or not p.has("money") or not p.has("alive"):
			return false
	if int(world.get("format",1)) in [2,3]:
		for name in ["company","shift","weather"]:
			if not world.economy.get(name) is Dictionary:return false
		for key in ["balance","reputation","capacity","equipment","garage","total_deliveries"]:
			if not world.economy.company.has(key):return false
		for key in ["day","status","started","duration","target","income","expenses","deliveries","damaged","late","report"]:
			if not world.economy.shift.has(key):return false
		for key in ["rain","road_closed","event_index","message"]:
			if not world.economy.weather.has(key):return false
		if not world.vehicles.has("van_01") or not world.doors.has("gate_01"):return false
		for v in world.vehicles.values():
			for key in ["pos","yaw","driver","speed","passengers","cargo","capacity","door_open","health","fuel","brake"]:
				if not v.has(key):return false
			if not v.cargo is Array or not v.passengers is Array:return false
			for iid in v.cargo:
				if not world.items.has(iid):return false
		for item in world.items.values():
			for key in ["pos","kind","holder","carriers","container","condition","secured","slots","delivered"]:
				if not item.has(key):return false
			if not item.carriers is Array:return false
		for o in world.orders.values():
			for key in ["kind","title","reward","route","stage","status","item","deadline","required_rep"]:
				if not o.has(key):return false
			if not o.route is Array or o.route.is_empty():return false
			for stop in o.route:
				if int(stop)<0 or int(stop)>=WorldLayout.DESTINATIONS.size():return false
	elif int(world.get("format",1)) != 1:return false
	if int(world.get("format",1))==3:
		if not world.get("activities") is Dictionary:return false
		for a in world.activities.values():
			if not a is Dictionary:return false
			for key in ["kind","title","pos","status","worker","finish_at"]:
				if not a.has(key):return false
		for key in ["engine","insurance","parts","discovered","repairs","chapter"]:
			if not world.economy.company.has(key):return false
		for vid in WorldState.FLEET:
			if not world.vehicles.has(vid) or world.vehicles[vid].get("model")!=vid or not world.vehicles[vid].get("owned") is bool:return false
		for sid in WorldState.STAFF:
			if not world.employees.get(sid) is Dictionary or not world.employees[sid].get("hired") is bool:return false
	return true
