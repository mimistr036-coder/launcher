extends CharacterBody3D
## Машина: аркадная физика, вход/выход игрока, фары. Сетевые прокси — та же сцена без физики.

var TL = load("res://br/texture_lib.gd")
var CT = load("res://br/car_types.gd")

var type_idx := 0
var paint_idx := 0
var driver = null               # player.gd (локальный) или null
var locked := false              # NPC-машины нельзя угнать
var display_name := "Машина"

var _wheel_pivots: Array = []    # [{pivot, mesh, front}]
var _head_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _spots: Array = []
var _steer_vis := 0.0
var _spin := 0.0
var _lights := false
var _braking := false
# машина под управлением другого игрока по сети
var remote_driven := false
var net_target := Vector3.INF
var net_yaw := 0.0


func setup(t: int, c: int) -> void:
	type_idx = t % CT.TYPES.size()
	paint_idx = c % CT.PAINTS.size()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var T: Dictionary = CT.TYPES[type_idx]
	var paint := TL.car_paint(CT.PAINTS[paint_idx])
	var glass := TL.car_glass()
	var dark := TL.flat(Color(0.09, 0.09, 0.11), 0.4, 0.5)
	var tire := TL.flat(Color(0.07, 0.07, 0.08), 0.0, 0.95)
	var body: Vector3 = T.body
	var cabin: Vector3 = T.cabin
	var wr: float = T.wheel_r
	var body_bottom := wr * 0.55
	var body_c := body_bottom + body.y * 0.5
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.9, 0.9, 0.8)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.95, 0.8)
	_head_mat.emission_energy_multiplier = 0.0
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.albedo_color = Color(0.5, 0.1, 0.08)
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.12, 0.08)
	_tail_mat.emission_energy_multiplier = 0.0
	_mkbox(body, paint, Vector3(0, body_c, 0))
	_mkbox(cabin, glass, Vector3(0, body_bottom + body.y + cabin.y * 0.5, T.cabin_z))
	_mkbox(Vector3(cabin.x * 0.98, 0.07, cabin.z * 0.98), paint,
		Vector3(0, body_bottom + body.y + cabin.y + 0.03, T.cabin_z))
	_mkbox(Vector3(0.28, 0.14, 0.08), _head_mat, Vector3(body.x * 0.32, body_c + body.y * 0.18, -body.z * 0.5 - 0.02))
	_mkbox(Vector3(0.28, 0.14, 0.08), _head_mat, Vector3(-body.x * 0.32, body_c + body.y * 0.18, -body.z * 0.5 - 0.02))
	_mkbox(Vector3(0.3, 0.13, 0.07), _tail_mat, Vector3(body.x * 0.32, body_c + body.y * 0.18, body.z * 0.5 + 0.02))
	_mkbox(Vector3(0.3, 0.13, 0.07), _tail_mat, Vector3(-body.x * 0.32, body_c + body.y * 0.18, body.z * 0.5 + 0.02))
	# колёса
	var wb: float = T.wheelbase
	for wp in [Vector3(T.track * 0.5, wr, -wb * 0.5), Vector3(-T.track * 0.5, wr, -wb * 0.5),
			Vector3(T.track * 0.5, wr, wb * 0.5), Vector3(-T.track * 0.5, wr, wb * 0.5)]:
		var pivot := Node3D.new()
		pivot.position = wp
		add_child(pivot)
		var inner := Node3D.new()
		inner.rotation.z = PI / 2.0
		pivot.add_child(inner)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = wr
		cm.bottom_radius = wr
		cm.height = 0.22
		cm.radial_segments = 10
		cm.material = tire
		mi.mesh = cm
		inner.add_child(mi)
		# диск
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = wr * 0.55
		hm.bottom_radius = wr * 0.55
		hm.height = 0.24
		hm.radial_segments = 8
		hm.material = TL.flat(Color(0.6, 0.6, 0.62), 0.8, 0.4)
		hub.mesh = hm
		inner.add_child(hub)
		_wheel_pivots.append({"pivot": pivot, "inner": inner, "front": wp.z < 0.0})
	# коллизия
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(body.x + 0.1, body.y + cabin.y + 0.3, body.z + 0.1)
	cs.shape = sh
	cs.position = Vector3(0, body_c + 0.2, 0)
	add_child(cs)
	display_name = T.name


func _mkbox(size: Vector3, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)


func set_lights(on: bool) -> void:
	if _lights == on:
		return
	_lights = on
	_head_mat.emission_energy_multiplier = 3.0 if on else 0.0
	_tail_mat.emission_energy_multiplier = 1.2 if on else 0.0
	if on and _spots.is_empty():
		var T: Dictionary = CT.TYPES[type_idx]
		for x in [T.body.x * 0.32, -T.body.x * 0.32]:
			var sp := SpotLight3D.new()
			sp.position = Vector3(x, 0.6, -T.body.z * 0.4)
			sp.rotation_degrees.x = -12
			sp.spot_range = 26.0
			sp.spot_angle = 34.0
			sp.light_energy = 1.6
			sp.light_color = Color(1.0, 0.95, 0.82)
			sp.shadow_enabled = false
			add_child(sp)
			_spots.append(sp)
	for sp in _spots:
		sp.visible = on


func car_input() -> Dictionary:
	if driver == null or not is_instance_valid(driver):
		return {"throttle": 0.0, "steer": 0.0, "handbrake": false}
	return driver.car_controls()


func _physics_process(delta: float) -> void:
	if remote_driven:
		if net_target.x != INF:
			global_position = global_position.lerp(net_target, 1.0 - pow(0.0001, delta))
			rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - pow(0.0001, delta))
		return
	var inp := {"throttle": 0.0, "steer": 0.0, "handbrake": false}
	var active := false
	if driver != null and is_instance_valid(driver):
		inp = car_input()
		active = true
	var T: Dictionary = CT.TYPES[type_idx]
	var maxs: float = T.max_speed
	var acc: float = T.accel
	var fwd := -transform.basis.z
	var v := velocity.dot(fwd)
	var floor_ok := is_on_floor()
	var th: float = inp.throttle
	var st: float = inp.steer
	var hb: bool = inp.handbrake
	_braking = th < 0.0 or hb
	if floor_ok:
		if th > 0.0:
			v = minf(v + acc * th * delta, maxs)
		elif th < 0.0:
			if v > 0.5:
				v = maxf(v + 24.0 * th * delta, 0.0)
			else:
				v = maxf(v + 7.5 * th * delta, -9.0)
		v -= v * 0.4 * delta
		if absf(v) < 0.05 and absf(th) < 0.01:
			v = 0.0
		if hb:
			v = move_toward(v, 0.0, 26.0 * delta)
		var sf := 2.0 * clampf(absf(v) / 6.0, 0.0, 1.0) * (1.0 - 0.5 * clampf(absf(v) / maxs, 0.0, 1.0))
		if hb:
			sf *= 1.35
		rotate_y(st * sf * delta * (1.0 if v >= 0.0 else -1.0))
		fwd = -transform.basis.z
		velocity = fwd * v
	else:
		velocity.y -= 16.0 * delta
		var hv := Vector3(velocity.x, 0, velocity.z)
		hv = hv.lerp(fwd * v, 1.0 - pow(0.2, delta))
		velocity.x = hv.x
		velocity.z = hv.z
	move_and_slide()
	# визуал колёс
	_spin += v * delta / maxf(T.wheel_r, 0.1)
	_steer_vis = lerpf(_steer_vis, st * 0.45, 10.0 * delta)
	for w in _wheel_pivots:
		w.inner.rotation.x = _spin
		if w.front:
			w.pivot.rotation.y = _steer_vis
	_tail_mat.emission_energy_multiplier = (1.2 if _lights else 0.0) + (2.5 if _braking else 0.0)


func honk() -> void:
	pass  # звук появится в следующей версии
