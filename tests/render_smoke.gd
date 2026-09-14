extends Node
func require(ok:bool,message:String) -> void:
	if not ok:push_error(message);get_tree().quit(1)
func key(code:Key,pressed:bool) -> void:
	var event=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed;Input.parse_input_event(event)
func shot(main:Node,title:String) -> void:
	main.toast_timer=0
	await get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	var directory=OS.get_environment("AFTER_HOURS_PREVIEW_DIR")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		get_viewport().get_texture().get_image().save_png(directory.path_join(title+".png"))
	require(main.view.camera.position.is_finite(),"Finite camera transform")
func _ready() -> void:
	Profile.nickname="Render test"
	var main=load("res://main.tscn").instantiate();add_child(main)
	var error=Session.host_game("Render test",1,"","RenderSmoke"+str(Time.get_ticks_msec()),false)
	require(error.is_empty(),"Host startup")
	await shot(main,"fps-depot")
	require(absf(main.view.camera.position.y-1.68)<.02,"Eye-height camera")
	require(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Gameplay captures mouse")
	main._open_tablet("map")
	await get_tree().process_frame
	await get_tree().process_frame
	require(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Tablet releases mouse")
	main._close_tablet()
	var w=Session.model;var p=w.data.players[Profile.player_id]
	w.patch("vehicles","van_01",{"pos":[-16.0,0.0,0.0],"yaw":0.0})
	w.patch("players",Profile.player_id,{"pos":[-13.0,0.0,0.0]})
	Session.request("vehicle","van_01")
	await shot(main,"fps-cab")
	require(p.vehicle=="van_01","Driver enters cab")
	key(KEY_UP,true);key(KEY_RIGHT,true)
	await get_tree().create_timer(.8).timeout
	key(KEY_UP,false);key(KEY_RIGHT,false)
	require(w.data.vehicles.van_01.speed>.2 and w.data.vehicles.van_01.yaw<0,"Arrow Up and Right drive and turn toward driver's right")
	key(KEY_SPACE,true)
	await get_tree().create_timer(.6).timeout
	key(KEY_SPACE,false)
	require(absf(w.data.vehicles.van_01.speed)<.05,"Space stops vehicle")
	Session.request("indicator","right")
	await shot(main,"fps-turn")
	Session.request("vehicle","van_01")
	var npc=w.data.npcs.walker_00;var at=WorldState.vec(npc.pos)
	w.patch("players",Profile.player_id,{"pos":WorldState.arr(at+Vector3(2.3,0,-3))})
	main.view.yaw=atan2(-2.3,3);main.view.pitch=-.06
	await shot(main,"pedestrian-walk")
	await get_tree().create_timer(.45).timeout
	await shot(main,"pedestrian-stride")
	w.patch("players",Profile.player_id,{"pos":[-11.0,0.0,-5.0]})
	main.view.yaw=-1.3;main.view.pitch=.07
	await shot(main,"fps-street")
	Session.leave()
	print("RENDER SMOKE: eye height, mouse capture, arrow steering, brakes and pedestrians passed / ",RenderingServer.get_current_rendering_method())
	get_tree().quit()
