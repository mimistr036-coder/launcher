extends Control
## Лаунчер «Провинция RP».
## Схема как у Black Russia: лаунчер проверяет версию кэша на сервере обновлений,
## докачивает game.pck и запускает игру прямо из кэша.

const CFG_PATH := "user://launcher.cfg"
const CACHE_DIR := "user://cache"
const PCK_PATH := "user://cache/game.pck"
const PCK_TMP := "user://cache/game.pck.tmp"
const VER_PATH := "user://cache/version.txt"
const DEFAULT_URL := "http://192.168.1.50:8090"

var base_url := ""
var remote := {}           # содержимое version.json
var local_version := 0
var http: HTTPRequest
var news_http: HTTPRequest
var _kind := ""            # version | news | pck
var _state := "boot"       # boot | check | download | ready | error
var _busy := false
var _autotest := false
var _autotest_done := false

# UI
var _title: Label
var _status: Label
var _bar: ProgressBar
var _news: Label
var _play: Button
var _retry: Button
var _cache_ver: Label
var _srv_ver: Label
var _settings: Control
var _url_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	base_url = str(_load_cfg().get_value("main", "updates_url", DEFAULT_URL)).strip_edges()
	var env_url := OS.get_environment("LAUNCHER_URL")
	if env_url != "":
		base_url = env_url.strip_edges()
	local_version = _read_local_version()
	_autotest = OS.get_environment("LAUNCHER_AUTOTEST") != ""
	_build_ui()
	var wd := get_tree().create_timer(120.0)
	wd.timeout.connect(func() -> void:
		if _autotest and not _autotest_done:
			print("[LAUNCHER_AUTOTEST] TIMEOUT")
			get_tree().quit(1))
	_start_check.call_deferred()


static func _load_cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(CFG_PATH)
	return c


func _read_local_version() -> int:
	var f := FileAccess.open(VER_PATH, FileAccess.READ)
	if f == null:
		return 0
	return int(f.get_line().strip_edges())


func _write_local_version(v: int) -> void:
	var f := FileAccess.open(VER_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line(str(v))

# ================= UI =================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var accent := ColorRect.new()
	accent.color = Color(0.95, 0.75, 0.25)
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.custom_minimum_size = Vector2(0, 4)
	add_child(accent)
	_title = _mk_label("ПРОВИНЦИЯ RP", 46, Color(0.95, 0.8, 0.3))
	_title.position = Vector2(60, 34)
	add_child(_title)
	var sub := _mk_label("ЛАУНЧЕР", 18, Color(0.6, 0.65, 0.8))
	sub.position = Vector2(62, 92)
	add_child(sub)
	_news = _mk_label("Загрузка новостей...", 16, Color(0.85, 0.87, 0.92))
	_news.position = Vector2(60, 150)
	_news.custom_minimum_size = Vector2(560, 300)
	_news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_news)
	_status = _mk_label("", 20, Color(1, 1, 1))
	_status.position = Vector2(660, 480)
	_status.custom_minimum_size = Vector2(560, 30)
	add_child(_status)
	_bar = ProgressBar.new()
	_bar.position = Vector2(660, 520)
	_bar.size = Vector2(540, 26)
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	add_child(_bar)
	_cache_ver = _mk_label("Кэш: нет", 15, Color(0.6, 0.9, 0.6))
	_cache_ver.position = Vector2(660, 560)
	add_child(_cache_ver)
	_srv_ver = _mk_label("Сервер: ?", 15, Color(0.6, 0.8, 1.0))
	_srv_ver.position = Vector2(800, 560)
	add_child(_srv_ver)
	_play = _mk_button("ИГРАТЬ", 26, Color(0.2, 0.55, 0.25))
	_play.position = Vector2(660, 600)
	_play.custom_minimum_size = Vector2(260, 64)
	_play.disabled = true
	_play.pressed.connect(_on_play)
	add_child(_play)
	_retry = _mk_button("ПРОВЕРИТЬ ОБНОВЛЕНИЯ", 17, Color(0.2, 0.35, 0.55))
	_retry.position = Vector2(940, 600)
	_retry.custom_minimum_size = Vector2(260, 64)
	_retry.pressed.connect(_start_check)
	add_child(_retry)
	var gear := _mk_button("НАСТРОЙКИ", 15, Color(0.25, 0.25, 0.3))
	gear.position = Vector2(1108, 480)
	gear.custom_minimum_size = Vector2(92, 30)
	gear.pressed.connect(_open_settings)
	add_child(gear)
	_build_settings()
	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_http_done)
	news_http = HTTPRequest.new()
	news_http.timeout = 12.0
	add_child(news_http)
	news_http.request_completed.connect(_on_news_done)


func _mk_label(t: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _mk_button(t: String, sz: int, col: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", sz)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	return b


func _build_settings() -> void:
	_settings = ColorRect.new()
	(_settings as ColorRect).color = Color(0, 0, 0, 0.7)
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	add_child(_settings)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.16)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	_settings.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(_mk_label("НАСТРОЙКИ", 24, Color(1, 1, 1)))
	v.add_child(_mk_label("Адрес сервера обновлений (HTTP):", 15, Color(0.7, 0.75, 0.85)))
	_url_edit = LineEdit.new()
	_url_edit.text = base_url
	_url_edit.add_theme_font_size_override("font_size", 17)
	v.add_child(_url_edit)
	var save := _mk_button("СОХРАНИТЬ", 17, Color(0.2, 0.45, 0.3))
	save.pressed.connect(_close_settings)
	v.add_child(save)


func _open_settings() -> void:
	_url_edit.text = base_url
	_settings.visible = true


func _close_settings() -> void:
	base_url = _url_edit.text.strip_edges().trim_suffix("/")
	var c := _load_cfg()
	c.set_value("main", "updates_url", base_url)
	c.save(CFG_PATH)
	_settings.visible = false
	_start_check()

# ================= поток загрузки =================

func _set_status(t: String) -> void:
	_status.text = t
	print("[launcher] ", t)


func _start_check() -> void:
	if _busy:
		return
	_busy = true
	_state = "check"
	_play.disabled = true
	_bar.value = 0
	_set_status("Проверка обновлений...")
	_kind = "version"
	http.set_download_file("")
	http.timeout = 12.0
	var err := http.request(base_url + "/version.json")
	if err != OK:
		_check_failed("Неверный адрес сервера: " + base_url)


func _check_failed(reason: String) -> void:
	_busy = false
	_state = "error"
	_set_status("Сервер обновлений недоступен (" + reason + ")")
	if local_version > 0 and FileAccess.file_exists(PCK_PATH):
		_set_status("Сервер недоступен. Можно играть с локальным кэшем v%d" % local_version)
		_play.disabled = false
	_srv_ver.text = "Сервер: недоступен"


func _on_http_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _kind == "version":
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_check_failed("код %d" % code)
			return
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed == null or not parsed.has("version"):
			_check_failed("кривой version.json")
			return
		remote = parsed
		_srv_ver.text = "Сервер: v%d" % int(remote.version)
		_busy = false
		_load_news()
		var rv := int(remote.version)
		if rv == local_version and FileAccess.file_exists(PCK_PATH):
			_state = "ready"
			_set_status("Кэш актуален (v%d). Готов к запуску!" % rv)
			_play.disabled = false
			_maybe_autotest_ready()
		else:
			_start_download()
	elif _kind == "pck":
		_finish_download(result, code)


func _start_download() -> void:
	_busy = true
	_state = "download"
	_set_status("Скачивание кэша v%d (%s)..." % [int(remote.version), _fmt_size(float(remote.get("size", 0)))])
	_bar.value = 0
	_kind = "pck"
	http.set_download_file(PCK_TMP)
	http.timeout = 0
	var url := base_url + "/" + str(remote.get("file", "game.pck")) + "?v=" + str(remote.version)
	var err := http.request(url)
	if err != OK:
		_busy = false
		_set_status("Ошибка запуска скачивания")
		return


func _process(_delta: float) -> void:
	if _state == "download" and http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		var total := float(http.get_body_size())
		var done := float(http.get_downloaded_bytes())
		if total > 0:
			_bar.value = done / total * 100.0
			_set_status("Скачивание кэша... %s / %s" % [_fmt_size(done), _fmt_size(total)])


func _finish_download(result: int, code: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_busy = false
		_state = "error"
		DirAccess.remove_absolute(PCK_TMP)
		_set_status("Скачивание не удалось (код %d). Нажми «ПРОВЕРИТЬ ОБНОВЛЕНИЯ»" % code)
		return
	# проверка размера и md5
	var expect_size := int(remote.get("size", -1))
	var expect_md5 := str(remote.get("md5", ""))
	var got_size := -1
	var fa := FileAccess.open(PCK_TMP, FileAccess.READ)
	if fa == null:
		_busy = false
		_state = "error"
		_set_status("Файл кэша не сохранился")
		return
	got_size = int(fa.get_length())
	fa = null
	if expect_size > 0 and got_size != expect_size:
		_busy = false
		_state = "error"
		_set_status("Размер не совпал (%d != %d)" % [got_size, expect_size])
		return
	if expect_md5 != "":
		var got_md5 := FileAccess.get_md5(PCK_TMP)
		if got_md5 != expect_md5:
			_busy = false
			_state = "error"
			_set_status("Контрольная сумма не совпала, скачай ещё раз")
			return
	DirAccess.remove_absolute(PCK_PATH)
	DirAccess.rename_absolute(PCK_TMP, PCK_PATH)
	_write_local_version(int(remote.version))
	local_version = int(remote.version)
	_cache_ver.text = "Кэш: v%d (%s)" % [local_version, _fmt_size(float(got_size))]
	_busy = false
	_state = "ready"
	_bar.value = 100
	_set_status("Готово! Кэш v%d установлен." % local_version)
	_play.disabled = false
	_maybe_autotest_ready()


func _fmt_size(v: float) -> String:
	if v > 1024.0 * 1024.0:
		return "%.1f МБ" % (v / 1024.0 / 1024.0)
	return "%.0f КБ" % (v / 1024.0)

# ================= запуск игры =================

func _on_play() -> void:
	if not FileAccess.file_exists(PCK_PATH):
		_set_status("Кэша нет — нажми «ПРОВЕРИТЬ ОБНОВЛЕНИЯ»")
		return
	_set_status("Запуск игры...")
	if not _mount_cache():
		return
	print("[launcher] кэш смонтирован: boot.tscn=", FileAccess.file_exists("res://br/boot.tscn"),
			" boot.gd=", FileAccess.file_exists("res://br/boot.gd"))
	if not ResourceLoader.exists("res://br/boot.tscn"):
		_set_status("Кэш повреждён (нет сцены игры). Нажми «ПРОВЕРИТЬ ОБНОВЛЕНИЯ»")
		return
	get_tree().change_scene_to_file("res://br/boot.tscn")


## Монтирует кэш. Возвращает true, если внутри есть сцена игры.
func _mount_cache() -> bool:
	var ok: bool = ProjectSettings.load_resource_pack(PCK_PATH, true)
	if not ok:
		var vi := Engine.get_version_info()
		print("[launcher] load_resource_pack=false; Godot=", Engine.get_version_info().string,
				"; путь=", ProjectSettings.globalize_path(PCK_PATH))
		_set_status("Кэш не открылся. Нужен Godot 4.3+ (у тебя %d.%d.%d) — обнови и нажми «ПРОВЕРИТЬ ОБНОВЛЕНИЯ»." % [vi.major, vi.minor, vi.patch])
	return ok


func _load_news() -> void:
	news_http.request(base_url + "/news.json")


func _on_news_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var n = JSON.parse_string(body.get_string_from_utf8())
	if n != null and n.has("news"):
		var lines: Array = []
		for item in n["news"]:
			lines.append("%s — %s\n%s" % [str(item.get("date", "")), str(item.get("title", "")), str(item.get("text", ""))])
		_news.text = "\n\n".join(lines)


func _maybe_autotest_ready() -> void:
	if not _autotest or _autotest_done:
		return
	_autotest_done = true
	var scene: PackedScene = null
	var scr: Script = null
	var bad := ""
	if _mount_cache():
		scene = load("res://br/boot.tscn")
		scr = load("res://br/boot.gd")
		# компилируем ВСЕ скрипты игры: ловит синтаксис неподдерживаемой версии движка
		var dir := DirAccess.open("res://br")
		if dir != null:
			for f in dir.get_files():
				if not f.ends_with(".gd"):
					continue
				var sc: Script = load("res://br/" + f)
				if sc == null or not sc.can_instantiate():
					bad += f + " "
	# can_instantiate() = скрипт игры реально скомпилировался
	if scene != null and scr != null and scr.can_instantiate() and bad.is_empty():
		print("[LAUNCHER_AUTOTEST] OK version=%d size=%d scene=found" % [local_version, int(remote.get("size", 0))])
		get_tree().quit(0)
	else:
		print("[LAUNCHER_AUTOTEST] FAIL scene=", scene, " boot=", scr, " bad_scripts=", bad)
		get_tree().quit(1)
