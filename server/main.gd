extends Node
## Выделенный сервер «Провинция RP»: агрегирует состояния игроков (15 Гц),
## раздаёт снапшоты, чат и системные сообщения. Симуляцию мира клиенты делают сами.

const NETS := preload("res://net_server.gd")

const MOTD := "Добро пожаловать на сервер ПРОВИНЦИЯ RP! Приятной игры."
const SNAPSHOT_HZ := 15.0

var net: Node
var port := 7777
var max_players := 100
var peers := {}   # id -> {"nick": String, "state": Dictionary}

var _snap_t := 0.0
var _log_t := 0.0


func _ready() -> void:
	net = NETS.new()
	net.name = "Net"
	net.srv = self
	add_child(net)
	_parse_args()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		printerr("[SRV] Не удалось занять UDP-порт %d (код %d). Занят другой процесс?" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false  # трафик клиентов идёт только через сервер
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[SRV] Сервер запущен: UDP-порт %d, слотов %d" % [port, max_players])


func _parse_args() -> void:
	var env_port := OS.get_environment("SRV_PORT")
	if env_port.is_valid_int():
		port = int(env_port)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.split("=")[1])
		elif a.begins_with("--max="):
			max_players = int(a.split("=")[1])


func _now() -> String:
	return Time.get_time_string_from_system()


func _on_peer_connected(id: int) -> void:
	peers[id] = {"nick": "Игрок%d" % id, "state": {}}
	print("[%s] + peer %d подключился (%d/%d)" % [_now(), id, peers.size(), max_players])
	net.rpc_sysmsg.rpc_id(id, MOTD)


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var nick: String = peers[id]["nick"]
	peers.erase(id)
	print("[%s] - peer %d (%s) отключился (%d/%d)" % [_now(), id, nick, peers.size(), max_players])
	net.rpc_sysmsg.rpc("%s покинул сервер" % nick)


func on_register(id: int, nick: String) -> void:
	if not peers.has(id):
		return
	var clean := nick.strip_edges().substr(0, 16)
	if clean.is_empty():
		clean = "Игрок%d" % id
	peers[id]["nick"] = clean
	print("[%s] * peer %d теперь известен как «%s»" % [_now(), id, clean])
	net.rpc_sysmsg.rpc("%s зашёл на сервер (%d/%d)" % [clean, peers.size(), max_players])


func on_state(id: int, px: float, py: float, pz: float, ry: float, anim: int,
		car_id: int, cx: float, cy: float, cz: float, cry: float, ct: int) -> void:
	if not peers.has(id):
		return
	peers[id]["state"] = {
		"n": peers[id]["nick"],
		"p": Vector3(px, py, pz),
		"ry": ry,
		"a": anim,
		"c": car_id,
		"cp": Vector3(cx, cy, cz),
		"cry": cry,
		"ct": ct,
	}


func on_chat(id: int, msg: String) -> void:
	if not peers.has(id):
		return
	var nick: String = peers[id]["nick"]
	var clean := msg.strip_edges().substr(0, 120)
	if clean.is_empty():
		return
	if clean.begins_with("/"):
		_command(id, nick, clean)
		return
	print("[%s] chat %s: %s" % [_now(), nick, clean])
	net.rpc_chat_msg.rpc(id, nick, clean)


func _command(id: int, nick: String, cmd: String) -> void:
	if cmd == "/online" or cmd == "/list":
		var names: Array = []
		for k in peers:
			names.append(peers[k]["nick"])
		net.rpc_sysmsg.rpc_id(id, "На сервере (%d): %s" % [names.size(), ", ".join(names)])
	else:
		net.rpc_sysmsg.rpc_id(id, "Неизвестная команда. Доступно: /list")


func _process(delta: float) -> void:
	_snap_t += delta
	if _snap_t >= 1.0 / SNAPSHOT_HZ:
		_snap_t = 0.0
		if not peers.is_empty() and multiplayer.multiplayer_peer != null:
			var snap := {}
			for id in peers:
				var st: Dictionary = peers[id]["state"]
				if not st.is_empty():
					snap[id] = st
			if not snap.is_empty():
				net.rpc_snapshot.rpc(snap)
	_log_t += delta
	if _log_t >= 60.0:
		_log_t = 0.0
		print("[%s] статус: игроков %d/%d" % [_now(), peers.size(), max_players])
