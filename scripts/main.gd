extends Node
const World = preload("res://scripts/world_state.gd")
const View = preload("res://scripts/world_view.gd")
const Saves = preload("res://scripts/save_store.gd")
const INK = Color("17272c")
const PAPER = Color("ebe9df")
const MUTED = Color("a4b7b7")
const ACCENT = Color("efb55f")
var ui: Control
var screen: Control
var hud: Control
var toast: Label
var status_label: Label
var inventory_label: Label
var objective_label: Label
var prompt_label: Label
var paused = false
var move_timer = 0.0
var hud_timer = 0.0
var toast_timer = 0.0
var current_menu = "main"
var view: Node3D
var tablet: Control
var tablet_page = ""
var last_message = ""
var last_money = -1
var brake_sent = false
var waypoint_name = ""
var waypoint_pos = Vector3.ZERO
var navigation_label: Label

func _ready() -> void:
	get_tree().auto_accept_quit = false
	view = View.new()
	add_child(view)
	add_child(load("res://scripts/game_audio.gd").new())
	var canvas = CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _theme()
	canvas.add_child(ui)
	Session.entered.connect(_enter_game)
	Session.ended.connect(func(reason: String):
		paused = false
		if is_instance_valid(tablet): tablet.queue_free(); tablet=null
		if hud: hud.queue_free(); hud = null
		_show_main()
		if not reason.is_empty(): _notify(reason))
	Session.notice.connect(_notify)
	_show_main()
	if not Profile.storage_error.is_empty(): _notify(Profile.storage_error)
	elif Profile.nickname.is_empty(): _show_identity()
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			Profile.nickname = "Courier"
			Session.host_game("Friends' night", 1, "", "Preview" + str(Time.get_ticks_msec()), false)
		if arg.begins_with("--screenshot="):
			get_tree().create_timer(2.5).timeout.connect(_capture.bind(arg.trim_prefix("--screenshot=")))

func _theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", PAPER)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_color", "LineEdit", PAPER)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _style(Color("314449"), 1, Color("5b6b6b")))
		t.set_stylebox("hover", type, _style(ACCENT))
		t.set_stylebox("pressed", type, _style(Color("c79754")))
		t.set_stylebox("focus", type, _style(Color(0, 0, 0, 0), 2, ACCENT))
		t.set_color("font_color", type, PAPER)
		t.set_color("font_hover_color", type, INK)
	t.set_stylebox("normal", "LineEdit", _style(Color("22363c"), 1, Color("56686a")))
	t.set_stylebox("focus", "LineEdit", _style(Color("22363c"), 2, ACCENT))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t

func _style(color: Color, border: int = 0, border_color: Color = ACCENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.set_border_width_all(border)
	style.border_color = border_color
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

func _label(parent: Node, text: String, size: int = 18, color: Color = PAPER) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _button(parent: Node, title: String, callback: Callable, primary: bool = false) -> Button:
	var b = Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 48
	if primary:
		b.add_theme_stylebox_override("normal", _style(ACCENT))
		b.add_theme_color_override("font_color", INK)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _field(parent: Node, caption: String, value: String = "", placeholder: String = "", secret: bool = false) -> LineEdit:
	_label(parent, caption.to_upper(), 12, MUTED)
	var edit = LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size.y = 43
	parent.add_child(edit)
	return edit

func _shell(kicker: String, title: String, subtitle: String = "") -> VBoxContainer:
	if screen: screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	var shade = ColorRect.new()
	shade.color = Color(0.045, 0.085, 0.1, 0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var backing = ColorRect.new()
	backing.color = Color(0.04,0.09,0.12,0.92)
	backing.size = Vector2(625,900)
	screen.add_child(backing)
	var margin = MarginContainer.new()
	margin.position = Vector2(64, 30)
	margin.size = Vector2(510, 835)
	screen.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_label(column, "AH  /  AFTER HOURS", 16, ACCENT)
	_label(column, kicker, 12, MUTED)
	_label(column, title, 46)
	if not subtitle.is_empty(): _label(column, subtitle, 16, MUTED)
	var gap = Control.new()
	gap.custom_minimum_size.y = 6
	column.add_child(gap)
	_label(screen, "PRIVATE CO-OP  /  01", 15, ACCENT).position = Vector2(1115, 44)
	_label(screen, "LAN + DIRECT IP    /    WINDOWS    /    CITY EXPANSION 0.3", 12, MUTED).position = Vector2(825, 850)
	return column

func _show_main() -> void:
	current_menu = "main"
	var col = _shell("THE LAST SHIFT IS YOURS.", "AFTER\nHOURS", "Вечерний город. Своя компания. Ваша команда.")
	_label(col, "ПЯТЬ РАЙОНОВ / ОДНА КОМПАНИЯ", 12, ACCENT)
	_button(col, "PLAY                                   →", _show_play, true)
	_button(col, "SETTINGS", _show_settings)
	_button(col, "EXIT", _quit)
	_label(col, "No accounts. No launcher. Just the crew.", 15, MUTED)
	if not Profile.nickname.is_empty(): _label(col, "Playing as " + Profile.nickname, 14, MUTED)

func _show_identity() -> void:
	var col = _shell("FIRST TIME HERE", "Meet the crew.", "Choose a nickname. Your progress stays with this PC.")
	var nick = _field(col, "Nickname", "", "Your nickname")
	nick.max_length = 24
	_button(col, "CONTINUE  →", func():
		if nick.text.strip_edges().is_empty(): _notify("Please enter a nickname."); return
		Profile.nickname = nick.text.strip_edges()
		if Profile.save_profile() != OK: _notify("Cannot save your profile."); return
		_show_main(), true)
	nick.grab_focus()

func _show_play() -> void:
	var col = _shell("PLAY", "Get together.", "One player hosts. Everyone else joins their address.")
	_button(col, "HOST GAME  →", _show_host, true)
	_button(col, "JOIN GAME  →", _show_join)
	_button(col, "SINGLE PLAYER", func(): _show_host(true))
	_button(col, "← BACK", _show_main)

func _show_host(solo: bool = false) -> void:
	var col = _shell("SINGLE PLAYER" if solo else "HOST GAME", "Начать смену.")
	var name_edit = _field(col, "Server name", "Friends' night")
	name_edit.max_length = 48
	var row = HBoxContainer.new()
	col.add_child(row)
	var limits = OptionButton.new()
	for count in ([1] if solo else [2, 4, 8]): limits.add_item(str(count) + (" player" if count == 1 else " players"), count)
	if not solo: limits.select(1)
	limits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(limits)
	var port_edit = SpinBox.new()
	port_edit.min_value = 1
	port_edit.max_value = 65535
	port_edit.value = Session.DEFAULT_PORT
	port_edit.prefix = "UDP "
	row.add_child(port_edit)
	var pass_edit = _field(col, "Password (optional)", "", "Friends only", true)
	pass_edit.max_length = 64
	var world_edit = _field(col, "New world name", "World01")
	world_edit.max_length = 40
	var saved = OptionButton.new()
	saved.add_item("NEW WORLD", 0)
	for world_slot in Saves.slots(Profile.root): saved.add_item("LOAD: " + world_slot)
	saved.item_selected.connect(func(index: int):
		world_edit.editable = index == 0
		if index > 0: world_edit.text = saved.get_item_text(index).trim_prefix("LOAD: "))
	col.add_child(saved)
	_button(col, "START GAME  →", func():
		var error = Session.host_game(name_edit.text, limits.get_selected_id(), pass_edit.text, world_edit.text, saved.selected > 0, int(port_edit.value))
		if not error.is_empty(): _notify(error), true)
	_button(col, "← BACK", _show_play)
	if not solo:
		var ips: Array = []
		for ip in IP.get_local_addresses():
			if "." in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): ips.append(ip)
		_label(col, "YOUR LOCAL ADDRESS  " + (", ".join(ips) if not ips.is_empty() else "Check Windows network settings"), 13, MUTED)
		_label(col, "Internet: public IP + UDP port forwarding, or a virtual LAN.", 13, MUTED)

func _show_join() -> void:
	var col = _shell("JOIN GAME", "Find your crew.", "Ask your host for their IP address and port.")
	var address = _field(col, "Server address", "", "192.168.1.50:27020")
	var pass_edit = _field(col, "Password", "", "If your host set one", true)
	pass_edit.max_length = 64
	_button(col, "CONNECT  →", func():
		var error = Session.join_game(address.text, pass_edit.text)
		if not error.is_empty(): _notify(error)
		else: _show_connecting(), true)
	if not Profile.recent.is_empty():
		_label(col, "RECENT SERVERS", 12, MUTED)
		var recent_list = OptionButton.new()
		recent_list.add_item("Choose a recent server…")
		for entry in Profile.recent: recent_list.add_item(str(entry))
		recent_list.item_selected.connect(func(index: int):
			if index > 0: address.text = recent_list.get_item_text(index))
		col.add_child(recent_list)
	_button(col, "← BACK", _show_play)
	_label(col, "The host must keep their game running.", 14, MUTED)

func _show_connecting() -> void:
	var col = _shell("CONNECTING", "Подключение…", "Verifying your identity and synchronizing the world.")
	_label(col, Session.address, 20, ACCENT)
	_button(col, "CANCEL", func(): Session.leave())

func _show_settings() -> void:
	var col = _shell("SETTINGS", "Настройки.")
	var nick = _field(col,"Nickname",Profile.nickname); nick.max_length=24
	var full=CheckButton.new(); full.text="Полный экран"; full.button_pressed=Profile.fullscreen;col.add_child(full)
	var shadow=CheckButton.new();shadow.text="Тени и сглаживание";shadow.button_pressed=Profile.shadows;col.add_child(shadow)
	_label(col,"Громкость",14,MUTED)
	var volume=HSlider.new();volume.max_value=1;volume.step=0.05;volume.value=Profile.volume;col.add_child(volume)
	_label(col,"Музыка",14,MUTED)
	var music=HSlider.new();music.max_value=1;music.step=0.05;music.value=Profile.music;col.add_child(music)
	_label(col,"WASD · Движение / руль    ПКМ · Камера\nE · Действие    F · Груз    G · Крепления\nTab · Планшет    M · Карта    Q · Положить\nПробел · Тормоз    H · Сигнал    Esc · Меню",16,MUTED)
	_button(col,"СОХРАНИТЬ",func():
		if nick.text.strip_edges().is_empty(): _notify("Введите имя.");return
		Profile.nickname=nick.text.strip_edges();Profile.fullscreen=full.button_pressed
		Profile.volume=volume.value;Profile.music=music.value;Profile.shadows=shadow.button_pressed
		Profile.apply_display();view.sun.shadow_enabled=Profile.shadows
		get_viewport().msaa_3d=Viewport.MSAA_2X if Profile.shadows else Viewport.MSAA_DISABLED
		if Profile.save_profile()!=OK:_notify("Не удалось сохранить настройки.");return
		_show_main(),true)
	_button(col,"← НАЗАД",_show_main)

func _enter_game() -> void:
	if screen: screen.queue_free();screen=null
	paused=false;last_money=-1;last_message=""
	hud=Control.new();hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.add_child(hud)
	var panel=PanelContainer.new();panel.position=Vector2(24,22);panel.custom_minimum_size=Vector2(400,0);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_theme_stylebox_override("panel",_style(Color(0.04,0.09,0.12,0.92)));hud.add_child(panel)
	var info=VBoxContainer.new();panel.add_child(info)
	_label(info,"AH  /  AFTER HOURS",17,ACCENT)
	status_label=_label(info,"",16)
	inventory_label=_label(info,"",14,MUTED)
	var objectives=PanelContainer.new();objectives.position=Vector2(1080,22);objectives.custom_minimum_size=Vector2(336,0);objectives.add_theme_stylebox_override("panel",_style(Color(0.04,0.09,0.12,0.92)));hud.add_child(objectives)
	objective_label=_label(objectives,"",15)
	var interaction=PanelContainer.new();interaction.position=Vector2(330,780);interaction.custom_minimum_size=Vector2(780,0);interaction.add_theme_stylebox_override("panel",_style(Color(0.04,0.09,0.12,0.94)));hud.add_child(interaction)
	prompt_label=_label(interaction,"",18,ACCENT);prompt_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label(hud,"WASD  ДВИЖЕНИЕ    ПКМ  КАМЕРА    E  ДЕЙСТВИЕ    F  ГРУЗ    TAB  КОНТРАКТЫ    M  КАРТА    ESC  МЕНЮ",13,PAPER).position=Vector2(230,860)
	navigation_label=_label(hud,"",17,ACCENT);navigation_label.position=Vector2(465,32);navigation_label.size=Vector2(555,90);navigation_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;navigation_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;navigation_label.add_theme_stylebox_override("normal",_style(Color(0.04,0.09,0.12,0.88)))
	_update_hud()
	_notify("Ваша компания готова. Нажмите Tab, выберите первый заказ. Груз появится у гаража.")

func _pause() -> void:
	_close_tablet();paused=true;Session.send_movement(Vector2.ZERO)
	var col=_shell("SESSION MENU","Перерыв.","Общая смена продолжается, пока открыто меню.")
	_button(col,"ПРОДОЛЖИТЬ  →",_resume,true)
	_button(col,"УПРАВЛЕНИЕ И ПОДСКАЗКИ",func():_resume();_open_tablet("help"))
	if Session.is_host:
		_button(col,"СОХРАНИТЬ МИР",func():Session.save_world())
		_button(col,"ЭВАКУАТОР В ГАРАЖ",func():_request("tow");_notify("Все должны выйти из машины. Эвакуация стоит 1 очко репутации."))
	_button(col,"СОХРАНИТЬ И ЗАВЕРШИТЬ" if Session.is_host else "ПОКИНУТЬ ИГРУ",func():
		var error=Session.leave()
		if not error.is_empty():_notify(error))
func _resume() -> void:
	paused=false
	if screen:screen.queue_free();screen=null
func _notify(message:String) -> void:
	if not is_instance_valid(toast):toast=_label(ui,"",16,ACCENT);toast.position=Vector2(245,690);toast.size=Vector2(950,65);toast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;toast.add_theme_stylebox_override("normal",_style(Color(0.04,0.09,0.12,0.94)))
	toast.text=message;toast.move_to_front();toast_timer=7.0
func _request(action:String,target:String="") -> void:
	Session.request(action,target)
	if is_instance_valid(tablet):
		get_tree().create_timer(0.25).timeout.connect(func():
			if is_instance_valid(tablet) and Session.active:_open_tablet(tablet_page))
func _close_tablet() -> void:
	if is_instance_valid(tablet):tablet.queue_free();tablet=null
	tablet_page="";view.capture_orbit=true
func _open_tablet(page:String="jobs") -> void:
	if not Session.active:return
	_close_tablet();tablet_page=page;view.capture_orbit=false;Session.send_movement(Vector2.ZERO)
	tablet=PanelContainer.new();tablet.position=Vector2(210,110);tablet.size=Vector2(1020,650);tablet.add_theme_stylebox_override("panel",_style(Color("112b37"),1,Color("496672")));ui.add_child(tablet)
	var col=VBoxContainer.new();tablet.add_child(col)
	var nav=HBoxContainer.new();col.add_child(nav)
	for tab in [["jobs","Заказы"],["map","Карта"],["cargo","Груз"],["garage","Бизнес"],["fleet","Автопарк"],["city","Город"],["help","Помощь"]]:
		var b=_button(nav,tab[1],_open_tablet.bind(tab[0]),page==tab[0]);b.custom_minimum_size.y=40;b.add_theme_font_size_override("font_size",15)
	_button(nav,"×",_close_tablet).custom_minimum_size.y=40
	var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(970,550);scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;col.add_child(scroll)
	var body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	var s=Session.state();var p=s.players[Profile.player_id];var company=s.economy.company
	match page:
		"jobs":
			_label(body,"КОНТРАКТЫ  /  ГРУЗЫ В ГАРАЖЕ",24,ACCENT)
			_label(body,"Одновременно: %d. Примите заказ, затем заберите коробку с погрузочной площадки."%[World.max_orders(s)],15,MUTED)
			for oid in s.orders:
				var o=s.orders[oid]
				if o.status in ["completed","failed"]:continue
				var dest=World.destination(o)
				var row=HBoxContainer.new();body.add_child(row)
				var text="%s  ·  %s  ·  до $%d"%[o.title,dest.name,o.reward]
				if o.status=="active":text="● "+text+"  /  в работе"
				var l=_label(row,text,16);l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;l.custom_minimum_size.x=620;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				if o.status=="available":
					var b=_button(row,"ПРИНЯТЬ",_request.bind("accept_order",oid));b.disabled=int(company.reputation)<int(o.required_rep) or s.economy.shift.status!="active"
					if b.disabled:b.text="Репутация %d"%o.required_rep if s.economy.shift.status=="active" else "Смена закрыта"
				else:_button(row,"МАРШРУТ",func():Session.request("ping",oid);_open_tablet("map"))
			_label(body,"Срочный: 3 минуты. Хрупкий: берегите от ударов. Тяжёлый: 3 места в багажнике.\nНесколько адресов: отметьте груз на каждом пункте. Оплата поступает после последнего.",15,MUTED)
		"map":
			_label(body,"ГОРОД / НАЖМИТЕ НА МЕТКУ, ЧТОБЫ ПОСТАВИТЬ ЦЕЛЬ",19,ACCENT)
			_label(body,"Золото: заказы · Зелёный: детали · Оранжевый: помощь · Синий: ваш автопарк",14,MUTED)
			var map=load("res://scripts/map_view.gd").new();body.add_child(map)
			map.chosen.connect(func(title:String,pos:Vector3):waypoint_name=title;waypoint_pos=pos;_close_tablet();_notify("Цель: "+title))
		"cargo":
			var v=s.vehicles[World.vehicle_near(s,p)]
			_label(body,"%s / %d МЕСТ / %d ЯЧЕЕК"%[World.vehicle_spec(v).name,World.vehicle_spec(v).seats,v.capacity],23,ACCENT)
			_label(body,"Для действий подойдите к задней двери. Откройте её клавишей E.\nВыберите коробку для разгрузки; доставляйте её получателю в руках.",16,MUTED)
			for iid in v.cargo:
				var item=s.items[iid];var row=HBoxContainer.new();body.add_child(row)
				var l=_label(row,"%s · %d%% · %s"%[World.TYPE_NAMES[item.kind],int(item.condition),"закреплён" if item.secured else "НЕ закреплён"],18);l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				_button(row,"ВЗЯТЬ",_request.bind("unload",iid))
			if v.cargo.is_empty():_label(body,"Багажник пока пуст.",18)
			_button(body,"ЗАКРЕПИТЬ ВСЁ [G]",_request.bind("secure"))
			_button(body,"ЗАГРУЗИТЬ ГРУЗ ИЗ РУК [F]",_request.bind("load"))
			_label(body,"Состояние фургона: %d%%  /  Топливо: %d%%"%[int(v.health),int(v.fuel)],17,ACCENT)
		"garage":
			_label(body,"КОМПАНИЯ  /  $%d  /  РЕПУТАЦИЯ %d"%[company.balance,company.reputation],23,ACCENT)
			var chapter=int(company.chapter)
			if chapter<World.CHAPTERS.size():
				var goal=World.CHAPTERS[chapter]
				_label(body,"ГЛАВА %d / %s"%[chapter+1,goal.title],21)
				_label(body,goal.hint+" · Награда $%d"%goal.reward,16,MUTED)
				var claim=_button(body,"ПОЛУЧИТЬ НАГРАДУ У ТЕРМИНАЛА",_request.bind("claim_chapter",str(chapter)),World.chapter_ready(s));claim.disabled=not World.chapter_ready(s)
			else:_label(body,"ИСТОРИЯ КОМПАНИИ ЗАВЕРШЕНА. ГОРОД ЖДЁТ НОВЫХ СМЕН.",18,ACCENT)
			_label(body,"Доставки: %d · Находки: %d/12 · Помощь водителям: %d · Детали: %d"%[company.total_deliveries,company.discovered,company.repairs,company.parts],16,MUTED)
			var role=HBoxContainer.new();body.add_child(role)
			for title in ["Курьер","Водитель","Грузчик","Диспетчер"]:_button(role,title,_request.bind("role",title),p.role==title).add_theme_font_size_override("font_size",14)
			for up in [["capacity","Вместимость: 6 → 10 ячеек"],["equipment","Автоматические крепления груза"],["garage","Расширение: 2 → 4 активных заказа"],["engine","Двигатели автопарка: скорость +18%"],["insurance","Защита кузова: урон от столкновений −35%"]]:
				var installed=int(company[up[0]])>0
				var b=_button(body,up[1]+("  /  УСТАНОВЛЕНО" if installed else "  /  $%d"%World.UPGRADE_PRICES[up[0]]),_request.bind("upgrade",up[0]));b.disabled=installed
			_label(body,"СОТРУДНИКИ / НАЙМ В ГАРАЖЕ",20,ACCENT)
			for sid in World.STAFF:
				var staff=World.STAFF[sid];var hired=s.employees[sid].hired
				var b=_button(body,staff.name+(" / В КОМАНДЕ" if hired else " / $%d"%staff.price),_request.bind("hire",sid));b.disabled=hired
				_label(body,("Скидка на сервис 35%; постепенно ремонтирует машины в мастерской." if sid=="mechanic" else "+2 активных заказа и +20% времени на новые доставки.")+" Зарплата: $90 за смену.",14,MUTED)
			_button(body,"РЕМОНТ И ЗАПРАВКА / НА СЕРВИСНОЙ ПЛОЩАДКЕ",_request.bind("repair"))
			var shift=s.economy.shift
			if shift.status=="finished":
				var r=shift.report
				_label(body,"ОТЧЁТ СМЕНЫ %d  /  %s"%[shift.day,"ЦЕЛЬ ВЫПОЛНЕНА" if r.success else "ЕСТЬ КУДА РАСТИ"],20,ACCENT)
				_label(body,"Доход $%d  −  расходы $%d  =  прибыль $%d\nДоставки %d  /  Опоздания %d  /  Повреждённые грузы %d"%[r.income,r.expenses,r.profit,r.deliveries,r.late,r.damaged],17)
				if Session.is_host:_button(body,"СЛЕДУЮЩАЯ СМЕНА / У ТЕРМИНАЛА",_request.bind("next_shift"),true)
			elif Session.is_host:_button(body,"ЗАВЕРШИТЬ СМЕНУ / У ТЕРМИНАЛА",func():_open_tablet("confirm"))
			_label(body,"Роли помогают договориться с друзьями. Каждый может выполнять любую работу.",14,MUTED)
		"fleet":
			_label(body,"АВТОПАРК / %d МАШИНЫ КОМПАНИИ"%World.owned_count(s),24,ACCENT)
			_label(body,"Новые машины продаются в Western Motors на западе. Каждая имеет свой багажник.
Покупка общая для команды. Цветной прямоугольник на карте показывает машину.",16,MUTED)
			_button(body,"НАВИГАЦИЯ К АВТОСАЛОНУ",func():waypoint_name="Western Motors";waypoint_pos=World.Layout.DEALER;_close_tablet())
			for vid in World.FLEET:
				var spec=World.FLEET[vid];var v=s.vehicles[vid]
				_label(body,"%s / %d мест / %d ячеек / до %d км/ч"%[spec.name,spec.seats,v.capacity,int(spec.top*3.6)],20)
				if v.owned:
					var row=HBoxContainer.new();body.add_child(row)
					_button(row,"НАЙТИ МАШИНУ",func():waypoint_name=spec.name;waypoint_pos=World.vec(v.pos);_close_tablet())
					if Session.is_host:_button(row,"ЭВАКУАЦИЯ",_request.bind("tow",vid))
					_label(body,"Кузов %d%% · Топливо %d%% · В багажнике %d грузов"%[int(v.health),int(v.fuel),v.cargo.size()],15,MUTED)
				else:
					var b=_button(body,"КУПИТЬ ЗА $%d / РЕПУТАЦИЯ %d"%[spec.price,spec.rep],_request.bind("buy_vehicle",vid));b.disabled=company.balance<spec.price or company.reputation<spec.rep
		"city":
			_label(body,"ГОРОДСКИЕ ЗАНЯТИЯ / ДЕТАЛИ: %d"%company.parts,24,ACCENT)
			_label(body,"Исследуйте районы, собирайте детали и помогайте водителям.
Ремонт: подойдите к машине, E начать, оставайтесь рядом 6 секунд, E закончить.
Один ремонт расходует 1 деталь и приносит $420. Новые вызовы — каждую смену.",17,MUTED)
			_button(body,"НАЙТИ МАСТЕРСКУЮ",func():waypoint_name="Atlas / Мастерская";waypoint_pos=World.Layout.WORKSHOP;_close_tablet())
			_button(body,"КУПИТЬ 3 ДЕТАЛИ / $180 / У ТЕРМИНАЛА МАСТЕРСКОЙ",_request.bind("buy_parts"))
			_button(body,"СЕРВИС БЛИЖАЙШЕЙ МАШИНЫ / В МАСТЕРСКОЙ",_request.bind("repair"))
			_label(body,"Находки %d/12 · Выполнено дорожных вызовов: %d"%[company.discovered,company.repairs],18,ACCENT)
			for aid in s.activities:
				var a=s.activities[aid]
				if a.kind!="service":continue
				var state_title="ВЫПОЛНЕН" if a.status=="completed" else "В РАБОТЕ" if a.status=="working" else "ДОСТУПЕН"
				var row=HBoxContainer.new();body.add_child(row)
				var l=_label(row,"%s / %s / %s"%[a.title,World.Layout.district(World.vec(a.pos)),state_title],15);l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				_button(row,"НАЙТИ",func():waypoint_name=a.title;waypoint_pos=World.vec(a.pos);_close_tablet())
		"confirm":
			_label(body,"Завершить текущую смену?",28,ACCENT)
			_label(body,"Незаконченные заказы будут закрыты без оплаты.\nВ отчёт войдут обслуживание ($80) и зарплаты сотрудников ($90 за каждого).",18)
			_button(body,"ДА, ПОДВЕСТИ ИТОГИ",func():_request("end_shift");_open_tablet("garage"),true)
			_button(body,"ПРОДОЛЖИТЬ РАБОТУ",_close_tablet)
		"help":
			_label(body,"ПЕРВАЯ ДОСТАВКА",26,ACCENT)
			_label(body,"1. Примите обычный заказ на вкладке «Контракты».\n2. Возьмите коробку у гаража: подойдите и нажмите E.\n3. У задней двери фургона: E открыть, F загрузить, G закрепить.\n4. Закройте багажник (E), подойдите сбоку и сядьте (E).\n5. Найдите адрес на карте (M), довезите груз. Пробел — тормоз.\n6. Остановитесь, выйдите (E), откройте багажник сзади.\n7. F — взять коробку; у жёлтой метки F — завершить доставку.\n8. Прибыль поступит компании. Улучшения покупаются в гараже.",18)
			_label(body,"Кампания: вкладка «Бизнес». Карта: нажмите метку для навигации.\nДетали: зелёные ящики. Вызовы: «Город». Машины: «Автопарк».\nПКМ + мышь — поворот камеры. Колесо — расстояние.\nТяжёлый груз: E у друга, чтобы нести вдвоём; Q — поставить.\nВ одиночку доступна медленная тележка. R — возрождение.\nЗастряли или закончился бензин? Выйдите и вызовите эвакуатор: Esc.\nПауза и планшет не останавливают общую смену. Хост сохраняет мир F5.",16,MUTED)

func nearest() -> Dictionary:
	if not Session.active:return {}
	var s=Session.state();var p=s.players[Profile.player_id];var pos=World.vec(p.pos);var vid=World.vehicle_near(s,p);var v=s.vehicles[vid]
	if not p.alive:return {"action":"respawn","id":"","label":"[R] ВОЗРОЖДЕНИЕ"}
	if p.vehicle!="":return {"action":"vehicle","id":p.vehicle,"label":"[E] ВЫЙТИ · WASD РУЛЬ · ПРОБЕЛ ТОРМОЗ · [M] КАРТА" if v.driver==Profile.player_id else "ПАССАЖИР · [E] ВЫЙТИ · [M] КАРТА"}
	var carry=World.held(p,s)
	for oid in s.orders:
		var o=s.orders[oid]
		if o.status=="active" and carry==o.item and pos.distance_to(World.vec(World.destination(o).pos))<3.5:return {"action":"complete_order","id":oid,"label":"[F] ПЕРЕДАТЬ ГРУЗ · "+World.destination(o).name}
	if pos.distance_to(World.rear(v))<3.4:
		return {"action":"cargo_door","id":vid,"label":"[E] "+("ЗАКРЫТЬ" if v.door_open else "ОТКРЫТЬ")+" БАГАЖНИК · [F] "+("ЗАГРУЗИТЬ" if carry!="" else "ВЗЯТЬ ГРУЗ")+" · [G] КРЕПЛЕНИЯ"}
	var best=3.1;var result={}
	if carry=="":
		for iid in s.items:
			var item=s.items[iid]
			if item.delivered or item.container!="":continue
			if item.holder!="" and (item.kind!="heavy" or item.carriers.size()!=1):continue
			var at=World.vec(item.pos) if item.holder=="" else World.vec(s.players[item.holder].pos)
			var d=pos.distance_to(at)
			if d<best:best=d;result={"action":"pickup","id":iid,"label":"[E] "+("ПОМОЧЬ НЕСТИ" if item.holder!="" else "ВЗЯТЬ")+" · "+World.TYPE_NAMES[item.kind]}
	if not result.is_empty():return result
	if pos.distance_to(World.vec(v.pos))<4.2:return {"action":"vehicle","id":vid,"label":"[E] "+World.vehicle_spec(v).name+" / %d ИЗ %d МЕСТ"%[v.passengers.size(),World.vehicle_spec(v).seats]}
	for aid in s.activities:
		var a=s.activities[aid]
		if a.status=="completed" or pos.distance_to(World.vec(a.pos))>3:continue
		if a.kind=="parts":return {"action":"collect_parts","id":aid,"label":"[E] ЗАБРАТЬ ДЕТАЛИ · +2 В ЗАПАС КОМПАНИИ"}
		if a.status=="working":
			if a.worker!=Profile.player_id:return {"action":"","id":"","label":"ДРУГОЙ ИГРОК РЕМОНТИРУЕТ МАШИНУ"}
			return {"action":"service_finish","id":aid,"label":"[E] ЗАВЕРШИТЬ РЕМОНТ · $420" if s.time>=a.finish_at else "РЕМОНТ · %d СЕК · ОСТАВАЙТЕСЬ РЯДОМ"%ceili(a.finish_at-s.time)}
		return {"action":"service_start","id":aid,"label":"[E] ПОМОЧЬ ВОДИТЕЛЮ · 1 ДЕТАЛЬ · $420"}
	if pos.distance_to(World.Layout.DEALER)<5:return {"action":"tablet","id":"fleet","label":"[E] АВТОСАЛОН · НОВЫЕ МАШИНЫ"}
	if pos.distance_to(World.Layout.WORKSHOP)<5:return {"action":"tablet","id":"city","label":"[E] МАСТЕРСКАЯ · СЕРВИС И ЗАПЧАСТИ"}
	if pos.distance_to(World.Layout.GARAGE)<3.2:return {"action":"tablet","id":"garage","label":"[E] ТЕРМИНАЛ · КОМПАНИЯ И УЛУЧШЕНИЯ"}
	if pos.distance_to(World.Layout.REPAIR)<3.0:return {"action":"repair","id":"","label":"[E] РЕМОНТ И ЗАПРАВКА ФУРГОНА"}
	if pos.distance_to(World.vec(s.doors.gate_01.pos))<2.5:return {"action":"door","id":"gate_01","label":"[E] ВОРОТА ГАРАЖА"}
	return {}
func _unhandled_key_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not Session.active:return
	match event.physical_keycode:
		KEY_ESCAPE:
			if is_instance_valid(tablet):_close_tablet()
			elif paused:_resume()
			else:_pause()
			return
		KEY_TAB:
			if not paused:
				if is_instance_valid(tablet):_close_tablet()
				else:_open_tablet()
			return
		KEY_M:
			if not paused:
				if tablet_page=="map":_close_tablet()
				else:_open_tablet("map")
			return
	if paused or is_instance_valid(tablet):return
	var s=Session.state();var p=s.players[Profile.player_id];var carry=World.held(p,s);var target=nearest()
	match event.physical_keycode:
		KEY_E:
			if target.get("action")=="tablet":_open_tablet(target.id)
			elif not target.is_empty() and not target.action in ["complete_order",""]:_request(target.action,target.id)
		KEY_F:
			if target.get("action")=="complete_order":_request(target.action,target.id)
			elif World.vec(p.pos).distance_to(World.rear(s.vehicles[World.vehicle_near(s,p)]))<3.6:
				if carry!="":_request("load")
				elif s.vehicles[World.vehicle_near(s,p)].cargo.size()==1:_request("unload",s.vehicles[World.vehicle_near(s,p)].cargo[0])
				else:_open_tablet("cargo")
		KEY_G:_request("secure")
		KEY_Q:
			if carry!="":_request("drop",carry)
		KEY_R:_request("respawn")
		KEY_H:
			if p.vehicle!="":_request("horn")
		KEY_I:_open_tablet("cargo")
		KEY_F5:
			var err=Session.save_world()
			if not err.is_empty():_notify(err)
func _process(dt:float) -> void:
	toast_timer-=dt
	if is_instance_valid(toast):toast.visible=toast_timer>0
	if not Session.active:return
	move_timer+=dt;hud_timer+=dt
	if move_timer>=1.0/30:
		move_timer=0;var axis=Vector2.ZERO
		var p=Session.state().players[Profile.player_id]
		if not paused and not is_instance_valid(tablet):
			axis=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).limit_length()
			if p.vehicle=="":axis=view.movement(axis)
		var brake=Input.is_physical_key_pressed(KEY_SPACE) or paused or is_instance_valid(tablet)
		if brake!=brake_sent:
			brake_sent=brake
			if p.vehicle!="" and Session.state().vehicles[p.vehicle].driver==Profile.player_id:Session.request("brake","on" if brake else "off")
		Session.send_movement(axis)
	if hud_timer>=0.1:hud_timer=0;_update_hud()
func _update_hud() -> void:
	if not is_instance_valid(hud) or not Session.active:return
	var s=Session.state();var p=s.players[Profile.player_id];var v=s.vehicles[World.vehicle_near(s,p)];var shift=s.economy.shift;var company=s.economy.company
	var count=0
	for player in s.players.values():
		if player.connected:count+=1
	var remain=maxi(0,int(shift.duration-(s.time-shift.started)))
	status_label.text="$%d  /  РЕПУТАЦИЯ %d  /  КОМАНДА %d/%d"%[company.balance,company.reputation,count,Session.player_limit]
	var carry=World.held(p,s)
	inventory_label.text="СМЕНА %d · %02d:%02d  /  %s"%[shift.day,remain/60,remain%60,p.role]
	if carry!="":inventory_label.text+="\nВ РУКАХ: "+World.TYPE_NAMES[s.items[carry].kind]+" · %d%%"%int(s.items[carry].condition)
	if p.vehicle!="":inventory_label.text+="\n%02d км/ч  ·  Топливо %d%%  ·  Кузов %d%%"%[int(absf(v.speed)*3.6),int(v.fuel),int(v.health)]
	objective_label.text="ПРИБЫЛЬ: $%d / $%d\n"%[shift.income-shift.expenses,shift.target]
	if int(company.chapter)<World.CHAPTERS.size():objective_label.text+="Глава %d: %s\n"%[int(company.chapter)+1,World.CHAPTERS[int(company.chapter)].title]
	var active=0
	for o in s.orders.values():
		if o.status!="active":continue
		active+=1
		var d=World.destination(o);var meters=int(World.vec(p.pos).distance_to(World.vec(d.pos)))
		objective_label.text+="\n%s\n%s · %d м\n"%[o.title,d.name,meters]
		if o.kind=="urgent":objective_label.text+="Осталось: %d сек\n"%maxi(0,int(o.deadline-s.time))
	if active==0:objective_label.text+="\n[TAB] Принять новый заказ\n[M] Карта района"
	if shift.status=="finished":objective_label.text="СМЕНА ЗАВЕРШЕНА\n\n[TAB] → Компания → Отчёт\nВернитесь к терминалу гаража."
	var direction_target=waypoint_pos;var direction_title=waypoint_name
	if direction_title.is_empty():
		for o in s.orders.values():
			if o.status=="active":
				direction_target=World.vec(World.destination(o).pos);direction_title=World.destination(o).name
				var item=s.items[o.item]
				if item.holder=="" and item.container=="":direction_target=World.vec(item.pos);direction_title="Забрать груз"
				break
	if direction_title!="":
		var delta=direction_target-World.vec(p.pos)
		var angle=wrapf(atan2(delta.x,-delta.z)+view.yaw,-PI,PI)
		var arrows=["↑","↗","→","↘","↓","↙","←","↖"]
		navigation_label.text=World.Layout.district(World.vec(p.pos))+"\n"+arrows[posmod(roundi(angle/(PI/4)),8)]+"  "+direction_title+"  ·  %d м"%int(delta.length())
		if delta.length()<4 and waypoint_name!="":waypoint_name=""
	else:navigation_label.text=World.Layout.district(World.vec(p.pos))+"\n[M] Выберите цель на карте"
	var target=nearest()
	prompt_label.text=target.get("label","[TAB] КОНТРАКТЫ  ·  [M] КАРТА  ·  [Q] ПОЛОЖИТЬ ГРУЗ" if carry!="" else "[TAB] КОНТРАКТЫ  ·  [M] КАРТА  ·  ПКМ ПОВОРОТ КАМЕРЫ")
	if not p.alive:prompt_label.text="[R] ВОЗРОДИТЬСЯ" if s.time>=p.dead_until else "ВОЗРОЖДЕНИЕ ЧЕРЕЗ %d"%ceili(p.dead_until-s.time)
	if last_money>=0 and int(company.balance)>last_money:_notify("На счёт компании поступило $%d."%(int(company.balance)-last_money))
	last_money=int(company.balance)
	if s.economy.weather.message!=last_message:
		last_message=s.economy.weather.message;_notify(last_message)
func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_quit()
func _quit() -> void:
	var err=Session.leave()
	if err.is_empty():get_tree().quit()
	else:_notify(err)
func _capture(path:String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
