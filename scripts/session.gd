extends Node
## ENet transport. All mutating requests are resolved using the sender's binding.
signal entered
signal ended(reason: String)
signal notice(message: String)
signal state_changed

const PROTOCOL = 2
const DEFAULT_PORT = 27020
const MAX_PLAYERS = 8
const World = preload("res://scripts/world_state.gd")
const Saves = preload("res://scripts/save_store.gd")
var model: WorldState
var replica: Dictionary = {}
var active = false
var is_host = false
var connecting = false
var slot = "World01"
var server_name = "Friends' night"
var player_limit = 4
var port = DEFAULT_PORT
var address = ""
var password = ""
var peers: Dictionary = {}
var pending: Dictionary = {}
var input_state: Dictionary = {}
var last_input: Dictionary = {}
var last_action: Dictionary = {}
var rate_buckets: Dictionary = {}
var pose_ticks: Dictionary = {}
var sequence = 0
var motion_timer = 0.0
var npc_timer = 0.0
var save_timer = 0.0
var connect_deadline = 0
var closing = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connection_failed.connect(func(): _finish("Connection failed. Check the address, UDP port and firewall."))
	multiplayer.server_disconnected.connect(func(): _finish("Host disconnected."))
	multiplayer.allow_object_decoding = false
	multiplayer.server_relay = false

func state() -> Dictionary:
	return model.data if is_host and model != null else replica

static func parse_address(text: String) -> Dictionary:
	var value = text.strip_edges()
	if value.is_empty() or value.length() > 255 or " " in value or "/" in value:
		return {"error": "Enter an IP address or hostname, optionally followed by :port."}
	var host = value
	var selected_port = DEFAULT_PORT
	if value.begins_with("["):
		var end = value.find("]")
		if end < 0: return {"error": "Use [IPv6]:port."}
		host = value.substr(1, end - 1)
		var suffix = value.substr(end + 1)
		if not suffix.is_empty():
			if not suffix.begins_with(":") or not suffix.substr(1).is_valid_int(): return {"error": "Invalid port."}
			selected_port = suffix.substr(1).to_int()
	elif value.count(":") == 1:
		var pieces = value.split(":")
		host = pieces[0]
		if not pieces[1].is_valid_int(): return {"error": "Invalid port."}
		selected_port = pieces[1].to_int()
	if host.is_empty() or selected_port < 1 or selected_port > 65535:
		return {"error": "Port must be between 1 and 65535."}
	return {"host": host, "port": selected_port, "canonical": ("[" + host + "]" if ":" in host else host) + ":" + str(selected_port)}

func host_game(name_text: String, limit: int, pass_text: String, save_slot: String, load_existing: bool, selected_port: int = DEFAULT_PORT) -> String:
	if active or connecting: return "Leave the current session first."
	if not Profile.storage_error.is_empty(): return Profile.storage_error
	if Profile.nickname.is_empty(): return "Enter your nickname first."
	if not Saves.valid_slot(save_slot): return "World name: use letters, numbers, hyphens or underscores."
	if limit < 1 or limit > MAX_PLAYERS or selected_port < 1 or selected_port > 65535: return "Invalid player limit or port."
	if pass_text.length() > 64: return "Password is too long (maximum 64 characters)."
	var next_model = World.new()
	var recovered = false
	if load_existing:
		var saved = Saves.read_world(Profile.root, save_slot)
		if not saved.ok: return saved.error
		next_model.load_world(saved.world)
		recovered = saved.get("recovered", false)
	else:
		var save_dir = Profile.root.path_join("Saves").path_join(save_slot)
		if DirAccess.dir_exists_absolute(save_dir): return "This world name already exists. Load it or choose a new name."
		next_model.create_world()
	var network: MultiplayerPeer = OfflineMultiplayerPeer.new()
	if limit > 1:
		var enet = ENetMultiplayerPeer.new()
		var err = enet.create_server(selected_port, 16, 3)
		if err != OK: return "Cannot host on UDP " + str(selected_port) + ": " + error_string(err)
		network = enet
	_reset()
	model = next_model
	slot = save_slot
	server_name = name_text.strip_edges().left(48)
	if server_name.is_empty(): server_name = "Friends' night"
	player_limit = limit
	password = pass_text
	port = selected_port
	is_host = true
	active = true
	multiplayer.multiplayer_peer = network
	peers[1] = Profile.player_id
	model.join_player(Profile.player_id, Profile.nickname)
	model.drain_events()
	var save_error = save_world(false)
	if not save_error.is_empty():
		_finish(save_error)
		return save_error
	entered.emit()
	if recovered: notice.emit("Recovered the previous healthy save from backup.")
	return ""

func join_game(server_address: String, pass_text: String) -> String:
	if active or connecting: return "Leave the current session first."
	if not Profile.storage_error.is_empty(): return Profile.storage_error
	if Profile.nickname.is_empty(): return "Enter your nickname first."
	var endpoint = parse_address(server_address)
	if endpoint.has("error"): return endpoint.error
	var enet = ENetMultiplayerPeer.new()
	var err = enet.create_client(endpoint.host, endpoint.port, 3)
	if err != OK: return "Cannot connect: " + error_string(err)
	_reset()
	address = endpoint.canonical
	Profile.remember(address)
	password = pass_text.left(64)
	connecting = true
	connect_deadline = Time.get_ticks_msec() + 12000
	multiplayer.multiplayer_peer = enet
	return ""

func _peer_connected(peer: int) -> void:
	if not active or not is_host: return
	var nonce = Crypto.new().generate_random_bytes(32).hex_encode()
	pending[peer] = {"nonce": nonce, "expires": Time.get_ticks_msec() + 10000}
	_challenge.rpc_id(peer, PROTOCOL, nonce, model.data.world_id)

static func auth_message(nonce: String, id: String, world_id: String) -> String:
	return str(PROTOCOL) + "|" + world_id + "|" + nonce + "|" + id

static func password_proof(secret: String, message: String) -> PackedByteArray:
	# Godot's HMAC backend rejects a zero-length key. Hashing also supports
	# the deliberate no-password case with the same handshake and packet shape.
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret.sha256_buffer(), message.to_utf8_buffer())

@rpc("authority", "call_remote", "reliable", 0)
func _challenge(version: int, nonce: String, world_id: String) -> void:
	if is_host or not connecting: return
	if version != PROTOCOL:
		_finish("Different game version. Everyone must use the same build.")
		return
	var message = auth_message(nonce, Profile.player_id, world_id)
	_hello.rpc_id(1, PROTOCOL, Profile.player_id, Profile.nickname, Profile.public_key, Profile.sign_challenge(message), password_proof(password, message))

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int, id: String, nick: String, pem: String, signature: PackedByteArray, proof: PackedByteArray) -> void:
	if not is_host or not active: return
	var peer = multiplayer.get_remote_sender_id()
	if not pending.has(peer): return
	var challenge = pending[peer]
	pending.erase(peer)
	if version != PROTOCOL or Time.get_ticks_msec() > challenge.expires:
		_reject(peer, "Incompatible version or connection timed out.")
		return
	if pem.length() > 700 or signature.size() != 256 or proof.size() != 32 or id.length() != 39 or nick.strip_edges().is_empty() or nick.length() > 24:
		_reject(peer, "Invalid player identity.")
		return
	var message = auth_message(challenge.nonce, id, model.data.world_id)
	var crypto = Crypto.new()
	if not crypto.constant_time_compare(proof, password_proof(password, message)):
		_reject(peer, "Incorrect password.")
		return
	var key = CryptoKey.new()
	if Profile.id_for_key(pem) != id or key.load_from_string(pem, true) != OK or not crypto.verify(HashingContext.HASH_SHA256, message.sha256_buffer(), signature, key):
		_reject(peer, "Identity verification failed.")
		return
	if id in peers.values():
		_reject(peer, "This PlayerID is already connected. Each computer needs its own profile.")
		return
	if peers.size() >= player_limit:
		_reject(peer, "Server is full.")
		return
	# Flush older mutations before the new snapshot. Reliable channel 0 preserves order.
	_flush_events()
	model.join_player(id, nick.strip_edges())
	_flush_events()
	peers[peer] = id
	_full_snapshot.rpc_id(peer, model.data.duplicate(true), server_name, player_limit)
	notice.emit(nick + " joined.")
	save_world(false)

func _reject(peer: int, reason: String) -> void:
	_rejected.rpc_id(peer, reason)
	get_tree().create_timer(0.3).timeout.connect(func():
		if active and is_host and not peers.has(peer) and peer in multiplayer.get_peers() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(peer))

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(reason: String) -> void:
	if not is_host: _finish(reason)

@rpc("authority", "call_remote", "reliable", 0)
func _full_snapshot(snapshot: Dictionary, name_text: String, limit: int) -> void:
	if is_host or not connecting: return
	if not Saves.valid_world(snapshot) or not snapshot.players.has(Profile.player_id):
		_finish("Invalid world snapshot.")
		return
	replica = snapshot
	server_name = name_text
	player_limit = limit
	connecting = false
	active = true
	entered.emit()

func request(action: String, target: String = "") -> void:
	if not active: return
	sequence += 1
	if is_host:
		_apply_action(1, sequence, action, target)
	else:
		_action.rpc_id(1, sequence, action, target)

@rpc("any_peer", "call_remote", "reliable", 0)
func _action(number: int, action: String, target: String) -> void:
	if is_host and active: _apply_action(multiplayer.get_remote_sender_id(), number, action, target)

func _apply_action(peer: int, number: int, action: String, target: String) -> void:
	if not peers.has(peer) or number <= int(last_action.get(peer, -1)) or number < 0: return
	if action.length() > 32 or target.length() > 64 or not _allow_rate(peer, "action", 15.0): return
	last_action[peer] = number
	var err = "Only the host can change the shift or call recovery." if peer != 1 and action in ["end_shift", "next_shift", "tow"] else model.command(peers[peer], action, target)
	if not err.is_empty():
		if peer == 1: notice.emit(err)
		else: _feedback.rpc_id(peer, err)
	_flush_events()

func send_movement(axis: Vector2) -> void:
	if not active: return
	sequence += 1
	if is_host: _apply_input(1, sequence, axis)
	else: _movement_input.rpc_id(1, sequence, axis)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _movement_input(number: int, axis: Vector2) -> void:
	if is_host and active: _apply_input(multiplayer.get_remote_sender_id(), number, axis)

func _apply_input(peer: int, number: int, axis: Vector2) -> void:
	if not peers.has(peer) or number <= int(last_input.get(peer, -1)) or number < 0: return
	if not axis.is_finite() or axis.length_squared() > 1.01 or not _allow_rate(peer, "input", 90.0): return
	last_input[peer] = number
	input_state[peers[peer]] = {"axis": axis.limit_length(), "expires": Time.get_ticks_msec() + 300}

func _allow_rate(peer: int, kind: String, per_second: float) -> bool:
	var bucket_key = str(peer) + "/" + kind
	var now = Time.get_ticks_msec() / 1000.0
	var bucket = rate_buckets.get(bucket_key, {"time": now, "tokens": per_second})
	bucket.tokens = minf(per_second, bucket.tokens + (now - bucket.time) * per_second)
	bucket.time = now
	var allowed = bucket.tokens >= 1.0
	if allowed: bucket.tokens -= 1.0
	rate_buckets[bucket_key] = bucket
	return allowed

@rpc("authority", "call_remote", "reliable", 0)
func _feedback(message: String) -> void:
	notice.emit(message)

func _flush_events() -> void:
	if model == null: return
	var changes = model.drain_events()
	if changes.is_empty(): return
	for peer in peers:
		if peer != 1: _delta.rpc_id(peer, model.data.world_id, changes)
	state_changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _delta(world_id: String, changes: Array) -> void:
	if is_host or not active or replica.world_id != world_id: return
	for event in changes:
		if int(event.revision) <= int(replica.revision): continue
		if int(event.revision) != int(replica.revision) + 1:
			_finish("World synchronization failed. Reconnect to receive a fresh snapshot.")
			return
		var pose_key = event.d + "/" + event.id
		var newer_pose = int(pose_ticks.get(pose_key, -1)) > int(event.tick)
		if newer_pose and event.fields.has("pos") and replica[event.d].has(event.id):
			# A newer unreliable pose may arrive before this reliable state delta.
			event.fields.erase("pos")
			event.fields.erase("yaw")
		World.apply_event(replica, event)
		if event.fields.has("pos"):
			pose_ticks[pose_key] = int(event.tick)
	state_changed.emit()

func _physics_process(dt: float) -> void:
	if connecting and Time.get_ticks_msec() > connect_deadline:
		_finish("Connection timed out. Check the IP, UDP port and host firewall.")
	if not active or not is_host: return
	for peer in pending.keys():
		if Time.get_ticks_msec() > pending[peer].expires:
			pending.erase(peer)
			_reject(peer, "Connection timed out.")
	var inputs = {}
	for id in input_state:
		if Time.get_ticks_msec() <= input_state[id].expires: inputs[id] = input_state[id].axis
	model.advance(dt, inputs)
	_flush_events()
	motion_timer += dt
	npc_timer += dt
	save_timer += dt
	if motion_timer >= 0.05:
		motion_timer = 0.0
		var poses = {"players": {}, "vehicles": {}}
		for id in model.data.players:
			var p = model.data.players[id]
			if p.connected: poses.players[id] = [p.pos, p.yaw]
		for id in model.data.vehicles:
			var v = model.data.vehicles[id]
			if not v.driver.is_empty() or absf(v.speed) > 0.01: poses.vehicles[id] = [v.pos, v.yaw, v.speed]
		for peer in peers:
			if peer != 1: _motion.rpc_id(peer, model.data.world_id, int(model.data.tick), model.data.time, poses)
	if npc_timer >= 0.2:
		npc_timer = 0.0
		var poses = {"npcs": {}, "police": {}}
		for domain in poses:
			for id in model.data[domain]: poses[domain][id] = [model.data[domain][id].pos, model.data[domain][id].get("yaw",0.0)]
		for peer in peers:
			if peer != 1: _actors.rpc_id(peer, model.data.world_id, int(model.data.tick), poses)
	if save_timer >= 30.0:
		save_timer = 0.0
		save_world(false)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _motion(world_id: String, tick: int, world_time: float, poses: Dictionary) -> void:
	if is_host or not active or replica.world_id != world_id: return
	_apply_poses(tick, poses)
	if tick >= int(replica.tick):
		replica.tick = tick
		replica.time = world_time

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _actors(world_id: String, tick: int, poses: Dictionary) -> void:
	if not is_host and active and replica.world_id == world_id: _apply_poses(tick, poses)

func _apply_poses(tick: int, poses: Dictionary) -> void:
	for domain in poses:
		for id in poses[domain]:
			var key = domain + "/" + id
			if not replica[domain].has(id) or tick < int(pose_ticks.get(key, -1)): continue
			pose_ticks[key] = tick
			replica[domain][id].pos = poses[domain][id][0]
			replica[domain][id].yaw = poses[domain][id][1]
			if domain == "vehicles" and poses[domain][id].size()>2: replica[domain][id].speed = poses[domain][id][2]

func _peer_disconnected(peer: int) -> void:
	pending.erase(peer)
	if not is_host or not active or not peers.has(peer): return
	var id = peers[peer]
	peers.erase(peer)
	input_state.erase(id)
	last_action.erase(peer)
	last_input.erase(peer)
	rate_buckets.erase(str(peer) + "/action")
	rate_buckets.erase(str(peer) + "/input")
	model.leave_player(id)
	_flush_events()
	save_world(false)
	notice.emit(model.data.players[id].nickname + " left. Progress saved.")

func save_world(show_message: bool = true) -> String:
	if not active or not is_host: return "Only the host can save the world."
	var error = Saves.write(Profile.root, slot, model.data)
	if not error.is_empty(): notice.emit(error)
	elif show_message: notice.emit("World saved.")
	return error

func leave() -> String:
	if is_host and active:
		var err = save_world(false)
		if not err.is_empty(): return err
		for peer in peers:
			if peer != 1: _host_left.rpc_id(peer)
	_finish("")
	return ""

@rpc("authority", "call_remote", "reliable", 0)
func _host_left() -> void:
	if not is_host: _finish("Host disconnected.")

func _finish(reason: String) -> void:
	if closing: return
	closing = true
	active = false
	connecting = false
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()
	closing = false
	ended.emit(reason)

func _reset() -> void:
	active = false
	connecting = false
	is_host = false
	model = null
	replica = {}
	peers.clear()
	pending.clear()
	input_state.clear()
	last_input.clear()
	last_action.clear()
	rate_buckets.clear()
	pose_ticks.clear()
	sequence = 0
	motion_timer = 0.0
	npc_timer = 0.0
	save_timer = 0.0
