extends Control

const MANIFEST_URL := "https://www.arh.seaetr.online/updates/latest.json"
const CURRENT_VERSION := "0.2.0"

var status_label: Label
var version_label: Label
var update_button: Button
var progress: ProgressBar
var manifest: Dictionary = {}
var local_version: String = CURRENT_VERSION


func _ready() -> void:
	local_version = _read_local_version()
	_build_ui()
	_check_for_updates()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("17131f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Аукцион"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",  thirty_two())
	box.add_child(title)
	version_label = Label.new()
	version_label.text = "Установлена версия %s" % local_version
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version_label)
	status_label = Label.new()
	status_label.text = "Проверка обновлений..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	progress = ProgressBar.new()
	progress.visible = false
	box.add_child(progress)
	update_button = Button.new()
	update_button.text = "Запустить игру"
	update_button.disabled = true
	update_button.custom_minimum_size = Vector2(0, 48)
	update_button.pressed.connect(_launch_game)
	box.add_child(update_button)


func thirty_two() -> int:
	return 32


func _check_for_updates() -> void:
	var request := HTTPRequest.new()
	add_child(request)
	var error := request.request(MANIFEST_URL)
	if error != OK:
		status_label.text = "Сервер обновлений недоступен. Запускается текущая версия."
		update_button.disabled = false
		return
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[1]) < 200 or int(result[1]) >= 300:
		status_label.text = "Не удалось проверить обновления."
		update_button.disabled = false
		return
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		status_label.text = "Некорректный ответ сервера обновлений."
		update_button.disabled = false
		return
	manifest = parsed
	var remote_version := String(manifest.get("version", CURRENT_VERSION))
	if _is_newer(remote_version, local_version):
		status_label.text = "Доступно обновление %s" % remote_version
		update_button.text = "Обновить и запустить"
		update_button.disabled = false
		update_button.pressed.disconnect(_launch_game)
		update_button.pressed.connect(_update_and_launch)
	else:
		status_label.text = "Установлена последняя версия."
		update_button.disabled = false


func _is_newer(remote: String, local: String) -> bool:
	var r := remote.split(".")
	var l := local.split(".")
	for index in 3:
		var rv := int(r[index]) if index < r.size() else 0
		var lv := int(l[index]) if index < l.size() else 0
		if rv != lv:
			return rv > lv
	return false


func _read_local_version() -> String:
	var path := OS.get_executable_path().get_base_dir().path_join("client_version.txt")
	if not FileAccess.file_exists(path):
		return CURRENT_VERSION
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text().strip_edges() if file else CURRENT_VERSION


func _update_and_launch() -> void:
	var url := String(manifest.get("download", ""))
	var expected_hash := String(manifest.get("sha256", "")).to_lower()
	if url.is_empty() or expected_hash.is_empty():
		status_label.text = "В манифесте отсутствуют данные обновления."
		return
	update_button.disabled = true
	progress.visible = true
	progress.value = 0
	status_label.text = "Скачивание обновления..."
	var archive_path := OS.get_user_data_dir().path_join("auction_update.zip")
	var request := HTTPRequest.new()
	request.download_file = archive_path
	add_child(request)
	var error := request.request(url)
	if error != OK:
		status_label.text = "Не удалось начать скачивание."
		update_button.disabled = false
		return
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[1]) < 200 or int(result[1]) >= 300:
		status_label.text = "Сервер не отдал архив обновления."
		update_button.disabled = false
		return
	var file := FileAccess.open(archive_path, FileAccess.READ)
	var actual_hash := HashingContext.new()
	actual_hash.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		actual_hash.update(file.get_buffer(mini(1048576, file.get_length() - file.get_position())))
	var digest := actual_hash.finish().hex_encode().to_lower()
	file.close()
	if digest != expected_hash:
		status_label.text = "Проверка обновления не пройдена."
		update_button.disabled = false
		return
	status_label.text = "Установка обновления..."
	var zip := ZIPReader.new()
	if zip.open(archive_path) != OK:
		status_label.text = "Архив обновления повреждён."
		update_button.disabled = false
		return
	var install_dir := OS.get_executable_path().get_base_dir()
	for entry: String in zip.get_files():
		if not entry.begins_with("game/") or entry.ends_with("/"):
			continue
		var relative := entry.trim_prefix("game/")
		var target := install_dir.path_join("game").path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var target_file := FileAccess.open(target, FileAccess.WRITE)
		target_file.store_buffer(zip.read_file(entry))
		target_file.close()
	zip.close()
	DirAccess.remove_absolute(archive_path)
	var version_file := FileAccess.open(install_dir.path_join("client_version.txt"), FileAccess.WRITE)
	version_file.store_string(String(manifest.get("version", CURRENT_VERSION)))
	version_file.close()
	_launch_game()


func _launch_game() -> void:
	var game_path := OS.get_executable_path().get_base_dir().path_join("game").path_join("Auction.exe")
	if not FileAccess.file_exists(game_path):
		status_label.text = "Файл игры не найден: %s" % game_path
		return
	OS.create_process(game_path, [])
	get_tree().quit()
