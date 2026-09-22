extends RefCounted
## Утилиты общего назначения: действия ввода, настройки, деньги, UI-хелперы.

const SETTINGS_PATH := "user://settings.cfg"

# ---------------- Ввод ----------------

static func setup_actions() -> void:
	_reg("move_forward", [KEY_W, KEY_UP])
	_reg("move_back", [KEY_S, KEY_DOWN])
	_reg("move_left", [KEY_A, KEY_LEFT])
	_reg("move_right", [KEY_D, KEY_RIGHT])
	_reg("jump", [KEY_SPACE])
	_reg("run", [KEY_SHIFT])
	_reg("enter_car", [KEY_E, KEY_F])
	_reg("chat", [KEY_T, KEY_ENTER])
	_reg("horn", [KEY_H])
	_reg("job", [KEY_J])
	_reg("pause", [KEY_ESCAPE])


static func _reg(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

# ---------------- Настройки ----------------

static func _load_cfg():  # ConfigFile; в 4.0 нет static var — храним в meta скрипта
	var s: Script = load("res://br/util.gd")
	if not s.has_meta("cfg"):
		var c := ConfigFile.new()
		c.load(SETTINGS_PATH)
		if not c.has_section_key("player", "nick"):
			var n := "Водитель%d" % (randi() % 90 + 10)
			c.set_value("player", "nick", n)
		s.set_meta("cfg", c)
	return s.get_meta("cfg")


static func get_set(section: String, key: String, def: Variant) -> Variant:
	return _load_cfg().get_value(section, key, def)


static func set_set(section: String, key: String, value: Variant) -> void:
	_load_cfg().set_value(section, key, value)
	_load_cfg().save(SETTINGS_PATH)


static func get_nick() -> String:
	return str(get_set("player", "nick", "Водитель"))


static func get_money() -> int:
	return int(get_set("game", "money", 500))


static func set_money(v: int) -> void:
	set_set("game", "money", maxi(0, v))

# ---------------- UI-хелперы ----------------

static func label(text: String, size: int = 18, color: Color = Color.WHITE, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", maxi(3, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.7, 0.85, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.22, 0.95)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.19, 0.22, 0.32, 0.95)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(0.24, 0.30, 0.44, 0.95)
	b.add_theme_stylebox_override("pressed", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.10, 0.11, 0.14, 0.6)
	b.add_theme_stylebox_override("disabled", sbd)
	return b


static func line_edit(placeholder: String, text: String = "", max_len: int = 24) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.max_length = max_len
	e.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	return e


static func panel_box(bg: Color = Color(0.06, 0.07, 0.11, 0.94), radius: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.border_width_bottom = 2
	sb.border_color = Color(0.25, 0.32, 0.5, 0.6)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func fmt_money(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
