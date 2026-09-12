extends Node
## A local identity is a key pair, not an online account or a network peer ID.
## Only public keys and one-use signatures leave this machine.
var root = "user://"
var nickname = ""
var player_id = ""
var key: CryptoKey
var public_key = ""
var recent: Array = []
var fullscreen = false
var storage_error = ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-dir="):
			root = arg.trim_prefix("--profile-dir=").path_join("")
	DirAccess.make_dir_recursive_absolute(root)
	var key_path = root.path_join("identity.key")
	key = CryptoKey.new()
	if FileAccess.file_exists(key_path):
		if key.load(key_path) != OK:
			storage_error = "Cannot read identity.key. Restore your profile backup."
			return
	else:
		key = Crypto.new().generate_rsa(2048)
		if key == null or key.save(key_path) != OK:
			storage_error = "Cannot save your local identity. Choose a writable profile folder."
			return
	public_key = key.save_to_string(true)
	player_id = id_for_key(public_key)
	var cfg = ConfigFile.new()
	if cfg.load(root.path_join("profile.cfg")) == OK:
		nickname = str(cfg.get_value("player", "nickname", "")).strip_edges().left(24)
		recent = cfg.get_value("network", "recent", [])
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	if DisplayServer.get_name() != "headless":
		apply_display()

static func id_for_key(pem: String) -> String:
	return "Player_" + pem.sha256_text().left(32)

func save_profile() -> Error:
	var cfg = ConfigFile.new()
	cfg.set_value("player", "nickname", nickname)
	cfg.set_value("network", "recent", recent)
	cfg.set_value("display", "fullscreen", fullscreen)
	return cfg.save(root.path_join("profile.cfg"))

func remember(address: String) -> void:
	recent.erase(address)
	recent.push_front(address)
	recent.resize(mini(recent.size(), 8))
	save_profile()

func apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func sign_challenge(message: String) -> PackedByteArray:
	return Crypto.new().sign(HashingContext.HASH_SHA256, message.sha256_buffer(), key)

