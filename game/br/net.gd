extends Node
## Сетевой клиент. Узел обязан называться «Net» и лежать в /root/RP/Net
## (пути RPC должны совпадать с сервером). Сигнатуры rpc_* синхронизированы
## с server/net_server.gd — меняй только парой!

signal net_ready
signal net_failed(reason)
signal net_lost
signal chat_msg(nick: String, msg: String)
signal sysmsg(text: String)

var connected := false
var _dbg_snap := false
var _dbg_state := false
var my_nick := "Игрок"
var world: Node = null


func connect_to(ip: String, port: int, nick: String) -> bool:
	my_nick = nick
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		net_failed.emit("Ошибка запуска подключения (код %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_fail)
	multiplayer.server_disconnected.connect(_on_disc)
	return true


func disconnect_now() -> void:
	connected = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _on_connected() -> void:
	connected = true
	print("[NET] подключено, отправляю регистр: ", my_nick)
	rpc_register.rpc(my_nick)


func _on_fail() -> void:
	connected = false
	net_failed.emit("Сервер недоступен")


func _on_disc() -> void:
	connected = false
	net_lost.emit()

# ---------- отправка ----------

func send_state(px: float, py: float, pz: float, ry: float, anim: int,
		car_id: int, cx: float, cy: float, cz: float, cry: float, ct: int) -> void:
	if connected and not _dbg_state:
		_dbg_state = true
		print("[NET] первое состояние отправлено")
	if connected:
		rpc_state.rpc(px, py, pz, ry, anim, car_id, cx, cy, cz, cry, ct)


func send_chat(msg: String) -> void:
	if connected:
		rpc_chat.rpc(msg)

# ---------- приём (НЕ МЕНЯТЬ СИГНАТУРЫ БЕЗ СЕРВЕРА) ----------

@rpc("any_peer", "reliable")
func rpc_register(_nick: String) -> void:
	pass  # только отправка с клиента


@rpc("any_peer", "unreliable")
func rpc_state(_px: float, _py: float, _pz: float, _ry: float, _anim: int,
		_car_id: int, _cx: float, _cy: float, _cz: float, _cry: float, _ct: int) -> void:
	pass  # только отправка с клиента


@rpc("any_peer", "reliable")
func rpc_chat(_msg: String) -> void:
	pass  # только отправка с клиента


@rpc("authority", "reliable")
func rpc_chat_msg(_sender_id: int, nick: String, msg: String) -> void:
	chat_msg.emit(nick, msg)


@rpc("authority", "reliable")
func rpc_sysmsg(text: String) -> void:
	sysmsg.emit(text)


@rpc("authority", "unreliable")
func rpc_snapshot(data: Dictionary) -> void:
	if not _dbg_snap:
		_dbg_snap = true
		print("[NET] первый снапшот: ", data.size(), " игроков, world=", world,
				" has_apply=", world != null and world.has_method("apply_snapshot"))
	if not connected:
		connected = true
		net_ready.emit()
	_apply_snapshot(data)


func _apply_snapshot(data: Dictionary) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var owner_node := get_parent()
	if owner_node == null or not owner_node.has_method("apply_snapshot"):
		return
	owner_node.apply_snapshot(data)


@rpc("authority", "reliable")
func rpc_kick(reason: String) -> void:
	net_lost.emit()
	sysmsg.emit("Вас кикнули: " + reason)
