extends "res://br/vehicle.gd"
## NPC-машина: ездит по правой полосе сетки дорог, тормозит перед препятствиями.

const CB := preload("res://br/city_builder.gd")

var axis := "x"
var line := 3
var dir := 1
var world: Node = null

var _next_check := 0.0
var _slow := 0.0
var _last_turn_pos := Vector3.INF


func configure_npc(ax: String, ln: int, d: int, t: float) -> void:
	axis = ax
	line = ln
	dir = d
	locked = true


func _ready() -> void:
	super._ready()
	# ставим на полосу
	var lane := _lane_pos()
	if axis == "x":
		global_position = Vector3(lane.x, 0.2, lane.z)
		rotation.y = 0.0 if dir > 0 else PI
	else:
		global_position = Vector3(lane.x, 0.2, lane.z)
		rotation.y = -PI / 2.0 if dir > 0 else PI / 2.0


func _lane_pos() -> Vector3:
	# правостороннее движение
	if axis == "x":
		return Vector3(_t(), 0.0, CB.line_coord(line) + 2.7 * dir)
	var lc := _t()
	return Vector3(CB.line_coord(line) - 2.7 * dir, 0.0, lc)


func _t() -> float:
	if axis == "x":
		return global_position.x
	return global_position.z


func _physics_process(delta: float) -> void:
	if driver != null and is_instance_valid(driver):
		super._physics_process(delta)
		return
	# препятствие впереди?
	var desired_speed := 8.0
	var ahead := _scan_ahead()
	if ahead:
		desired_speed = 0.0
	var fwd := -transform.basis.z
	var v := velocity.dot(fwd)
	# целевое направление по полосе
	var lane := _lane_pos()
	var cross := 0.0
	if axis == "x":
		cross = (lane.z - global_position.z) * dir
	else:
		cross = (lane.x - global_position.x) * (-dir)
	var target_yaw := rotation.y - clampf(cross * 0.12, -0.5, 0.5)
	# держимся дороги: на перекрёстке можем повернуть
	_maybe_turn()
	var yaw_err := wrapf(target_yaw - rotation.y, -PI, PI)
	var inp := {"throttle": 0.0, "steer": clampf(yaw_err * 1.6, -1.0, 1.0), "handbrake": false}
	if v < desired_speed:
		inp.throttle = 1.0 if desired_speed > 0.5 else 0.0
	elif v > desired_speed + 1.0:
		inp.throttle = -0.7
	# стабильная аркадная модель (упрощённая копия vehicle)
	var T: Dictionary = CT.TYPES[type_idx]
	var maxs: float = T.max_speed
	var acc: float = T.accel
	var floor_ok := is_on_floor()
	var th: float = inp.throttle
	var st: float = inp.steer
	if floor_ok:
		if th > 0.0:
			v = minf(v + acc * th * delta, minf(maxs, 9.0))
		elif th < 0.0:
			v = maxf(v + 22.0 * th * delta, 0.0)
		v -= v * 0.4 * delta
		if ahead:
			v = move_toward(v, 0.0, 30.0 * delta)
		var sf := 2.0 * clampf(absf(v) / 6.0, 0.0, 1.0)
		rotate_y(st * sf * delta * (1.0 if v >= 0.0 else -1.0))
		fwd = -transform.basis.z
		velocity = fwd * v
	else:
		velocity.y -= 16.0 * delta
	move_and_slide()
	_spin += v * delta / maxf(T.wheel_r, 0.1)
	for w in _wheel_pivots:
		w.inner.rotation.x = _spin


func _scan_ahead() -> bool:
	var fwd := -transform.basis.z
	var p := global_position + fwd * 2.0
	if world == null:
		return false
	var others: Array = world.cars + world.npcs
	for c in others:
		if c == self or not is_instance_valid(c):
			continue
		var d: Vector3 = c.global_position - global_position
		var df := d.dot(fwd)
		if df > 1.0 and df < 7.5 and absf(d.cross(fwd).length()) < 2.2:
			return true
	if world.player != null and is_instance_valid(world.player):
		var d2: Vector3 = world.player.global_position - global_position
		var df2 := d2.dot(fwd)
		if world.player.current_car == null and df2 > 0.5 and df2 < 7.0 and d2.cross(fwd).length() < 2.0:
			return true
	return false


func _maybe_turn() -> void:
	# на перекрёстке с вероятностью поворачиваем
	for k in range(CB.GRID + 1):
		var lc := CB.line_coord(k)
		var along := global_position.x if axis == "x" else global_position.z
		if absf(along - lc) < 0.6:
			if rng_turn():
				var new_axis := "z" if axis == "x" else "x"
				var new_line := k
				var new_dir := 1 if randf() < 0.5 else -1
				axis = new_axis
				line = new_line
				dir = new_dir
				var target_yaw := 0.0
				if axis == "x":
					target_yaw = 0.0 if dir > 0 else PI
				else:
					target_yaw = -PI / 2.0 if dir > 0 else PI / 2.0
				rotation.y = target_yaw
			return


func rng_turn() -> bool:
	# 35% шанс поворота на перекрёстке
	return randf() < 0.35
