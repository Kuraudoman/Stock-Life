extends "res://scripts/ui/overlay.gd"
## 角色对话（GDD 第 10 节）：主角与对方的半身立绘 + 对话框 + 选项。
## 台词格式见 data/dialogues/tutorial.json：{who, expr, text}；choices 为最后的选项 {text, affection, reply}。
## 说话的一方亮起，另一方变暗。点击对话框、空格或回车继续；文字逐字显示，再点一下直接显示全文。

const CHARS_PER_SEC := 45.0

@onready var left_portrait: Control = %LeftPortrait
@onready var right_portrait: Control = %RightPortrait
@onready var box: PanelContainer = %Box
@onready var name_label: Label = %NameLabel
@onready var text_label: RichTextLabel = %TextLabel
@onready var choices_box: HBoxContainer = %Choices
@onready var skip_button: Button = %SkipButton
@onready var next_button: Button = %NextButton

var lines: Array = []
var choices: Array = []
var _index := -1
var _chosen := false
var _tween: Tween


## 在加入场景树之前调用。
func setup(p_lines: Array, p_choices: Array = []) -> void:
	lines = p_lines.duplicate(true)
	choices = p_choices


func _ready() -> void:
	next_button.pressed.connect(_advance)
	skip_button.pressed.connect(func(): close())
	box.gui_input.connect(_on_box_input)
	text_label.gui_input.connect(_on_box_input)
	left_portrait.who = "heroine"
	# 右边站着第一个不是主角的说话人
	for line in lines:
		if String(line.get("who", "")) != "heroine":
			right_portrait.who = String(line.who)
			break
	if right_portrait.who == "heroine":
		right_portrait.visible = false
	_show(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance()
		get_viewport().set_input_as_handled()


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _show(i: int) -> void:
	if i >= lines.size():
		close()
		return
	_index = i
	var line: Dictionary = lines[i]
	var who := String(line.get("who", "noelle"))
	var expr := String(line.get("expr", "normal"))
	if who == "heroine":
		var layers: Dictionary = _heroine_layers(expr)
		left_portrait.set_character("heroine", layers.expr, layers.overlays, false)
		right_portrait.dim = true
		right_portrait.queue_redraw()
		name_label.text = String(GameState.player.get("name", "希雅"))
	else:
		right_portrait.visible = true
		right_portrait.set_character(who, expr, [], false)
		left_portrait.dim = true
		left_portrait.queue_redraw()
		name_label.text = String(GameState.character(who).get("name", who))
	text_label.text = GameState.fill_text(String(line.get("text", "")))
	text_label.visible_ratio = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(text_label, "visible_ratio", 1.0, maxf(0.15, text_label.get_total_character_count() / CHARS_PER_SEC))
	var last := i == lines.size() - 1
	next_button.text = "继续 ▶" if not last or (not choices.is_empty() and not _chosen) else "关闭"
	next_button.visible = true


## 主角对话表情。不在这套立绘里的名字退回 smile。
const HEROINE_ART := ["smile", "grin", "frown", "coin", "panic", "sleepy", "cold", "dizzy", "hospital", "cry", "ecstatic"]


func _heroine_layers(expr: String) -> Dictionary:
	if expr not in HEROINE_ART:
		expr = "smile"
	return {"expr": expr, "overlays": []}


func _advance() -> void:
	if not choices_box.get_children().is_empty():
		return  # 等玩家选
	if text_label.visible_ratio < 1.0:
		if _tween:
			_tween.kill()
		text_label.visible_ratio = 1.0
		return
	if _index < lines.size() - 1:
		_show(_index + 1)
	elif not choices.is_empty() and not _chosen:
		_show_choices()
	else:
		close()


func _show_choices() -> void:
	next_button.visible = false
	for i in choices.size():
		var b := Button.new()
		b.text = GameState.fill_text(String(choices[i].text))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(_choose.bind(i))
		choices_box.add_child(b)


func _choose(i: int) -> void:
	_chosen = true
	for b in choices_box.get_children():
		b.queue_free()
	var c: Dictionary = choices[i]
	var aff: Dictionary = c.get("affection", {})
	for who in aff:
		GameState.add_affection(String(who), int(aff[who]))
	if c.has("reply"):
		lines.append(c.reply)
		# 等按钮真正移除后再显示回应，避免 _advance 以为还在选择中
		await get_tree().process_frame
		_show(lines.size() - 1)
	else:
		close()
