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
	if mode == "shot" or mode == "shot15":
		_start_world(false, "", 0, "ТестБот")
		if world != null and world.day_night != null and mode == "shot15":
			world.day_night.time_h = 15.57
		var ts := get_tree().create_timer(3.5)
		ts.timeout.connect(func() -> void:
			# вид сверху
			var cam2 := Camera3D.new()
			world.add_child(cam2)
			cam2.global_position = world.city.spawn_point + Vector3(0, 90, 0)
			cam2.rotation.x = -PI / 2
			cam2.current = true
			var t2 := get_tree().create_timer(0.6)
			t2.timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png("/tmp/city-top.png")
				cam2.current = false
				cam2.queue_free()
				var t3 := get_tree().create_timer(0.4)
				t3.timeout.connect(func() -> void:
					get_viewport().get_texture().get_image().save_png("/tmp/city.png")
					print("[AUTOTEST] скриншоты готовы")
					get_tree().quit(0)))
			return)
		var tgeo := get_tree().create_timer(2.8)
		tgeo.timeout.connect(_dump_geo)
		return
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
	# подаём машину через гараж (припаркованных больше нет)
	var tspawn := get_tree().create_timer(1.5)
	tspawn.timeout.connect(func() -> void:
		if world != null:
			world.spawn_car(0))
	# тест руления: машину ставим на чистый асфальт у спавна, игрок подходит и садится,
	# жмём вправо — нос должен пойти вправо (rotation.y уменьшаться)
	var tcar := get_tree().create_timer(1.9)
	tcar.timeout.connect(func() -> void:
		if world != null and world.player != null and world.cars.size() > 0:
			var car = world.cars[0]
			var sp: Vector3 = world.city.spawn_point
			car.global_position = sp + Vector3(0, 0.5, 5.0)
			car.rotation.y = 0.0
			car.velocity = Vector3.ZERO
			world.player.global_position = sp + Vector3(0, 0.2, 2.5)
			world.try_enter_car(world.player)
			if world.player.current_car == null:
				_autotest_fail = "не удалось сесть в машину"
				return
			Input.action_press("move_forward")
			Input.action_press("move_right"))
	var tcar2 := get_tree().create_timer(2.7)
	tcar2.timeout.connect(func() -> void:
		Input.action_release("move_forward")
		Input.action_release("move_right")
		if world != null and world.player != null and world.player.current_car != null:
			var car = world.player.current_car
			var ry: float = car.rotation.y
			var spd: float = car.velocity.length()
			var cy: float = car.global_position.y
			print("[AUTOTEST] руление вправо: rotation.y=", ry, " speed=", spd, " y=", cy)
			if cy < -1.0:
				_autotest_fail = "машина провалилась в тесте руления (y=%.1f)" % cy
			elif spd > 1.0 and ry > -0.05:
				_autotest_fail = "руль инвертирован (rotation.y=%.2f)" % ry
			world.try_enter_car(world.player))
	# валидация геометрии города: индексы всех поверхностей в пределах вершин
	var tgeo := get_tree().create_timer(2.0)
	tgeo.timeout.connect(func() -> void:
		if world == null or world.city == null:
			return
		var surf := 0
		var tris := 0
		var bad := 0
		for geo in world.city.get_children():
			if not (geo is MeshInstance3D) or geo.mesh == null:
				continue
			for sidx in range(geo.mesh.get_surface_count()):
				var arrays: Array = geo.mesh.surface_get_arrays(sidx)
				if arrays == null or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if raw_idx == null:
					continue
				var idxa: PackedInt32Array = raw_idx
				surf += 1
				tris += idxa.size() / 3
				if verts.size() > 65000:
					bad += 1
					print("[AUTOTEST] поверхность ", surf, " слишком большая: ", verts.size(), " вершин")
				for ii in idxa:
					if ii >= verts.size():
						bad += 1
		print("[AUTOTEST] геометрия: поверхностей=", surf, " треугольников=", tris, " битых индексов=", bad)
		if bad > 0:
			_autotest_fail = "битые индексы мешей: %d" % bad)
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
		var t := get_tree().create_timer(3.2)
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
				elif world.cars.size() < 1:
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


func _dump_geo() -> void:
	if world == null or world.city == null:
		return
	var shown := 0
	for geo in world.city.get_children():
		if not (geo is MeshInstance3D) or geo.mesh == null:
			continue
		var aab: AABB = geo.mesh.get_aabb()
		print("[GEO] ", geo.name, " aabb_pos=", aab.position, " aabb_size=", aab.size)
		for sidx in range(geo.mesh.get_surface_count()):
			var arrs: Array = geo.mesh.surface_get_arrays(sidx)
			var vv: Variant = arrs[Mesh.ARRAY_VERTEX]
			if vv == null:
				continue
			var verts: PackedVector3Array = vv
			var worst := 0.0
			for v in verts:
				var dev: float = maxf(absf(v.y), maxf(absf(v.x), absf(v.z)))
				if dev > worst:
					worst = dev
			if worst > 60.0 and shown < 12:
				shown += 1
				var samples := ""
				var got := 0
				for i in range(verts.size()):
					var v2: Vector3 = verts[i]
					if absf(v2.y) > 60.0 or absf(v2.x) > 500.0 or absf(v2.z) > 500.0:
						samples += " [%d]=%s" % [i, v2]
						got += 1
						if got >= 4:
							break
				print("[BAD] ", geo.name, " worst_dev=", worst, samples)
