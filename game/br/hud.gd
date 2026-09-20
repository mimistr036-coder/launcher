extends Control
## HUD: виртуальный джойстик, кнопки, миникарта, чат, деньги, часы, пауза.
## Всё управление мультитач: джойстик + камера + кнопки одновременно.

var UTIL = load("res://br/util.gd")
var CB = load("res://br/city_builder.gd")

var world = null
var mode := "walk"            # walk | car
var touchscreen := false

var _fingers := {}            # touch index -> {"type": "stick"/"cam"/"btn", "n": String}
var _stick_vec := Vector2.ZERO
var _knob := Vector2.ZERO
var _cam_delta := Vector2.ZERO
var _held := {}
var _events: Array = []

var _vs := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_r := 58.0
var _buttons: Array = []      # {n, pos, r, l, hold}
var _map_rect := Rect2()
var _map_tex: ImageTexture
var _map_span := 1.0
var _ctx_near := false

var _chat_panel: PanelContainer
var _chat_log: Label
var _chat_edit: LineEdit
var _chat_open := false
var _chat_lines: Array = []
var _notices: VBoxContainer
var _notice_list: Array = []
var _garage_panel: Control
var garage_pick := -1
var _money_label: Label
var _clock_label: Label
var _fps_label: Label
var _hint: Label
var _pause_panel: Control
var _quality_btn: Button
var _paused := false
var _fps_t := 0.0
var _fps_n := 0
var _fps_v := 0


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	touchscreen = DisplayServer.is_touchscreen_available()
	if world.city.map_img != null:
		_map_tex = ImageTexture.create_from_image(world.city.map_img)
	_map_span = 2.0 * (CB.HALF + 30.0)
	_build_static()
	_layout()

# ================= построение UI =================

func _build_static() -> void:
	_money_label = UTIL.label("₽ 0", 22, Color(0.55, 1.0, 0.6))
	_money_label.position = Vector2(0, 0)
	add_child(_money_label)
	_clock_label = UTIL.label("09:00", 20, Color(0.9, 0.9, 1.0))
	add_child(_clock_label)
	_fps_label = UTIL.label("", 13, Color(1, 1, 1, 0.55))
	add_child(_fps_label)
	_hint = UTIL.label("WASD — движение · SHIFT — бег · E — сесть/выйти · ПРОБЕЛ — прыжок · T — чат · J — работа", 15, Color(1, 1, 1, 0.6))
	add_child(_hint)
	_notices = VBoxContainer.new()
	_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notices)
	# чат
	_chat_panel = UTIL.panel_box(Color(0.04, 0.05, 0.08, 0.75), 10)
	_chat_panel.visible = false
	add_child(_chat_panel)
	var cv := VBoxContainer.new()
	_chat_panel.add_child(cv)
	_chat_log = UTIL.label("", 15, Color(0.95, 0.95, 0.95), false)
	_chat_log.custom_minimum_size = Vector2(430, 118)
	_chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cv.add_child(_chat_log)
	var hb := HBoxContainer.new()
	cv.add_child(hb)
	_chat_edit = UTIL.line_edit("Сообщение...", "", 90)
	_chat_edit.custom_minimum_size = Vector2(340, 0)
	_chat_edit.text_submitted.connect(_on_chat_send)
	hb.add_child(_chat_edit)
	var send = UTIL.button("▶", 16)
	send.pressed.connect(_on_chat_send_btn)
	hb.add_child(send)
	var close = UTIL.button("✕", 16)
	close.pressed.connect(_close_chat)
	hb.add_child(close)
	# пауза
	_pause_panel = ColorRect.new()
	(_pause_panel as ColorRect).color = Color(0, 0, 0, 0.62)
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_panel)
	var pc = UTIL.panel_box()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(360, 0)
	_pause_panel.add_child(pc)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pc.add_child(pv)
	pv.add_child(UTIL.label("ПАУЗА", 26, Color(1, 1, 1)))
	var resume = UTIL.button("ПРОДОЛЖИТЬ", 20)
	resume.pressed.connect(_toggle_pause)
	pv.add_child(resume)
	_quality_btn = UTIL.button("Графика: Авто", 18)
	_quality_btn.pressed.connect(_cycle_quality)
	pv.add_child(_quality_btn)
	var cam_btn = UTIL.button("", 18)
	cam_btn.pressed.connect(func() -> void:
		var inv: bool = int(UTIL.get_set("game", "cam_inv", 0)) == 1
		UTIL.set_set("game", "cam_inv", 0 if inv else 1)
		_update_cam_btn(cam_btn))
	_update_cam_btn(cam_btn)
	pv.add_child(cam_btn)
	var to_menu = UTIL.button("В ГЛАВНОЕ МЕНЮ", 18)
	to_menu.pressed.connect(func() -> void:
		_toggle_pause()
		world.exit_to_menu())
	pv.add_child(to_menu)
	var quit = UTIL.button("ВЫХОД ИЗ ИГРЫ", 18)
	quit.pressed.connect(func() -> void: get_tree().quit())
	pv.add_child(quit)
	_update_quality_btn()


func _layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	_vs = vp.get_visible_rect().size
	_stick_center = Vector2(125, _vs.y - 135)
	_map_rect = Rect2(12, 12, 150, 150)
	var r := Vector2(_vs.x, _vs.y)
	_buttons.clear()
	if mode == "walk":
		_buttons.append({"n": "run", "pos": r - Vector2(80, 205), "r": 46, "l": "БЕГ", "hold": true})
		_buttons.append({"n": "jump", "pos": r - Vector2(170, 115), "r": 38, "l": "ПРЫЖОК", "hold": false})
		_buttons.append({"n": "enter", "pos": r - Vector2(80, 95), "r": 42, "l": "СЕСТЬ", "hold": false})
		_buttons.append({"n": "chat", "pos": r - Vector2(260, 75), "r": 30, "l": "ЧАТ", "hold": false})
		_buttons.append({"n": "job", "pos": r - Vector2(180, 250), "r": 32, "l": "РАБОТА", "hold": false})
		_buttons.append({"n": "garage", "pos": r - Vector2(280, 190), "r": 32, "l": "ГАРАЖ", "hold": false})
	else:
		_buttons.append({"n": "gas", "pos": r - Vector2(80, 175), "r": 50, "l": "ГАЗ", "hold": true})
		_buttons.append({"n": "brake", "pos": r - Vector2(195, 115), "r": 42, "l": "ТОРМОЗ", "hold": true})
		_buttons.append({"n": "handbrake", "pos": r - Vector2(185, 220), "r": 30, "l": "ДРИФТ", "hold": true})
		_buttons.append({"n": "enter", "pos": r - Vector2(80, 85), "r": 38, "l": "ВЫЙТИ", "hold": false})
		_buttons.append({"n": "chat", "pos": r - Vector2(275, 85), "r": 28, "l": "ЧАТ", "hold": false})
	_buttons.append({"n": "menu", "pos": Vector2(_vs.x - 40, 44), "r": 26, "l": "МЕНЮ", "hold": false})
	_hint.visible = not touchscreen and mode == "walk"
	_hint.position = Vector2(20, _vs.y - 30)
	_money_label.position = Vector2(_vs.x - 150, 14)
	_clock_label.position = Vector2(_vs.x - 150, 44)
	_fps_label.position = Vector2(_vs.x - 150, 72)
	_notices.position = Vector2(_vs.x * 0.5 - 200, 14)
	_notices.custom_minimum_size = Vector2(400, 0)
	_chat_panel.position = Vector2(12, _vs.y - 310)

# ================= ввод =================

func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_ESCAPE:
				if _chat_open:
					_close_chat()
				elif _garage_panel != null:
					show_garage()
				else:
					_toggle_pause()
				return
			KEY_T:
				if not _chat_open and not _paused:
					_open_chat()
				return
			KEY_J:
				_push("job")
			KEY_H:
				_push("horn")
	if _paused or _chat_open:
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			var role := _hit_test(ev.position)
			_fingers[ev.index] = role
			_press_role(role, ev.position)
		else:
			_release_role(_fingers.get(ev.index, {"type": ""}))
			_fingers.erase(ev.index)
	elif ev is InputEventScreenDrag:
		var role2: Dictionary = _fingers.get(ev.index, {"type": ""})
		if role2.get("type", "") == "stick":
			_update_stick(ev.position)
		elif role2.get("type", "") == "cam":
			_cam_delta += ev.relative


func _hit_test(pos: Vector2) -> Dictionary:
	for b in _buttons:
		if pos.distance_to(b.pos) < b.r + 10.0:
			return {"type": "btn", "n": b.n}
	if mode == "walk" and pos.distance_to(_stick_center) < _stick_r * 1.7:
		return {"type": "stick"}
	if pos.x > _vs.x * 0.42 and pos.y > 90.0:
		return {"type": "cam"}
	return {"type": ""}


func _press_role(role: Dictionary, pos: Vector2) -> void:
	match role.get("type", ""):
		"stick":
			_update_stick(pos)
		"cam":
			pass
		"btn":
			var n: String = role.n
			var b := _btn_by_name(n)
			if b.is_empty():
				return
			if n == "menu":
				_toggle_pause()
				return
			if n == "chat":
				_open_chat()
				return
			if n == "garage":
				show_garage()
				return
			if b.hold:
				_held[n] = true
			else:
				_push(n)


func _release_role(role: Dictionary) -> void:
	if role.get("type", "") == "stick":
		_stick_vec = Vector2.ZERO
		_knob = Vector2.ZERO
	elif role.get("type", "") == "btn":
		_held.erase(role.n)


func _btn_by_name(n: String) -> Dictionary:
	for b in _buttons:
		if b.n == n:
			return b
	return {}


func _update_stick(pos: Vector2) -> void:
	var v := (pos - _stick_center) / _stick_r
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.22:
		v = Vector2.ZERO
	_stick_vec = v
	_knob = v * _stick_r

# ================= публичный API =================

func move_axis() -> Vector2:
	return _stick_vec


func is_held(n: String) -> bool:
	return _held.get(n, false)


func push_event(n: String) -> void:
	_events.append(n)


func _push(n: String) -> void:
	_events.append(n)


func consume_event(n: String) -> bool:
	if _events.has(n):
		_events.erase(n)
		return true
	return false


func take_cam_delta() -> Vector2:
	var d := _cam_delta
	_cam_delta = Vector2.ZERO
	return d


func set_mode(m: String) -> void:
	mode = m
	_held.clear()
	_layout()


func notice(text: String) -> void:
	var l = UTIL.label(text, 18, Color(1, 0.95, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notices.add_child(l)
	_notice_list.append({"l": l, "t": 4.5})


func sys(text: String) -> void:
	_chat_line("[С] " + text)


func add_chat(nick_: String, msg: String) -> void:
	_chat_line(nick_ + ": " + msg)


func update_money() -> void:
	_money_label.text = "₽ " + UTIL.fmt_money(UTIL.get_money())

# ================= чат =================

func _chat_line(s: String) -> void:
	_chat_lines.append(s)
	if _chat_lines.size() > 8:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)


func _open_chat() -> void:
	_chat_open = true
	_chat_panel.visible = true
	_chat_edit.grab_focus()


func _close_chat() -> void:
	_chat_open = false
	_chat_edit.release_focus()
	_chat_panel.visible = false


func _on_chat_send_btn() -> void:
	_on_chat_send(_chat_edit.text)


func _on_chat_send(text: String) -> void:
	var msg := str(text).strip_edges()
	_chat_edit.text = ""
	if msg.is_empty():
		_close_chat()
		return
	if world.net != null and world.net.connected:
		world.net.send_chat(msg)
	else:
		add_chat(UTIL.get_nick(), msg)

# ================= пауза =================

func show_garage() -> void:
	if _garage_panel != null:
		_garage_panel.queue_free()
		_garage_panel = null
		return
	_garage_panel = Control.new()
	_garage_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_garage_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_garage_panel)
	var pc = UTIL.panel_box()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(380, 0)
	_garage_panel.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	v.add_child(UTIL.label("ГАРАЖ", 26, Color(1, 1, 1)))
	v.add_child(UTIL.label("Машина подаётся рядом с тобой", 14, Color(0.7, 0.75, 0.85)))
	var CT = load("res://br/car_types.gd")
	for i in range(CT.TYPES.size()):
		var tname: String = CT.TYPES[i].name
		var b = UTIL.button(tname, 19)
		b.pressed.connect(func() -> void:
			garage_pick = i
			_push("garage_pick")
			show_garage())
		v.add_child(b)
	var close = UTIL.button("ЗАКРЫТЬ", 16)
	close.pressed.connect(show_garage)
	v.add_child(close)


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_panel.visible = _paused
	get_tree().paused = _paused


func _cycle_quality() -> void:
	var q := int(UTIL.get_set("game", "quality", -1))
	var next_q := 1 if q < 0 else q + 1
	if next_q > 3:
		next_q = -1
	world.apply_quality(next_q)
	_update_quality_btn()


func _update_cam_btn(btn: Button) -> void:
	var inv: bool = int(UTIL.get_set("game", "cam_inv", 0)) == 1
	btn.text = "Камера: обычная" if not inv else "Камера: инверсия"


func _update_quality_btn() -> void:
	var q := int(UTIL.get_set("game", "quality", -1))
	var names := {-1: "Авто", 1: "Низкая", 2: "Средняя", 3: "Высокая"}
	_quality_btn.text = "Графика: " + names.get(q, "Авто")

# ================= цикл и отрисовка =================

func _process(delta: float) -> void:
	if size.x > 0 and (absf(size.x - _vs.x) > 2.0 or absf(size.y - _vs.y) > 2.0):
		_layout()
	_fps_n += 1
	_fps_t += delta
	if _fps_t >= 0.5:
		_fps_v = int(round(_fps_n / _fps_t))
		_fps_n = 0
		_fps_t = 0.0
		_fps_label.text = "%d FPS" % _fps_v
	update_money()
	if world != null and world.day_night != null:
		_clock_label.text = world.day_night.clock_text()
	var i := 0
	while i < _notice_list.size():
		var n: Dictionary = _notice_list[i]
		n.t -= delta
		if n.t < 1.0:
			n.l.modulate.a = maxf(n.t, 0.0)
		if n.t <= 0.0:
			n.l.queue_free()
			_notice_list.remove_at(i)
		else:
			i += 1
	if world != null and world.player != null and mode == "walk":
		_ctx_near = world.find_car_near(world.player.global_position) != null
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	_draw_minimap()
	# джойстик
	if mode == "walk":
		draw_circle(_stick_center, _stick_r, Color(0, 0, 0, 0.28))
		draw_arc(_stick_center, _stick_r, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0)
		var knob_pos := _stick_center + _knob
		draw_circle(knob_pos, 26.0, Color(0.85, 0.9, 1.0, 0.5))
	# кнопки
	var f := get_theme_default_font()
	for b in _buttons:
		if b.n == "enter" and mode == "walk" and not _ctx_near:
			continue
		var held: bool = _held.get(b.n, false)
		var col := Color(0.85, 0.9, 1.0, 0.55) if held else Color(0.08, 0.1, 0.15, 0.5)
		draw_circle(b.pos, b.r, col)
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.3), 2.0)
		if b.n == "enter" and _ctx_near and mode == "walk":
			draw_arc(b.pos, b.r + 4.0 + sin(Time.get_ticks_msec() / 150.0) * 2.0, 0, TAU, 40, Color(0.4, 1.0, 0.5, 0.9), 3.0)
		draw_string(f, b.pos - Vector2(b.r, 0) + Vector2(0, 6), b.l,
			HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, 15, Color(1, 1, 1, 0.92))


func _draw_minimap() -> void:
	if _map_tex == null:
		return
	draw_texture_rect(_map_tex, _map_rect, false)
	draw_rect(_map_rect, Color(1, 1, 1, 0.3), false, 2.0)
	var to_map := func(wp: Vector3) -> Vector2:
		return _map_rect.position + Vector2(
			(wp.x + CB.HALF + 30.0) / _map_span * _map_rect.size.x,
			(wp.z + CB.HALF + 30.0) / _map_span * _map_rect.size.y)
	# другие игроки
	for id in world.remotes:
		var rp: Node = world.remotes[id]
		if rp != null and is_instance_valid(rp) and rp.visible:
			draw_circle(to_map.call(rp.global_position), 3.5, Color(1, 0.3, 0.3))
	# цель работы
	if world.job.active and world.job.points.size() > world.job.idx:
		var pulse := 3.5 + sin(Time.get_ticks_msec() / 200.0) * 1.5
		draw_circle(to_map.call(world.job.points[world.job.idx]), pulse, Color(1, 0.85, 0.1))
	# я
	if world.player != null:
		var me: Vector2 = to_map.call(world.player.global_position)
		var yaw: float = world.player.model.rotation.y
		if world.player.current_car != null and is_instance_valid(world.player.current_car):
			yaw = world.player.current_car.rotation.y
		draw_circle(me, 5.0, Color(0.2, 1, 0.4))
		var dir := Vector2(sin(yaw), cos(yaw))
		draw_line(me, me + dir * 10.0, Color(0.2, 1, 0.4), 2.0)
	# север
	draw_string(get_theme_default_font(), _map_rect.position + Vector2(68, 16), "С",
		HORIZONTAL_ALIGNMENT_CENTER, 20, 14, Color(1, 1, 1, 0.8))
