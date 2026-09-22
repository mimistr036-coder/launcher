extends RefCounted
## Процедурная модель человека (игроки): боксы + анимация ходьбы кодом.

const JACKETS := [Color(0.2, 0.25, 0.38), Color(0.16, 0.16, 0.17), Color(0.35, 0.28, 0.2),
	Color(0.22, 0.32, 0.24), Color(0.45, 0.45, 0.47), Color(0.5, 0.2, 0.2)]
const PANTS := [Color(0.15, 0.18, 0.3), Color(0.2, 0.2, 0.24), Color(0.3, 0.26, 0.2)]
const SKIN := [Color(0.85, 0.65, 0.5), Color(0.9, 0.72, 0.58), Color(0.72, 0.52, 0.38)]
# виды одежды: 0 куртка, 1 спортивки, 2 пуховик, 3 сигнальный жилет, 4 куртка+кепка, 5 худи
const TRACKSUIT := [Color(0.13, 0.2, 0.42), Color(0.35, 0.1, 0.12), Color(0.1, 0.3, 0.2), Color(0.2, 0.2, 0.22)]


static func build(variant: int = 0) -> Node3D:
	var TL = load("res://br/texture_lib.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var root := Node3D.new()
	root.name = "Model"
	var jacket = TL.flat(JACKETS[abs(variant) % JACKETS.size()])
	var pants = TL.flat(PANTS[abs(variant * 3 + 1) % PANTS.size()])
	var skin = TL.flat(SKIN[abs(variant * 7 + 2) % SKIN.size()])
	var shoe = TL.flat(Color(0.12, 0.12, 0.13))
	var hair = TL.flat(Color(0.16, 0.12, 0.08))
	var kind := wrapi(variant, 0, 6)
	var torso_sz := Vector3(0.44, 0.62, 0.26)
	if kind == 1:
		# спортивный костюм с полосками
		jacket = TL.stripes(TRACKSUIT[abs(variant * 5) % TRACKSUIT.size()])
		pants = TL.stripes(TRACKSUIT[abs(variant * 5 + 1) % TRACKSUIT.size()])
	elif kind == 2:
		# пуховик — широкий, яркий
		jacket = TL.flat([Color(0.75, 0.3, 0.15), Color(0.2, 0.45, 0.6), Color(0.6, 0.55, 0.2)][abs(variant) % 3])
		torso_sz = Vector3(0.56, 0.66, 0.34)
	elif kind == 3:
		jacket = TL.flat(Color(0.16, 0.17, 0.19))
	elif kind == 5:
		jacket = TL.flat([Color(0.25, 0.3, 0.42), Color(0.45, 0.25, 0.2), Color(0.3, 0.38, 0.3)][abs(variant) % 3])
	# торс
	_part(root, "Torso", torso_sz, jacket, Vector3(0, 1.23, 0))
	if kind == 3:
		# сигнальный жилет со светоотражающими полосами
		_part(root, "Vest", Vector3(0.5, 0.5, 0.31), TL.flat(Color(0.95, 0.5, 0.05)), Vector3(0, 1.28, 0))
		_part(root, "VestStripe1", Vector3(0.52, 0.07, 0.32), TL.flat(Color(0.85, 0.85, 0.85)), Vector3(0, 1.36, 0))
		_part(root, "VestStripe2", Vector3(0.52, 0.07, 0.32), TL.flat(Color(0.85, 0.85, 0.85)), Vector3(0, 1.18, 0))
	if kind == 4:
		# кепка с козырьком
		_part(root, "Cap", Vector3(0.28, 0.09, 0.28), TL.flat([Color(0.15, 0.3, 0.6), Color(0.05, 0.05, 0.05)][abs(variant) % 2]), Vector3(0, 1.86, 0))
		_part(root, "CapPeak", Vector3(0.24, 0.03, 0.16), TL.flat(Color(0.08, 0.08, 0.09)), Vector3(0, 1.82, -0.2))
	if kind == 5:
		# капюшон за головой
		_part(root, "Hood", Vector3(0.34, 0.3, 0.12), jacket, Vector3(0, 1.7, 0.17))
	if kind == 2:
		# швы пуховика
		_part(root, "Puff1", Vector3(0.58, 0.05, 0.36), TL.flat(Color(0.1, 0.1, 0.1)), Vector3(0, 1.36, 0))
		_part(root, "Puff2", Vector3(0.58, 0.05, 0.36), TL.flat(Color(0.1, 0.1, 0.1)), Vector3(0, 1.12, 0))
	_part(root, "Head", Vector3(0.24, 0.26, 0.24), skin, Vector3(0, 1.68, 0))
	_part(root, "Hair", Vector3(0.26, 0.1, 0.26), hair, Vector3(0, 1.82, 0))
	# руки (пивоты у плеч); у пуховика рукава толще
	var arm_sz := Vector3(0.13, 0.58, 0.15) if kind != 2 else Vector3(0.17, 0.58, 0.19)
	var arm_l := _pivot(root, "ArmL", Vector3(-0.29, 1.48, 0))
	_part(arm_l, "Mesh", arm_sz, jacket, Vector3(0, -0.29, 0))
	var hand_l := _part(arm_l, "Hand", Vector3(0.11, 0.12, 0.12), skin, Vector3(0, -0.62, 0))
	hand_l.name = "Hand"
	var arm_r := _pivot(root, "ArmR", Vector3(0.29, 1.48, 0))
	_part(arm_r, "Mesh", arm_sz, jacket, Vector3(0, -0.29, 0))
	_part(arm_r, "Hand", Vector3(0.11, 0.12, 0.12), skin, Vector3(0, -0.62, 0))
	# ноги (пивоты у бёдер)
	var leg_l := _pivot(root, "LegL", Vector3(-0.11, 0.92, 0))
	_part(leg_l, "Mesh", Vector3(0.17, 0.8, 0.19), pants, Vector3(0, -0.4, 0))
	_part(leg_l, "Foot", Vector3(0.17, 0.1, 0.26), shoe, Vector3(0, -0.84, 0.03))
	var leg_r := _pivot(root, "LegR", Vector3(0.11, 0.92, 0))
	_part(leg_r, "Mesh", Vector3(0.17, 0.8, 0.19), pants, Vector3(0, -0.4, 0))
	_part(leg_r, "Foot", Vector3(0.17, 0.1, 0.26), shoe, Vector3(0, -0.84, 0.03))
	root.set_meta("phase", 0.0)
	return root


static func _part(parent: Node3D, pname: String, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _pivot(parent: Node3D, pname: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	return n


## state: 0 idle, 1 walk, 2 run, 3 jump, 4 sit
static func animate(model: Node3D, state: int, dt: float) -> void:
	if model == null or not is_instance_valid(model):
		return
	var speed_factor := 0.0
	match state:
		1:
			speed_factor = 1.0
		2:
			speed_factor = 1.9
		3:
			speed_factor = 0.0
		_:
			speed_factor = 0.0
	var phase: float = model.get_meta("phase", 0.0)
	phase += dt * (2.4 + speed_factor * 4.0) * (1.0 if speed_factor > 0.0 else 0.0)
	model.set_meta("phase", phase)
	var swing := sin(phase) * 0.55 * minf(speed_factor, 1.2)
	var leg_l := model.get_node_or_null("LegL")
	var leg_r := model.get_node_or_null("LegR")
	var arm_l := model.get_node_or_null("ArmL")
	var arm_r := model.get_node_or_null("ArmR")
	if state == 4:  # сидя
		if leg_l != null:
			leg_l.rotation.x = -1.4
		if leg_r != null:
			leg_r.rotation.x = -1.4
		if arm_l != null:
			arm_l.rotation.x = -0.9
		if arm_r != null:
			arm_r.rotation.x = -0.9
		return
	if leg_l != null:
		leg_l.rotation.x = swing
	if leg_r != null:
		leg_r.rotation.x = -swing
	if arm_l != null:
		arm_l.rotation.x = -swing * 0.8
	if arm_r != null:
		arm_r.rotation.x = swing * 0.8
	if state == 3:  # прыжок — ноги поджаты
		if leg_l != null:
			leg_l.rotation.x = 0.5
		if leg_r != null:
			leg_r.rotation.x = -0.3
