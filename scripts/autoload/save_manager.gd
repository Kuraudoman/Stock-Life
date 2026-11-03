extends Node
## 存档读写、校验、版本迁移（GDD 第 11 节“存档系统”）。
##
## - 每个存档是 saves 文件夹里的一个独立 JSON 文件：<存档名>.stocklife.json
## - 每天收盘后自动覆盖 autosave.stocklife.json
## - 先写临时文件，成功后再替换旧存档，避免写到一半崩溃导致存档损坏
## - 用 JSON 而不是 .tres/.res：Resource 加载时可能执行嵌入脚本，分享存档不安全

const FORMAT := "stock-life-save"
const SAVE_VERSION := 3
const EXT := ".stocklife.json"
const AUTOSAVE_NAME := "autosave"
const MANUAL_SAVE_NAME := "slot1"

## 实际使用的存档目录（绝对路径）。
var save_dir := ""
## 游戏目录不可写、改用 user://saves 时为 true，标题界面会显示实际路径。
var using_fallback := false
var last_error := ""


func _ready() -> void:
	save_dir = get_save_dir()


func get_save_dir() -> String:
	var dir: String
	if OS.has_feature("editor"):
		dir = ProjectSettings.globalize_path("res://saves")
	elif OS.get_name() == "macOS":
		dir = ProjectSettings.globalize_path("user://saves")
	else:
		dir = OS.get_executable_path().get_base_dir().path_join("saves")
	using_fallback = false
	if not _ensure_writable(dir):
		dir = ProjectSettings.globalize_path("user://saves")
		using_fallback = true
		_ensure_writable(dir)
	return dir


func _ensure_writable(dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return false
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func path_for(slot_name: String) -> String:
	return save_dir.path_join(slot_name + EXT)


# ---------------------------------------------------------------- 写入

func save_game(slot_name: String = MANUAL_SAVE_NAME, is_auto: bool = false) -> bool:
	if not GameState.has_game:
		return false
	var doc := {
		"format": FORMAT,
		"saveVersion": SAVE_VERSION,
		"gameVersion": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"savedAt": Time.get_datetime_string_from_system(false, false),
		"label": GameState.save_label(),
		"data": GameState.to_save_data(),
	}
	var path := path_for(slot_name)
	if not write_json_atomic(path, doc):
		EventBus.message_posted.emit("【存档失败】%s" % last_error, "warn")
		return false
	EventBus.game_saved.emit(path, is_auto)
	if not is_auto:
		EventBus.message_posted.emit("【存档】已保存到 %s" % path.get_file(), "info")
	return true


func autosave() -> bool:
	return save_game(AUTOSAVE_NAME, true)


func write_json_atomic(path: String, doc: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "无法写入 %s（错误 %d）" % [tmp, FileAccess.get_open_error()]
		return false
	f.store_string(JSON.stringify(doc, "\t", false, true))
	f.close()
	# 校验临时文件能被完整读回，再替换旧存档
	if read_json(tmp).is_empty():
		last_error = "临时文件校验失败"
		return false
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		# 替换失败时恢复旧存档
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, path)
		last_error = "替换存档失败（错误 %d）" % err
		return false
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return true


# ---------------------------------------------------------------- 读取与校验

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 读取并校验存档。成功返回存档文档（已迁移到当前版本），失败返回空字典并设置 last_error。
func load_doc(path: String) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "找不到存档文件"
		return {}
	var doc := read_json(path)
	if doc.is_empty():
		last_error = "存档已损坏，或不是 JSON 文件"
		return {}
	if doc.get("format", "") != FORMAT:
		last_error = "这不是 Stock-Life 的存档"
		return {}
	var v := int(doc.get("saveVersion", 0))
	if v > SAVE_VERSION:
		last_error = "存档来自更新版本的游戏（存档版本 %d），请先升级游戏" % v
		return {}
	doc = migrate(doc)
	var err := validate_data(doc.get("data", null))
	if err != "":
		last_error = "存档数据不完整：%s" % err
		return {}
	return doc


func load_game(path: String) -> bool:
	var doc := load_doc(path)
	if doc.is_empty():
		return false
	GameState.apply_save_data(doc.data)
	return true


static func validate_data(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "缺少 data"
	for k in ["seed", "day", "cash", "debt", "holdings", "market", "player"]:
		if not data.has(k):
			return "缺少字段 %s" % k
	var m: Variant = data.market
	if typeof(m) != TYPE_DICTIONARY:
		return "market 格式错误"
	for k in ["seed", "rngState", "currentDay", "lastCloseDay", "isOpen", "tick", "stocks"]:
		if not m.has(k):
			return "缺少字段 market.%s" % k
	var companies := GameState.load_companies()
	for c in companies:
		if not m.stocks.has(c.id):
			return "缺少股票 %s" % c.id
	return ""


## 按版本号逐级升级旧存档。新增版本时在这里加一个分支。
static func migrate(doc: Dictionary) -> Dictionary:
	var v := int(doc.get("saveVersion", 1))
	while v < SAVE_VERSION:
		match v:
			1:
				# M1：新闻事件日程、预测记录、第一章状态。事件日程留空，读档时按种子重新生成，
				# 已经过去的消息当作发生过（GameState.apply_save_data）；主角的新字段由 Life.normalize 补齐。
				var data: Dictionary = doc.get("data", {})
				data["events"] = {}
				data["predictions"] = []
				data["predStats"] = {"made": 0, "resolved": 0, "hits": 0}
				data["chapterState"] = "active"
				var fl: Dictionary = data.get("flags", {})
				fl.erase("chapter1_over_notice")
				# 旧存档已经过了开局，跳过开场剧情
				fl["tut_intro"] = true
				fl["tutorial"] = true
				data["flags"] = fl
				doc["data"] = data
			2:
				# M2 晚间：住所 / 交通 / 服装和进行中的城区由 Life.normalize 与 apply_save_data 补默认值。
				# 版本 2 的存档停在收盘，还没花过行动点，这里显式写成「当晚还没开始」。
				var data2: Dictionary = doc.get("data", {})
				if not data2.has("evening"):
					data2["evening"] = {"active": false}
				doc["data"] = data2
			_:
				pass
		v += 1
	doc.saveVersion = SAVE_VERSION
	return doc


# ---------------------------------------------------------------- 存档列表

## 列出 saves 文件夹中的存档，按保存时间倒序。损坏的文件也会列出并标记。
func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(EXT):
			continue
		var path := save_dir.path_join(file)
		var doc := read_json(path)
		var ok: bool = doc.get("format", "") == FORMAT
		out.append({
			"path": path,
			"name": file.trim_suffix(EXT),
			"label": String(doc.get("label", "")) if ok else "（无法识别的存档）",
			"savedAt": String(doc.get("savedAt", "")) if ok else "",
			"valid": ok,
		})
	out.sort_custom(func(a, b): return a.savedAt > b.savedAt)
	return out


func latest_save_path() -> String:
	for s in list_saves():
		if s.valid:
			return s.path
	return ""


func open_save_folder() -> void:
	OS.shell_open(save_dir)
