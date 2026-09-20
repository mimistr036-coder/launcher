extends Node
## Сетевой узел сервера. Имя должно быть «Net» и путь /root/RP/Net —
## как у клиента (см. game/br/net.gd). Сигнатуры rpc_* синхронизированы!

var srv = null  # main.gd


func sender_id() -> int:
	return multiplayer.get_remote_sender_id()

# ---------- приём от клиентов ----------

@rpc("any_peer", "reliable")
func rpc_register(nick: String) -> void:
	if srv != null:
		srv.on_register(sender_id(), nick)


@rpc("any_peer", "unreliable")
func rpc_state(px: float, py: float, pz: float, ry: float, anim: int,
		car_id: int, cx: float, cy: float, cz: float, cry: float, ct: int) -> void:
	if srv != null:
		srv.on_state(sender_id(), px, py, pz, ry, anim, car_id, cx, cy, cz, cry, ct)


@rpc("any_peer", "reliable")
func rpc_chat(msg: String) -> void:
	if srv != null:
		srv.on_chat(sender_id(), msg)

# ---------- отправка клиентам ----------

@rpc("authority", "reliable")
func rpc_chat_msg(_sender_id: int, _nick: String, _msg: String) -> void:
	pass  # только сервер отправляет


@rpc("authority", "reliable")
func rpc_sysmsg(_text: String) -> void:
	pass


@rpc("authority", "unreliable")
func rpc_snapshot(_data: Dictionary) -> void:
	pass


@rpc("authority", "reliable")
func rpc_kick(_reason: String) -> void:
	pass
