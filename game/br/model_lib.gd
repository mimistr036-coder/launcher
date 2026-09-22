extends RefCounted
## Загрузка GLB-моделей в рантайме (CC0-пак Kenney City Kit).
## Работает и из смонтированного кэша (PCK), и в редакторе:
## Godot умеет парсить glTF на лету через GLTFDocument.

static func _cache() -> Dictionary:
	var s: Script = load("res://br/model_lib.gd")
	if not s.has_meta("glb"):
		s.set_meta("glb", {})
	return s.get_meta("glb")


## path — res://путь к .glb; target_h — привести высоту к метрам (0 = как есть);
## with_collision — добавить StaticBody3D с trimesh-коллизией.
static func spawn(path: String, target_h: float = 0.0, with_collision: bool = false) -> Node3D:
	var key := "%s|%.2f|%s" % [path, target_h, str(with_collision)]
	if _cache().has(key):
		var ps: PackedScene = _cache()[key]
		return ps.instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("[model_lib] GLB не загружен (" + str(err) + "): " + path)
		return null
	var node := doc.generate_scene(state)
	if node == null:
		push_warning("[model_lib] пустая сцена: " + path)
		return null
	var root3d := node as Node3D
	if root3d == null:
		node.queue_free()
		return null
	if with_collision:
		_add_collision(root3d)
	var packed := PackedScene.new()
	packed.pack(root3d)
	_cache()[key] = packed
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	if target_h > 0.0:
		var aabb := _aabb(inst)
		if aabb.size.y > 0.01:
			var k := target_h / aabb.size.y
			inst.scale = Vector3(k, k, k)
	return inst


static func _aabb(n: Node3D) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var rel := mi.transform * mi.get_aabb()
			if cur != n:
				var p := cur.get_parent()
				while p != null and p is Node3D and p != n:
					rel = (p as Node3D).transform * rel
					p = p.get_parent()
			if first:
				total = rel
				first = false
			else:
				total = total.merge(rel)
		for c in cur.get_children():
			stack.append(c)
	return total


static func _add_collision(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "GLBCol"
	var stack: Array = [root]
	var shapes := 0
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				cs.transform = mi.transform
				body.add_child(cs)
				shapes += 1
		for c in cur.get_children():
			stack.append(c)
	if shapes > 0:
		root.add_child(body)
