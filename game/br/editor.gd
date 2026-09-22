extends CanvasLayer
## Редактор карты как в Roblox Studio: ставишь объекты тапом по миру,
## крутишь, меняешь размер и цвет, сохраняешь. Карта живёт в user://custom_map.json
## и загружается при старте мира автоматически.

const ML = "res://br/model_lib.gd"
const TL = "res://br/texture_lib.gd"
const MAP_PATH := "user://custom_map.json"
const MAX_OBJECTS := 400
const HOMES := ["res://models/building-small-a.glb", "res://models/building-small-b.glb",
	"res://models/building-small-c.glb", "res://models/building-small-d.glb"]

var world = null
var active := false
var objects: Array = []          # {node, data}
var selected_idx := -1
var obj_type := "block"
var obj_color := Color(0.72, 0.72, 0.75)
var obj_size := Vector3(4.0, 3.0, 4.0)
var size_axis := 0               # 0=X 1=Y 2=Z (для выбранного объекта)
var moving := false              # следующий тап переставляет выбранный объект

var _panel: PanelContainer
var _sel_label: Label
var _size_label: Label


func _ready() -> void:
	layer = 8
	_build_panel()
	_panel.visible = false


func set_active(on: bool) -> void:
	active = on
	_panel.visible = on
	moving = false
	_refresh()
	if not on:
		save_map()


# ================= панель =================

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "РЕДАКТОР КАРТЫ"
	title.add_theme_font_size_override("font_size", 15)
	v.add_child(title)
	# тип объекта
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 4)
	for t in [["БЛОК", "block"], ["ПЛИТА", "plate"], ["КОЛОННА", "column"],
			["ДОМ", "house"], ["ФОНТАН", "fountain"], ["ДЕРЕВО", "tree"]]:
		var b := _mk_btn(t[0], 12)
		b.toggle_mode = true
		var tt: String = t[1]
		b.pressed.connect(func() -> void:
			obj_type = tt
			_sync_type_buttons()
			_refresh())
		b.name = "T_" + t[1]
		r1.add_child(b)
	v.add_child(r1)
	# цвета
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 4)
	for c in [Color(0.72, 0.72, 0.75), Color(0.75, 0.4, 0.35), Color(0.4, 0.55, 0.75),
			Color(0.45, 0.65, 0.45), Color(0.85, 0.75, 0.5), Color(0.5, 0.45, 0.6),
			Color(0.25, 0.27, 0.3), Color(0.9, 0.9, 0.9)]:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(30, 26)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(5)
		sw.add_theme_stylebox_override("normal", sb)
		var cc := c
		sw.pressed.connect(func() -> void:
			obj_color = cc
			_apply_color_to_selected())
		r2.add_child(sw)
	v.add_child(r2)
	# действия над выбранным
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 4)
	r3.add_child(_mk_btn("◀", func() -> void: _rotate_sel(-15.0)))
	r3.add_child(_mk_btn("▶", func() -> void: _rotate_sel(15.0)))
	r3.add_child(_mk_btn("РАЗМЕР-", func() -> void: _scale_sel(0.88)))
	r3.add_child(_mk_btn("РАЗМЕР+", func() -> void: _scale_sel(1.14)))
	v.add_child(r3)
	var r4 := HBoxContainer.new()
	r4.add_theme_constant_override("separation", 4)
	r4.add_child(_mk_btn("ПЕРЕНЕСТИ", func() -> void: moving = true))
	r4.add_child(_mk_btn("КОПИЯ", func() -> void: _dup_sel()))
	r4.add_child(_mk_btn("УДАЛИТЬ", func() -> void: _del_sel()))
	v.add_child(r4)
	# сохранение / выход
	var r5 := HBoxContainer.new()
	r5.add_theme_constant_override("separation", 4)
	r5.add_child(_mk_btn("СОХРАНИТЬ", func() -> void: save_map()))
	var exit_btn := _mk_btn("ВЫЙТИ ИЗ РЕДАКТОРА", func() -> void: set_active(false))
	r5.add_child(exit_btn)
	v.add_child(r5)
	_sel_label = Label.new()
	_sel_label.add_theme_font_size_override("font_size", 11)
	v.add_child(_sel_label)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 11)
	hint.text = "Тап по земле — поставить. Тап по объекту — выбрать."
	hint.modulate = Color(0.7, 0.75, 0.85)
	v.add_child(hint)
	add_child(_panel)


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b


func _sync_type_buttons() -> void:
	for c in _panel.find_children("T_*", "", true, false):
		if c is Button:
			(c as Button).button_pressed = c.name == "T_" + obj_type


# ================= ввод =================

func _input(ev: InputEvent) -> void:
	if not active:
		return
	var pos := Vector2.ZERO
	var pressed := false
	if ev is InputEventScreenTouch:
		pos = ev.position
		pressed = ev.pressed
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		pressed = ev.pressed
	if not pressed:
		return
	if _panel.get_global_rect().has_point(pos):
		return
	_tap(pos)


func _tap(pos: Vector2) -> void:
	if world == null or world._cam == null:
		return
	var cam: Camera3D = world._cam
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 150.0)
	if world.player != null:
		q.exclude = [world.player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var hit_col: Object = hit.get("collider")
	# выбор объекта редактора
	if hit_col != null and hit_col is Node and (hit_col as Node).is_in_group("editobj_root"):
		selected_idx = _find_by_collider(hit_col)
		moving = false
		_refresh()
		return
	if moving and selected_idx >= 0:
		objects[selected_idx].node.global_position = _snap_xz(hit.position, objects[selected_idx])
		moving = false
		_refresh()
		return
	# поставить новый
	if objects.size() >= MAX_OBJECTS:
		return
	_spawn_at(obj_type, _snap_xz(hit.position, null), 0.0, obj_size, obj_color)
	_refresh()


func _snap_xz(p: Vector3, o) -> Vector3:
	var y := p.y
	if o != null and o.has("node"):
		y = o.node.global_position.y
	return Vector3(roundf(p.x), y, roundf(p.z))


# ================= создание объектов =================

func _spawn_at(type: String, pos: Vector3, rot_deg: float, size: Vector3, col: Color) -> void:
	var root := Node3D.new()
	root.add_to_group("editobj_root")
	var data := {"type": type, "pos": [pos.x, pos.y, pos.z], "rot": rot_deg,
		"size": [size.x, size.y, size.z], "color": col.to_html(false)}
	root.set_meta("data", data)
	if type == "block":
		_mesh_box(root, size, col)
		root.position = pos + Vector3(0, size.y * 0.5, 0)
	elif type == "plate":
		_mesh_box(root, Vector3(size.x, 0.2, size.z), col)
		root.position = pos + Vector3(0, 0.1, 0)
	elif type == "column":
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = maxf(size.y, 0.5)
		cm.radial_segments = 10
		cm.material = load(TL).flat(col)
		mi.mesh = cm
		root.add_child(mi)
		_add_box_col(root, Vector3(1.2, maxf(size.y, 0.5), 1.2), Vector3(0, maxf(size.y, 0.5) * 0.5, 0))
		root.position = pos
	elif type == "house":
		var m = load(ML).spawn(HOMES[abs(int(pos.x)) % HOMES.size()], clampf(size.y, 4.0, 12.0), true)
		if m != null:
			root.add_child(m)
		root.position = pos
	elif type == "fountain":
		var f = load(ML).spawn("res://models/pavement-fountain.glb", 5.5, true)
		if f != null:
			root.add_child(f)
		root.position = pos
	elif type == "tree":
		_make_tree(root, size.y)
		root.position = pos
	root.rotation.y = deg_to_rad(rot_deg)
	world.add_child(root)
	objects.append({"node": root, "data": data})
	selected_idx = objects.size() - 1


func _mesh_box(root: Node3D, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = load(TL).flat(col)
	mi.mesh = bm
	root.add_child(mi)
	_add_box_col(root, size, Vector3.ZERO)


func _add_box_col(root: Node3D, size: Vector3, off: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = off
	body.add_child(cs)
	root.add_child(body)


func _make_tree(root: Node3D, h: float) -> void:
	var tl = load(TL)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.24
	tm.height = h * 0.55
	tm.radial_segments = 6
	tm.material = tl.wood()
	trunk.mesh = tm
	trunk.position = Vector3(0, h * 0.275, 0)
	root.add_child(trunk)
	var fol := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.05
	fm.bottom_radius = h * 0.3
	fm.height = h * 0.7
	fm.radial_segments = 7
	fm.material = tl.foliage(0)
	fol.mesh = fm
	fol.position = Vector3(0, h * 0.72, 0)
	root.add_child(fol)
	_add_box_col(root, Vector3(0.5, h, 0.5), Vector3(0, h * 0.5, 0))


# ================= правка выбранного =================

func _find_by_collider(col: Object) -> int:
	var n: Node = col
	while n != null and not n.is_in_group("editobj_root"):
		n = n.get_parent()
	if n == null:
		return -1
	for i in range(objects.size()):
		if objects[i].node == n:
			return i
	return -1


func _rotate_sel(d: float) -> void:
	if selected_idx < 0:
		return
	var o = objects[selected_idx]
	o.data.rot = float(o.data.rot) + d
	o.node.rotation.y = deg_to_rad(float(o.data.rot))
	_refresh()


func _scale_sel(k: float) -> void:
	if selected_idx < 0:
		return
	var o = objects[selected_idx]
	var s: Vector3 = Vector3(o.data.size[0], o.data.size[1], o.data.size[2]) * k
	if s.length() > 60.0 or s.length() < 1.0:
		return
	var pos: Vector3 = o.node.global_position
	var was_sel := selected_idx
	_remove_at(was_sel)
	_spawn_at(o.data.type, Vector3(pos.x, pos.y - Vector3(o.data.size[0], o.data.size[1], o.data.size[2]).y * 0.5, pos.z), float(o.data.rot), s, Color(o.data.color))
	# после пересоздания вернуть прежнюю высоту точки (для block ставим на поверхность)
	objects[objects.size() - 1].node.global_position = Vector3(pos.x, objects[objects.size() - 1].node.global_position.y if o.data.type != "block" else pos.y, pos.z)
	_refresh()


func _dup_sel() -> void:
	if selected_idx < 0 or objects.size() >= MAX_OBJECTS:
		return
	var o = objects[selected_idx]
	_spawn_at(o.data.type, o.node.global_position + Vector3(3, 0, 0), float(o.data.rot),
		Vector3(o.data.size[0], o.data.size[1], o.data.size[2]), Color(o.data.color))
	_refresh()


func _del_sel() -> void:
	if selected_idx < 0:
		return
	_remove_at(selected_idx)
	selected_idx = -1
	_refresh()


func _remove_at(i: int) -> void:
	var o = objects[i]
	o.node.queue_free()
	objects.remove_at(i)
	if selected_idx == i:
		selected_idx = -1


func _apply_color_to_selected() -> void:
	if selected_idx < 0:
		return
	var o = objects[selected_idx]
	var pos: Vector3 = o.node.global_position
	var i := selected_idx
	_remove_at(i)
	_spawn_at(o.data.type, Vector3(pos.x, pos.y - Vector3(o.data.size[0], o.data.size[1], o.data.size[2]).y * 0.5, pos.z), float(o.data.rot), Vector3(o.data.size[0], o.data.size[1], o.data.size[2]), obj_color)
	if o.data.type == "block":
		objects[objects.size() - 1].node.global_position = pos
	_refresh()


func _refresh() -> void:
	if _sel_label == null:
		return
	if selected_idx >= 0 and selected_idx < objects.size():
		var o = objects[selected_idx]
		_sel_label.text = "Выбран: %s  |  поворот %d°" % [o.data.type, int(o.data.rot)]
	else:
		_sel_label.text = "Ничего не выбрано"


# ================= файл карты =================

func save_map() -> void:
	var arr := []
	for o in objects:
		arr.append(o.data)
	var f := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"objects": arr}))
	f.close()


func load_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		return
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not parsed.has("objects"):
		return
	for d in parsed["objects"]:
		if d.has("type") and d.has("pos"):
			var p: Array = d["pos"]
			var s: Array = d.get("size", [4.0, 3.0, 4.0])
			_spawn_at(d["type"], Vector3(p[0], p[1], p[2]), float(d.get("rot", 0.0)),
				Vector3(s[0], s[1], s[2]), Color(str(d.get("color", "b8b8bf"))))
	selected_idx = -1
	_refresh()
