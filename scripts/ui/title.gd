extends Control
## 标题与存档：新游戏（主角名字、随机种子、是否播放教学）、继续、存档列表、打开存档文件夹。

const MAIN_SCENE := "res://scenes/main.tscn"

@onready var name_edit: LineEdit = %NameEdit
@onready var tutorial_button: Button = %TutorialButton
@onready var seed_edit: LineEdit = %SeedEdit
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var slot_list: ItemList = %SlotList
@onready var load_button: Button = %LoadButton
@onready var refresh_button: Button = %RefreshButton
@onready var open_folder_button: Button = %OpenFolderButton
@onready var save_dir_label: Label = %SaveDirLabel
@onready var status_label: Label = %StatusLabel
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel

var _saves: Array = []


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	load_button.pressed.connect(_on_load_selected)
	refresh_button.pressed.connect(_refresh_slots)
	open_folder_button.pressed.connect(SaveManager.open_save_folder)
	quit_button.pressed.connect(func(): get_tree().quit())
	slot_list.item_selected.connect(func(_i): load_button.disabled = false)
	slot_list.item_activated.connect(func(i): _load_path(_saves[i].path))
	seed_edit.text_submitted.connect(func(_t): _on_new_game())
	name_edit.text_submitted.connect(func(_t): _on_new_game())
	tutorial_button.toggled.connect(func(on): tutorial_button.text = "诺艾尔教学：%s" % ("开" if on else "关"))
	version_label.text = "v%s · M1 MVP" % ProjectSettings.get_setting("application/config/version", "0.2.0")
	save_dir_label.text = "存档位置：%s" % SaveManager.save_dir
	if SaveManager.using_fallback:
		save_dir_label.text += "\n（游戏目录没有写入权限，已改用用户数据目录）"
	_refresh_slots()
	new_game_button.grab_focus()


func _refresh_slots() -> void:
	slot_list.clear()
	_saves = SaveManager.list_saves()
	for s in _saves:
		var text := "%s    %s    %s" % [s.name, s.label, String(s.savedAt).replace("T", " ")]
		var idx := slot_list.add_item(text)
		if not s.valid:
			slot_list.set_item_custom_fg_color(idx, Color(0.812, 0.231, 0.196))
	if _saves.is_empty():
		slot_list.add_item("（还没有存档）")
		slot_list.set_item_disabled(0, true)
	load_button.disabled = true
	continue_button.disabled = SaveManager.latest_save_path() == ""


func _on_new_game() -> void:
	var t := seed_edit.text.strip_edges()
	var game_seed := -1
	if t != "":
		# 数字直接作为种子；文字也可以，用它的哈希值
		game_seed = absi(t.to_int()) if t.is_valid_int() else absi(t.hash())
	GameState.new_game(game_seed, name_edit.text, tutorial_button.button_pressed)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_continue() -> void:
	_load_path(SaveManager.latest_save_path())


func _on_load_selected() -> void:
	var sel := slot_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _saves.size():
		return
	_load_path(_saves[sel[0]].path)


func _load_path(path: String) -> void:
	if path == "":
		return
	if SaveManager.load_game(path):
		get_tree().change_scene_to_file(MAIN_SCENE)
	else:
		status_label.text = "无法读取 %s：%s" % [path.get_file(), SaveManager.last_error]
