class_name WorldState
extends RefCounted
## Authoritative, deterministic game rules; no scene, UI, or client-side rewards.
const Layout = preload("res://scripts/world_layout.gd")
const SPEED = 5.5
const INTERACT_RANGE = 3.1
const RESPAWN_DELAY = 3.0
const SPAWN = Layout.SPAWN
const DELIVERY = Vector3(-16,0,-8)
const SHIFT_SECONDS = 1200.0
const TYPES = ["standard", "urgent", "fragile", "heavy", "multi"]
const TYPE_NAMES = {"standard":"Обычная доставка", "urgent":"Срочный заказ", "fragile":"Хрупкий груз", "heavy":"Тяжёлый груз", "multi":"Несколько адресов"}
const UPGRADE_PRICES = {"capacity":800, "equipment":650, "garage":1200, "engine":1500, "insurance":1100}
const FLEET = {
 "van_01":{"name":"AH Transit", "price":0, "rep":0, "seats":4, "capacity":6, "top":16.0, "length":5.4, "width":2.5, "spawn":Vector3(-34,0,29)},
 "courier_02":{"name":"Swift Courier", "price":2200, "rep":3, "seats":2, "capacity":3, "top":23.0, "length":4.3, "width":2.05, "spawn":Vector3(-149,0,58)},
 "truck_03":{"name":"Atlas Cargo", "price":4600, "rep":7, "seats":2, "capacity":18, "top":13.5, "length":7.2, "width":2.8, "spawn":Vector3(-138,0,58)}
}
const STAFF = {"mechanic":{"name":"Мира · механик", "price":1000, "wage":90}, "dispatcher":{"name":"Лев · диспетчер", "price":1400, "wage":90}}
const CHAPTERS = [
 {"title":"Первый рейс", "hint":"Выполните первую доставку", "reward":300},
 {"title":"Знакомство с городом", "hint":"Найдите 4 ящика с деталями в новых районах", "reward":450},
 {"title":"Своими руками", "hint":"Помогите 2 водителям на дороге", "reward":650},
 {"title":"Большая смена", "hint":"8 доставок за всё время и репутация 5", "reward":900},
 {"title":"Своя команда", "hint":"Наймите сотрудника и купите вторую машину", "reward":1200},
 {"title":"Весь город", "hint":"20 доставок и автопарк из 3 машин", "reward":2500}
]
const PART_SPOTS = [Vector3(-190,0,-120),Vector3(-174,0,-44),Vector3(-120,0,32),Vector3(-75,0,-119),Vector3(-12,0,-96),Vector3(48,0,-90),Vector3(174,0,-84),Vector3(201,0,0),Vector3(174,0,82),Vector3(61,0,136),Vector3(-61,0,136),Vector3(-174,0,120)]
const SERVICE_SPOTS = [Vector3(-106,0,-57),Vector3(106,0,-94),Vector3(48,0,98)]
var data: Dictionary = {}
var events: Array = []
var npc_clock = 0.0
var slow_clock = 0.0

static func vec(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))
static func arr(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
static func rear(v: Dictionary) -> Vector3:
	return vec(v.pos) + Vector3(0,0,-float(FLEET[v.get("model","van_01")].length)/2.0-0.4).rotated(Vector3.UP,float(v.yaw))
static func destination(order: Dictionary) -> Dictionary:
	return Layout.DESTINATIONS[int(order.route[mini(int(order.stage),order.route.size()-1)])]
static func held(p: Dictionary, state: Dictionary) -> String:
	for id in p.inventory:
		if state.items.has(id) and not state.items[id].delivered: return id
	return ""

func create_world() -> void:
	data = {"format":3, "world_id":Crypto.new().generate_random_bytes(16).hex_encode(), "time":64800.0, "tick":0, "revision":0,
		"players":{}, "items":{}, "orders":{}, "npcs":{}, "police":{}, "employees":{}, "activities":{},
		"vehicles":{"van_01":{"pos":arr(Layout.VAN), "yaw":0.0,"driver":"","passengers":[],"speed":0.0,"cargo":[],"capacity":6,"door_open":false,"health":100.0,"fuel":100.0,"brake":false}},
		"properties":{"depot_01":{"pos":arr(Layout.GARAGE),"owner":"company","price":0}},
		"doors":{"gate_01":{"pos":[-37.5,0.0,20.0],"open":true}},
		"containers":{"supply_01":{"pos":[-47.0,0.0,16.0],"inventory":{"supplies":12}}},
		"economy":{"ledger":{"paid_orders":0,"employee_wages":0}, "company":{"balance":650,"reputation":0,"capacity":0,"equipment":0,"garage":0,"total_deliveries":0},
			"shift":{"day":1,"status":"active","started":64800.0,"duration":SHIFT_SECONDS,"target":1600,"income":0,"expenses":0,"deliveries":0,"damaged":0,"late":0,"report":{}},
			"weather":{"rain":false,"road_closed":false,"event_index":0,"message":"Первая смена. Откройте планшет [Tab] и возьмите заказ."}}}
	for i in range(10):
		data.npcs["walker_%02d"%i] = {"pos":[-50.0+i*10.0,0.0,6.0],"phase":i*0.63,"yaw":0.0}
	data.police["patrol_01"] = {"pos":[55.0,0.0,-15.0],"phase":0.0,"yaw":0.0}
	_expand_world()
	_make_orders()
	events.clear()

static func vehicle_near(state: Dictionary, player: Dictionary) -> String:
	if player.vehicle != "" and state.vehicles.has(player.vehicle): return player.vehicle
	var selected="van_01"; var best=INF
	for vid in state.vehicles:
		var v=state.vehicles[vid]
		if not v.get("owned",true): continue
		var d=vec(v.pos).distance_squared_to(vec(player.pos))
		if d<best: selected=vid;best=d
	return selected
static func vehicle_spec(v: Dictionary) -> Dictionary:
	return FLEET[v.get("model","van_01")]
static func owned_count(state: Dictionary) -> int:
	var count=0
	for v in state.vehicles.values():
		if v.get("owned",true): count+=1
	return count
static func max_orders(state: Dictionary) -> int:
	return 2+int(state.economy.company.garage)*2+(2 if state.employees.get("dispatcher",{}).get("hired",false) else 0)
static func chapter_ready(state: Dictionary) -> bool:
	var c=state.economy.company
	match int(c.chapter):
		0:return int(c.total_deliveries)>=1
		1:return int(c.discovered)>=4
		2:return int(c.repairs)>=2
		3:return int(c.total_deliveries)>=8 and int(c.reputation)>=5
		4:return owned_count(state)>=2 and (state.employees.mechanic.hired or state.employees.dispatcher.hired)
		5:return int(c.total_deliveries)>=20 and owned_count(state)>=3
	return false
func _expand_world() -> void:
	# Additive migration: never replace an existing order, item, wallet, vehicle or world ID.
	data.format=3
	if not data.has("activities"): data.activities={}
	data.economy.company.merge({"engine":0,"insurance":0,"parts":0,"discovered":0,"repairs":0,"chapter":0},false)
	for vid in FLEET:
		var spec=FLEET[vid]
		if not data.vehicles.has(vid):
			data.vehicles[vid]={"pos":arr(spec.spawn),"yaw":0.0,"driver":"","passengers":[],"speed":0.0,"cargo":[],"capacity":spec.capacity,"door_open":false,"health":100.0,"fuel":100.0,"brake":false,"owned":false,"model":vid}
		data.vehicles[vid].merge({"owned":vid=="van_01","model":vid},false)
	for sid in STAFF:
		if not data.employees.has(sid):data.employees[sid]={"hired":false,"name":STAFF[sid].name,"owner":""}
	for i in range(PART_SPOTS.size()):
		var aid="parts_%02d"%i
		if not data.activities.has(aid):data.activities[aid]={"kind":"parts","title":"Ящик с деталями","pos":arr(PART_SPOTS[i]),"status":"available","worker":"","finish_at":0.0}
	for i in range(SERVICE_SPOTS.size()):
		var aid="service_%02d"%i
		if not data.activities.has(aid):data.activities[aid]={"kind":"service","title":"Помощь на дороге","pos":arr(SERVICE_SPOTS[i]),"status":"available","worker":"","finish_at":0.0}
	for i in range(10,26):
		var nid="walker_%02d"%i
		if not data.npcs.has(nid):data.npcs[nid]={"pos":[-174.0,0.0,-70.0],"phase":i*0.63,"yaw":0.0,"district":i%3}

func _make_orders() -> void:
	var day = int(data.economy.shift.day)
	for i in range(30):
		var kind = TYPES[i%5]
		var stop=(i+day-1)%5 if i<5 else 5+(i-5+(day-1)*3)%(Layout.DESTINATIONS.size()-5)
		var route = [stop]
		if kind == "multi": route.append((stop+2)%Layout.DESTINATIONS.size() if i>=5 else (i+day+1)%5)
		var oid = "d%03d_%02d"%[day,i+1]
		if data.orders.has(oid):continue
		var bonus=0 if i<5 else int(vec(Layout.DESTINATIONS[stop].pos).distance_to(Layout.GARAGE)*2)
		patch("orders",oid,{"kind":kind,"title":TYPE_NAMES[kind],"reward":[350,550,600,850,950][i%5]+bonus,"route":route,"stage":0,"status":"available","item":"cargo_"+oid,"accepted_by":"","completed_by":"","deadline":0.0,"paid":0,"required_rep":0 if i<10 else (2 if i<20 else 5)})

func load_world(snapshot: Dictionary) -> void:
	data = snapshot.duplicate(true)
	if int(data.get("format",1)) < 2:
		var old = data
		create_world()
		data.world_id = old.world_id
		data.time = old.time
		data.economy.shift.started = old.time
		data.players = old.players
		data.economy.ledger = old.economy.ledger
		data.employees = old.employees.duplicate(true)
		data.containers.supply_01.inventory = old.containers.supply_01.inventory.duplicate(true)
		if old.properties.depot_01.owner != "":
			data.properties.depot_01.owner = old.properties.depot_01.owner
			data.economy.company.garage = 1
		for employee in old.employees.values():
			if employee.owner != "": data.economy.company.equipment = 1
		data.doors.gate_01.open = old.doors.gate_01.open
		for p in data.players.values(): p.pos = arr(SPAWN)
		# Preserve old carried parcels and unpaid/completed jobs when expanding the district.
		for oid in old.orders:
			var o = old.orders[oid].duplicate(true)
			o.merge({"kind":"standard","title":"Заказ из версии 0.1","route":[0],"stage":0,"deadline":0.0,"paid":0,"required_rep":0,"accepted_by":""},true)
			if o.status == "open": o.status = "active"
			data.orders[oid] = o
		for iid in old.items:
			var item = old.items[iid].duplicate(true)
			item.merge({"kind":"standard","container":"","carriers":[],"condition":100.0,"secured":false,"slots":1,"pos":arr(SPAWN)},true)
			if item.holder != "": item.carriers = [item.holder]
			data.items[iid] = item
	_expand_world()
	_make_orders()
	for a in data.activities.values():
		if a.status=="working":a.status="available";a.worker="";a.finish_at=0.0
	for p in data.players.values():
		p.connected = false
		p.vehicle = ""
		if not p.has("role"): p.role = "Курьер"
	for v in data.vehicles.values():
		v.driver = ""; v.passengers = []; v.speed = 0.0; v.brake = false
	for p in data.players.values():p.pos=arr(_safe_position(vec(p.pos)))
	# Paired carrying cannot survive a process restart. Keep the leader's cargo.
	for iid in data.items:
		var item = data.items[iid]
		for helper in item.carriers.slice(1):
			if data.players.has(helper): data.players[helper].inventory.erase(iid)
		item.carriers = [item.holder] if item.holder != "" else []
	events.clear()

func patch(domain: String, id: String, fields: Dictionary, inv: Dictionary = {}, stats: Dictionary = {}) -> void:
	data.revision += 1
	var event = {"revision":data.revision,"tick":data.tick,"d":domain,"id":id,"fields":fields.duplicate(true),"inv":inv.duplicate(true),"stats":stats.duplicate(true)}
	apply_event(data,event)
	events.append(event)
func erase(domain: String, id: String) -> void:
	data.revision += 1
	var event = {"revision":data.revision,"tick":data.tick,"d":domain,"id":id,"fields":{},"inv":{},"stats":{},"remove":true}
	apply_event(data,event); events.append(event)
static func apply_event(state: Dictionary, event: Dictionary) -> void:
	state.revision = event.revision
	if event.get("remove",false):
		state[event.d].erase(event.id)
		return
	if not state[event.d].has(event.id): state[event.d][event.id] = {}
	var record = state[event.d][event.id]
	record.merge(event.fields,true)
	if not event.inv.is_empty():
		if not record.has("inventory"): record.inventory = {}
		for item in event.inv:
			if int(event.inv[item]) <= 0: record.inventory.erase(item)
			else: record.inventory[item] = event.inv[item]
	if not event.stats.is_empty(): record.stats.merge(event.stats,true)
func drain_events() -> Array:
	var result = events
	events = []
	return result
func join_player(id: String, nick: String) -> void:
	if not data.players.has(id):
		patch("players",id,{"nickname":nick,"pos":arr(SPAWN+Vector3(data.players.size()%4,0,0)),"yaw":0.0,"money":300,"inventory":{},"owned":{},"stats":{"deliveries":0,"deaths":0},"alive":true,"dead_until":0.0,"vehicle":"","connected":true,"role":"Курьер"})
	else: patch("players",id,{"nickname":nick,"connected":true,"pos":arr(_safe_position(vec(data.players[id].pos)))})
func leave_player(id: String) -> void:
	if not data.players.has(id): return
	var p = data.players[id]
	if p.vehicle != "": exit_vehicle(id,true)
	var iid = held(p,data)
	if iid != "" and data.items[iid].carriers.size()>1: _drop(iid)
	patch("players",id,{"connected":false})
func near(id: String, location: Array, distance: float = INTERACT_RANGE) -> bool:
	return vec(data.players[id].pos).distance_to(vec(location)) <= distance
func active_orders() -> int:
	var count = 0
	for o in data.orders.values():
		if o.status == "active": count += 1
	return count
func cargo_used(vid: String="van_01") -> int:
	var count = 0
	for iid in data.vehicles[vid].cargo: count += int(data.items[iid].slots)
	return count

func command(id: String, action: String, target: String) -> String:
	if not data.players.has(id) or not data.players[id].connected: return "Игрок не подключён."
	var p = data.players[id]
	var vid = vehicle_near(data,p)
	if action in ["vehicle","cargo_door","load","secure","repair","tow"] and data.vehicles.has(target):vid=target
	if action=="unload" and data.items.has(target) and data.vehicles.has(data.items[target].container):vid=data.items[target].container
	if p.vehicle!="":vid=p.vehicle
	var van = data.vehicles[vid]
	var company = data.economy.company
	var shift = data.economy.shift
	var carry = held(p,data)
	if action in ["vehicle","cargo_door","load","unload","secure","repair","tow"] and not van.owned:return "Сначала купите эту машину в автосалоне."
	if action == "respawn":
		if p.alive or data.time < p.dead_until: return "Возрождение пока недоступно."
		patch("players",id,{"alive":true,"pos":arr(SPAWN),"vehicle":""}); return ""
	if not p.alive: return "Нажмите R для возрождения."
	if action == "role":
		if not target in ["Курьер","Водитель","Грузчик","Диспетчер"]: return "Неизвестная роль."
		patch("players",id,{"role":target}); return ""
	if p.vehicle != "":
		if action == "vehicle": return exit_vehicle(id)
		if action == "brake" and van.driver == id:
			patch("vehicles",vid,{"brake":target == "on"}); return ""
		if action == "horn":
			patch("vehicles",vid,{"horn_tick":data.tick}); return ""
		if not action in ["accept_order","ping"]: return "Сначала выйдите из фургона."
	match action:
		"accept_order":
			if shift.status != "active": return "Смена закончилась. Начните следующую в гараже."
			if not data.orders.has(target): return "Неизвестный заказ."
			var order = data.orders[target]
			if order.status != "available": return "Этот заказ уже принят."
			if company.reputation < order.required_rep: return "Для этого клиента нужна репутация %d."%order.required_rep
			if active_orders() >= max_orders(data): return "Сначала завершите активные заказы или расширьте гараж."
			var dock = Vector3(-45+data.items.size()%8*2.0,0,22)
			patch("orders",target,{"status":"active","accepted_by":id,"deadline":data.time+(180.0 if order.kind=="urgent" else 750.0)*(1.2 if data.employees.dispatcher.hired else 1.0)})
			patch("items",order.item,{"pos":arr(dock),"kind":order.kind,"holder":"","carriers":[],"container":"","delivered":false,"condition":100.0,"secured":false,"slots":3 if order.kind=="heavy" else 1})
		"pickup":
			if carry != "": return "Руки заняты. Сначала положите груз."
			if not data.items.has(target): return "Неизвестный груз."
			var item = data.items[target]
			if item.delivered or item.container != "": return "Груз недоступен."
			var loc = item.pos if item.holder=="" else data.players[item.holder].pos
			if not near(id,loc): return "Подойдите к грузу."
			if item.holder != "" and (item.kind!="heavy" or item.carriers.size()!=1 or not data.players[item.holder].connected): return "Груз уже несут."
			var carriers = item.carriers.duplicate(); carriers.append(id)
			patch("items",target,{"holder":id if item.holder=="" else item.holder,"carriers":carriers})
			patch("players",id,{}, {target:1})
		"drop":
			if carry=="" or carry!=target: return "У вас нет этого груза."
			_drop(carry)
		"cargo_door", "load", "unload", "secure":
			if absf(van.speed)>0.2 or not near(id,arr(rear(van)),3.6): return "Подойдите к задней двери остановленного фургона."
			if action=="cargo_door":
				patch("vehicles",vid,{"door_open":not van.door_open}); return ""
			if not van.door_open: return "Сначала откройте багажник [E]."
			if action=="load":
				if carry=="": return "Возьмите груз в руки."
				var item = data.items[carry]
				if cargo_used(vid)+int(item.slots)>int(van.capacity): return "Багажник заполнен."
				for carrier in item.carriers:
					if not near(carrier,arr(rear(van)),4.5): return "Второй грузчик слишком далеко."
					patch("players",carrier,{}, {carry:0})
				var cargo = van.cargo.duplicate(); cargo.append(carry)
				patch("vehicles",vid,{"cargo":cargo})
				patch("items",carry,{"holder":"","carriers":[],"container":vid,"secured":int(company.equipment)>0})
			elif action=="unload":
				if carry!="": return "Руки заняты."
				if not target in van.cargo: return "Этого груза нет в багажнике."
				var cargo = van.cargo.duplicate(); cargo.erase(target)
				patch("vehicles",vid,{"cargo":cargo})
				patch("items",target,{"container":"","holder":id,"carriers":[id],"secured":false,"pos":p.pos.duplicate()})
				patch("players",id,{}, {target:1})
			else:
				for iid in van.cargo: patch("items",iid,{"secured":true})
		"complete_order":
			if not data.orders.has(target): return "Неизвестный заказ."
			var o = data.orders[target]
			if o.status!="active" or carry!=o.item: return "Нужен груз этого активного заказа."
			if not near(id,destination(o).pos,3.5): return "Доставьте груз к отмеченному адресу."
			var item = data.items[o.item]
			if int(o.stage)+1<o.route.size():
				patch("orders",target,{"stage":int(o.stage)+1}); return ""
			var late = data.time>o.deadline and o.deadline>0
			var pay = int(round(float(o.reward)*maxf(0.2,item.condition/100.0)*(0.65 if late else 1.0)))
			for carrier in item.carriers:
				patch("players",carrier,{}, {o.item:0},{"deliveries":data.players[carrier].stats.deliveries+1})
			patch("items",o.item,{"holder":"","carriers":[],"delivered":true})
			patch("orders",target,{"status":"completed","completed_by":id,"paid":pay})
			patch("economy","company",{"balance":company.balance+pay,"reputation":maxi(0,int(company.reputation)+(0 if late else 1)),"total_deliveries":company.total_deliveries+1})
			patch("economy","ledger",{"paid_orders":data.economy.ledger.paid_orders+pay})
			patch("economy","shift",{"income":shift.income+pay,"deliveries":shift.deliveries+1,"damaged":shift.damaged+(1 if item.condition<99 else 0),"late":shift.late+(1 if late else 0)})
		"vehicle":
			if not data.vehicles.has(target) or not van.owned or not near(id,van.pos,4.2) or absf(van.speed)>0.5: return "Подойдите к остановленному фургону."
			if carry!="": return "Сначала загрузите груз в багажник."
			if van.passengers.size()>=int(vehicle_spec(van).seats): return "Все места заняты."
			var seats = van.passengers.duplicate(); seats.append(id)
			patch("vehicles",vid,{"passengers":seats,"driver":id if van.driver=="" else van.driver,"brake":false})
			patch("players",id,{"vehicle":vid,"pos":van.pos.duplicate()})
		"repair":
			if not ((near(id,arr(Layout.REPAIR),5) and vec(van.pos).distance_to(Layout.REPAIR)<12) or (near(id,arr(Layout.WORKSHOP),7) and vec(van.pos).distance_to(Layout.WORKSHOP)<18)): return "Поставьте фургон у ремонтной площадки в гараже."
			var cost = int(ceil(((100-van.health)*1.4+(100-van.fuel)*0.6)*(0.65 if data.employees.mechanic.hired else 1.0)))
			if cost>company.balance: return "Не хватает денег на ремонт. Доступен бесплатный эвакуатор в меню смены."
			_spend(cost); patch("vehicles",vid,{"health":100.0,"fuel":100.0})
		"tow":
			if van.passengers.size()>0: return "Все игроки должны выйти из фургона."
			var tow_pos=vehicle_spec(van).spawn
			var placed=false
			for offset in [Vector3.ZERO,Vector3(8,0,0),Vector3(-8,0,0),Vector3(0,0,9)]:
				var candidate=tow_pos+offset
				if not vehicle_blocked(candidate,vid) and not vehicle_blocked(candidate+Vector3(0,0,float(vehicle_spec(van).length)/2-1.0),vid) and not vehicle_blocked(candidate-Vector3(0,0,float(vehicle_spec(van).length)/2-1.0),vid):
					var occupied=false
					for player in data.players.values():
						if player.connected and vec(player.pos).distance_to(candidate)<5:occupied=true
					if not occupied:tow_pos=candidate;placed=true;break
			if not placed:return "Освободите парковку у базы этой машины для эвакуации."
			patch("vehicles",vid,{"pos":arr(tow_pos),"yaw":0.0,"speed":0.0,"health":maxf(35,van.health),"fuel":maxf(20,van.fuel)})
			patch("economy","company",{"reputation":maxi(0,int(company.reputation)-1)})
		"upgrade":
			if not target in UPGRADE_PRICES or not near(id,arr(Layout.GARAGE),5): return "Улучшения покупаются у терминала в гараже."
			if int(company[target])>0: return "Улучшение уже установлено."
			var cost = UPGRADE_PRICES[target]
			if company.balance<cost: return "Недостаточно денег компании."
			_spend(cost); patch("economy","company",{target:1})
			if target=="capacity": patch("vehicles","van_01",{"capacity":10})
		"buy_vehicle":
			if not FLEET.has(target) or not near(id,arr(Layout.DEALER),6):return "Покупка доступна в автосалоне на западе города."
			var spec=FLEET[target]
			if data.vehicles[target].owned:return "Эта машина уже принадлежит компании."
			if int(company.reputation)<int(spec.rep):return "Нужна репутация %d."%spec.rep
			if int(company.balance)<int(spec.price):return "Недостаточно денег компании."
			_spend(spec.price);patch("vehicles",target,{"owned":true})
			patch("economy","weather",{"message":"Новая машина в автопарке: "+spec.name})
		"hire":
			if not STAFF.has(target) or not near(id,arr(Layout.GARAGE),5):return "Сотрудники нанимаются в гараже."
			if data.employees[target].hired:return "Сотрудник уже работает у вас."
			if company.balance<STAFF[target].price:return "Недостаточно денег компании."
			_spend(STAFF[target].price);patch("employees",target,{"hired":true,"owner":"company"})
		"claim_chapter":
			if not near(id,arr(Layout.GARAGE),5) or not chapter_ready(data):return "Сначала выполните цель главы и вернитесь в гараж."
			if target!=str(int(company.chapter)):return "Эта награда уже получена или пока недоступна."
			var reward=int(CHAPTERS[int(company.chapter)].reward)
			patch("economy","company",{"balance":company.balance+reward,"chapter":int(company.chapter)+1})
			patch("economy","weather",{"message":"Глава завершена! Бонус компании $%d. Следующая цель — в планшете."%reward})
		"collect_parts":
			if not data.activities.has(target):return "Неизвестное место."
			var a=data.activities[target]
			if a.kind!="parts" or a.status!="available" or not near(id,a.pos,3):return "Подойдите к доступному ящику с деталями."
			patch("activities",target,{"status":"completed"})
			patch("economy","company",{"parts":int(company.parts)+2,"discovered":int(company.discovered)+1})
			patch("economy","weather",{"message":"Найдены 2 детали. Они пригодятся для помощи водителям."})
		"service_start", "service_finish":
			if not data.activities.has(target):return "Неизвестный вызов."
			var a=data.activities[target]
			if a.kind!="service" or not near(id,a.pos,4) or carry!="":return "Подойдите к сломанной машине со свободными руками."
			if shift.status!="active":return "Помощь на дороге доступна во время смены."
			if company.parts<1:return "Нужна 1 деталь. Ищите ящики в городе или покупайте детали в мастерской."
			if action=="service_start":
				if a.status!="available":return "Этот вызов уже занят или выполнен."
				patch("activities",target,{"status":"working","worker":id,"finish_at":data.time+6.0})
			else:
				if a.status!="working" or a.worker!=id or data.time<a.finish_at:return "Подождите окончания ремонта рядом с машиной."
				patch("activities",target,{"status":"completed","worker":"","finish_at":0.0})
				patch("economy","company",{"parts":int(company.parts)-1,"repairs":int(company.repairs)+1,"balance":company.balance+420,"reputation":company.reputation+1})
				patch("economy","shift",{"income":shift.income+420})
				patch("economy","weather",{"message":"Водитель снова в пути. Компания получила $420 и репутацию."})
		"buy_parts":
			if not near(id,arr(Layout.WORKSHOP),6):return "Детали продаются в мастерской промышленного района."
			if company.balance<180:return "Нужно $180 за 3 детали."
			_spend(180);patch("economy","company",{"parts":int(company.parts)+3})
		"end_shift":
			if not near(id,arr(Layout.GARAGE),6): return "Вернитесь к терминалу в гараже."
			if shift.status!="active": return "Смена уже завершена."
			_end_shift()
		"next_shift":
			if shift.status!="finished" or not near(id,arr(Layout.GARAGE),6): return "Завершите смену и вернитесь в гараж."
			for iid in data.items.keys():
				if not data.items[iid].delivered: _drop(iid)
				erase("items",iid)
			for oid in data.orders.keys(): erase("orders",oid)
			for fleet_id in data.vehicles:patch("vehicles",fleet_id,{"cargo":[]})
			for aid in data.activities:
				if data.activities[aid].kind=="service":patch("activities",aid,{"status":"available","worker":"","finish_at":0.0})
			patch("economy","shift",{"day":int(shift.day)+1,"status":"active","started":data.time,"income":0,"expenses":0,"deliveries":0,"damaged":0,"late":0,"target":1600+int(shift.day)*200,"report":{}})
			patch("economy","weather",{"rain":false,"road_closed":false,"event_index":0,"message":"Новая смена. Новые клиенты ждут доставку."})
			_make_orders()
		"door":
			if not data.doors.has(target) or not near(id,data.doors[target].pos,5): return "Подойдите к воротам."
			var door = data.doors[target]
			if door.open:
				for player in data.players.values():
					if player.connected and absf(player.pos[2]-20)<1 and player.pos[0]>-49 and player.pos[0]<-26: return "В проёме стоит игрок."
				for parked in data.vehicles.values():
					if absf(parked.pos[2]-20)<float(vehicle_spec(parked).length)/2 and parked.pos[0]>-50 and parked.pos[0]<-25:return "В проёме стоит машина."
			patch("doors",target,{"open":not door.open})
		"take_supply", "store_supply":
			if not data.containers.has(target) or not near(id,data.containers[target].pos): return "Подойдите к стеллажу."
			var c = data.containers[target]
			var amount = 1 if action=="take_supply" else -1
			var have = int(p.inventory.get("supplies",0))
			if (amount>0 and int(c.inventory.get("supplies",0))<=0) or (amount<0 and have<=0): return "Нет расходников."
			patch("containers",target,{}, {"supplies":int(c.inventory.get("supplies",0))-amount})
			patch("players",id,{}, {"supplies":have+amount})
		"ping":
			if not data.orders.has(target) or data.orders[target].status!="active": return "Выберите активный заказ."
			patch("economy","weather",{"message":p.nickname+": едем к "+destination(data.orders[target]).name})
		_: return "Неизвестное действие."
	return ""

func _drop(iid: String) -> void:
	var item = data.items[iid]
	var pos = item.pos
	if item.holder!="" and data.players.has(item.holder): pos = data.players[item.holder].pos.duplicate()
	for carrier in item.carriers:
		if data.players.has(carrier): patch("players",carrier,{}, {iid:0})
	patch("items",iid,{"holder":"","carriers":[],"pos":pos})
func _spend(cost: int) -> void:
	patch("economy","company",{"balance":data.economy.company.balance-cost})
	if data.economy.shift.status=="active": patch("economy","shift",{"expenses":data.economy.shift.expenses+cost})
func _end_shift() -> void:
	var s = data.economy.shift
	for oid in data.orders:
		if data.orders[oid].status=="active": patch("orders",oid,{"status":"failed"})
	var wages=0
	for sid in STAFF:
		if data.employees[sid].hired:wages+=int(STAFF[sid].wage)
	var fee = mini(80+wages,int(data.economy.company.balance))
	patch("economy","ledger",{"employee_wages":int(data.economy.ledger.employee_wages)+mini(wages,fee)})
	_spend(fee)
	var profit = int(s.income)-int(s.expenses)
	patch("economy","shift",{"status":"finished","report":{"profit":profit,"success":profit>=s.target,"income":s.income,"expenses":s.expenses,"deliveries":s.deliveries,"late":s.late,"damaged":s.damaged}})
	patch("economy","weather",{"message":"Смена завершена. Вернитесь в гараж: отчёт и следующая ночь [Tab]."})
func exit_vehicle(id: String, forced: bool = false) -> String:
	var p = data.players[id]
	if p.vehicle=="": return "Вы не в фургоне."
	var v = data.vehicles[p.vehicle]
	if absf(v.speed)>1 and not forced: return "Остановитесь перед выходом."
	var pos = SPAWN
	for offset in [Vector3(2.4,0,0),Vector3(-2.4,0,0),Vector3(0,0,-4),Vector3(0,0,4)]:
		var candidate = vec(v.pos)+offset.rotated(Vector3.UP,float(v.yaw))
		if not blocked_walk(candidate): pos=candidate; break
	var seats = v.passengers.duplicate(); seats.erase(id)
	var driver = v.driver
	if driver==id: driver=seats[0] if not seats.is_empty() else ""
	patch("vehicles",p.vehicle,{"driver":driver,"passengers":seats,"speed":0.0,"brake":false,"pos":v.pos.duplicate(),"yaw":v.yaw})
	patch("players",id,{"vehicle":"","pos":arr(pos)})
	return ""
func blocked(position: Vector3, radius: float, vehicle: bool = false) -> bool:
	if Layout.blocked(position,radius,vehicle and data.economy.weather.road_closed): return true
	if not data.doors.gate_01.open and Rect2(-49,19.7,23,0.6).grow(radius).has_point(Vector2(position.x,position.z)): return true
	return false
func _safe_position(pos:Vector3) -> Vector3:
	if not blocked_walk(pos):return pos
	for radius in [2.5,4.5,7.0,10.0]:
		for i in range(16):
			var candidate=pos+Vector3(sin(i*TAU/16)*radius,0,cos(i*TAU/16)*radius)
			if not blocked_walk(candidate):return candidate
	return SPAWN
func blocked_walk(position:Vector3) -> bool:
	if blocked(position,0.4):return true
	for v in data.vehicles.values():
		var spec=vehicle_spec(v)
		var local=(position-vec(v.pos)).rotated(Vector3.UP,-float(v.yaw))
		if Rect2(-float(spec.width)/2-0.3,-float(spec.length)/2-0.25,float(spec.width)+0.6,float(spec.length)+0.5).has_point(Vector2(local.x,local.z)):return true
	return false
func vehicle_blocked(position:Vector3, vid:String) -> bool:
	if blocked(position,float(FLEET[vid].width)/2.0,true):return true
	for other in data.vehicles:
		if other==vid:continue
		var v=data.vehicles[other];var spec=vehicle_spec(v)
		var local=(position-vec(v.pos)).rotated(Vector3.UP,-float(v.yaw))
		if Rect2(-float(spec.width)/2,-float(spec.length)/2,float(spec.width),float(spec.length)).grow(float(FLEET[vid].width)/2.0).has_point(Vector2(local.x,local.z)):return true
	return false
func _crash(speed: float, vid: String="van_01") -> void:
	var van = data.vehicles[vid]
	var damage = maxf(0,speed-3)*2.0*(0.65 if int(data.economy.company.insurance)>0 else 1.0)
	if damage<=0: return
	patch("vehicles",vid,{"health":maxf(0,van.health-damage),"speed":0.0})
	for iid in van.cargo:
		var item=data.items[iid]
		var loss=damage*(0.15 if item.secured else 1.0)*(1.5 if item.kind=="fragile" else 1.0)
		patch("items",iid,{"condition":maxf(10,item.condition-loss)})

func advance(dt: float, inputs: Dictionary) -> void:
	data.tick += 1; data.time += dt
	for vid in data.vehicles:
		var v = data.vehicles[vid]
		if v.driver!="" and data.players.has(v.driver) and data.players[v.driver].connected:
			var axis: Vector2 = inputs.get(v.driver,Vector2.ZERO)
			var top = float(vehicle_spec(v).top)*(1.18 if data.economy.company.engine else 1.0)*(0.55 if v.health<35 else 1.0)*(0.75 if data.economy.weather.rain else 1.0)
			if v.fuel<=0 or v.health<=0 or v.door_open: top=0
			v.speed = move_toward(float(v.speed),clampf(-axis.y*top,-6,top),dt*(24 if v.brake else 7)) if not v.brake else move_toward(float(v.speed),0,dt*24)
			if absf(v.speed)>0.1: v.yaw += axis.x*dt*1.5*clampf(v.speed/4,-1,1)
			var pos=vec(v.pos)+Vector3(sin(v.yaw),0,cos(v.yaw))*v.speed*dt
			var longitudinal=Vector3(sin(v.yaw),0,cos(v.yaw))*maxf(0.6,(float(vehicle_spec(v).length)-float(vehicle_spec(v).width))/2.0)
			if not vehicle_blocked(pos,vid) and not vehicle_blocked(pos+longitudinal,vid) and not vehicle_blocked(pos-longitudinal,vid): v.pos=arr(pos)
			else: _crash(absf(v.speed),vid); v.speed=0.0
			v.fuel=maxf(0,v.fuel-absf(v.speed)*dt*0.008)
	for id in data.players:
		var p=data.players[id]
		if not p.connected or not p.alive: continue
		if p.vehicle!="":
			var seat=data.vehicles[p.vehicle];p.pos=seat.pos.duplicate();p.yaw=seat.yaw;continue
		var hit=false
		for moving in data.vehicles.values():
			if absf(moving.speed)>8 and vec(p.pos).distance_to(vec(moving.pos))<1.8:hit=true;break
		if hit:
			var dropped=held(p,data)
			if dropped!="":_drop(dropped)
			patch("players",id,{"alive":false,"dead_until":data.time+RESPAWN_DELAY},{},{"deaths":p.stats.deaths+1})
			continue
		var carry=held(p,data)
		if carry!="" and data.items[carry].holder!=id: continue
		var speed=SPEED
		if carry!="":
			speed=4.1
			if data.items[carry].kind=="heavy": speed=3.4 if data.items[carry].carriers.size()>1 else 1.7
		var axis:Vector2=inputs.get(id,Vector2.ZERO)
		var pos=vec(p.pos)
		var dx=Vector3(axis.x*speed*dt,0,0)
		var dz=Vector3(0,0,axis.y*speed*dt)
		if not blocked_walk(pos+dx): pos+=dx
		if not blocked_walk(pos+dz): pos+=dz
		p.pos=arr(pos)
		if axis.length_squared()>0.01: p.yaw=atan2(axis.x,axis.y)
		if carry!="":
			for helper in data.items[carry].carriers.slice(1):
				var candidate=pos+Vector3(1.2,0,0).rotated(Vector3.UP,p.yaw)
				data.players[helper].pos=arr(candidate if not blocked(candidate,0.4) else pos)
				data.players[helper].yaw=p.yaw
	# 5 Hz nearby pedestrians; distant actors get a cheaper update.
	npc_clock+=dt
	if npc_clock>=0.2:
		var elapsed=npc_clock; npc_clock=0.0
		for i in range(data.npcs.size()):
			var actor=data.npcs.values()[i]
			actor.phase+=elapsed*0.09
			var close=false
			for p in data.players.values():
				if p.connected and vec(p.pos).distance_to(vec(actor.pos))<30: close=true; break
			if close or int(data.tick)%60<12:
				var t=fposmod(actor.phase,4.0)
				var corners=[Vector3(-51,0,6),Vector3(51,0,6),Vector3(51,0,33),Vector3(-51,0,33)]
				if actor.has("district"):
					var loops=[[Vector3(-174,0,-70),Vector3(-118,0,-70),Vector3(-118,0,32),Vector3(-174,0,32)],[Vector3(118,0,-70),Vector3(174,0,-70),Vector3(174,0,70),Vector3(118,0,70)],[Vector3(-50,0,80),Vector3(50,0,80),Vector3(50,0,110),Vector3(-50,0,110)]]
					corners=loops[int(actor.district)]
				var a=corners[int(t)]; var b=corners[(int(t)+1)%4]
				actor.pos=arr(a.lerp(b,fposmod(t,1.0))); actor.yaw=atan2(b.x-a.x,b.z-a.z)
		var patrol=data.police.patrol_01
		patrol.phase+=elapsed*0.07
		patrol.pos=[56.0,0.0,sin(patrol.phase)*31.0]; patrol.yaw=0.0 if cos(patrol.phase)>0 else PI
	slow_clock+=dt
	if slow_clock>=1.0:
		slow_clock=0.0
		for fleet_id in data.vehicles:
			var v=data.vehicles[fleet_id]
			if data.employees.mechanic.hired and vec(v.pos).distance_to(Layout.WORKSHOP)<18 and absf(v.speed)<0.1:v.health=minf(100,v.health+0.5)
			if v.driver!="" or (data.employees.mechanic.hired and vec(v.pos).distance_to(Layout.WORKSHOP)<18):patch("vehicles",fleet_id,{"fuel":v.fuel,"health":v.health})
		for aid in data.activities:
			var a=data.activities[aid]
			if a.status=="working":
				var worker=data.players.get(a.worker,{})
				if worker.is_empty() or not worker.connected or not worker.alive or worker.vehicle!="" or not near(a.worker,a.pos,4):patch("activities",aid,{"status":"available","worker":"","finish_at":0.0})
		var s=data.economy.shift
		if s.status=="active":
			var elapsed=data.time-s.started
			var weather=data.economy.weather
			if elapsed>=float(s.duration): _end_shift()
			elif elapsed>180 and weather.event_index==0:
				patch("economy","weather",{"rain":true,"event_index":1,"message":"Начался дождь. На мокрой дороге фургон едет медленнее. Закрепите груз [G]."})
			elif elapsed>420 and weather.event_index==1:
				patch("economy","weather",{"road_closed":true,"event_index":2,"message":"Центральная улица перекрыта. Объезжайте по северной или южной дороге."})
			elif elapsed>660 and weather.event_index==2:
				var message="Клиенты подтвердили адреса. Продолжайте доставку."
				for oid in data.orders:
					var o=data.orders[oid]
					if o.status=="active" and int(o.stage)==0:
						var route=o.route.duplicate(); route[0]=(int(route[0])+1)%5
						patch("orders",oid,{"route":route}); message="Клиент изменил адрес. Новый маршрут отмечен на карте."; break
				patch("economy","weather",{"rain":false,"event_index":3,"message":message})
			elif elapsed>900 and weather.event_index==3:
				patch("vehicles","van_01",{"health":maxf(30,data.vehicles.van_01.health-25)})
				patch("economy","weather",{"road_closed":false,"event_index":4,"message":"Загорелась лампа двигателя. Ремонт доступен на площадке у гаража."})
