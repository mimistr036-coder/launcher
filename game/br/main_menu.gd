extends Control
## Главное меню клиента: ник, адрес сервера, офлайн-режим.

signal start(online: bool, ip: String, port: int, nick: String)

var UTIL = load("res://br/util.gd")

var _nick: LineEdit
var _ip: LineEdit
var _port: LineEdit
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# фоновая полоса-дорога
	var road := ColorRect.new()
	road.color = Color(0.1, 0.11, 0.15)
	road.position = Vector2(0, 0)
	road.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	road.custom_minimum_size = Vector2(0, 90)
	add_child(road)
	var title = UTIL.label("ПРОВИНЦИЯ RP", 52, Color(0.95, 0.8, 0.3))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-220, 60)
	title.custom_minimum_size = Vector2(440, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub = UTIL.label("Русский город. Своя игра.", 18, Color(0.7, 0.75, 0.85))
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-220, 122)
	sub.custom_minimum_size = Vector2(440, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var panel = UTIL.panel_box()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UTIL.label("НИК", 14, Color(0.6, 0.65, 0.75)))
	_nick = UTIL.line_edit("Водитель", UTIL.get_nick(), 20)
	v.add_child(_nick)
	v.add_child(UTIL.label("IP СЕРВЕРА", 14, Color(0.6, 0.65, 0.75)))
	_ip = UTIL.line_edit("например 192.168.1.50", UTIL.get_set("net", "ip", "127.0.0.1"), 40)
	v.add_child(_ip)
	var ports: int = UTIL.get_set("net", "port", 7777)
	_port = UTIL.line_edit("7777", str(ports), 6)
	v.add_child(_port)
	v.add_child(_spacer(6))
	var connect_btn = UTIL.button("ПОДКЛЮЧИТЬСЯ К СЕРВЕРУ", 20)
	connect_btn.pressed.connect(_on_connect)
	v.add_child(connect_btn)
	var offline_btn = UTIL.button("ИГРАТЬ БЕЗ СЕТИ", 18)
	offline_btn.pressed.connect(_on_offline)
	v.add_child(offline_btn)
	_status = UTIL.label("", 15, Color(1, 0.6, 0.5))
	v.add_child(_status)
	var cache_ver := ""
	var vf := FileAccess.open("user://cache/version.txt", FileAccess.READ)
	if vf != null:
		cache_ver = vf.get_line().strip_edges()
	var ver = UTIL.label("Провинция RP · клиент v1.0 · " + (cache_ver if cache_ver != "" else "кэш не найден"), 13, Color(1, 1, 1, 0.45))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.position = Vector2(0, -26)
	ver.custom_minimum_size = Vector2(0, 20)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ver)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_connect() -> void:
	var nick_ := _nick.text.strip_edges()
	if nick_.is_empty():
		_status.text = "Введи ник"
		return
	var ip := _ip.text.strip_edges()
	if ip.is_empty():
		_status.text = "Введи IP сервера"
		return
	var port := int(_port.text.strip_edges())
	if port < 1 or port > 65535:
		_status.text = "Неверный порт"
		return
	UTIL.set_set("player", "nick", nick_)
	UTIL.set_set("net", "ip", ip)
	UTIL.set_set("net", "port", port)
	start.emit(true, ip, port, nick_)


func _on_offline() -> void:
	var nick_ := _nick.text.strip_edges()
	if nick_.is_empty():
		nick_ = "Водитель"
	UTIL.set_set("player", "nick", nick_)
	start.emit(false, "", 7777, nick_)
