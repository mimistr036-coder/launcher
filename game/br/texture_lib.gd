extends RefCounted
## Процедурные материалы и текстуры. Вся графика города генерируется кодом,
## поэтому в проекте нет ни одного бинарного ассета (кэш получается крошечным).

# В Godot 4.0 нет static var — кэш храним в метаданных скрипта
# (скрипт кэшируется движком по пути, метаданные живут всю сессию).

static func _cache():
	var s: Script = load("res://br/texture_lib.gd")
	if not s.has_meta("mats"):
		s.set_meta("mats", {})
	return s.get_meta("mats")


static func _night_mats():
	var s: Script = load("res://br/texture_lib.gd")
	if not s.has_meta("night"):
		s.set_meta("night", [])
	return s.get_meta("night")

const WALL_PALETTE := [
	Color("ddd3b4"),  # кремовый
	Color("d9c49a"),  # бежевый
	Color("cfa96e"),  # охристый
	Color("b9c8b1"),  # мятно-зелёный
	Color("adb9c4"),  # серо-голубой
	Color("c98f6e"),  # кирпичный
	Color("d8d0c0"),  # светлый камень
	Color("cbb9d0"),  # сиреневатый
]

# ---------------- Базовое ----------------

static func flat(color: Color, metallic: float = 0.0, rough: float = 0.9, unshaded: bool = false) -> StandardMaterial3D:
	var key := "flat_%s_%s_%s_%s" % [color.to_html(), metallic, rough, unshaded]
	if _cache().has(key):
		return _cache()[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache()[key] = m
	return m


static func noise_img(w: int, h: int, freq: float, seedv: int, base: Color, vary: float) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seedv
	n.frequency = freq
	for y in range(h):
		for x in range(w):
			var v := n.get_noise_2d(float(x), float(y))
			var f := clampf(0.5 + v * vary, 0.0, 1.0)
			img.set_pixel(x, y, Color(base.r * f, base.g * f, base.b * f))
	return img


static func _ground_mat(kind: String) -> StandardMaterial3D:
	var cfg := {}
	match kind:
		"asphalt":
			cfg = {"c": Color(0.31, 0.32, 0.345), "f": 0.09, "s": 11, "v": 0.30}
		"walk":
			cfg = {"c": Color(0.63, 0.62, 0.59), "f": 0.2, "s": 12, "v": 0.18}
		"grass":
			cfg = {"c": Color(0.31, 0.45, 0.22), "f": 0.06, "s": 13, "v": 0.32}
		"plaza":
			cfg = {"c": Color(0.56, 0.5, 0.42), "f": 0.15, "s": 14, "v": 0.25}
		"dirt":
			cfg = {"c": Color(0.42, 0.36, 0.26), "f": 0.1, "s": 15, "v": 0.35}
		_:
			cfg = {"c": Color(0.5, 0.5, 0.5), "f": 0.1, "s": 1, "v": 0.3}
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(
		noise_img(128, 128, cfg["f"], cfg["s"], cfg["c"], cfg["v"]))
	m.roughness = 1.0
	return m


static func ground(kind: String) -> StandardMaterial3D:
	var key := "ground_" + kind
	if _cache().has(key):
		return _cache()[key]
	var m := _ground_mat(kind)
	_cache()[key] = m
	return m

# ---------------- Фасады панелек ----------------
## Текстура фасада: сетка окон на всю стену (UV каждой грани 0..1).
## Ширины зданий квантованы, поэтому текстур немного и они шарятся.

static func facade(cols: int, floors: int, variant: int) -> StandardMaterial3D:
	var key := "facade_%d_%d_%d" % [cols, floors, variant]
	if _cache().has(key):
		return _cache()[key]
	var cw := 32
	var ch := 28
	var w := cols * cw
	var h := floors * ch
	var wall: Color = WALL_PALETTE[abs(variant) % WALL_PALETTE.size()]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var emis := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(wall)
	emis.fill(Color(0, 0, 0))
	var seam := wall.darkened(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = cols * 1000 + floors * 31 + variant
	# цоколь первого этажа — тёмная каменная полоса
	var plinth := Color(0.32, 0.31, 0.30)
	for yy in range(ch - 8, ch):
		for x in range(w):
			img.set_pixel(x, yy, plinth.darkened(rng.randf() * 0.08))
	for row in range(floors):
		var y0 := row * ch
		# панельные швы
		for x in range(w):
			img.set_pixel(x, clampi(y0 + ch - 2, 0, h - 1), seam)
			if row > 0:
				img.set_pixel(x, y0, seam)
		for col in range(cols):
			var x0 := col * cw
			for yy in range(ch):
				img.set_pixel(clampi(x0 + cw - 1, 0, w - 1), y0 + yy, seam)
			# окно
			var wx := x0 + 7
			var wy := y0 + 6
			var ww := cw - 14
			var wh := ch - 11
			var glass := Color(0.17, 0.22, 0.29).lightened(rng.randf() * 0.16)
			glass = glass.lerp(Color(0.45, 0.56, 0.66), rng.randf() * 0.35)
			if row == 0 and variant == 2:
				glass = Color(0.85, 0.87, 0.9).darkened(rng.randf() * 0.3)
			# ночью светится часть окон этого окна
			var lit := rng.randf() < 0.28
			if row == 0 and variant == 2:
				lit = true
			var wc := Color(1.0, 0.72, 0.35).lightened(rng.randf() * 0.3)
			if row == 0 and variant == 2:
				wc = Color(0.95, 0.97, 1.0)
			for yy in range(wh):
				for xx in range(ww):
					var px := clampi(wx + xx, 0, w - 1)
					var py := clampi(wy + yy, 0, h - 1)
					var c := glass
					if yy < 2:
						c = glass.lightened(0.35)
					img.set_pixel(px, py, c)
					if lit:
						emis.set_pixel(px, py, wc)
				# верх окна подсвечен небом
				for xx in range(ww):
					emis.set_pixel(clampi(wx + xx, 0, w - 1), clampi(wy, 0, h - 1), Color(0.18, 0.2, 0.25))
			# белая рамка окна
			for xx in range(ww + 2):
				img.set_pixel(clampi(wx - 1 + xx, 0, w - 1), clampi(wy - 1, 0, h - 1), Color(0.92, 0.92, 0.9))
				img.set_pixel(clampi(wx - 1 + xx, 0, w - 1), clampi(wy + wh, 0, h - 1), Color(0.92, 0.92, 0.9))
			for yy2 in range(wh):
				img.set_pixel(clampi(wx - 1, 0, w - 1), clampi(wy + yy2, 0, h - 1), Color(0.92, 0.92, 0.9))
				img.set_pixel(clampi(wx + ww, 0, w - 1), clampi(wy + yy2, 0, h - 1), Color(0.92, 0.92, 0.9))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(emis)
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.95
	_cache()[key] = m
	_night_mats().append([m, 1.9])
	return m


static func shop_window() -> StandardMaterial3D:
	return facade(4, 1, 2)

# ---------------- Ночная подсветка ----------------

static func night_mat(base_color: Color, base_energy: float, register: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.emission_enabled = true
	m.emission = base_color
	m.emission_energy_multiplier = 0.0
	if register:
		_night_mats().append([m, base_energy])
	return m


static func set_night(f: float) -> void:
	for e in _night_mats():
		e[0].emission_energy_multiplier = e[1] * f

# ---------------- Машины ----------------

static func car_paint(color: Color) -> StandardMaterial3D:
	var key := "paint_" + color.to_html()
	if _cache().has(key):
		return _cache()[key]
	var m := flat(color, 0.55, 0.35)
	_cache()[key] = m
	return m


static func car_glass() -> StandardMaterial3D:
	return flat(Color(0.07, 0.09, 0.13), 0.85, 0.12)

# ---------------- Прочее ----------------

static func water() -> StandardMaterial3D:
	return flat(Color(0.15, 0.32, 0.45, 0.9), 0.2, 0.15)


static func wood() -> StandardMaterial3D:
	var key := "wood"
	if _cache().has(key):
		return _cache()[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(
		noise_img(64, 64, 0.25, 21, Color(0.45, 0.32, 0.18), 0.35))
	m.roughness = 1.0
	_cache()[key] = m
	return m


static func foliage(variant: int) -> StandardMaterial3D:
	var colors := [Color(0.16, 0.34, 0.12), Color(0.22, 0.40, 0.13), Color(0.30, 0.42, 0.14)]
	return flat(colors[abs(variant) % colors.size()])
