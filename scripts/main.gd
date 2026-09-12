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

func _ready() -> void:
	get_tree().auto_accept_quit = false
	add_child(View.new())
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
	shade.color = Color(0.045, 0.085, 0.1, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
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
	_label(screen, "LAN + DIRECT IP    /    WINDOWS    /    PROTOTYPE 0.1", 12, MUTED).position = Vector2(825, 850)
	return column

func _show_main() -> void:
	current_menu = "main"
	var col = _shell("THE LAST SHIFT IS YOURS.", "AFTER\nHOURS", "A small yard. A shared world. Your friends.")
	_label(col, "PRIVATE MULTIPLAYER SANDBOX", 12, ACCENT)
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
	var col = _shell("SINGLE PLAYER" if solo else "HOST GAME", "Open the yard.")
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
	var col = _shell("CONNECTING", "Joining the yard…", "Verifying your identity and synchronizing the world.")
	_label(col, Session.address, 20, ACCENT)
	_button(col, "CANCEL", func(): Session.leave())

func _show_settings() -> void:
	var col = _shell("SETTINGS", "Make it yours.")
	var nick = _field(col, "Nickname", Profile.nickname)
	nick.max_length = 24
	var full = CheckButton.new()
	full.text = "Fullscreen"
	full.button_pressed = Profile.fullscreen
	col.add_child(full)
	_label(col, "PLAYER ID\n" + Profile.player_id, 12, MUTED)
	_label(col, "WASD · Move / drive     E · Interact     F · Deliver\nQ · Drop parcel     T · Store supply     R · Respawn\nEsc · Session menu     F5 · Save (host)", 16, MUTED)
	_button(col, "SAVE SETTINGS", func():
		if nick.text.strip_edges().is_empty(): _notify("Please enter a nickname."); return
		Profile.nickname = nick.text.strip_edges()
		Profile.fullscreen = full.button_pressed
		Profile.apply_display()
		if Profile.save_profile() != OK: _notify("Cannot save settings."); return
		_show_main(), true)
	_button(col, "← BACK", _show_main)

func _enter_game() -> void:
	if screen: screen.queue_free(); screen = null
	paused = false
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud)
	var panel = PanelContainer.new()
	panel.position = Vector2(24, 22)
	panel.custom_minimum_size = Vector2(375, 0)
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.12, 0.14, 0.93)))
	hud.add_child(panel)
	var info = VBoxContainer.new()
	panel.add_child(info)
	_label(info, "AH  /  " + Session.server_name, 16, ACCENT)
	status_label = _label(info, "", 15)
	inventory_label = _label(info, "", 14, MUTED)
	var objectives = PanelContainer.new()
	objectives.position = Vector2(1050, 22)
	objectives.custom_minimum_size.x = 365
	objectives.add_theme_stylebox_override("panel", _style(Color(0.07, 0.12, 0.14, 0.94)))
	hud.add_child(objectives)
	objective_label = _label(objectives, "", 16, PAPER)
	var interaction = PanelContainer.new()
	interaction.position = Vector2(420, 780)
	interaction.add_theme_stylebox_override("panel", _style(Color(0.07, 0.12, 0.14, 0.9)))
	hud.add_child(interaction)
	prompt_label = _label(interaction, "", 22, ACCENT)
	_label(hud, "WASD MOVE  ·  E INTERACT  ·  F DELIVER  ·  Q DROP  ·  T STORE  ·  ESC MENU", 13, PAPER).position = Vector2(385, 860)
	_update_hud()

func _pause() -> void:
	paused = true
	Session.send_movement(Vector2.ZERO)
	var col = _shell("SESSION MENU", "Take a breather.", "The shared world keeps running while this menu is open.")
	_button(col, "RESUME  →", _resume, true)
	if Session.is_host: _button(col, "SAVE WORLD", func(): Session.save_world())
	_button(col, "SAVE & END SESSION" if Session.is_host else "LEAVE SESSION", func():
		var error = Session.leave()
		if not error.is_empty(): _notify(error))
	if Session.is_host: _label(col, "Ending the session disconnects the whole crew.", 14, MUTED)

func _resume() -> void:
	paused = false
	if screen: screen.queue_free(); screen = null

func _notify(message: String) -> void:
	if not is_instance_valid(toast):
		toast = _label(ui, "", 16, ACCENT)
		toast.position = Vector2(64, 810)
	toast.text = message
	toast.move_to_front()
	toast_timer = 6.0

func nearest() -> Dictionary:
	if not Session.active: return {}
	var state = Session.state()
	var p = state.players[Profile.player_id]
	if not p.alive: return {"action": "respawn", "id": "", "label": "[R]  RESPAWN"}
	if not p.vehicle.is_empty(): return {"action": "vehicle", "id": p.vehicle, "label": "[E]  EXIT VAN     WASD DRIVE"}
	var best = 3.0
	var result: Dictionary = {}
	var mapping = {"items": ["pickup", "PICK UP PARCEL"], "doors": ["door", "TOGGLE GATE"], "containers": ["take_supply", "TAKE SUPPLY  /  [T] STORE"], "vehicles": ["vehicle", "ENTER VAN"], "properties": ["buy_property", "BUY DEPOT · $600"], "employees": ["hire", "HIRE · $150"]}
	for domain in mapping:
		for id in state[domain]:
			var entity = state[domain][id]
			if domain == "items" and (entity.delivered or not entity.holder.is_empty()): continue
			if domain in ["properties", "employees"] and not entity.owner.is_empty(): continue
			var distance = World.vec(p.pos).distance_to(World.vec(entity.pos))
			if distance < best:
				best = distance
				result = {"action": mapping[domain][0], "id": id, "label": "[E]  " + mapping[domain][1]}
	if World.vec(p.pos).distance_to(World.DELIVERY) < 2.8: return {"action": "deliver", "id": "", "label": "[F]  DELIVER PARCEL"}
	return result

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not Session.active: return
	if event.keycode == KEY_ESCAPE:
		if paused: _resume()
		else: _pause()
		return
	if paused: return
	var p = Session.state().players[Profile.player_id]
	match event.keycode:
		KEY_E:
			var target = nearest()
			if not target.is_empty() and target.action not in ["deliver", "respawn"]: Session.request(target.action, target.id)
		KEY_F:
			for id in Session.state().orders:
				var order = Session.state().orders[id]
				if order.status == "open" and p.inventory.has(order.item):
					Session.request("complete_order", id)
					return
			_notify("Pick up a parcel, then bring it to Dispatch.")
		KEY_Q:
			for id in p.inventory:
				if id.begins_with("parcel_"):
					Session.request("drop", id)
					return
		KEY_T:
			var target = nearest()
			if target.get("action", "") == "take_supply": Session.request("store_supply", target.id)
		KEY_R: Session.request("respawn")
		KEY_F5:
			var error = Session.save_world()
			if not error.is_empty(): _notify(error)

func _process(dt: float) -> void:
	toast_timer -= dt
	if is_instance_valid(toast): toast.visible = toast_timer > 0
	if not Session.active: return
	move_timer += dt
	hud_timer += dt
	if move_timer >= 1.0 / 30.0:
		move_timer = 0.0
		var axis = Vector2.ZERO
		if not paused:
			axis = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length()
		Session.send_movement(axis)
	if hud_timer >= 0.1:
		hud_timer = 0.0
		_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(hud) or not Session.active: return
	var state = Session.state()
	var p = state.players[Profile.player_id]
	var connected = 0
	for player in state.players.values():
		if player.connected: connected += 1
	var clock = int(state.time)
	status_label.text = "$%d    /    %d:%02d    /    CREW %d/%d" % [p.money, (clock / 3600) % 24, (clock / 60) % 60, connected, Session.player_limit]
	var inventory: Array = []
	for item in p.inventory: inventory.append(item.replace("parcel_", "Parcel ") + " ×" + str(p.inventory[item]))
	inventory_label.text = "INVENTORY\n" + ("Empty — grab a parcel at the loading bays." if inventory.is_empty() else "\n".join(inventory))
	var done = 0
	for order in state.orders.values():
		if order.status == "completed": done += 1
	objective_label.text = "TONIGHT'S SHIFT\n\nDeliver the parcels to Dispatch.\n$250 per delivery.\n\n%02d / 08  ORDERS COMPLETED\n\nBuy the depot · $600\nHire a worker · $150\nWorker earns $25 / 30 sec" % done
	var target = nearest()
	prompt_label.text = target.get("label", "Find a parcel at the loading bays.")
	if not p.alive:
		prompt_label.text = "YOU ARE DOWN  ·  [R] RESPAWN" if state.time >= p.dead_until else "YOU ARE DOWN  ·  RESPAWN IN %d" % ceili(p.dead_until - state.time)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _quit() -> void:
	var error = Session.leave()
	if error.is_empty(): get_tree().quit()
	else: _notify(error + " Exit cancelled to protect your save.")

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
