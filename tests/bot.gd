extends Node
## Test-only filesystem driver. Excluded from every export preset.
var direction = Vector2.ZERO
var tick_timer = 0.0
var dump_timer = 0.0
var command_id = -1
var last_message = ""
var options = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var parts = arg.trim_prefix("--").split("=", true, 1)
			options[parts[0]] = parts[1]
	Profile.nickname = options.get("nickname", "Bot")
	Session.ended.connect(func(reason: String): last_message = reason)
	Session.notice.connect(func(message: String): last_message = message)
	if options.get("role") == "host":
		last_message = Session.host_game("Integration test", int(options.get("limit", "8")), options.get("password", "crew"), "NetworkTest", options.get("load", "false") == "true", int(options.get("port", "27020")))
	else:
		last_message = Session.join_game("127.0.0.1:" + options.get("port", "27020"), options.get("password", "crew"))

func _process(dt: float) -> void:
	tick_timer += dt
	dump_timer += dt
	if tick_timer >= 1.0 / 30.0:
		tick_timer = 0
		Session.send_movement(direction)
	if dump_timer < 0.1: return
	dump_timer = 0
	var command_path = Profile.root.path_join("command.json")
	if FileAccess.file_exists(command_path):
		var cmd = JSON.parse_string(FileAccess.get_file_as_string(command_path))
		if cmd is Dictionary and int(cmd.get("id", -1)) > command_id:
			command_id = int(cmd.id)
			if cmd.has("move"): direction = Vector2(cmd.move[0], cmd.move[1])
			if cmd.has("teleport") and Session.is_host:
				for id in cmd.teleport: Session.model.patch("players", id, {"pos": cmd.teleport[id]})
				Session._flush_events()
			for action in cmd.get("actions", []): Session.request(action.action, action.get("target", ""))
			if cmd.get("save", false): Session.save_world()
			if cmd.get("quit", false):
				Session.leave()
				get_tree().quit()
	var summary = {"active": Session.active, "connecting": Session.connecting, "id": Profile.player_id, "message": last_message, "world": Session.state(), "command_id": command_id}
	var path = Profile.root.path_join("state.json")
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
