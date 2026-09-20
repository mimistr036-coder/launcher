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
	Color("cfc5ad"), Color("bfb49a"), Color("c9c2b4"),
	Color("a8b0b4"), Color("c0b190"), Color("b3a48c"),
	Color("a5b4a1"), Color("c2b0a6"),
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
	var img: Image
	match kind:
		"asphalt":
			img = noise_img(128, 128, 0.7, 11, Color(0.3, 0.31, 0.33), 0.3)
			var ra := RandomNumberGenerator.new()
			ra.seed = 77
			for k in range(14):  # латанки и пятна
				var cx := ra.randi_range(0, 127)
				var cz := ra.randi_range(0, 127)
				var rr := ra.randi_range(6, 18)
				var shade := 0.24 if ra.randf() < 0.6 else 0.4
				for dy in range(-rr, rr + 1):
					for dx in range(-rr, rr + 1):
						if dx * dx + dy * dy <= rr * rr:
							img.set_pixel((cx + dx) % 128, (cz + dy) % 128, Color(shade, shade + 0.01, shade + 0.02))
		"walk":
			# тротуарная плитка: светлая + тёмные швы сеткой
			img = noise_img(128, 128, 0.3, 12, Color(0.66, 0.65, 0.62), 0.12)
			for i in range(0, 129, 32):
				for q in range(128):
					img.set_pixel(i % 128, q, Color(0.5, 0.49, 0.47))
					img.set_pixel(q, i % 128, Color(0.5, 0.49, 0.47))
		"grass":
			img = noise_img(128, 128, 0.18, 13, Color(0.34, 0.48, 0.22), 0.42)
		"plaza":
			img = noise_img(128, 128, 0.25, 14, Color(0.68, 0.64, 0.57), 0.12)
		"dirt":
			img = noise_img(128, 128, 0.2, 15, Color(0.5, 0.43, 0.3), 0.3)
		_:
			img = noise_img(128, 128, 0.2, 1, Color(0.55, 0.55, 0.55), 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
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
	var seam := wall.darkened(0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = cols * 1000 + floors * 31 + variant
	for row in range(floors):
		var y0 := row * ch
		# междуэтажный шов
		for x in range(w):
			img.set_pixel(x, clampi(y0 + ch - 1, 0, h - 1), seam)
			img.set_pixel(x, clampi(y0 + ch - 2, 0, h - 1), wall.darkened(0.1))
		for col in range(cols):
			var x0 := col * cw
			# вертикальный шов панели
			for yy in range(ch):
				img.set_pixel(clampi(x0 + cw - 1, 0, w - 1), y0 + yy, seam)
			# окно: 5..cw-5, 4..ch-8
			var wx := x0 + 5
			var wy := y0 + 4
			var ww := cw - 10
			var wh := ch - 12
			var glass := Color(0.16, 0.21, 0.27).lightened(rng.randf() * 0.10)
			var lit := rng.randf() < 0.3
			var wc := Color(1.0, 0.75, 0.4).lightened(rng.randf() * 0.25)
			for yy in range(wh):
				for xx in range(ww):
					var c := glass
					if yy == 0:
						c = glass.lightened(0.35)  # блеск сверху
					img.set_pixel(wx + xx, wy + yy, c)
					if lit:
						emis.set_pixel(wx + xx, wy + yy, wc)
			# подоконник
			for xx in range(ww + 2):
				img.set_pixel(clampi(wx - 1 + xx, 0, w - 1), clampi(wy + wh + 1, 0, h - 1), wall.darkened(0.35))
		# входная дверь на первом этаже (средняя панель)
		if row == 0 and cols >= 3:
			var dx := (cols / 2) * cw + 6
			for yy in range(ch - 4):
				for xx in range(cw - 12):
					img.set_pixel(dx + xx, y0 + 4 + yy, Color(0.22, 0.16, 0.12))
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
