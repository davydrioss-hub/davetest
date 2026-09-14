extends Node
const World=preload("res://scripts/world_state.gd")
const Saves=preload("res://scripts/save_store.gd")
const Network=preload("res://scripts/session.gd")
var failures:Array=[]
var checks=0
func check(ok:bool,description:String) -> void:
	checks+=1
	if not ok:failures.append(description);printerr("FAIL: "+description)
func at(w:WorldState,id:String,pos:Vector3) -> void:w.data.players[id].pos=World.arr(pos)
func accept(w:WorldState,index:int) -> Dictionary:
	var oid="d001_%02d"%index
	check(w.command("a","accept_order",oid).is_empty(),"Accept contract "+oid)
	return w.data.orders[oid]
func pickup(w:WorldState,o:Dictionary) -> void:
	at(w,"a",World.vec(w.data.items[o.item].pos));check(w.command("a","pickup",o.item).is_empty(),"Pick up "+o.kind)
func deliver(w:WorldState,oid:String) -> void:
	at(w,"a",World.vec(World.destination(w.data.orders[oid]).pos));check(w.command("a","complete_order",oid).is_empty(),"Deliver at validated destination")
func setup() -> WorldState:
	var model=World.new();model.create_world();model.join_player("a","Alice");model.join_player("b","Bob");return model
func _ready() -> void:call_deferred("run")
func run() -> void:
	var w=World.new();w.create_world();w.join_player("a","Alice");w.join_player("b","Bob")
	check(w.data.orders.size()==30 and w.data.items.is_empty(),"Contracts exist before cargo spawns")
	var balance=w.data.economy.company.balance
	check(not w.command("a","add_money","99999").is_empty() and w.data.economy.company.balance==balance,"Client cannot mint money")
	var o=accept(w,1);var iid=o.item
	check(not w.command("b","accept_order","d001_01").is_empty() and w.data.items.size()==1,"Accept race creates only one cargo")
	check(not w.command("a","pickup",iid).is_empty(),"Pickup distance checked")
	pickup(w,o);at(w,"b",World.vec(w.data.players.a.pos))
	check(not w.command("b","pickup",iid).is_empty(),"Exclusive standard cargo pickup")
	check(not w.command("b","drop",iid).is_empty(),"Ownership checked on drop")
	check(not w.command("a","complete_order","d001_01").is_empty(),"Destination validated")
	var v=w.data.vehicles.van_01
	at(w,"a",World.rear(v));check(not w.command("a","load","").is_empty(),"Closed cargo door rejects loading")
	w.command("a","cargo_door","");check(w.command("a","load","").is_empty(),"Load physical cargo")
	check(w.data.players.a.inventory.is_empty() and v.cargo==[iid] and w.data.items[iid].container=="van_01","Loading conserves cargo ownership")
	w.command("a","secure","");check(w.data.items[iid].secured,"Straps secure cargo")
	check(not w.command("b","unload",iid).is_empty(),"Remote cargo transfer rejected")
	w.command("a","unload",iid);check(v.cargo.is_empty() and w.data.players.a.inventory.has(iid),"Unload conserves cargo")
	deliver(w,"d001_01")
	check(w.data.economy.company.balance==balance+350 and w.data.players.a.inventory.is_empty(),"Atomic company reward consumes parcel")
	check(not w.command("a","complete_order","d001_01").is_empty() and w.data.economy.company.balance==balance+350,"Duplicate payment rejected")
	# Multi-stop contracts pay only at the final address.
	o=accept(w,5);pickup(w,o);var previous=w.data.economy.company.balance
	deliver(w,"d001_05")
	check(o.stage==1 and o.status=="active" and w.data.economy.company.balance==previous,"First route stop has no payment")
	check(not w.command("a","complete_order","d001_05").is_empty(),"Cannot skip the second address")
	deliver(w,"d001_05");check(o.status=="completed" and w.data.economy.company.balance==previous+950,"Final route stop pays once")
	# Heavy cargo: solo trolley; a second player assists and disconnect clears both owners.
	o=accept(w,4);pickup(w,o)
	var start=World.vec(w.data.players.a.pos)
	w.advance(0.1,{"a":Vector2(0,1)})
	check(is_equal_approx(World.vec(w.data.players.a.pos).distance_to(start),0.17),"Solo heavy trolley remains playable")
	at(w,"b",World.vec(w.data.players.a.pos));check(w.command("b","pickup",o.item).is_empty(),"Second player assists heavy carrying")
	start=World.vec(w.data.players.a.pos);w.advance(0.1,{"a":Vector2(0,1)})
	check(is_equal_approx(World.vec(w.data.players.a.pos).distance_to(start),0.34),"Cooperative carrying is faster")
	w.leave_player("b");check(w.data.items[o.item].holder=="" and w.data.players.a.inventory.is_empty() and w.data.players.b.inventory.is_empty(),"Helper disconnect safely drops heavy cargo")
	w.join_player("b","Bob");pickup(w,o);deliver(w,"d001_04")
	# Damage and lateness affect server-calculated payment.
	o=accept(w,3);pickup(w,o);at(w,"a",World.rear(v));w.command("a","load","")
	w._crash(12);check(w.data.items[o.item].condition<100 and v.health<100,"Crash damages unsecured fragile cargo")
	w.command("a","secure","");var condition=w.data.items[o.item].condition;w._crash(12)
	check(condition-w.data.items[o.item].condition<5,"Securing reduces crash damage")
	w.command("a","unload",o.item);previous=w.data.economy.company.balance;deliver(w,"d001_03")
	check(w.data.economy.company.balance-previous<600,"Damaged cargo reduces payout")
	o=accept(w,2);pickup(w,o);w.data.time=o.deadline+1;previous=w.data.economy.company.balance;deliver(w,"d001_02")
	check(w.data.economy.company.balance-previous==358 and w.data.economy.shift.late==1,"Urgent deadline reduces payment without softlock")
	# Four seats; only the assigned driver controls physics.
	w.command("a","cargo_door","")
	for id in ["a","b","c","d","e"]:
		w.join_player(id,id);at(w,id,World.vec(v.pos))
		var error=w.command(id,"vehicle","van_01")
		check(error.is_empty() if id!="e" else not error.is_empty(),"Seat capacity: "+id)
	var oldpos=v.pos.duplicate();w.advance(0.1,{"b":Vector2(0,-1)})
	check(v.pos==oldpos and v.driver=="a","Passenger cannot drive")
	w.leave_player("a");check(v.driver=="b" and not "a" in v.passengers,"Driver disconnect transfers seat authority")
	for id in ["b","c","d"]:w.exit_vehicle(id,true)
	w.join_player("a","Alice");at(w,"a",World.Layout.GARAGE)
	previous=w.data.economy.company.balance
	check(w.command("a","upgrade","capacity").is_empty() and v.capacity==10 and w.data.economy.company.balance==previous-800,"Capacity purchase validates budget and applies")
	check(not w.command("a","upgrade","capacity").is_empty(),"Cannot buy same upgrade twice")
	at(w,"b",Vector3(0,0,0));check(not w.command("b","upgrade","equipment").is_empty(),"Remote upgrade rejected")
	# Death and respawn are server decisions, never client-written stats.
	v.driver="b";v.door_open=false;v.speed=10;v.pos=[0,0,0];at(w,"a",Vector3(0,0,0))
	w.advance(0.02,{"b":Vector2(0,-1)})
	check(not w.data.players.a.alive,"Moving vehicle can knock player down")
	check(not w.command("a","respawn","").is_empty(),"Respawn cooldown enforced")
	w.data.time+=4;check(w.command("a","respawn","").is_empty(),"Respawn restores player at garage")
	v.driver="";v.speed=0.0
	# Closed gates and building footprints are actual authoritative obstacles.
	at(w,"a",Vector3(-37,0,18));w.command("a","door","gate_01")
	check(w.blocked(Vector3(-37,0,20),0.4),"Closed garage gate blocks movement")
	w.command("a","door","gate_01");check(not w.blocked(Vector3(-37,0,20),0.4),"Open garage gate passes movement")
	check(w.blocked(Vector3(-40,0,-20),0.4),"Building footprint blocks movement")
	# Reports, cleanup, and reliable deletes keep replicas consistent across nights.
	at(w,"a",World.Layout.GARAGE);var replica=w.data.duplicate(true);w.drain_events()
	check(w.command("a","end_shift","").is_empty(),"Host rule ends shift at garage")
	check(w.data.economy.shift.report.deliveries==5,"Report totals completed jobs")
	var wid=w.data.world_id
	check(w.command("a","next_shift","").is_empty(),"Next shift starts with persistent company")
	for event in w.drain_events():World.apply_event(replica,event)
	check(replica==w.data,"Deltas including deletions reconstruct next night exactly")
	check(w.data.world_id==wid and w.data.economy.shift.day==2 and v.capacity==10,"Next shift preserves world and upgrades")
	# Persistence, atomic save backup, and stable local identity.
	var root=OS.get_environment("AFTER_HOURS_TEST_ROOT")
	if root.is_empty():root="user://core-tests-"+str(Time.get_ticks_msec())
	check(Saves.write(root,"World01",w.data).is_empty(),"Atomic world save succeeds")
	var saved=Saves.read_world(root,"World01")
	if not saved.ok: printerr(saved)
	check(saved.ok and saved.world.economy.company.balance==w.data.economy.company.balance and saved.world.economy.company.capacity==1 and not saved.world.players.a.connected,"Save retains company and offline player state")
	check(Saves.write(root,"World01",w.data).is_empty(),"Save can atomically replace prior save")
	var f=FileAccess.open(root.path_join("Saves/World01/world.sav"),FileAccess.WRITE);f.store_string("damaged");f.close()
	check(Saves.read_world(root,"World01").get("recovered",false),"Corrupt primary restores healthy backup")
	check(not Saves.valid_slot("../other") and not Saves.valid_slot(""),"Save path traversal rejected")
	check(Network.parse_address("192.168.1.50").port==27020,"LAN address default UDP port")
	check(Network.parse_address("[::1]:28000").port==28000,"IPv6 direct address parsed")
	check(Network.parse_address("localhost:0").has("error"),"Invalid port rejected")
	var changed=w.data.duplicate(true);changed.economy.erase("company")
	check(not Saves.valid_world(changed),"Malformed new world cannot silently regenerate")
	var night=World.new();night.create_world();night.join_player("a","Alice");night.command("a","accept_order","d001_01")
	for t in [181.0,421.0,661.0,901.0,1201.0]:
		night.data.time=night.data.economy.shift.started+t;night.advance(1.01,{})
		if t==181:check(night.data.economy.weather.rain,"Weather event begins rain")
		if t==421:check(night.blocked(Vector3(18,0,0),1,true) and not night.blocked(Vector3(18,0,0),0.4),"Road closure blocks vehicles, not pedestrians")
		if t==661:check(night.data.orders.d001_01.route==[1],"Address change updates active route")
		if t==901:check(night.data.vehicles.van_01.health==75 and not night.data.economy.weather.road_closed,"Breakdown event changes authoritative vehicle state")
		if t==1201:check(night.data.economy.shift.status=="finished" and night.data.orders.d001_01.status=="failed","Shift timer closes unpaid work and creates report")
	var legacy=World.new();legacy.create_world();legacy.join_player("a","Legacy")
	legacy.data.erase("format");legacy.data.players.a.money=875;legacy.data.players.a.inventory={"parcel_01":1}
	legacy.data.items={"parcel_01":{"pos":[1,0,1],"holder":"a","delivered":false}}
	legacy.data.orders={"order_01":{"item":"parcel_01","reward":250,"status":"open","completed_by":""}}
	var migrated=World.new();migrated.load_world(legacy.data)
	check(migrated.data.format==3 and migrated.data.world_id==legacy.data.world_id and migrated.data.players.a.money==875,"Migration preserves legacy identity and wallet")
	migrated.join_player("a","Legacy");at(migrated,"a",World.DELIVERY)
	check(migrated.command("a","complete_order","order_01").is_empty() and migrated.data.players.a.inventory.is_empty(),"Legacy carried parcel remains deliverable after migration")
	# Expanded city: every destination, collectible and service point is reachable on foot.
	var city=World.new();city.create_world();city.join_player("a","Alice");city.join_player("b","Bob")
	for dest in World.Layout.DESTINATIONS:check(not city.blocked(World.vec(dest.pos),0.4),"Destination is outside authoritative walls: "+dest.name)
	for pos in World.PART_SPOTS+World.SERVICE_SPOTS:check(not city.blocked(pos,0.4),"Activity location is reachable")
	check(city.blocked(Vector3(190,0,60),0.4) and not city.blocked(Vector3(199,0,38),0.4),"Harbor water is blocked but its pier is traversable")
	check(not city.command("a","collect_parts","parts_00").is_empty(),"Remote collectible rejected")
	at(city,"a",World.PART_SPOTS[0]);check(city.command("a","collect_parts","parts_00").is_empty(),"Collect parts at landmark")
	at(city,"b",World.PART_SPOTS[0]);check(not city.command("b","collect_parts","parts_00").is_empty() and city.data.economy.company.parts==2,"Collect race cannot duplicate shared parts")
	at(city,"a",World.SERVICE_SPOTS[0]);at(city,"b",World.SERVICE_SPOTS[0])
	check(city.command("a","service_start","service_00").is_empty(),"Roadside service reserves a job")
	check(not city.command("b","service_start","service_00").is_empty(),"Second worker cannot take reserved service")
	check(not city.command("a","service_finish","service_00").is_empty(),"Repair cannot bypass its server timer")
	city.data.time+=7;check(not city.command("b","service_finish","service_00").is_empty(),"Only assigned worker finishes service")
	var budget=city.data.economy.company.balance
	check(city.command("a","service_finish","service_00").is_empty() and city.data.economy.company.parts==1 and city.data.economy.company.balance==budget+420,"Service consumes one part and pays once")
	check(not city.command("a","service_finish","service_00").is_empty() and city.data.economy.company.balance==budget+420,"Repeated repair payment rejected")
	at(city,"a",World.SERVICE_SPOTS[1]);city.command("a","service_start","service_01");at(city,"a",World.SPAWN);city.advance(1.1,{})
	check(city.data.activities.service_01.status=="available" and city.data.economy.company.parts==1,"Leaving service releases reservation without consuming parts")
	city.data.economy.company.balance=20000;city.data.economy.company.reputation=10
	check(not city.command("a","buy_vehicle","courier_02").is_empty(),"Remote vehicle purchase rejected")
	at(city,"a",World.Layout.DEALER);budget=city.data.economy.company.balance
	check(city.command("a","buy_vehicle","courier_02").is_empty() and city.data.vehicles.courier_02.owned and city.data.economy.company.balance==budget-2200,"Purchase adds usable second vehicle")
	check(not city.command("b","vehicle","truck_03").is_empty(),"Unpurchased truck cannot be driven")
	check(not city.command("a","buy_vehicle","courier_02").is_empty(),"Duplicate fleet purchase rejected")
	var car=city.data.vehicles.courier_02
	at(city,"a",World.vec(car.pos));check(city.command("a","vehicle","courier_02").is_empty(),"Player boards purchased vehicle")
	at(city,"b",World.vec(city.data.vehicles.van_01.pos));city.command("b","vehicle","van_01")
	var cstart=car.pos.duplicate();var vstart=city.data.vehicles.van_01.pos.duplicate();city.advance(0.1,{"a":Vector2(0,-1)})
	check(car.pos!=cstart and city.data.vehicles.van_01.pos==vstart and city.data.players.a.pos==car.pos,"Driver input and seated position apply to assigned vehicle only")
	city.exit_vehicle("a",true);city.exit_vehicle("b",true)
	city.command("a","accept_order","d001_01");var cargo=city.data.orders.d001_01.item
	at(city,"a",World.vec(city.data.items[cargo].pos));city.command("a","pickup",cargo)
	at(city,"a",World.rear(car));city.command("a","cargo_door","courier_02");city.command("a","load","courier_02")
	check(car.cargo==[cargo] and city.data.items[cargo].container=="courier_02" and city.data.vehicles.van_01.cargo.is_empty(),"Each vehicle has independent authoritative cargo")
	city.command("a","unload",cargo);at(city,"a",World.DELIVERY);city.command("a","complete_order","d001_01")
	check(city.data.orders.d001_01.status=="completed","Cargo from second vehicle can complete a delivery")
	at(city,"a",World.Layout.GARAGE);budget=city.data.economy.company.balance
	check(city.command("a","claim_chapter","0").is_empty() and city.data.economy.company.chapter==1 and city.data.economy.company.balance==budget+300,"First campaign chapter awards validated progress")
	check(not city.command("a","claim_chapter","0").is_empty() and not city.command("a","claim_chapter","1").is_empty(),"Campaign cannot replay reward or skip requirements")
	check(city.command("a","hire","dispatcher").is_empty() and World.max_orders(city.data)==4,"Hired dispatcher adds two active contracts")
	check(not city.command("a","hire","dispatcher").is_empty(),"Repeated employee hire rejected")
	city.command("a","end_shift","");city.command("a","next_shift","")
	check(city.data.activities.parts_00.status=="completed" and city.data.activities.service_00.status=="available" and city.data.economy.company.repairs==1,"New shift preserves exploration and resets road calls")
	check(Saves.write(root,"City03",city.data).is_empty(),"Expanded world saves")
	var city_save=Saves.read_world(root,"City03")
	check(city_save.ok and city_save.world.vehicles.courier_02.owned and city_save.world.economy.company.chapter==1 and city_save.world.employees.dispatcher.hired,"Fleet, campaign and staff survive host save")
	car.door_open=false;at(city,"a",World.vec(car.pos));city.command("a","vehicle","courier_02")
	Saves.write(root,"Seated03",city.data)
	var seated_save=Saves.read_world(root,"Seated03");var seated=World.new();seated.load_world(seated_save.world);seated.join_player("a","Alice")
	check(seated.data.players.a.vehicle=="" and not seated.blocked_walk(World.vec(seated.data.players.a.pos)),"Saving inside a vehicle reloads the courier at a walkable exit")
	var exit_pos=World.vec(seated.data.players.a.pos);seated.advance(0.1,{"a":Vector2(1,0)})
	check(World.vec(seated.data.players.a.pos)!=exit_pos,"Reconnected courier can move after disembarking from saved vehicle")
	# A real v0.2 payload gains content additively, retaining an accepted job and its cargo.
	var old2=World.new();old2.create_world();old2.join_player("a","Old player");old2.command("a","accept_order","d001_01")
	old2.data.format=2;old2.data.erase("activities");old2.data.vehicles.erase("courier_02");old2.data.vehicles.erase("truck_03");old2.data.employees={}
	for extra in ["parts","discovered","repairs","chapter","engine","insurance"]:old2.data.economy.company.erase(extra)
	old2.data.economy.company.balance=1234
	var expanded=World.new();expanded.load_world(old2.data)
	check(expanded.data.world_id==old2.data.world_id and expanded.data.economy.company.balance==1234 and expanded.data.orders.d001_01.status=="active" and expanded.data.items.has("cargo_d001_01"),"V0.2 migration preserves ID, company budget, accepted job and parcel")
	check(expanded.data.vehicles.size()==3 and expanded.data.activities.size()==15 and Saves.valid_world(expanded.data),"Migration adds fleet and activities as a valid current world")
	var driving=preload("res://scripts/driving.gd")
	for heading in [0.0,PI/2,PI,-PI/2]:
		var forward=driving.forward(heading);var right=forward.cross(Vector3.UP)
		var foot_axis=driving.walk_axis(Vector2(0,-1),heading)
		check(Vector3(foot_axis.x,0,foot_axis.y).dot(forward)>.99,"First-person forward follows camera")
		var strafe=driving.walk_axis(Vector2(1,0),heading)
		check(Vector3(strafe.x,0,strafe.y).dot(right)>.99,"Strafe right follows camera")
		var drive_case={"speed":5.0,"yaw":heading,"brake":false,"steer":0.0}
		for i in range(30):driving.step(drive_case,Vector2(1,-1),16,5.4,1.0/60)
		check(driving.forward(drive_case.yaw).dot(right)>.1,"Right steering turns toward driver's right")
		drive_case={"speed":-3.0,"yaw":heading,"brake":false,"steer":0.0}
		for i in range(30):driving.step(drive_case,Vector2(1,1),16,5.4,1.0/60)
		check(driving.forward(drive_case.yaw).dot(right)<-.05,"Reverse steering has inverse yaw")
	var stopping={"speed":16.0,"yaw":0.0,"brake":true,"steer":0.0}
	for i in range(60):driving.step(stopping,Vector2(1,-1),16,5.4,1.0/60)
	check(is_zero_approx(stopping.speed),"Brake overrides accelerator")
	var reverse={"speed":10.0,"yaw":0.0,"brake":false,"steer":0.0}
	driving.step(reverse,Vector2(0,1),16,5.4,.1)
	check(reverse.speed>0 and reverse.speed<10,"Reverse input brakes before changing direction")
	for i in range(240):driving.step(reverse,Vector2(0,1),0,5.4,1.0/60)
	check(is_zero_approx(reverse.speed),"Empty fuel blocks reverse and forward")
	var gaze=setup();var gaze_start=World.vec(gaze.data.players.a.pos)
	gaze.advance(.1,{"a":Vector2(0,1)},{"a":PI})
	check(is_equal_approx(absf(gaze.data.players.a.yaw),PI) and World.vec(gaze.data.players.a.pos).z>gaze_start.z,"Backpedalling preserves gaze")
	var pedestrians=preload("res://scripts/pedestrian_routes.gd")
	for loop in range(pedestrians.LOOPS.size()):
		var points=pedestrians.route(loop);var span=pedestrians.length(points);var walkable=true;var smooth=true
		for meter in range(ceili(span*2)):
			var pose=pedestrians.sample(points,meter*.5)
			walkable=walkable and not World.Layout.blocked(pose.position,.35)
			var next=pedestrians.sample(points,meter*.5+.27)
			smooth=smooth and pose.position.distance_to(next.position)<=.271
		check(walkable,"Pedestrian loop avoids buildings and water")
		check(smooth,"Constant walking distance around corners and wrap")
	var walkers=setup();var starts={}
	for id in walkers.data.npcs:starts[id]=World.vec(walkers.data.npcs[id].pos)
	walkers.advance(.2,{})
	var max_step=0.0
	for id in starts:max_step=maxf(max_step,starts[id].distance_to(World.vec(walkers.data.npcs[id].pos)))
	check(max_step<=.291,"Pedestrians spawn on route and walk below 1.5 metres per second")
	var parked=walkers.data.vehicles.van_01
	parked.pos=walkers.data.npcs.walker_00.pos.duplicate()
	var blocked_npc=walkers.data.npcs.walker_00.pos.duplicate()
	walkers.data.players.a.pos=parked.pos.duplicate();walkers.advance(.2,{})
	check(walkers.data.npcs.walker_00.pos==blocked_npc and walkers.data.npcs.walker_00.speed==0,"Pedestrian waits for parked car")
	var signals=setup();at(signals,"a",World.vec(signals.data.vehicles.van_01.pos)+Vector3(3,0,0));signals.command("a","vehicle","van_01")
	at(signals,"b",World.vec(signals.data.vehicles.van_01.pos)+Vector3(3,0,0));signals.command("b","vehicle","van_01")
	check(signals.command("a","indicator","left")=="" and signals.data.vehicles.van_01.indicator=="left","Driver controls server-owned signal")
	check(signals.command("b","indicator","right")!="" and signals.data.vehicles.van_01.indicator=="left","Passenger cannot override signal")
	signals.command("a","indicator","left")
	check(signals.data.vehicles.van_01.indicator=="off","Repeated signal command cancels it")
	var nav=preload("res://scripts/navigation.gd")
	var route=nav.path(Vector3(0,0,0),Vector3(56,0,0),true)
	var safe_route=route.size()>2
	for i in range(route.size()-1):safe_route=safe_route and nav.clear(route[i],route[i+1],true)
	check(safe_route,"GPS finds detour around closed road")
	check(driving.bearing(Vector3.LEFT,0)>1.5 and driving.bearing(Vector3.RIGHT,0)<-1.5,"HUD bearing matches driver space")
	print("CORE TESTS: %d passed / %d total"%[checks-failures.size(),checks])
	get_tree().quit(0 if failures.is_empty() else 1)
