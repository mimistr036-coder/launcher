extends Node
## Работа «Курьер»: доехать по 3 точкам — получить деньги.

const TL := preload("res://br/texture_lib.gd")
const UTIL := preload("res://br/util.gd")

var world = null
var active := false
var points: Array = []
var idx := 0

var _marker: Node3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D


func _ready() -> void:
	_marker = Node3D.new()
	_marker.visible = false
	add_child(_marker)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy_multiplier = 1.5
	_ring = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.8
	cm.bottom_radius = 1.8
	cm.height = 0.25
	cm.material = mat
	_ring.mesh = cm
	_ring.position = Vector3(0, 0.15, 0)
	_marker.add_child(_ring)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.16)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.9
	bm.height = 16.0
	bm.material = beam_mat
	_beam.mesh = bm
	_beam.position = Vector3(0, 8, 0)
	_marker.add_child(_beam)


func toggle() -> void:
	if active:
		_stop("Работа отменена")
		return
	var src: Array = world.city.job_points
	if src.size() < 3:
		world.hud.notice("Работы пока нет")
		return
	points = []
	var pool := src.duplicate()
	var cur: Vector3 = world.player.global_position
	for i in range(3):
		var best_i := 0
		var best_d := INF
		for k in range(pool.size()):
			var d: float = pool[k].distance_to(cur)
			if d > 30.0 and d < best_d:
				best_d = d
				best_i = k
		points.append(pool[best_i])
		cur = pool[best_i]
		pool.remove_at(best_i)
	idx = 0
	active = true
	_marker.visible = true
	_marker.global_position = points[0]
	world.hud.notice("Работа: Курьер. Доставь 3 заказа по меткам (жёлтая точка на карте)!")
	world.hud.sys("Работа начата: точка 1/3")


func _stop(msg: String) -> void:
	active = false
	_marker.visible = false
	world.hud.notice(msg)


func _process(delta: float) -> void:
	if not active or world == null or world.player == null:
		return
	_ring.rotation.y += delta * 1.5
	var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.08
	_ring.scale = Vector3(s, 1, s)
	var p: Vector3 = world.player.global_position
	if world.player.current_car != null and is_instance_valid(world.player.current_car):
		p = world.player.current_car.global_position
	if p.distance_to(points[idx]) < 4.0:
		var reward := 150
		idx += 1
		if idx >= points.size():
			var total := 600 + randi() % 300
			UTIL.set_money(UTIL.get_money() + total)
			world.hud.update_money()
			_stop("Заказы доставлены! +₽%d" % total)
		else:
			_marker.global_position = points[idx]
			world.hud.sys("Точка %d/3 (+₽%d)" % [idx + 1, reward])
