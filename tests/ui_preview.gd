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
	Session.request("accept_order","d001_01")
	main.call("_open_tablet","jobs")
	await capture(directory,"contracts")
	main.call("_open_tablet","map")
	await capture(directory,"map")
	main.call("_open_tablet","garage")
	await capture(directory,"company")
	main.call("_close_tablet")
	var model=Session.model
	var iid=model.data.orders.d001_01.item
	model.patch("players",Profile.player_id,{"pos":model.data.items[iid].pos.duplicate()})
	Session.request("pickup",iid)
	model.patch("players",Profile.player_id,{"pos":WorldState.arr(WorldState.rear(model.data.vehicles.van_01))})
	Session.request("cargo_door")
	Session.request("load")
	Session.request("secure")
	main.view.yaw=2.8
	await capture(directory,"loading")
	main.call("_open_tablet","cargo")
	await capture(directory,"cargo")
	main.call("_close_tablet")
	model.patch("vehicles","van_01",{"pos":[-16.0,0.0,0.0],"yaw":PI/2,"door_open":false})
	model.patch("players",Profile.player_id,{"pos":[-16.0,0.0,-8.0],"yaw":PI})
	main.view.yaw=0.3
	await capture(directory,"city")
	model.patch("economy","weather",{"rain":true,"road_closed":true})
	await capture(directory,"rain")
	Session.leave()
	await get_tree().process_frame
	get_tree().quit()
func capture(directory:String,title:String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(title+".png"))
