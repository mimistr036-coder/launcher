extends CharacterBody3D
## Другой игрок по сети: интерполяция состояния.

var HUM = load("res://br/humanoid.gd")

var nick := "Игрок"
var peer_id := 0
var model: Node3D
var label: Label3D

var _t_pos := Vector3.ZERO
var _t_yaw := 0.0
var _state := 0
var _fresh := false


func setup(p_id: int, p_nick: String, variant: int) -> void:
	peer_id = p_id
	nick = p_nick
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	model = HUM.build(variant)
	add_child(model)
	label = Label3D.new()
	label.text = nick
	label.font_size = 40
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.15, 0)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 10
	add_child(label)


func set_state(pos: Vector3, yaw: float, state: int) -> void:
	if not _fresh:
		_fresh = true
		global_position = pos
	_t_pos = pos
	_t_yaw = yaw
	_state = state


func _physics_process(delta: float) -> void:
	if not _fresh:
		return
	global_position = global_position.lerp(_t_pos, 1.0 - pow(0.0001, delta))
	if global_position.distance_to(_t_pos) > 6.0:
		global_position = _t_pos
	model.rotation.y = lerp_angle(model.rotation.y, _t_yaw, 1.0 - pow(0.0001, delta))
	HUM.animate(model, _state, delta)
