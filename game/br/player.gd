extends CharacterBody3D
## Локальный игрок: ходьба/бег/прыжок, вход в машину, тач + клавиатура.

var HUM = load("res://br/humanoid.gd")

var nick := "Игрок"
var variant := 0
var world: Node = null
var hud: Node = null
var current_car: Node = null

var model: Node3D
var label: Label3D
var _state_anim := 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
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
	label.modulate = Color(0.65, 1.0, 0.65)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 10
	add_child(label)


func _physics_process(delta: float) -> void:
	if current_car != null:
		if not is_instance_valid(current_car):
			current_car = null
		else:
			return  # физикой управляет машина
	var axis := Vector2.ZERO
	var want_run := false
	var jump := false
	var enter := false
	if hud != null and is_instance_valid(hud):
		axis = hud.move_axis()
		want_run = hud.is_held("run")
		jump = hud.consume_event("jump")
		enter = hud.consume_event("enter")
	var kaxis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if kaxis.length() > 0.1:
		axis = kaxis
	if Input.is_action_pressed("run"):
		want_run = true
	if Input.is_action_just_pressed("jump"):
		jump = true
	if Input.is_action_just_pressed("enter_car"):
		enter = true
	var cam_yaw: float = world.cam_yaw if world != null else 0.0
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir := fwd * (-axis.y) + right * axis.x
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := 7.2 if want_run else 3.9
	if axis.length() < 0.05 and kaxis.length() < 0.05:
		speed = 0.0
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target_v.z, 30.0 * delta)
	if is_on_floor():
		if jump:
			velocity.y = 6.4
	else:
		velocity.y -= 16.0 * delta
	move_and_slide()
	# модель
	if dir.length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
	if not is_on_floor():
		_state_anim = 3
	elif speed > 5.0 and dir.length() > 0.05:
		_state_anim = 2
	elif speed > 0.1 and dir.length() > 0.05:
		_state_anim = 1
	else:
		_state_anim = 0
	HUM.animate(model, _state_anim, delta)
	if enter and world != null:
		world.try_enter_car(self)


func car_controls() -> Dictionary:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	if Input.is_action_pressed("move_forward"):
		throttle = 1.0
	elif Input.is_action_pressed("move_back"):
		throttle = -1.0
	steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	handbrake = Input.is_action_pressed("jump")
	if hud != null and is_instance_valid(hud):
		var a: Vector2 = hud.move_axis()
		if absf(a.x) > 0.1:
			steer = clampf(steer + a.x, -1.0, 1.0)
		if hud.is_held("gas"):
			throttle = 1.0
		elif hud.is_held("brake"):
			throttle = -1.0
		if hud.is_held("handbrake"):
			handbrake = true
		if hud.is_held("run") and throttle == 0.0:
			throttle = 1.0  # «БЕГ» работает как газ-бустер в машине
	return {"throttle": throttle, "steer": steer, "handbrake": handbrake}


func anim_state() -> int:
	return 5 if current_car != null else _state_anim
