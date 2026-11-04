class_name SaveManager
extends RefCounted

## 存档：user://save.json
## 写入是原子的 —— 先写 .tmp，再把旧档挪成 .bak，最后把 .tmp 改名成正式档。
## 读取时正式档坏了就退回 .bak。schema 见 spec.md「技术」表。

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"

const SCHEMA_VERSION := 1


static func default_data() -> Dictionary:
	var plots: Array = []
	for i in Balance.PLOT_COUNT:
		plots.append({"state": "empty", "planted_at": 0})
	return {
		"version": SCHEMA_VERSION,
		"coins": Balance.START_COINS,
		"plots": plots,
		"last_seen_at": int(Time.get_unix_time_from_system()),
	}


static func load_data() -> Dictionary:
	var data := _read_json(SAVE_PATH)
	if data.is_empty():
		data = _read_json(BAK_PATH)
	if data.is_empty() or not data.has("plots"):
		return default_data()
	if int(data.get("version", 0)) != SCHEMA_VERSION:
		# M1 还没有迁移逻辑：版本对不上就当新档，别让旧档把游戏卡死。
		push_warning("save version mismatch, starting fresh")
		return default_data()
	return data


static func save_data(data: Dictionary) -> bool:
	data["last_seen_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot open tmp save: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var abs_tmp := ProjectSettings.globalize_path(TMP_PATH)
	var abs_save := ProjectSettings.globalize_path(SAVE_PATH)
	var abs_bak := ProjectSettings.globalize_path(BAK_PATH)

	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BAK_PATH):
			DirAccess.remove_absolute(abs_bak)
		if DirAccess.rename_absolute(abs_save, abs_bak) != OK:
			push_warning("could not rotate save to .bak")
	if DirAccess.rename_absolute(abs_tmp, abs_save) != OK:
		push_error("atomic rename failed")
		return false
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("corrupt save at %s" % path)
		return {}
	return parsed
