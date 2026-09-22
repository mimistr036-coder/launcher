extends Node3D
## Генератор города «Провинцинск»: геометрия, коллизии, миникарта, точки спавна.
## Вся генерация детерминирована (фиксированный сид) — у всех игроков город одинаковый.
## Хочешь изменить город — крути константы ниже или функции block_*().

const P := 110.0        # шаг сетки (ширина блока + дорога)
const ROAD_W := 12.0    # ширина асфальта
const WALK_W := 3.0     # ширина тротуара
const GRID := 7         # блоков по каждой стороне (7x7)
const HALF := GRID * P * 0.5

var TL = load("res://br/texture_lib.gd")

const SEED := 26092026

var rng := RandomNumberGenerator.new()

# Результаты генерации (читает world.gd)
var car_spawns: Array = []        # {pos: Vector3, rot: float, type: int, color: int}
var npc_spawns: Array = []        # {axis: "x"/"z", line: int, dir: int, t: float, type: int}
var job_points: Array = []        # Vector3 — цели курьера
var map_img: Image                # картинка для миникарты
var spawn_point := Vector3.ZERO
var traffic_mats := {}            # {"ns_r": mat, ...} — маты лампочек светофоров

var _st: Dictionary = {}          # Material -> SurfaceTool
var _colbody: StaticBody3D
var _rects: Array = []            # прямоугольники зданий для миникарты
var _tree_pts: Array = []         # точки занятые деревьями
var _sign_count := 0

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

const SHOP_NAMES := ["ПРОДУКТЫ 24", "ЦВЕТЫ", "КАФЕ «ЛУЧ»", "ЛОМБАРД", "ХОЗ. ТОВАРЫ", "ПИЦЦЕРИЯ", "ЗООМАГАЗИН", "АТТЕЛЬЕ"]

# Типы особых кварталов
const BT_DEFAULT := 0
const BT_PLAZA := 1
const BT_SCHOOL := 2
const BT_GAS := 3
const BT_SHOP := 4
const BT_PHARM := 5
const BT_PARK := 6
const BT_GARAGES := 7
const BT_MOTOPARK := 8
const BT_VILLAGE := 9   # частный сектор (модели Kenney, CC0)
const ML = "res://br/model_lib.gd"
const BT_CLINIC := 9


static func line_coord(i: int) -> float:
	return -HALF + P * i


func block_type(i: int, j: int) -> int:
	if i == 3 and j == 3:
		return BT_PLAZA
	# кирпичный центр вокруг площади
	if absi(i - 3) + absi(j - 3) == 1:
		return BT_DEFAULT
	if i == 1 and j == 1:
		return BT_SCHOOL
	if i == 5 and j == 2:
		return BT_GAS
	if i == 2 and j == 5:
		return BT_SHOP
	if i == 4 and j == 1:
		return BT_PHARM
	if i == 5 and j == 5:
		return BT_PARK
	if i == 1 and j == 5:
		return BT_GARAGES
	if i == 3 and j == 5:
		return BT_MOTOPARK
	if i == 0 and j == 3:
		return BT_CLINIC
	# частный сектор по краям карты
	if (i == 6 and j == 6) or (i == 0 and j == 6) or (i == 6 and j == 0):
		return BT_VILLAGE
	return BT_DEFAULT


## Район города: влияет на этажность и материал домов
func district_of(i: int, j: int) -> String:
	var t := block_type(i, j)
	if t != BT_DEFAULT:
		return "special"
	if absi(i - 3) + absi(j - 3) == 1:
		return "center"   # кирпичный центр
	var d := maxi(absi(i - 3), absi(j - 3))
	if d <= 2:
		return "mid"      # панельные 9-12 эт
	return "edge"         # хрущёвки 5 эт


func build() -> void:
	rng.seed = SEED
	_colbody = StaticBody3D.new()
	_colbody.name = "Colliders"
	add_child(_colbody)
	_ground_and_roads()
	_blocks()
	_lamps_and_lights()
	_npc_defs()
	_finalize_meshes()
	_minimap()
	spawn_point = Vector3(line_coord(3) + 24.0, 0.15, line_coord(3) + 16.0)

# =================== ПРИМИТИВЫ ===================

# SurfaceTool не имеет get_vertex_count() — считаем вершины сами
var _st_verts: Dictionary = {}    # SurfaceTool -> int

func _st_for(mat: Material) -> SurfaceTool:
	var st: SurfaceTool = _st.get(mat)
	if st != null and int(_st_verts.get(st, 0)) >= MAX_SURF_VERTS:
		# поверхность распухла — отдаём готовый меш и начинаем новую
		var n := 0
		for ch in get_children():
			if ch.name.begins_with("Geo"):
				n = maxi(n, int(ch.name.trim_prefix("Geo")))
		_flush_surface(mat, st, n + 1)
		st = null
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return st


func _quad(st: SurfaceTool, pts: Array, normal: Vector3, uvs: Array) -> void:
	# 4 вершины + 2 треугольника (порядок вершин — по часовой снаружи, как принято в Godot)
	# ВАЖНО: индексы отсчитываются от вершин ЭТОЙ поверхности (commit() обнуляет нумерацию)
	for k in range(4):
		st.set_normal(normal)
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])
	_st_verts[st] = int(_st_verts.get(st, 0)) + 4
	var b: int = int(_st_verts[st]) - 4
	st.add_index(b)
	st.add_index(b + 1)
	st.add_index(b + 2)
	st.add_index(b)
	st.add_index(b + 2)
	st.add_index(b + 3)


func _box(mat: Material, center: Vector3, size: Vector3, face_uv: bool = false, uv_scale: float = 4.0, top_mat: Material = null) -> void:
	var half := size * 0.5
	var normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n in normals:
		# ВАЖНО: abs()! у отрицательных нормалей max_axis_index без abs даёт неверную ось
		var a: int = n.abs().max_axis_index()
		# крыша отдельным материалом (у фасадных домов)
		var st := _st_for(top_mat if (n.y > 0 and top_mat != null) else mat)
		var ui := (a + 1) % 3
		var vi := (a + 2) % 3
		var u: Vector3 = AXES[ui]
		var v: Vector3 = AXES[vi]
		if n[a] < 0:
			var tmp: Vector3 = u
			u = v
			v = tmp
			var t2 := ui
			ui = vi
			vi = t2
		var hu := half[ui]
		var hv := half[vi]
		var face_c: Vector3 = center + n * half[a]
		var pts := [
			face_c - u * hu - v * hv,
			face_c + u * hu - v * hv,
			face_c + u * hu + v * hv,
			face_c - u * hu + v * hv,
		]
		var uvs := []
		if face_uv:
			uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		else:
			for c in pts:
				uvs.append(Vector2(u.dot(c - center), v.dot(c - center)) / uv_scale)
		_quad(st, pts, n, uvs)


func _cyl(mat: Material, base: Vector3, r_bottom: float, r_top: float, h: float, segs: int = 6) -> void:
	var st := _st_for(mat)
	var prev_sin := 0.0
	var prev_cos := 1.0
	for s in range(segs + 1):
		var ang := TAU * float(s) / float(segs)
		var sn := sin(ang)
		var cs := cos(ang)
		if s > 0:
			var n := Vector3((sn + prev_sin) * 0.5, 0.0, (cs + prev_cos) * 0.5).normalized()
			var pts := [
				base + Vector3(prev_cos * r_bottom, 0.0, prev_sin * r_bottom),
				base + Vector3(cs * r_bottom, 0.0, sn * r_bottom),
				base + Vector3(cs * r_top, h, sn * r_top),
				base + Vector3(prev_cos * r_top, h, prev_sin * r_top),
			]
			var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			if r_top <= 0.001:
				pts[2] = base + Vector3(0.0, h, 0.0)
				pts[3] = base + Vector3(0.0, h, 0.0)
			_quad(st, pts, n, uvs)
		prev_sin = sn
		prev_cos = cs


## Бордюр мешает только машинам (слой 8) — пешеходы свободно переступают
func _col_box_l8(center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 8
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	b.add_child(cs)
	add_child(b)


## Пандус-въезд на тротуар/двор (наклонный бокс, слой 8)
func _ramp_l8(center: Vector3, size: Vector3, along_x: bool) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 8
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	if along_x:
		cs.rotation.x = deg_to_rad(3.9)
	else:
		cs.rotation.z = deg_to_rad(-3.9)
	b.add_child(cs)
	add_child(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = TL.flat(Color(0.62, 0.62, 0.60))
	mi.mesh = bm
	mi.position = center
	if along_x:
		mi.rotation.x = deg_to_rad(3.9)
	else:
		mi.rotation.z = deg_to_rad(-3.9)
	add_child(mi)


func _col_box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	_colbody.add_child(cs)


func _col_cyl(base: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = base + Vector3(0, h * 0.5, 0)
	_colbody.add_child(cs)


const MAX_SURF_VERTS := 60000  # 16-битные индексы: не превышать 65536 вершин на поверхность

func _finalize_meshes() -> void:
	var idx := 0
	for mat in _st:
		idx = _flush_surface(mat, _st[mat], idx)


func _flush_surface(mat: Material, st: SurfaceTool, idx: int) -> int:
	_st_verts.erase(st)
	var mesh := st.commit()
	if mesh != null:
		mesh.surface_set_material(0, mat)  # БЕЗ ЭТОГО ВЕСЬ ГОРОД БЕЛЫЙ
		var mi := MeshInstance3D.new()
		mi.name = "Geo%d" % idx
		idx += 1
		mi.mesh = mesh
		add_child(mi)
	return idx


func _sign(text: String, pos: Vector3, height_m: float = 0.9, color: Color = Color(1, 0.9, 0.5)) -> void:
	if _sign_count >= 20:
		return
	_sign_count += 1
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = height_m / 48.0
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.05, 0.08)
	l.outline_size = 14
	l.position = pos
	l.name = "Sign%d" % _sign_count
	add_child(l)

# =================== ЗЕМЛЯ И ДОРОГИ ===================

func _ground_and_roads() -> void:
	var grass = TL.ground("grass")
	var asph = TL.ground("asphalt")
	var L := 2.0 * HALF + ROAD_W
	var gsize := L + 120.0
	# земля до горизонта — город не «плавает в пустоте»
	_box(grass, Vector3(0, -0.26, 0), Vector3(900, 0.2, 900))
	# сплошной пол-коллизия: верх на уровне дороги (дорога НИЖЕ тротуара на 15 см)
	_col_box(Vector3(0, -0.575, 0), Vector3(gsize, 0.85, gsize))
	# трава вокруг города (верх на уровне тротуара y=0)
	_box(grass, Vector3(0, -0.1, -HALF - ROAD_W * 0.5 - 30.0), Vector3(gsize, 0.2, 60.0))
	_box(grass, Vector3(0, -0.1, HALF + ROAD_W * 0.5 + 30.0), Vector3(gsize, 0.2, 60.0))
	_box(grass, Vector3(-HALF - ROAD_W * 0.5 - 30.0, -0.1, 0), Vector3(60.0, 0.2, L))
	_box(grass, Vector3(HALF + ROAD_W * 0.5 + 30.0, -0.1, 0), Vector3(60.0, 0.2, L))
	# вертикальные дороги (проезжая часть на 15 см ниже тротуара)
	for i in range(GRID + 1):
		_box(asph, Vector3(line_coord(i), -0.25, 0), Vector3(ROAD_W, 0.2, L), false, 2.5)
	# горизонтальные дороги (сегменты между вертикальными)
	for j in range(GRID + 1):
		var z := line_coord(j)
		for i in range(GRID):
			var x0 := line_coord(i) + ROAD_W * 0.5
			var x1 := line_coord(i + 1) - ROAD_W * 0.5
			_box(asph, Vector3((x0 + x1) * 0.5, -0.25, z), Vector3(x1 - x0, 0.2, ROAD_W), false, 2.5)
	# разметка (визуал, без коллизии)
	var white = TL.flat(Color(0.85, 0.85, 0.82))
	for i in [0, 3, 7]:
		var x := line_coord(i)
		var z2 := -HALF + 5.0
		while z2 < HALF:
			if _away_from_lines(z2):
				_box(white, Vector3(x, -0.14, z2), Vector3(0.3, 0.02, 3.5))
			z2 += 10.0
	for j2 in [0, 3, 7]:
		var zz := line_coord(j2)
		var xx := -HALF + 5.0
		while xx < HALF:
			if _away_from_lines(xx):
				_box(white, Vector3(xx, -0.14, zz), Vector3(3.5, 0.02, 0.3))
			xx += 10.0
	# зебры на внутренних перекрёстках
	for i3 in range(2, 6):
		for j3 in range(2, 6):
			var xi := line_coord(i3)
			var zj := line_coord(j3)
			for side in [-1.0, 1.0]:
				var zc: float = zj + side * (ROAD_W * 0.5 + 2.2)
				for k in range(-2, 3):
					_box(white, Vector3(xi + k * 1.4, -0.14, zc), Vector3(0.7, 0.02, 3.0))
	# дорожные знаки «пешеходный переход» у некоторых зебр
	for i6 in [2, 4]:
		for j6 in [2, 4]:
			var sx := line_coord(i6)
			var szc := line_coord(j6)
			_road_sign(Vector3(sx + ROAD_W * 0.5 + 1.8, 0, szc - ROAD_W * 0.5 - 3.0))
			_road_sign(Vector3(sx - ROAD_W * 0.5 - 1.8, 0, szc + ROAD_W * 0.5 + 3.0))
	# бордюры: бетон от дна дороги (-0.15) до верха тротуара (+0.02), коллизия для машин,
	# в середине каждого сегмента — пандус-въезд во двор
	var curb = TL.flat(Color(0.62, 0.62, 0.60))
	var edge := ROAD_W * 0.5 + 0.25
	var pad := ROAD_W * 0.5 + 0.9
	var GAP := 4.2
	for i4 in range(GRID + 1):
		var lx := line_coord(i4)
		for side4 in [-1.0, 1.0]:
			for j4 in range(GRID):
				var z0 := line_coord(j4) + pad
				var z1 := line_coord(j4 + 1) - pad
				if z1 - z0 < 8.0:
					continue
				var zm: float = (z0 + z1) * 0.5
				var half: float = (z1 - z0) * 0.5 - GAP * 0.5
				for sgn in [-1.0, 1.0]:
					var c: float = zm + sgn * (GAP * 0.5 + half * 0.5)
					_box(curb, Vector3(lx + side4 * edge, -0.065, c), Vector3(0.4, 0.17, half))
					_col_box_l8(Vector3(lx + side4 * edge, -0.065, c), Vector3(0.4, 0.17, half))
				_ramp_l8(Vector3(lx + side4 * edge, -0.08, zm), Vector3(0.45, 0.16, GAP + 0.6), false)
	for j5 in range(GRID + 1):
		var lz := line_coord(j5)
		for side5 in [-1.0, 1.0]:
			for i5 in range(GRID):
				var x0 := line_coord(i5) + pad
				var x1 := line_coord(i5 + 1) - pad
				if x1 - x0 < 8.0:
					continue
				var xm: float = (x0 + x1) * 0.5
				var half2: float = (x1 - x0) * 0.5 - GAP * 0.5
				for sgn2 in [-1.0, 1.0]:
					var c2: float = xm + sgn2 * (GAP * 0.5 + half2 * 0.5)
					_box(curb, Vector3(c2, -0.065, lz + side5 * edge), Vector3(half2, 0.17, 0.4))
					_col_box_l8(Vector3(c2, -0.065, lz + side5 * edge), Vector3(half2, 0.17, 0.4))
				_ramp_l8(Vector3(xm, -0.08, lz + side5 * edge), Vector3(GAP + 0.6, 0.16, 0.45), true)

func _away_from_lines(t: float) -> bool:
	for j in range(GRID + 1):
		if absf(t - line_coord(j)) < ROAD_W * 0.5 + 3.0:
			return false
	return true

# =================== КВАРТАЛЫ ===================

func _block_area(i: int, j: int) -> Dictionary:
	return {
		"x0": line_coord(i) + ROAD_W * 0.5, "x1": line_coord(i + 1) - ROAD_W * 0.5,
		"z0": line_coord(j) + ROAD_W * 0.5, "z1": line_coord(j + 1) - ROAD_W * 0.5,
	}


func _blocks() -> void:
	for i in range(GRID):
		for j in range(GRID):
			var area := _block_area(i, j)
			var t := block_type(i, j)
			var walk = TL.ground("walk")
			var w := WALK_W
			_box(walk, Vector3((area.x0 + area.x1) * 0.5, -0.1, area.z0 + w * 0.5),
				Vector3(area.x1 - area.x0, 0.2, w))
			_box(walk, Vector3((area.x0 + area.x1) * 0.5, -0.1, area.z1 - w * 0.5),
				Vector3(area.x1 - area.x0, 0.2, w))
			_box(walk, Vector3(area.x0 + w * 0.5, -0.1, (area.z0 + area.z1) * 0.5),
				Vector3(w, 0.2, area.z1 - area.z0 - 2.0 * w))
			_box(walk, Vector3(area.x1 - w * 0.5, -0.1, (area.z0 + area.z1) * 0.5),
				Vector3(w, 0.2, area.z1 - area.z0 - 2.0 * w))
			var cx0: float = area.x0 + w
			var cx1: float = area.x1 - w
			var cz0: float = area.z0 + w
			var cz1: float = area.z1 - w
			var cc := Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5)
			var cs := Vector3(cx1 - cx0, 0.2, cz1 - cz0)
			_col_box(cc, cs)  # тротуар/двор выше дороги — машины заезжают только по пандусам
			match t:
				BT_PLAZA:
					_block_plaza(cx0, cx1, cz0, cz1)
				BT_SCHOOL:
					_block_school(cx0, cx1, cz0, cz1)
				BT_GAS:
					_block_gas(cx0, cx1, cz0, cz1)
				BT_SHOP:
					_block_shop(cx0, cx1, cz0, cz1)
				BT_PHARM:
					_block_pharm(cx0, cx1, cz0, cz1)
				BT_PARK:
					_block_park(cx0, cx1, cz0, cz1)
				BT_GARAGES:
					_block_garages(cx0, cx1, cz0, cz1)
				BT_MOTOPARK:
					_block_motopark(cx0, cx1, cz0, cz1)
				BT_CLINIC:
					_block_clinic(cx0, cx1, cz0, cz1)
				BT_VILLAGE:
					_block_village(cx0, cx1, cz0, cz1)
				_:
					_block_default(cx0, cx1, cz0, cz1, district_of(i, j))

# ---------- жилой квартал ----------

func _block_default(cx0: float, cx1: float, cz0: float, cz1: float, district: String = "mid") -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var rects: Array = []
	var pal: int = rng.randi() % 6  # палитра квартала — дома в одном тоне
	var arch := rng.randi() % 5
	if district == "center":
		arch = rng.randi() % 2 + 4  # perimeter или «лицом к лицу» — сплошной центр
	if arch == 0:
		# классический микрорайон: 1-2 дома на каждой стороне периметра
		for side in range(4):
			if rng.randf() < 0.1:
				continue  # пустая сторона — там двор с деревьями
			var along0: float = cx0 if side < 2 else cz0
			var along1: float = cx1 if side < 2 else cz1
			var cursor := along0 + rng.randf() * 8.0
			var n := 1 if rng.randf() < 0.55 else 2
			for k in range(n):
				var room := along1 - 6.0 - cursor
				if room < 26.0:
					break
				var frac := 1.0 if n == 1 else rng.randf_range(0.45, 0.62)
				var wq := _qw(room * frac)
				if wq < 20.0 or cursor + wq > along1 - 6.0:
					break
				_house(cursor, wq, side, cx0, cx1, cz0, cz1, pal, 0, district)
				if district == "center" and rng.randf() < 0.45:
					# крыло во двор — П-образный план дома
					var wing_fl: int = [5, 6, 6, 7][rng.randi() % 4]
					if side < 2:
						_house(cz0 + 13.0, _qw((cz1 - cz0) * 0.5), 2, cx0, cx1, cz0, cz1, pal, wing_fl, district)
					else:
						_house(cx0 + 13.0, _qw((cx1 - cx0) * 0.5), 0, cx0, cx1, cz0, cz1, pal, wing_fl, district)
				cursor += wq + 4.0 + rng.randf() * 6.0
	elif arch == 1:
		# башни во дворе
		for k in range(2):
			var wq := _qw(rng.randf_range(17.0, 25.0))
			if wq < 14.0 or wq > cx1 - cx0 - 12.0:
				continue
			var floors: int = [9, 12, 14, 16][rng.randi() % 4]
			if district == "edge":
				floors = [9, 12][rng.randi() % 2]
			var px: float = rng.randf_range(cx0 + wq * 0.5 + 6.0, cx1 - wq * 0.5 - 6.0)
			var pz: float = rng.randf_range(cz0 + wq * 0.5 + 6.0, cz1 - wq * 0.5 - 6.0)
			var h := floors * 2.8 + 0.9
			var cols: int = clampi(roundi(wq / 4.0), 4, 12)
			var mat = TL.facade(cols, floors, (pal + k) % 6)
			_building(Vector3(px, h * 0.5, pz), Vector3(wq, h, wq * rng.randf_range(0.65, 0.9)), mat, floors, rng.randi() % 4)
	elif arch == 2:
		# «колодец»: одинаковые дома по всем четырём сторонам
		var floors: int = [5, 9][rng.randi() % 2]
		if district == "center":
			floors = [6, 7][rng.randi() % 2]
		elif district == "edge":
			floors = 5
		for side in range(4):
			var along0: float = cx0 if side < 2 else cz0
			var along1: float = cx1 if side < 2 else cz1
			var wq := _qw((along1 - along0) - 14.0)
			_house(along0 + 7.0, wq, side, cx0, cx1, cz0, cz1, pal, floors, district)
	elif arch == 3:
		# длинный дом через весь квартал + башня
		var side := rng.randi() % 4
		var along0: float = cx0 if side < 2 else cz0
		var along1: float = cx1 if side < 2 else cz1
		_house(along0 + 6.0, _qw(along1 - along0 - 12.0), side, cx0, cx1, cz0, cz1, pal)
		var wq2 := _qw(rng.randf_range(15.0, 20.0))
		var px: float = rng.randf_range(cx0 + wq2 * 0.5 + 8.0, cx1 - wq2 * 0.5 - 8.0)
		var pz: float = rng.randf_range(cz0 + wq2 * 0.5 + 8.0, cz1 - wq2 * 0.5 - 8.0)
		var fl2: int = [9, 12, 14][rng.randi() % 3]
		if district == "edge":
			fl2 = 9
		var h2 := fl2 * 2.8 + 0.9
		var mat2 = TL.facade(clampi(roundi(wq2 / 4.0), 4, 12), fl2, (pal + 3) % 6)
		_building(Vector3(px, h2 * 0.5, pz), Vector3(wq2, h2, wq2 * 0.8), mat2, fl2, rng.randi() % 4)
	else:
		# пары домов «лицом к лицу» через двор
		var side_a := rng.randi() % 4
		var side_b := (side_a + 2) % 4
		for side in [side_a, side_b]:
			var along0: float = cx0 if side < 2 else cz0
			var along1: float = cx1 if side < 2 else cz1
			_house(along0 + 6.0, _qw(along1 - along0 - 12.0), side, cx0, cx1, cz0, cz1, pal, 0, district)
	_courtyard(cx0, cx1, cz0, cz1, rects)
	# киоск у угла квартала
	if district != "village" and rng.randf() < 0.4:
		var ki := rng.randi() % 4
		var kp := Vector3(cx0 + 5.0, 0, cz0 + 9.0)
		if ki == 1:
			kp = Vector3(cx1 - 5.0, 0, cz1 - 9.0)
		elif ki == 2:
			kp = Vector3(cx1 - 9.0, 0, cz0 + 5.0)
		_kiosk(kp, ki, KIOSK_NAMES[rng.randi() % KIOSK_NAMES.size()])
	if job_points.size() < 26:
		job_points.append(Vector3(rng.randf_range(cx0 + 15, cx1 - 15), 0.1, rng.randf_range(cz0 + 15, cz1 - 15)))


## Дом вдоль стороны квартала (cursor — начало вдоль стороны)
func _house(cursor: float, wq: float, side: int, cx0: float, cx1: float, cz0: float, cz1: float, pal: int, force_floors: int = 0, district: String = "mid") -> void:
	if wq < 18.0:
		return
	var floors: int = force_floors
	if floors <= 0:
		if district == "center":
			floors = [6, 7, 7, 8, 9][rng.randi() % 5]
		elif district == "mid":
			floors = [9, 9, 12, 12, 14][rng.randi() % 5]
		else:
			floors = [5, 5, 5, 5, 9][rng.randi() % 5]
	var depth: float = [14.0, 16.0, 18.0][rng.randi() % 3]
	var h := floors * 2.8 + 0.9
	var cols: int = clampi(roundi(wq / 4.0), 4, 12)
	var mat
	if district == "center":
		mat = TL.facade_brick(cols, floors, (pal + rng.randi() % 2) % 4)
	else:
		mat = TL.facade(cols, floors, (pal + rng.randi() % 2) % 6)
	var pos: Vector3
	var sz: Vector3
	if side == 0:
		pos = Vector3(cursor + wq * 0.5, h * 0.5, cz0 + depth * 0.5)
		sz = Vector3(wq, h, depth)
	elif side == 1:
		pos = Vector3(cursor + wq * 0.5, h * 0.5, cz1 - depth * 0.5)
		sz = Vector3(wq, h, depth)
	elif side == 2:
		pos = Vector3(cx0 + depth * 0.5, h * 0.5, cursor + wq * 0.5)
		sz = Vector3(depth, h, wq)
	else:
		pos = Vector3(cx1 - depth * 0.5, h * 0.5, cursor + wq * 0.5)
		sz = Vector3(depth, h, wq)
	# ступенчатый объём: высокие дома — два смежных объёма разной высоты
	if floors >= 9 and wq >= 34 and rng.randf() < 0.65:
		var wa := _qw(wq * rng.randf_range(0.52, 0.62))
		var wb := wq - wa - 4.0
		if wb >= 20.0:
			var fb: int = floors - [2, 3, 4][rng.randi() % 3]
			var h_b: float = fb * 2.8 + 0.9
			var matb
			if district == "center":
				matb = TL.facade_brick(clampi(roundi(wb / 4.0), 4, 12), fb, (pal + 2) % 4)
			else:
				matb = TL.facade(clampi(roundi(wb / 4.0), 4, 12), fb, (pal + 2) % 6)
			var off_a: float = -(wq - wa) * 0.5
			var off_b: float = -wq * 0.5 + wa + 4.0 + wb * 0.5
			if side == 0 or side == 1:
				_building(pos + Vector3(off_a, 0, 0), Vector3(wa, h, sz.z), mat, floors, side)
				_building(pos + Vector3(off_b, (h_b - h) * 0.5, 0), Vector3(wb, h_b, sz.z), matb, fb, side)
			else:
				_building(pos + Vector3(0, 0, off_a), Vector3(sz.x, h, wa), mat, floors, side)
				_building(pos + Vector3(0, (h_b - h) * 0.5, off_b), Vector3(sz.x, h_b, wb), matb, fb, side)
			return
	_building(pos, sz, mat, floors, side)


func _qw(v: float) -> float:
	return maxf(20.0, float(roundi(v / 4.0)) * 4.0)


func _building(pos: Vector3, sz: Vector3, mat: Material, floors: int, side: int) -> void:
	var roof = TL.roof_mat()
	# стены с фасадной текстурой, крыша — рулонная с гравием
	_box(mat, pos, sz, true, 4.0, roof)
	_rects.append({"x": pos.x - sz.x * 0.5, "z": pos.z - sz.z * 0.5, "w": sz.x, "d": sz.z})
	# цоколь: тёмный пояс высотой 1 м, чуть шире дома
	var base_m = TL.flat(Color(0.34, 0.33, 0.31))
	var by := 0.5
	if side == 0 or side == 1:
		_box(base_m, Vector3(pos.x, by, pos.z), Vector3(sz.x + 0.3, 1.0, sz.z + 0.3), false, 4.0, roof)
	else:
		_box(base_m, Vector3(pos.x, by, pos.z), Vector3(sz.x + 0.3, 1.0, sz.z + 0.3), false, 4.0, roof)
	# карниз под парапетом: тёмная полоса по периметру
	_box(TL.flat(Color(0.30, 0.30, 0.32)), Vector3(pos.x, sz.y - 0.25, pos.z),
		Vector3(sz.x + 0.45, 0.5, sz.z + 0.45), false, 4.0, roof)
	# парапет по краю крыши
	_box(TL.flat(Color(0.42, 0.42, 0.45)), Vector3(pos.x, sz.y + 0.35, pos.z),
		Vector3(sz.x + 0.35, 0.5, sz.z + 0.35), false, 4.0, roof)
	# лифтовая будка и вентшахты
	if floors >= 5:
		_box(TL.flat(Color(0.52, 0.53, 0.55)), Vector3(pos.x + rng.randf_range(-sz.x * 0.2, sz.x * 0.2),
				sz.y + 1.15, pos.z + rng.randf_range(-sz.z * 0.2, sz.z * 0.2)), Vector3(3.2, 1.6, 2.6), false, 4.0, roof)
		_box(TL.flat(Color(0.45, 0.46, 0.48)), Vector3(pos.x - sz.x * 0.28, sz.y + 0.55, pos.z + sz.z * 0.22),
			Vector3(1.3, 0.9, 1.3))
	if floors >= 9 and rng.randf() < 0.7:
		_cyl(TL.flat(Color(0.3, 0.3, 0.33)), Vector3(pos.x + sz.x * 0.25, sz.y + 0.5, pos.z - sz.z * 0.2), 0.05, 0.03, 6.0, 4)
	# ориентация уличного фасада
	var out := Vector3(0, 0, -1)
	if side == 1: out = Vector3(0, 0, 1)
	elif side == 2: out = Vector3(-1, 0, 0)
	elif side == 3: out = Vector3(1, 0, 0)
	var along_w: float = sz.x if side < 2 else sz.z
	var out_d: float = sz.z if side < 2 else sz.x
	# лестничная клетка: остеклённая полоса во всю высоту
	if floors >= 5 and rng.randf() < 0.65:
		var sg = TL.flat(Color(0.5, 0.56, 0.62), 0.35, 0.4)
		var soff := along_w * 0.3
		if side < 2:
			_box(sg, pos + out * (out_d * 0.5 + 0.06) + Vector3(soff, sz.y * 0.5 + 0.3, 0), Vector3(2.4, sz.y - 3.0, 0.14))
		else:
			_box(sg, pos + out * (out_d * 0.5 + 0.06) + Vector3(0, sz.y * 0.5 + 0.3, soff), Vector3(0.14, sz.y - 3.0, 2.4))
	# балконы на уличном фасаде
	if floors >= 5 and rng.randf() < 0.85:
		var n := clampi(int(along_w / 9.0), 2, 5)
		var balc = TL.flat(Color(0.75, 0.74, 0.71))
		var rail = TL.flat(Color(0.5, 0.52, 0.56))
		for k in range(n):
			var f: int = 2 + int(float(k) * float(maxi(floors - 3, 1)) / float(n))
			var t := (float(k) + 0.5) / float(n) - 0.5
			var bp := pos + out * (out_d * 0.5 + 0.62) + Vector3(0, f * 2.8 + 0.12, 0)
			var bs := Vector3(1.15, 0.16, 2.5)
			if side < 2:
				bp.x += along_w * t
				bs = Vector3(2.5, 0.16, 1.15)
			else:
				bp.z += along_w * t
			_box(balc, bp, bs)
			var rs := Vector3(2.5, 1.0, 0.09)
			if side < 2:
				rs = Vector3(0.09, 1.0, 1.15)
			_box(rail, bp + out * 0.5 + Vector3(0, 0.55, 0), rs)
		# эркер-лента: остекление выступом на левой трети фасада
		if floors >= 5 and rng.randf() < 0.45 and along_w >= 24.0:
			var bw := along_w * 0.26
			var bh := (floors - 1) * 2.8 - 1.0
			var glass = TL.flat(Color(0.30, 0.40, 0.50), 0.5, 0.35)
			var tpos: Vector3
			var tsz: Vector3
			var tc := pos + out * (out_d * 0.5 + 0.3) + Vector3(0, 1.6 + bh * 0.5, 0)
			if side < 2:
				tpos = tc + Vector3(-along_w * 0.26, 0, 0)
				tsz = Vector3(bw, bh, 0.9)
			else:
				tpos = tc + Vector3(0, 0, -along_w * 0.26)
				tsz = Vector3(0.9, bh, bw)
			_box(glass, tpos, tsz)
			# крышка эркера
			var cap := pos + out * (out_d * 0.5 + 0.42) + Vector3(0, 1.6 + bh + 0.12, 0)
			if side < 2:
				_box(TL.flat(Color(0.5, 0.5, 0.53)), cap + Vector3(-along_w * 0.26, 0, 0), Vector3(bw + 0.4, 0.22, 1.2))
			else:
				_box(TL.flat(Color(0.5, 0.5, 0.53)), cap + Vector3(0, 0, -along_w * 0.26), Vector3(1.2, 0.22, bw + 0.4))
		# козырёк над подъездом: по центру уличного фасада
		var cp := pos + out * (out_d * 0.5 + 0.75) + Vector3(0, 2.65, 0)
		var csz := Vector3(3.4, 0.14, 1.8)
		if side >= 2:
			csz = Vector3(1.8, 0.14, 3.4)
		_box(TL.canopy_mat(), cp, csz)
		# стойки козырька
		for sx in [-1.0, 1.0]:
			var pp := cp + out * 0.5 + Vector3(0, -1.25, 0)
			if side < 2:
				pp.x += sx * 1.3
				_box(TL.flat(Color(0.35, 0.36, 0.38), 0.5, 0.5), pp, Vector3(0.09, 2.5, 0.09))
			else:
				pp.z += sx * 1.3
				_box(TL.flat(Color(0.35, 0.36, 0.38), 0.5, 0.5), pp, Vector3(0.09, 2.5, 0.09))
	_col_box(pos, sz)
	# вывеска/магазин на первом этаже (только к улице)
	if floors >= 5 and rng.randf() < 0.3:
		var sw = TL.shop_window()
		var spos: Vector3
		var ssz: Vector3
		if side == 0:
			spos = pos + Vector3(0, 1.6, -sz.z * 0.5 - 0.12)
			ssz = Vector3(sz.x - 3.0, 3.0, 0.2)
		elif side == 1:
			spos = pos + Vector3(0, 1.6, sz.z * 0.5 + 0.12)
			ssz = Vector3(sz.x - 3.0, 3.0, 0.2)
		elif side == 2:
			spos = pos + Vector3(-sz.x * 0.5 - 0.12, 1.6, 0)
			ssz = Vector3(0.2, 3.0, sz.z - 3.0)
		else:
			spos = pos + Vector3(sz.x * 0.5 + 0.12, 1.6, 0)
			ssz = Vector3(0.2, 3.0, sz.z - 3.0)
		_box(sw, spos, ssz, true)
		var col := Color(1.0, 0.85, 0.4) if rng.randf() < 0.5 else Color(0.6, 0.9, 1.0)
		var so: Vector3 = spos
		if side == 0:
			so.z -= 0.2
		elif side == 1:
			so.z += 0.2
		elif side == 2:
			so.x -= 0.2
		else:
			so.x += 0.2
		_sign(SHOP_NAMES[rng.randi() % SHOP_NAMES.size()], so + Vector3(0, 2.7, 0), 0.8, col)


func _courtyard(cx0: float, cx1: float, cz0: float, cz1: float, rects: Array) -> void:
	for t in range(rng.randi_range(5, 11)):
		var p := _yard_point(cx0 + 5, cx1 - 5, cz0 + 5, cz1 - 5, rects, 3.0)
		if p.x != INF:
			if rng.randf() < 0.35:
				_birch(p)
			else:
				_tree(p)
	for b in range(rng.randi_range(1, 3)):
		var bp := _yard_point(cx0 + 6, cx1 - 6, cz0 + 6, cz1 - 6, rects, 2.0)
		if bp.x != INF:
			_bench_fixed(bp, rng.randf() * TAU)
	for tr in range(rng.randi_range(1, 2)):
		var tp := _yard_point(cx0 + 4, cx1 - 4, cz0 + 4, cz1 - 4, rects, 1.5)
		if tp.x != INF:
			_cyl(TL.flat(Color(0.25, 0.3, 0.25)), tp, 0.35, 0.3, 1.1, 6)
	if rng.randf() < 0.45:
		var pad_c := _yard_point(cx0 + 16, cx1 - 16, cz0 + 12, cz1 - 12, rects, 0.0)
		if pad_c.x != INF:
			_box(TL.ground("asphalt"), pad_c + Vector3(0, 0.015, 0), Vector3(24, 0.02, 13))
			for k in range(rng.randi_range(3, 5)):
				if rng.randf() < 0.6:
					car_spawns.append({"pos": pad_c + Vector3(-8 + k * 4.5, 0, rng.randf_range(-3, 3)),
						"rot": 90.0 + rng.randf_range(-8, 8), "type": rng.randi() % 4, "color": rng.randi() % 6})
	if rng.randf() < 0.3:
		var gx := rng.randf_range(cx0 + 14, cx1 - 40)
		var gz := rng.randf_range(cz0 + 12, cz1 - 12)
		var gcol: Color = [Color(0.5, 0.3, 0.2), Color(0.35, 0.42, 0.5), Color(0.55, 0.5, 0.4)][rng.randi() % 3]
		for g in range(6):
			_garage(Vector3(gx + g * 6.2, 0, gz), gcol)
	# забор-профлист вокруг части двора
	if rng.randf() < 0.5:
		var fx0 := cx0 + rng.randf_range(8, 14)
		var fz0 := cz0 + rng.randf_range(8, 14)
		var fx1 := fx0 + rng.randf_range(30, minf(cx1 - fx0 - 4, 55))
		var fz1 := fz0 + rng.randf_range(24, minf(cz1 - fz0 - 4, 45))
		if fx1 > fx0 + 16 and fz1 > fz0 + 14:
			_fence_proflist(fx0, fz0, fx1, fz1)
	# кусты вдоль домов
	for bsh in range(rng.randi_range(3, 7)):
		var bsp := _yard_point(cx0 + 4, cx1 - 4, cz0 + 4, cz1 - 4, rects, 2.2)
		if bsp.x != INF:
			var bcol := Color(0.22, 0.38, 0.18) * (0.85 + rng.randf() * 0.3)
			_box(TL.flat(bcol), bsp + Vector3(0, 0.35, 0), Vector3(rng.randf_range(0.9, 1.6), 0.7, rng.randf_range(0.9, 1.6)))
	# лужайка с деревьями (модель Kenney, CC0)
	if rng.randf() < 0.35:
		var lp := _yard_point(cx0 + 14, cx1 - 14, cz0 + 14, cz1 - 14, rects, 1.0)
		if lp.x != INF:
			var tile = load(ML).spawn("res://models/grass-trees.glb", rng.randf_range(5.5, 7.0), false)
			if tile != null:
				tile.position = lp + Vector3(0, 0.03, 0)
				tile.rotation.y = rng.randf() * TAU
				add_child(tile)


## Забор из профлиста с воротами
func _fence_proflist(x0: float, z0: float, x1: float, z1: float) -> void:
	var m = TL.proflist([Color("4a6a8a"), Color("5a705a"), Color("7a6a5a"), Color("6a6f75")][rng.randi() % 4])
	var pm = TL.flat(Color(0.3, 0.3, 0.32), 0.5, 0.6)
	var h := 2.1
	var gap_side := rng.randi() % 4
	for side in range(4):
		var a := Vector3(x0, 0, z0)
		var b := Vector3(x1, 0, z0)
		if side == 1: b = Vector3(x1, 0, z1)
		elif side == 2: a = Vector3(x1, 0, z1)
		elif side == 3: b = Vector3(x0, 0, z1)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
		if side == gap_side:
			# проём 4 м в центре стороны
			var half := (len - 4.0) * 0.5
			var dir := (b - a).normalized()
			for seg in [-1.0, 1.0]:
				var c1: Vector3 = mid + dir * (2.0 + half * 0.5) * seg
				var sz := Vector3(half, h, 0.08)
				if not horizontal:
					sz = Vector3(0.08, h, half)
				_box(m, c1 + Vector3(0, h * 0.5, 0), sz)
		else:
			var sz2 := Vector3(len, h, 0.08)
			if not horizontal:
				sz2 = Vector3(0.08, h, len)
			_box(m, mid + Vector3(0, h * 0.5, 0), sz2)
		# столбы по углам стороны
		for e in [a, b]:
			_box(pm, e + Vector3(0, h * 0.5 + 0.15, 0), Vector3(0.14, h + 0.3, 0.14))


func _yard_point(x0: float, x1: float, z0: float, z1: float, rects: Array, margin: float) -> Vector3:
	for attempt in range(12):
		var p := Vector3(rng.randf_range(x0, x1), 0, rng.randf_range(z0, z1))
		var clear := true
		for r in rects:
			if p.x > r.x - margin and p.x < r.x + r.w + margin and p.z > r.z - margin and p.z < r.z + r.d + margin:
				clear = false
				break
		if clear:
			for tp in _tree_pts:
				if tp.distance_to(p) < 4.5:
					clear = false
					break
		if clear:
			_tree_pts.append(p)
			return p
	return Vector3.INF

# ---------- уличные объекты ----------

func _tree(p: Vector3) -> void:
	_cyl(TL.wood(), p, 0.22, 0.16, 2.2, 5)
	_cyl(TL.foliage(rng.randi() % 3), p + Vector3(0, 1.4, 0), 1.7, 0.1, 3.2, 6)
	_cyl(TL.foliage(rng.randi() % 3), p + Vector3(0, 3.4, 0), 1.15, 0.05, 1.8, 6)
	_col_cyl(p, 0.28, 3.0)


## Берёза: белый ствол в чёрную крапинку, светлая листва
func _birch(p: Vector3) -> void:
	_cyl(TL.birch(), p, 0.17, 0.12, 3.4, 5)
	_cyl(TL.foliage(rng.randi() % 3), p + Vector3(0, 2.2, 0), 1.35, 0.08, 3.0, 6)
	_col_cyl(p, 0.22, 3.0)


## Киоск у дороги: «ШАУРМА», «ЦВЕТЫ» и т.д.
const KIOSK_NAMES := ["ШАУРМА", "ЦВЕТЫ", "ОВОЩИ", "КОФЕ", "ПЕЧАТЬ", "ЖЕМЧУЖИНКА"]

func _kiosk(p: Vector3, rot_i: int, kname: String) -> void:
	var col: Color = [Color("c2503c"), Color("3c6ac2"), Color("3ca05a"), Color("c2923c")][rot_i % 4]
	var m = TL.flat(col)
	_box(m, p + Vector3(0, 1.35, 0), Vector3(3.2, 2.7, 2.4))
	# окно выдачи на фронт (+z локально)
	var front := Vector3(0, 0, 1)
	if rot_i % 2 == 1:
		front = Vector3(1, 0, 0) if rot_i == 1 else Vector3(-1, 0, 0)
	elif rot_i == 2:
		front = Vector3(0, 0, -1)
	var fp := p + front * 1.23 + Vector3(0, 1.3, 0)
	var fsz := Vector3(2.0, 0.9, 0.08)
	if absf(front.x) > 0.5:
		fsz = Vector3(0.08, 0.9, 2.0)
	_box(TL.flat(Color(0.15, 0.2, 0.25)), fp, fsz)
	# крыша-козырёк
	_box(TL.flat(col.darkened(0.35)), p + Vector3(0, 2.85, 0), Vector3(3.7, 0.3, 2.9))
	# вывеска
	var sp := p + front * 1.3 + Vector3(0, 3.4, 0)
	_sign(kname, sp, 0.62, Color(1, 0.95, 0.7))
	_col_box(p + Vector3(0, 1.35, 0), Vector3(3.2, 2.7, 2.4))


## Дорожный знак «пешеходный переход»
func _road_sign(p: Vector3) -> void:
	_cyl(TL.flat(Color(0.6, 0.62, 0.65), 0.7, 0.4), p, 0.05, 0.04, 2.8, 5)
	# синий квадрат с белой каймой
	var plate = TL.flat(Color(0.16, 0.35, 0.75))
	_box(plate, p + Vector3(0, 2.55, 0), Vector3(0.66, 0.66, 0.05))
	_box(TL.flat(Color(0.92, 0.92, 0.92)), p + Vector3(0, 2.55, -0.03), Vector3(0.4, 0.3, 0.02))
	_col_cyl(p, 0.08, 2.8)


func _bench_fixed(p: Vector3, ang: float) -> void:
	var wood = TL.wood()
	var metal = TL.flat(Color(0.35, 0.36, 0.4), 0.6, 0.5)
	var ca := cos(ang)
	var sa := sin(ang)
	var right := Vector3(ca, 0, sa)
	var fwd := Vector3(-sa, 0, ca)
	for part in [[Vector3(0, 0.45, 0), Vector3(1.8, 0.07, 0.5), wood],
			[Vector3(0, 0.75, -0.22), Vector3(1.8, 0.5, 0.07), wood],
			[Vector3(-0.75, 0.22, 0), Vector3(0.08, 0.45, 0.45), metal],
			[Vector3(0.75, 0.22, 0), Vector3(0.08, 0.45, 0.45), metal]]:
		var off: Vector3 = part[0]
		var sz: Vector3 = part[1]
		var roff := Vector3(off.dot(right), off.y, off.dot(fwd))
		var rsz := Vector3(sz.dot(right), sz.y, sz.dot(fwd))
		_box(part[2], p + roff, rsz)


func _garage(p: Vector3, col: Color) -> void:
	var m = TL.flat(col)
	_box(m, p + Vector3(0, 1.5, 0), Vector3(6.0, 3.0, 4.6))
	_box(TL.shutter(), p + Vector3(0, 1.2, 2.32), Vector3(4.6, 2.4, 0.08))
	_col_box(p + Vector3(0, 1.5, 0), Vector3(6.0, 3.0, 4.6))

## Частный сектор: домики Kenney City Kit (CC0) с заборами
func _block_village(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var homes := ["res://models/building-small-a.glb", "res://models/building-small-b.glb",
		"res://models/building-small-c.glb", "res://models/building-small-d.glb", "res://models/building-garage.glb"]
	var pw := 28.0
	var ph := 30.0
	var cols := 3
	var rows := 3
	var mstart := Vector3((cx0 + cx1) * 0.5 - pw * cols * 0.5, 0, (cz0 + cz1) * 0.5 - ph * rows * 0.5)
	for r in range(rows):
		for c in range(cols):
			var cellc := mstart + Vector3(pw * (c + 0.5), 0, ph * (r + 0.5))
			if rng.randf() < 0.12:
				continue  # пустой участок
			var path: String = homes[rng.randi() % homes.size()]
			var hm = load(ML).spawn(path, rng.randf_range(5.2, 6.8), true)
			if hm == null:
				continue
			hm.position = cellc + Vector3(rng.randf_range(-3, 3), 0.05, rng.randf_range(-3, 3))
			hm.rotation.y = (PI * 0.5 * rng.randi_range(0, 3)) + rng.randf_range(-0.1, 0.1)
			add_child(hm)
			_rects.append({"x": hm.position.x - 5, "z": hm.position.z - 5, "w": 10, "d": 10})
			# заборчик участка с проёмом к улице
			_fence_proflist(cellc.x - pw * 0.5 + 2.0, cellc.z - ph * 0.5 + 2.0,
				cellc.x + pw * 0.5 - 2.0, cellc.z + ph * 0.5 - 2.0)
			if rng.randf() < 0.5:
				_tree(cellc + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-9, 9)))
	if job_points.size() < 26:
		job_points.append(Vector3((cx0 + cx1) * 0.5, 0.1, (cz0 + cz1) * 0.5))


# ---------- особые кварталы ----------

func _block_plaza(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("plaza"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var m := Vector3((cx0 + cx1) * 0.5, 0, (cz0 + cz1) * 0.5)
	# фонтан — модель Kenney City Kit (CC0), загрузка в рантайме
	var ftn = load(ML).spawn("res://models/pavement-fountain.glb", 5.5, true)
	if ftn != null:
		ftn.position = m + Vector3(0, 0.05, 0)
		add_child(ftn)
	else:
		var stone = TL.flat(Color(0.5, 0.5, 0.52))
		_box(stone, m + Vector3(0, 0.6, 0), Vector3(5, 1.2, 5))
		_box(stone, m + Vector3(0, 1.8, 0), Vector3(3, 1.2, 3))
	_col_box(m + Vector3(0, 1, 0), Vector3(5, 2, 5))
	_rects.append({"x": m.x - 2.5, "z": m.z - 2.5, "w": 5, "d": 5})
	for k in range(8):
		var a := TAU * k / 8.0
		_bench_fixed(m + Vector3(cos(a) * 11, 0, sin(a) * 11), a + PI * 0.5)
	for k in range(4):
		var a2 := TAU * k / 4.0 + 0.4
		var fp := m + Vector3(cos(a2) * 17, 0, sin(a2) * 17)
		_box(TL.ground("grass"), fp + Vector3(0, 0.02, 0), Vector3(3.4, 0.06, 3.4))
		for f in range(5):
			_box(TL.flat([Color(0.9, 0.3, 0.3), Color(0.95, 0.8, 0.2), Color(0.9, 0.5, 0.8)][f % 3]),
				fp + Vector3(rng.randf_range(-1.2, 1.2), 0.2, rng.randf_range(-1.2, 1.2)), Vector3(0.25, 0.35, 0.25))
	job_points.append(m + Vector3(6, 0.1, 6))
	job_points.append(m + Vector3(-8, 0.1, -8))


func _block_school(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var mat = TL.facade(9, 3, 1)
	var h := 3 * 3.2 + 0.9
	var zc := cz0 + 18.0
	var mcx := (cx0 + cx1) * 0.5
	var parts := [
		[Vector3(mcx, h * 0.5, zc), Vector3(36, h, 14)],
		[Vector3(cx0 + 10, h * 0.5, zc + 12), Vector3(14, h, 14)],
		[Vector3(cx1 - 10, h * 0.5, zc + 12), Vector3(14, h, 14)],
	]
	for pb in parts:
		_box(mat, pb[0], pb[1], true)
		_col_box(pb[0], pb[1])
		_rects.append({"x": pb[0].x - pb[1].x * 0.5, "z": pb[0].z - pb[1].z * 0.5, "w": pb[1].x, "d": pb[1].z})
	_sign("ШКОЛА №7", Vector3(mcx, h + 1.3, zc - 7.2), 1.1, Color(0.5, 0.85, 1.0))
	_box(TL.ground("asphalt"), Vector3(mcx, -0.085, cz0 + 7), Vector3(46, 0.03, 10))
	car_spawns.append({"pos": Vector3(mcx - 12, 0, cz0 + 7), "rot": 90, "type": 1, "color": 3})
	car_spawns.append({"pos": Vector3(mcx + 12, 0, cz0 + 7), "rot": 90, "type": 2, "color": 0})
	# забор с проездом по центру
	var fence = TL.flat(Color(0.45, 0.4, 0.35))
	_box(fence, Vector3(mcx, 0.55, cz0 + 1.5), Vector3(24, 1.1, 0.12))
	_box(fence, Vector3(mcx, 0.55, cz1 - 1.5), Vector3(cx1 - cx0 - 4, 1.1, 0.12))
	_box(fence, Vector3(cx0 + 1.5, 0.55, (cz0 + cz1) * 0.5), Vector3(0.12, 1.1, cz1 - cz0 - 4))
	_box(fence, Vector3(cx1 - 1.5, 0.55, (cz0 + cz1) * 0.5), Vector3(0.12, 1.1, cz1 - cz0 - 4))
	for t in range(6):
		var p := _yard_point(cx0 + 6, cx1 - 6, cz0 + 36, cz1 - 6, [], 2.0)
		if p.x != INF:
			_tree(p)


func _block_gas(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("asphalt"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var m := Vector3((cx0 + cx1) * 0.5, 0, (cz0 + cz1) * 0.5 + 8)
	var roof = TL.flat(Color(0.85, 0.3, 0.2))
	for px in [-8.0, 8.0]:
		for pz in [-4.0, 4.0]:
			_box(TL.flat(Color(0.4, 0.4, 0.45), 0.5, 0.4), m + Vector3(px, 2.5, pz), Vector3(0.4, 5.0, 0.4))
			_col_box(m + Vector3(px, 2.5, pz), Vector3(0.4, 5.0, 0.4))
	_box(roof, m + Vector3(0, 5.2, 0), Vector3(20, 0.4, 12))
	for px in [-5.0, 5.0]:
		_box(TL.flat(Color(0.85, 0.25, 0.2)), m + Vector3(px, 0.7, 0), Vector3(0.8, 1.4, 0.5))
		_box(TL.flat(Color(0.1, 0.1, 0.12)), m + Vector3(px, 1.0, 0.28), Vector3(0.5, 0.35, 0.06))
		_col_box(m + Vector3(px, 0.7, 0), Vector3(0.8, 1.4, 0.5))
	var kmat = TL.facade(4, 1, 0)
	_box(kmat, Vector3(cx1 - 10, 1.6, cz0 + 8), Vector3(7, 3.2, 5), true)
	_col_box(Vector3(cx1 - 10, 1.6, cz0 + 8), Vector3(7, 3.2, 5))
	_sign("АЗС", m + Vector3(0, 7.2, 0), 1.6, Color(1, 0.35, 0.25))
	car_spawns.append({"pos": m + Vector3(-3, 0, -2), "rot": 0, "type": 0, "color": 1})
	car_spawns.append({"pos": m + Vector3(3, 0, -2), "rot": 0, "type": 3, "color": 4})
	job_points.append(Vector3(cx0 + 14, 0.1, cz1 - 14))


func _block_shop(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var h := 5.2
	var m := Vector3((cx0 + cx1) * 0.5, h * 0.5, cz1 - 12)
	_box(TL.facade(7, 1, 2), m, Vector3(30, h, 18), true)
	_box(TL.flat(Color(0.25, 0.26, 0.3)), m + Vector3(0, h + 0.15, 0), Vector3(30.6, 0.3, 18.6))
	_col_box(m, Vector3(30, h, 18))
	_rects.append({"x": m.x - 15, "z": m.z - 9, "w": 30, "d": 18})
	_sign("ПРОДУКТЫ 24", Vector3(m.x, h + 1.4, m.z - 9.2), 1.3, Color(1, 0.8, 0.3))
	var pz := cz0 + 12.0
	_box(TL.ground("asphalt"), Vector3(m.x, -0.085, pz), Vector3(34, 0.03, 16))
	for k in range(6):
		if rng.randf() < 0.7:
			car_spawns.append({"pos": Vector3(m.x - 12 + k * 5, 0, pz + rng.randf_range(-3, 3)),
				"rot": 90 + rng.randf_range(-10, 10), "type": rng.randi() % 4, "color": rng.randi() % 6})
	job_points.append(Vector3(m.x, 0.1, m.z - 11))
	for t in range(4):
		var p := _yard_point(cx0 + 6, cx1 - 6, cz0 + 24, cz1 - 24, [{"x": m.x - 15, "z": cz0 + 3, "w": 30, "d": 18}], 3.0)
		if p.x != INF:
			_tree(p)


func _block_pharm(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var h := 4.6
	var m := Vector3((cx0 + cx1) * 0.5, h * 0.5, cz0 + 12)
	_box(TL.facade(4, 1, 0), m, Vector3(18, h, 14), true)
	_box(TL.flat(Color(0.25, 0.26, 0.3)), m + Vector3(0, h + 0.15, 0), Vector3(18.5, 0.3, 14.5))
	_col_box(m, Vector3(18, h, 14))
	_rects.append({"x": m.x - 9, "z": m.z - 7, "w": 18, "d": 14})
	_sign("АПТЕКА", Vector3(m.x, h + 1.3, m.z - 7.2), 1.1, Color(0.4, 1.0, 0.55))
	job_points.append(Vector3(m.x + 3, 0.1, m.z - 9))
	_courtyard(cx0 + 10, cx1 - 4, cz0 + 24, cz1 - 6, [{"x": m.x - 9, "z": m.z - 7, "w": 18, "d": 14}])


func _block_park(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var m := Vector3((cx0 + cx1) * 0.5, 0, (cz0 + cz1) * 0.5)
	_box(TL.water(), m + Vector3(-12, 0.04, 10), Vector3(16, 0.08, 11))
	for k in range(8):
		var a := TAU * k / 8.0
		_box(TL.flat(Color(0.45, 0.45, 0.48)), m + Vector3(-12 + cos(a) * 8.6, 0.05, 10 + sin(a) * 5.8),
			Vector3(rng.randf_range(0.6, 1.2), 0.25, rng.randf_range(0.6, 1.2)))
	var pond := {"x": m.x - 20, "z": m.z + 4, "w": 16, "d": 12}
	for t in range(20):
		var p := _yard_point(cx0 + 5, cx1 - 5, cz0 + 5, cz1 - 5, [pond], 2.5)
		if p.x != INF:
			if rng.randf() < 0.4:
				_birch(p)
			else:
				_tree(p)
	# поляны с деревьями (модели Kenney, CC0)
	for t2 in range(5):
		var p2 := _yard_point(cx0 + 10, cx1 - 10, cz0 + 10, cz1 - 10, [pond], 3.0)
		if p2.x != INF:
			var tmodel = "res://models/grass-trees-tall.glb" if rng.randf() < 0.5 else "res://models/grass-trees.glb"
			var tile2 = load(ML).spawn(tmodel, rng.randf_range(6.0, 8.0), false)
			if tile2 != null:
				tile2.position = p2 + Vector3(0, 0.03, 0)
				tile2.rotation.y = rng.randf() * TAU
				add_child(tile2)
	for b in range(6):
		var bp := _yard_point(cx0 + 8, cx1 - 8, cz0 + 8, cz1 - 8, [pond], 2.0)
		if bp.x != INF:
			_bench_fixed(bp, rng.randf() * TAU)
	job_points.append(m + Vector3(14, 0.1, -14))
	job_points.append(m + Vector3(0, 0.1, 0))


func _block_garages(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("dirt"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var zm := (cz0 + cz1) * 0.5
	for row in range(2):
		var z := zm - 9.0 + row * 18.0
		for g in range(8):
			var gx := cx0 + 8 + g * 10.0
			var col: Color = [Color(0.45, 0.3, 0.2), Color(0.3, 0.4, 0.5), Color(0.5, 0.5, 0.42), Color(0.35, 0.35, 0.38)][g % 4]
			_garage(Vector3(gx, 0, z), col)
			if rng.randf() < 0.3:
				car_spawns.append({"pos": Vector3(gx + 3, 0, z + (4.5 if row == 0 else -4.5)),
					"rot": 90.0 + (0 if row == 0 else 180) + rng.randf_range(-15, 15),
					"type": rng.randi() % 4, "color": rng.randi() % 6})
	job_points.append(Vector3(cx0 + 12, 0.1, zm))


func _block_motopark(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("asphalt"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var m := Vector3((cx0 + cx1) * 0.5, 2.6, cz0 + 10)
	_box(TL.flat(Color(0.4, 0.45, 0.5), 0.4, 0.6), m, Vector3(26, 5.2, 13))
	_box(TL.flat(Color(0.3, 0.33, 0.38)), m + Vector3(0, 5.4, 0), Vector3(26.6, 0.3, 13.6))
	_col_box(m, Vector3(26, 5.2, 13))
	_rects.append({"x": m.x - 13, "z": m.z - 6.5, "w": 26, "d": 13})
	_sign("АВТОПАРК", Vector3(m.x, 6.6, m.z - 6.7), 1.0, Color(0.9, 0.9, 0.6))
	for k in range(8):
		car_spawns.append({"pos": Vector3(cx0 + 12 + (k % 4) * 14.0, 0, cz1 - 14 - float(k / 4) * 7.0),
			"rot": 90 + (0 if k < 4 else 180) + rng.randf_range(-6, 6),
			"type": rng.randi() % 4, "color": rng.randi() % 6})
	job_points.append(Vector3(cx1 - 10, 0.1, cz1 - 10))


func _block_clinic(cx0: float, cx1: float, cz0: float, cz1: float) -> void:
	_box(TL.ground("grass"), Vector3((cx0 + cx1) * 0.5, -0.1, (cz0 + cz1) * 0.5),
		Vector3(cx1 - cx0, 0.2, cz1 - cz0))
	var floors := 9
	var h := floors * 2.8 + 0.9
	var m := Vector3((cx0 + cx1) * 0.5, h * 0.5, cz1 - 14)
	_box(TL.facade(8, floors, 1), m, Vector3(30, h, 18), true)
	_box(TL.flat(Color(0.25, 0.26, 0.3)), m + Vector3(0, h + 0.15, 0), Vector3(30.5, 0.3, 18.5))
	_col_box(m, Vector3(30, h, 18))
	_rects.append({"x": m.x - 15, "z": m.z - 9, "w": 30, "d": 18})
	_sign("ПОЛИКЛИНИКА №1", Vector3(m.x, h + 1.3, m.z - 9.2), 1.0, Color(0.55, 1.0, 0.6))
	var pz := cz0 + 10.0
	_box(TL.ground("asphalt"), Vector3(m.x, -0.085, pz), Vector3(26, 0.03, 12))
	car_spawns.append({"pos": Vector3(m.x - 6, 0, pz), "rot": 90, "type": 1, "color": 2})
	car_spawns.append({"pos": Vector3(m.x + 6, 0, pz), "rot": 90, "type": 0, "color": 5})
	job_points.append(Vector3(m.x, 0.1, m.z - 11))
	for t in range(5):
		var p := _yard_point(cx0 + 6, cx1 - 6, cz0 + 22, cz1 - 22, [{"x": m.x - 15, "z": m.z - 9, "w": 30, "d": 18}], 3.0)
		if p.x != INF:
			_tree(p)

# =================== УЛИЧНОЕ ===================

func _lamp(p: Vector3, pole: Material, head: Material, along_z: bool) -> void:
	var arm := Vector3(-0.9, 6.3, 0)
	var head_off := Vector3(-1.7, 6.05, 0)
	var arm_sz := Vector3(1.9, 0.12, 0.12)
	var head_sz := Vector3(0.7, 0.18, 0.3)
	if along_z:
		arm = Vector3(0, 6.3, -0.9)
		head_off = Vector3(0, 6.05, -1.7)
		arm_sz = Vector3(0.12, 0.12, 1.9)
		head_sz = Vector3(0.3, 0.18, 0.7)
	_box(pole, p + Vector3(0, 3.2, 0), Vector3(0.14, 6.4, 0.14))
	_box(pole, p + arm, arm_sz)
	_box(head, p + head_off, head_sz)


func _lamps_and_lights() -> void:
	var pole = TL.flat(Color(0.32, 0.33, 0.36), 0.6, 0.5)
	var head = TL.night_mat(Color(1.0, 0.85, 0.55), 2.4)
	for i in [0, 3, 7]:
		var x := line_coord(i)
		var z := -HALF + 20.0
		var side := 1.0
		while z < HALF:
			if _away_from_lines(z):
				_lamp(Vector3(x + side * (ROAD_W * 0.5 + 0.7), 0, z), pole, head, false)
				side = -side
			z += 44.0
	for j in [0, 3, 7]:
		var zz := line_coord(j)
		var xx := -HALF + 30.0
		var side2 := 1.0
		while xx < HALF:
			if _away_from_lines(xx):
				_lamp(Vector3(xx, 0, zz + side2 * (ROAD_W * 0.5 + 0.7)), pole, head, true)
				side2 = -side2
			xx += 44.0
	traffic_mats = {
		"ns_r": TL.night_mat(Color(1, 0.15, 0.1), 2.2),
		"ns_y": TL.night_mat(Color(1, 0.75, 0.1), 2.2),
		"ns_g": TL.night_mat(Color(0.1, 1, 0.25), 2.2),
		"ew_r": TL.night_mat(Color(1, 0.15, 0.1), 2.2),
		"ew_y": TL.night_mat(Color(1, 0.75, 0.1), 2.2),
		"ew_g": TL.night_mat(Color(0.1, 1, 0.25), 2.2),
	}
	for i2 in range(2, 6):
		for j2 in range(2, 6):
			_traffic_light(Vector3(line_coord(i2) + ROAD_W * 0.5 + 1.0, 0, line_coord(j2) - ROAD_W * 0.5 - 1.0))
	for spot in [Vector3(line_coord(3) + 22, 0, line_coord(2) + ROAD_W * 0.5 + 1.5),
			Vector3(line_coord(1) + 40, 0, line_coord(4) - ROAD_W * 0.5 - 1.5),
			Vector3(line_coord(5) - 30, 0, line_coord(6) + ROAD_W * 0.5 + 1.5)]:
		_bus_stop(spot)


func _traffic_light(p: Vector3) -> void:
	var pole = TL.flat(Color(0.25, 0.26, 0.28), 0.5, 0.5)
	var body = TL.flat(Color(0.16, 0.17, 0.19))
	_box(pole, p + Vector3(0, 2.0, 0), Vector3(0.12, 4.0, 0.12))
	_box(body, p + Vector3(-0.25, 3.9, 0), Vector3(0.3, 0.9, 0.3))
	_box(traffic_mats["ns_r"], p + Vector3(-0.42, 4.15, 0), Vector3(0.06, 0.2, 0.2))
	_box(traffic_mats["ns_y"], p + Vector3(-0.42, 3.9, 0), Vector3(0.06, 0.2, 0.2))
	_box(traffic_mats["ns_g"], p + Vector3(-0.42, 3.65, 0), Vector3(0.06, 0.2, 0.2))
	_box(body, p + Vector3(0, 3.9, 0.25), Vector3(0.3, 0.9, 0.3))
	_box(traffic_mats["ew_r"], p + Vector3(0, 4.15, 0.42), Vector3(0.2, 0.2, 0.06))
	_box(traffic_mats["ew_y"], p + Vector3(0, 3.9, 0.42), Vector3(0.2, 0.2, 0.06))
	_box(traffic_mats["ew_g"], p + Vector3(0, 3.65, 0.42), Vector3(0.2, 0.2, 0.06))


func _bus_stop(p: Vector3) -> void:
	var pole = TL.flat(Color(0.35, 0.36, 0.4), 0.5, 0.5)
	var roof = TL.flat(Color(0.5, 0.2, 0.2))
	_box(pole, p + Vector3(-2, 1.4, 0), Vector3(0.12, 2.8, 0.12))
	_box(pole, p + Vector3(2, 1.4, 0), Vector3(0.12, 2.8, 0.12))
	_box(roof, p + Vector3(0, 2.9, 0), Vector3(5, 0.15, 2))
	_bench_fixed(p + Vector3(0, 0, 0), PI * 0.5)
	_sign("АВТОБУС", p + Vector3(0, 3.6, 0), 0.6, Color(0.8, 0.9, 1.0))
	job_points.append(p + Vector3(2, 0.1, 0))



func _away_from_lines_wide(t: float) -> bool:
	for j in range(GRID + 1):
		if absf(t - line_coord(j)) < ROAD_W * 0.5 + 5.0:
			return false
	return true


func _npc_defs() -> void:
	var defs := [
		["x", 3, 1, -200.0], ["x", 3, -1, 150.0], ["x", 1, 1, 60.0], ["x", 5, -1, -100.0],
		["z", 2, -1, -180.0], ["z", 2, 1, 120.0], ["z", 4, 1, -60.0], ["z", 6, -1, 30.0],
	]
	for d in defs:
		npc_spawns.append({"axis": d[0], "line": d[1], "dir": d[2], "t": d[3], "type": rng.randi() % 4})

# =================== МИНИКАРТА ===================

func _minimap() -> void:
	var size := 512
	var span := 2.0 * (HALF + 30.0)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.13, 0.16, 0.11))
	var road := Color(0.24, 0.25, 0.27)
	var building := Color(0.5, 0.48, 0.44)
	var rw := maxi(2, int(ROAD_W / span * size))
	for i in range(GRID + 1):
		var x := int((line_coord(i) - ROAD_W * 0.5 + HALF + 30.0) / span * size)
		img.fill_rect(Rect2i(x, 0, rw, size), road)
		var z := int((line_coord(i) - ROAD_W * 0.5 + HALF + 30.0) / span * size)
		img.fill_rect(Rect2i(0, z, size, rw), road)
	for i2 in range(GRID):
		for j2 in range(GRID):
			var t := block_type(i2, j2)
			var a := _block_area(i2, j2)
			var col := Color(0.17, 0.2, 0.14)
			match t:
				BT_PLAZA:
					col = Color(0.42, 0.38, 0.32)
				BT_PARK:
					col = Color(0.15, 0.28, 0.12)
				BT_GARAGES:
					col = Color(0.28, 0.24, 0.19)
				BT_MOTOPARK, BT_GAS, BT_SHOP, BT_PHARM:
					col = Color(0.3, 0.31, 0.33)
			img.fill_rect(Rect2i(
				int((a.x0 + HALF + 30.0) / span * size), int((a.z0 + HALF + 30.0) / span * size),
				maxi(2, int((a.x1 + HALF + 30.0) / span * size) - int((a.x0 + HALF + 30.0) / span * size)),
				maxi(2, int((a.z1 + HALF + 30.0) / span * size) - int((a.z0 + HALF + 30.0) / span * size))), col)
	for r in _rects:
		img.fill_rect(Rect2i(
			int((r.x + HALF + 30.0) / span * size), int((r.z + HALF + 30.0) / span * size),
			maxi(1, int((r.x + r.w + HALF + 30.0) / span * size) - int((r.x + HALF + 30.0) / span * size)),
			maxi(1, int((r.z + r.d + HALF + 30.0) / span * size) - int((r.z + HALF + 30.0) / span * size))), building)
	var pa := _block_area(5, 5)
	var pc := Vector3((pa.x0 + pa.x1) * 0.5, 0, (pa.z0 + pa.z1) * 0.5)
	img.fill_rect(Rect2i(int((pc.x - 20 + HALF + 30.0) / span * size), int((pc.z + 4 + HALF + 30.0) / span * size), 22, 15),
		Color(0.16, 0.3, 0.42))
	map_img = img
