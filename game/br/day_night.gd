extends Node
## Цикл дня и ночи: солнце, луна, небо, туман, ночная подсветка города.

var TL = load("res://br/texture_lib.gd")

const DAY_LEN := 600.0  # полные сутки за 10 минут

var time_h := 9.0
var night := 0.0
var day := 1.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var base_shadow := true

var _sky_mat: ProceduralSkyMaterial

const DAY_TOP := Color(0.36, 0.62, 0.86)
const DAY_HOR := Color(0.72, 0.8, 0.86)
const NIGHT_TOP := Color(0.015, 0.025, 0.07)
const NIGHT_HOR := Color(0.05, 0.07, 0.14)
const DUSK := Color(0.9, 0.5, 0.3)


func setup(p_sun: DirectionalLight3D, p_moon: DirectionalLight3D, p_env: Environment) -> void:
	sun = p_sun
	moon = p_moon
	env = p_env
	_sky_mat = (env.sky.sky_material as ProceduralSkyMaterial)
	_apply(true)


func _process(delta: float) -> void:
	time_h = fmod(time_h + delta * 24.0 / DAY_LEN, 24.0)
	_apply(false)


func _apply(force: bool) -> void:
	var ang := (time_h - 6.0) / 12.0 * PI
	var elev := sin(ang)
	day = clampf(elev * 2.0, 0.0, 1.0)
	night = clampf(-elev * 2.6, 0.0, 1.0)
	# солнце
	if sun != null:
		sun.rotation = Vector3(deg_to_rad(-72.0 * clampf(elev, -0.25, 1.0)), deg_to_rad(time_h * 15.0 - 90.0), 0.0)
		sun.light_energy = 1.15 * day
		sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.6, 0.35), clampf(1.0 - elev * 3.0, 0.0, 1.0))
		sun.shadow_enabled = base_shadow and day > 0.03
	if moon != null:
		moon.rotation = Vector3(deg_to_rad(72.0 * clampf(night, 0.0, 1.0) - 20.0), deg_to_rad(time_h * 15.0 + 90.0), 0.0)
		moon.light_energy = 0.25 * night
	# небо и свет среды
	if _sky_mat != null:
		var dusk_f := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0)
		_sky_mat.sky_top_color = DAY_TOP.lerp(NIGHT_TOP, night).lerp(DUSK.darkened(0.4), dusk_f * 0.35 * day)
		_sky_mat.sky_horizon_color = DAY_HOR.lerp(NIGHT_HOR, night).lerp(DUSK, dusk_f * 0.5 * maxf(day, 0.15))
		_sky_mat.ground_bottom_color = NIGHT_HOR.lerp(Color(0.2, 0.22, 0.2), day)
		_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	if env != null:
		env.ambient_light_energy = 0.28 + day * 0.55
		env.ambient_light_color = Color(0.6, 0.7, 0.85).lerp(Color(0.25, 0.3, 0.45), night)
		env.fog_density = 0.0015 + night * 0.012
		env.fog_light_color = _sky_mat.sky_horizon_color if _sky_mat != null else Color(0.5, 0.5, 0.5)
	TL.set_night(night)


func clock_text() -> String:
	var h := int(time_h)
	var m := int(fmod(time_h, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
