extends Node
## Точка входа игры (загружается лаунчером из кэша или напрямую из редактора).
## Имя корневого узла — «RP» (важно для сетевых RPC-путей, см. net.gd).

var UTIL = load("res://br/util.gd")
var MENUS = load("res://br/main_menu.gd")
var WORLDS = load("res://br/world.gd")
var NETS = load("res://br/net.gd")

var menu = null
var world = null
var net = null
var _autotest_done := false
var _autotest_fail := ''


func _ready() -> void:
	UTIL.setup_actions()
	var at := OS.get_environment("GAME_AUTOTEST")
	if at.length() > 0:
		_autotest(at)
		return
	_show_menu()


func _show_menu() -> void:
	menu = MENUS.new()
	menu.name = "Menu"
	add_child(menu)
	menu.start.connect(_on_start)


func _on_start(online: bool, ip: String, port: int, nick: String) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	_start_world(online, ip, port, nick)


func _start_world(online: bool, ip: String, port: int, nick: String) -> void:
	if online:
		net = NETS.new()
		net.name = "Net"
		add_child(net)
	world = WORLDS.new()
	world.name = "World"
	world.setup(online, ip, port, nick, net)
	add_child(world)


func back_to_menu() -> void:
	if world != null:
		world.queue_free()
		world = null
	if net != null:
		net.disconnect_now()
		net.queue_free()
		net = null
	_show_menu()

# ================= автотесты (CI) =================

func _autotest(mode: String) -> void:
	print("[AUTOTEST] start mode=", mode)
	var online := mode.begins_with("mp:")
	var ip := "127.0.0.1"
	var port := 7777
	if online:
		var parts := mode.split(":")
		if parts.size() >= 3:
			ip = parts[1]
			port = int(parts[2])
	var wd := get_tree().create_timer(50.0)
	wd.timeout.connect(func() -> void:
		if not _autotest_done:
			print("[AUTOTEST] TIMEOUT")
			get_tree().quit(1))
	_start_world(online, ip, port, "ТестБот")
	if not online:
		# проверка направления: W должен вести ОТ камеры (вдоль fwd камеры)
		var tdir := get_tree().create_timer(1.0)
		tdir.timeout.connect(func() -> void:
			if world != null and world.player != null:
				world.cam_yaw = 0.0
				Input.action_press("move_forward"))
	var tdir2 := get_tree().create_timer(1.4)
	tdir2.timeout.connect(func() -> void:
		Input.action_release("move_forward")
		if world != null and world.player != null:
			var fwd := Vector3(-sin(world.cam_yaw), 0, -cos(world.cam_yaw))
			var dot: float = world.player.velocity.dot(fwd)
			print("[AUTOTEST] движение W: velocity*fwd=", dot)
			if dot < 1.0:
				_autotest_fail = "управление инвертировано (dot=%.2f)" % dot)
	if online:
		var poll := Timer.new()
		poll.wait_time = 0.5
		poll.autostart = true
		add_child(poll)
		poll.timeout.connect(func() -> void:
			if _autotest_done:
				return
			if world != null and world.net_ok:
				_autotest_done = true
				print("[AUTOTEST] OK snapshot received, remotes=", world.remotes.size())
				get_tree().quit(0))
	else:
		var t := get_tree().create_timer(3.0)
		t.timeout.connect(func() -> void:
			var ok := true
			var why := ""
			if world == null:
				ok = false
				why = "no world"
			else:
				if world.player == null:
					ok = false
					why = "no player"
				elif world.cars.size() < 5:
					ok = false
					why = "cars=" + str(world.cars.size())
				elif world.city.map_img == null:
					ok = false
					why = "no map"
				elif world.city.job_points.size() < 5:
					ok = false
					why = "job_points=" + str(world.city.job_points.size())
				elif world.player.global_position.y < -3.0:
					ok = false
					why = "player fell under map (y=" + str(world.player.global_position.y) + ")"
				elif _autotest_fail != "":
					ok = false
					why = _autotest_fail
			_autotest_done = true
			if ok:
				print("[AUTOTEST] OK cars=", world.cars.size(), " npcs=", world.npcs.size(),
					" job_points=", world.city.job_points.size())
				get_tree().quit(0)
			else:
				print("[AUTOTEST] FAIL: ", why)
				get_tree().quit(1))
