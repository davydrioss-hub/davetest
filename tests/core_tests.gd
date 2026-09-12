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
func _ready() -> void:call_deferred("run")
func run() -> void:
	var w=World.new();w.create_world();w.join_player("a","Alice");w.join_player("b","Bob")
	check(w.data.orders.size()==10 and w.data.items.is_empty(),"Contracts exist before cargo spawns")
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
	check(migrated.data.format==2 and migrated.data.world_id==legacy.data.world_id and migrated.data.players.a.money==875,"Migration preserves legacy identity and wallet")
	migrated.join_player("a","Legacy");at(migrated,"a",World.DELIVERY)
	check(migrated.command("a","complete_order","order_01").is_empty() and migrated.data.players.a.inventory.is_empty(),"Legacy carried parcel remains deliverable after migration")
	print("CORE TESTS: %d passed / %d total"%[checks-failures.size(),checks])
	get_tree().quit(0 if failures.is_empty() else 1)
