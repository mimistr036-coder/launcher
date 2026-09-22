extends RefCounted
## Процедурные материалы и текстуры. Вся графика города генерируется кодом,
## поэтому в проекте нет ни одного бинарного ассета (кэш получается крошечным).

# В Godot 4.0 нет static var — кэш храним в метаданных скрипта
# (скрипт кэшируется движком по пути, метаданные живут всю сессию).

static func _is40() -> bool:
	var s: Script = load("res://br/texture_lib.gd")
	if not s.has_meta("is40"):
		var vi := Engine.get_version_info()
		s.set_meta("is40", vi.major == 4 and vi.minor == 0)
	return s.get_meta("is40")


## В Godot 4.0 (GL Compatibility) рантайм-текстуры темнеют — гамма-компенсация по пикселям.
static func _fix_img(img: Image) -> void:
	if not _is40():
		return
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.01:
				continue
			img.set_pixel(x, y, Color(pow(c.r, 0.75), pow(c.g, 0.75), pow(c.b, 0.75), c.a))


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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	_fix_img(img)
	return img


static func _ground_mat(kind: String) -> StandardMaterial3D:
	var img: Image
	match kind:
		"asphalt":
			img = noise_img(128, 128, 0.55, 11, Color(0.37, 0.38, 0.40), 0.13)
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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	var seam := wall.darkened(0.25)
	var frame := Color(0.92, 0.92, 0.9)
	var accent: Color = [Color("7a94a8"), Color("a8766e"), Color("6e8a6a"), Color("9a8a5e")][abs(variant) % 4]
	var rng := RandomNumberGenerator.new()
	rng.seed = cols * 1000 + floors * 31 + variant
	for row in range(floors):
		var y0 := row * ch
		# междуэтажный шов с тенью
		for x in range(w):
			img.set_pixel(x, clampi(y0 + ch - 1, 0, h - 1), seam)
			img.set_pixel(x, clampi(y0 + ch - 2, 0, h - 1), wall.darkened(0.12))
		for col in range(cols):
			var x0 := col * cw
			for yy in range(ch):
				img.set_pixel(clampi(x0 + cw - 1, 0, w - 1), y0 + yy, seam)
				if x0 > 0:
					img.set_pixel(clampi(x0, 0, w - 1), y0 + yy, wall.darkened(0.08))
			# окно с белой рамой и отражением неба
			var wx := x0 + 5
			var wy := y0 + 4
			var ww := cw - 10
			var wh := ch - 12
			var glass := Color(0.13, 0.19, 0.26).lightened(rng.randf() * 0.08)
			var lit := rng.randf() < 0.3
			var wc := Color(1.0, 0.75, 0.4).lightened(rng.randf() * 0.25)
			for yy in range(wh):
				for xx in range(ww):
					var c := glass
					if yy == 0 or yy == wh - 1 or xx == 0 or xx == ww - 1:
						c = frame  # рама
					elif yy < wh / 3:
						c = glass.lightened(0.30)  # отражение неба
					elif yy == wh / 2:
						c = glass.darkened(0.25)  # импост
					img.set_pixel(wx + xx, wy + yy, c)
					if lit and yy > 0 and yy < wh - 1 and xx > 0 and xx < ww - 1:
						emis.set_pixel(wx + xx, wy + yy, wc)
			# подоконник с тенью
			for xx in range(ww + 4):
				img.set_pixel(clampi(wx - 2 + xx, 0, w - 1), clampi(wy + wh + 1, 0, h - 1), frame.darkened(0.25))
				img.set_pixel(clampi(wx - 2 + xx, 0, w - 1), clampi(wy + wh + 2, 0, h - 1), wall.darkened(0.3))
		# акцентная полоса между 1 и 2 этажом
		if row == 1:
			for x in range(w):
				img.set_pixel(x, y0, accent)
				img.set_pixel(x, clampi(y0 + 1, 0, h - 1), accent.darkened(0.15))
		# первый этаж темнее (цокольная зона)
		if row == 0:
			for x in range(w):
				for yy in range(ch):
					img.set_pixel(x, y0 + yy, img.get_pixel(x, y0 + yy).darkened(0.13))
	# входная дверь на первом этаже (средняя панель)
	if floors > 0 and cols >= 3:
		var dx := (cols / 2) * cw + 6
		var dcol := Color(0.24, 0.19, 0.14)
		for yy in range(ch - 6):
			for xx in range(cw - 12):
				var c := dcol
				if yy < 2:
					c = dcol.lightened(0.3)  # козырёк-тень сверху
				if xx < 1 or xx > cw - 14:
					c = frame
				if yy > ch - 12 and xx == (cw - 12) / 2:
					c = Color(0.8, 0.8, 0.75)  # ручка
				img.set_pixel(dx + xx, 4 + yy, c)
	_fix_img(img)
	_fix_img(emis)
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(emis)
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.95
	_cache()[key] = m
	_night_mats().append([m, 1.9])
	return m


static func facade_brick(cols: int, floors: int, brick_idx: int) -> StandardMaterial3D:
	var key := "brick_%d_%d_%d" % [cols, floors, brick_idx]
	if _cache().has(key):
		return _cache()[key]
	var cw := 32
	var ch := 28
	var w := cols * cw
	var h := floors * ch
	var base: Color = [Color("8a5a48"), Color("9a7f62"), Color("74625c"), Color("a89880")][abs(brick_idx) % 4]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var emis := Image.create(w, h, false, Image.FORMAT_RGB8)
	emis.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + cols * 31 + floors * 7 + brick_idx
	var bw := 8
	var bh := 4
	for y in range(h):
		var row := y / bh
		var off := (row % 2) * (bw / 2)
		for x in range(w):
			var bi := (x + off) / bw
			var mortar := (y % bh == 0) or ((x + off) % bw == 0)
			if mortar:
				img.set_pixel(x, y, Color(0.72, 0.69, 0.64).darkened(rng.randf() * 0.06))
			else:
				var f := 1.0 + sin(float(bi * 13 + row * 7)) * 0.08 + rng.randf() * 0.06
				var c := base * f
				if row == 0:
					c = c.darkened(0.2)  # цокольный ряд
				img.set_pixel(x, y, c)
	# окна с белыми рамами поверх кирпича
	var frame := Color(0.93, 0.92, 0.88)
	for row in range(floors):
		var y0 := row * ch
		# перемычка-карниз над рядом окон
		for x in range(w):
			img.set_pixel(x, clampi(y0 + 2, 0, h - 1), base.darkened(0.35))
		for col in range(cols):
			var wx := col * cw + 6
			var wy := y0 + 5
			var ww := cw - 12
			var wh := ch - 14
			var lit := rng.randf() < 0.28
			var wc := Color(1.0, 0.78, 0.42).lightened(rng.randf() * 0.2)
			for yy in range(wh):
				for xx in range(ww):
					var c := Color(0.12, 0.18, 0.25).lightened(rng.randf() * 0.07)
					if yy < wh / 3:
						c = c.lightened(0.28)
					if yy == 0 or yy == wh - 1 or xx == 0 or xx == ww - 1:
						c = frame
					img.set_pixel(wx + xx, wy + yy, c)
					if lit and yy > 0 and yy < wh - 1 and xx > 0 and xx < ww - 1:
						emis.set_pixel(wx + xx, wy + yy, wc)
			for xx in range(ww + 4):
				img.set_pixel(clampi(wx - 2 + xx, 0, w - 1), clampi(wy + wh + 1, 0, h - 1), frame.darkened(0.3))
	_fix_img(img)
	_fix_img(emis)
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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

## Рулонная кровля с гравием
static func roof_mat() -> StandardMaterial3D:
	if _cache().has("roof"):
		return _cache()["roof"]
	var img := noise_img(128, 128, 0.65, 5, Color(0.26, 0.27, 0.28), 0.10)
	for y in range(0, 128, 32):
		for x in range(128):
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, c.lightened(0.18))
			img.set_pixel(x, (y + 1) % 128, c.lightened(0.08))
	var m := flat(Color(1, 1, 1))
	m.albedo_texture = ImageTexture.create_from_image(img)
	_fix_img(img)
	m.albedo_texture = ImageTexture.create_from_image(img)
	_cache()["roof"] = m
	return m


## Дверь подъезда (металл, тёплые тона)
static func door_mat() -> StandardMaterial3D:
	if _cache().has("door"):
		return _cache()["door"]
	var img := Image.create(32, 64, false, Image.FORMAT_RGB8)
	var base := Color(0.30, 0.36, 0.30)
	for y in range(64):
		for x in range(32):
			var c := base
			if x < 2 or x > 29 or y < 2:
				c = Color(0.85, 0.85, 0.82)
			elif y > 46 and (x % 8 < 4):
				c = base.darkened(0.25)
			if y == 32:
				c = base.darkened(0.3)
			if x == 25 and y > 26 and y < 38:
				c = Color(0.85, 0.83, 0.7)
			img.set_pixel(x, y, c)
	_fix_img(img)
	var m := flat(Color(1, 1, 1))
	m.albedo_texture = ImageTexture.create_from_image(img)
	_cache()["door"] = m
	return m


## Профлист забора (вертикальные волны)
static func proflist(col: Color) -> StandardMaterial3D:
	var key := "prof_" + col.to_html(false)
	if _cache().has(key):
		return _cache()[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var f := 0.75 + 0.35 * absf(sin(float(x) * 0.5))
			var c := col * f
			if y < 2:
				c = col.lightened(0.3)
			img.set_pixel(x, y, c)
	_fix_img(img)
	var m := flat(Color(1, 1, 1), 0.4, 0.6)
	m.albedo_texture = ImageTexture.create_from_image(img)
	_cache()[key] = m
	return m


## Жалюзийные ворота ракушки
static func shutter() -> StandardMaterial3D:
	if _cache().has("shutter"):
		return _cache()["shutter"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var f := 0.8 if (y % 6 < 3) else 1.05
			var c := Color(0.62, 0.6, 0.55) * f
			if x < 2 or x > 61:
				c = Color(0.45, 0.44, 0.4)
			img.set_pixel(x, y, c)
	_fix_img(img)
	var m := flat(Color(1, 1, 1))
	m.albedo_texture = ImageTexture.create_from_image(img)
	_cache()["shutter"] = m
	return m


## Козырёк подъезда (сотовый поликарбонат)
static func canopy_mat() -> StandardMaterial3D:
	if _cache().has("canopy"):
		return _cache()["canopy"]
	var img := noise_img(64, 64, 0.8, 9, Color(0.35, 0.45, 0.52), 0.06)
	for y in range(0, 64, 8):
		for x in range(64):
			img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.25))
	var m := flat(Color(1, 1, 1), 0.2, 0.5)
	m.albedo_texture = ImageTexture.create_from_image(img)
	_cache()["canopy"] = m
	return m


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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = ImageTexture.create_from_image(
		noise_img(64, 64, 0.25, 21, Color(0.45, 0.32, 0.18), 0.35))
	m.roughness = 1.0
	_cache()[key] = m
	return m


static func foliage(variant: int) -> StandardMaterial3D:
	var colors := [Color(0.16, 0.34, 0.12), Color(0.22, 0.40, 0.13), Color(0.30, 0.42, 0.14)]
	return flat(colors[abs(variant) % colors.size()])
