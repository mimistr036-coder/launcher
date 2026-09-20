extends Node3D
## Мир: город, игрок, машины, камера, сеть, HUD.

const CB := preload("res://br/city_builder.gd")
const VEH := preload("res://br/vehicle.gd")
const NPC := preload("res://br/npc_car.gd")
const PLAYER := preload("res://br/player.gd")
const HUDS := preload("res://br/hud.gd")
const DN := preload("res://br/day_night.gd")
const JOBS := preload("res://br/job.gd")
const TRAF := preload("res://br/traffic_lights.gd")
const UTIL := preload("res://br/util.gd")

var online := false
var server_ip := ""
var server_port := 7777
var nick := "Игрок"
var net: Node = null
var net_ok := false

var city: Node3D
var player: CharacterBody3D
var hud: Control
var day_night: Node
var job: Node
var traffic: Node
var cars: Array = []
var npcs: Array = []
var remotes: Dictionary = {}   # peer_id -> remote player node

var cam_yaw := 0.0
var cam_pitch := -0.30
var _rig: Node3D
var _rig_pitch: Node3D
var _cam: Camera3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var _send_t := 0.0
var _leaving := false


func setup(p_online: bool, ip: String, port: int, p_nick: String, p_net: Node) -> void:
	online = p_online
	server_ip = ip
	server_port = port
	nick = p_nick
	net = p_net


func _ready() -> void:
	_build_environment()
	city = CB.new()
	city.name = "City"
	add_child(city)
	city.build()
	_spawn_player()
	_spawn_cars()
	_spawn_npcs()
	_build_camera()
	hud = HUDS.new()
	hud.name = "HUD"
	hud.world = self
	add_child(hud)
	hud.setup()
	player.hud = hud
	traffic = TRAF.new()
	traffic.name = "Traffic"
	traffic.city = city
	add_child(traffic)
	job = JOBS.new()
	job.name = "Job"
	job.world = self
	add_child(job)
	if online and net != null:
		net.world = self
		net.net_ready.connect(_on_net_ready)
		net.net_failed.connect(_on_net_failed)
		net.net_lost.connect(_on_net_lost)
		net.chat_msg.connect(_on_chat)
		net.sysmsg.connect(_on_sys)
		net.connect_to(server_ip, server_port, nick)
	_apply_quality(int(UTIL.get_set("game", "quality", -1)))
	hud.notice("Добро пожаловать в г. Провинцинск!")
	if online:
		hud.sys("Подключение к %s:%d ..." % [server_ip, server_port])


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.002
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -60, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = false
	add_child(moon)
	day_night = DN.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(sun, moon, env)


func _spawn_player() -> void:
	player = PLAYER.new()
	player.name = "Player"
	player.nick = nick
	player.world = self
	player.variant = randi() % 6
	add_child(player)
	player.global_position = city.spawn_point
	cam_yaw = city.spawn_point.angle_to(Vector3.ONE)  # просто начальный ракурс
	cam_yaw = PI * 0.25


func _spawn_cars() -> void:
	var idx := 0
	for s in city.car_spawns:
		var car := VEH.new()
		car.name = "Car%d" % idx
		idx += 1
		car.setup(int(s.type), int(s.color))
		add_child(car)
		car.global_position = s.pos + Vector3(0, 0.3, 0)
		car.rotation_degrees.y = float(s.rot)
		cars.append(car)


func _spawn_npcs() -> void:
	var idx := 0
	for s in city.npc_spawns:
		var car := NPC.new()
		car.name = "NPC%d" % idx
		idx += 1
		car.setup(int(s.type), (idx * 3) % 7)
		car.world = self
		add_child(car)
		car.configure_npc(s.axis, int(s.line), int(s.dir), float(s.t))
		# стартовая позиция на полосе
		var lane: Vector3
		if s.axis == "x":
			lane = Vector3(float(s.t), 0.3, CB.line_coord(int(s.line)) + 2.7 * float(s.dir))
			car.rotation.y = 0.0 if float(s.dir) > 0 else PI
		else:
			lane = Vector3(CB.line_coord(int(s.line)) - 2.7 * float(s.dir), 0.3, float(s.t))
			car.rotation.y = -PI / 2.0 if float(s.dir) > 0 else PI / 2.0
		car.global_position = lane
		npcs.append(car)


func _build_camera() -> void:
	_rig = Node3D.new()
	_rig.name = "CamRig"
	add_child(_rig)
	_rig_pitch = Node3D.new()
	_rig.add_child(_rig_pitch)
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.position = Vector3(0, 0, 5.6)
	_rig_pitch.add_child(_cam)
	_cam.current = true
	var tp: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	_rig.global_position = tp
	_rig.rotation.y = cam_yaw
	_rig_pitch.rotation.x = cam_pitch


func _process(delta: float) -> void:
	if hud != null:
		var d := hud.take_cam_delta()
		cam_yaw -= d.x * 0.005
		cam_pitch = clampf(cam_pitch - d.y * 0.004, -1.15, 0.45)
		if hud.consume_event("job"):
			job.toggle()
		if hud.consume_event("horn") and player.current_car != null:
			player.current_car.honk()
	_update_camera(delta)
	# фары своей машины
	if player.current_car != null and is_instance_valid(player.current_car):
		player.current_car.set_lights(day_night.night > 0.35)
	traffic.night = day_night.night
	# сеть: отправка состояния
	if online and net != null and net.connected and player != null:
		_send_t += delta
		if _send_t >= 1.0 / 15.0:
			_send_t = 0.0
			_send_state()


func _update_camera(delta: float) -> void:
	var in_car := player.current_car != null and is_instance_valid(player.current_car)
	var target: Node3D = player.current_car if in_car else player
	var tpos: Vector3 = target.global_position + Vector3(0, 2.0 if in_car else 1.55, 0)
	if in_car:
		var v: Vector3 = player.current_car.velocity
		var fwd: Vector3 = -player.current_car.transform.basis.z
		if fwd.dot(v) > 3.0:
			cam_yaw = lerp_angle(cam_yaw, player.current_car.rotation.y, 1.0 - pow(0.02, delta))
	_rig.global_position = _rig.global_position.lerp(tpos, 1.0 - pow(0.0001, delta))
	_rig.rotation.y = cam_yaw
	_rig_pitch.rotation.x = cam_pitch
	var dist := 7.4 if in_car else 5.6
	var desired: Vector3 = _rig_pitch.global_transform * Vector3(0, 0, dist)
	var from: Vector3 = tpos
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
	var hit := space.intersect_ray(q)
	var final_local := dist
	if hit.has("position"):
		var f: float = from.distance_to(hit.position) / dist
		final_local = clampf(dist * f - 0.25, 1.2, dist)
	_cam.position = Vector3(0, 0, final_local)


func _send_state() -> void:
	var car_id := 0
	var ct := 0
	var pp := player.global_position
	var ry := player.model.rotation.y
	var anim: int = player.anim_state()
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var cry := 0.0
	if player.current_car != null and is_instance_valid(player.current_car):
		car_id = cars.find(player.current_car) + 1
		ct = player.current_car.type_idx
		cx = player.current_car.global_position.x
		cy = player.current_car.global_position.y
		cz = player.current_car.global_position.z
		cry = player.current_car.rotation.y
	net.send_state(pp.x, pp.y, pp.z, ry, anim, car_id, cx, cy, cz, cry, ct)

# ---------------- сеть ----------------

func apply_snapshot(data: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	for key in data.keys():
		var id := int(key)
		if id == my_id:
			net_ok = true
			continue
		var e: Dictionary = data[key]
		var rp: Node = remotes.get(id)
		if rp == null or not is_instance_valid(rp):
			rp = load("res://br/remote_player.gd").new()
			remotes[id] = rp
			add_child(rp)
			rp.setup(id, str(e.get("n", "Игрок")), id % 6)
			if str(e.get("n", "")) != "":
				hud.sys("%s зашёл в город" % str(e.get("n")))
		var pos: Vector3 = e.get("p", Vector3.ZERO)
		rp.set_state(pos, float(e.get("ry", 0.0)), int(e.get("a", 0)))
		var cid := int(e.get("c", 0))
		if cid > 0 and cid <= cars.size():
			var car: Node = cars[cid - 1]
			car.remote_driven = true
			car.net_target = e.get("cp", Vector3.ZERO)
			car.net_yaw = float(e.get("cry", 0.0))
			car.locked = true
			rp.visible = false
		else:
			rp.visible = true
	# удаляем отвалившихся
	for id2 in remotes.keys():
		if not data.has(id2) and not data.has(str(id2)):
			if is_instance_valid(remotes[id2]):
				remotes[id2].queue_free()
			remotes.erase(id2)


func _on_net_ready() -> void:
	net_ok = true
	hud.sys("Подключено! Твой ID: %d" % multiplayer.get_unique_id())


func _on_net_failed(reason: String) -> void:
	hud.sys("Не удалось подключиться: " + reason)
	_back_to_menu_soon()


func _on_net_lost() -> void:
	if _leaving:
		return
	hud.sys("Соединение с сервером потеряно")
	_back_to_menu_soon()


func _on_chat(sender: String, msg: String) -> void:
	hud.add_chat(sender, msg)


func _on_sys(text: String) -> void:
	hud.sys(text)


func _back_to_menu_soon() -> void:
	if _leaving:
		return
	_leaving = true
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(func() -> void:
		var boot := get_parent()
		if boot != null and boot.has_method("back_to_menu"):
			boot.back_to_menu()
	)

# ---------------- машины ----------------

func find_car_near(p: Vector3, max_d: float = 3.0) -> Node:
	var best: Node = null
	var best_d := max_d
	for car in cars:
		if not is_instance_valid(car) or car.locked or car.driver != null:
			continue
		var d: float = car.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = car
	return best


func try_enter_car(p: Node) -> void:
	if p.current_car != null:
		_exit_car(p)
		return
	var car := find_car_near(p.global_position, 3.2)
	if car == null:
		hud.notice("Рядом нет свободной машины")
		return
	car.driver = p
	p.current_car = car
	p.collision_layer = 0
	p.visible = false
	p.global_position = car.global_position + Vector3(0, 0.3, 0)
	hud.set_mode("car")
	hud.notice("«%s» — в путь! (ГАЗ/ТОРМОЗ справа, руль — джойстик)" % car.display_name)


func _exit_car(p: Node) -> void:
	var car: Node = p.current_car
	var T: Dictionary = load("res://br/car_types.gd").TYPES[car.type_idx]
	var side: Vector3 = car.global_transform.basis.x * (T.body.x * 0.5 + 0.8)
	p.global_position = car.global_position + side + Vector3(0, 0.2, 0)
	p.velocity = Vector3.ZERO
	p.visible = true
	p.collision_layer = 2
	car.driver = null
	car.set_lights(day_night.night > 0.35)
	p.current_car = null
	hud.set_mode("walk")


func exit_to_menu() -> void:
	_leaving = true
	var boot := get_parent()
	if boot != null and boot.has_method("back_to_menu"):
		boot.back_to_menu()

# ---------------- качество ----------------

func apply_quality(q: int) -> void:
	UTIL.set_set("game", "quality", q)
	var lvl := q
	if lvl < 0:
		lvl = 2 if OS.has_feature("mobile") else 3
	day_night.base_shadow = lvl >= 2
	sun.directional_shadow_max_distance = 80.0 if lvl == 2 else 150.0
	env.glow_enabled = lvl >= 3
