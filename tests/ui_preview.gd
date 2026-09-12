extends Node
## Manual render verification helper; excluded from the game export.
func _ready() -> void:
	Profile.nickname = "Courier"
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	var directory = OS.get_environment("AFTER_HOURS_PREVIEW_DIR")
	if directory.is_empty(): directory = "user://previews"
	DirAccess.make_dir_recursive_absolute(directory)
	for page in ["main", "identity", "play", "host", "join", "settings"]:
		main.call("_show_" + page)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join(page + ".png"))
	var error = Session.host_game("Friends' night", 1, "", "Visual" + str(Time.get_ticks_msec()), false)
	if not error.is_empty(): printerr(error)
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("gameplay.png"))
	Session.leave()
	get_tree().quit()
