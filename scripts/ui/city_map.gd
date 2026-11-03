extends "res://scripts/ui/overlay.gd"
## 晚间城市地图（GDD 第 10 节）。选一个区域，花行动点做事，然后结束今晚。
## 休市日会连续过：睡完一晚如果下一天不开市，这张地图刷新成下一天，不回到交易界面。

const Calendar := preload("res://scripts/core/calendar.gd")
const UI := preload("res://scripts/ui/ui_style.gd")
const DialogScene := preload("res://scenes/dialog.tscn")

@onready var title: Label = %Title
@onready var ap_label: Label = %ApLabel
@onready var stats_label: Label = %StatsLabel
@onready var map = %Map
@onready var place_title: Label = %PlaceTitle
@onready var place_blurb: Label = %PlaceBlurb
@onready var actions_box: VBoxContainer = %Actions
@onready var log_label: RichTextLabel = %Log
@onready var hint_label: Label = %HintLabel
@onready var end_button: Button = %EndButton
@onready var heroine: Control = %Heroine

var _selected := "home"
var _carry: Array = []


func _ready() -> void:
	end_button.pressed.connect(_on_end)
	map.location_selected.connect(_on_location)
	_refresh()
	var tut := GameState.consume_tutorial("evening")
	if not tut.is_empty():
		_show_lines(tut.get("lines", []))


func _on_location(id: String) -> void:
	_selected = id
	_refresh()


func _refresh() -> void:
	var snap := GameState.evening_snapshot()
	title.text = "%s · %s" % [Calendar.format_date(GameState.day), String(snap.get("title", "晚间"))]
	ap_label.text = "行动点 %d / %d" % [int(snap.get("ap", 0)), int(snap.get("ap_max", 0))]
	var ap_color := UI.WARN if int(snap.ap) == 0 else UI.ACCENT
	ap_label.add_theme_color_override("font_color", ap_color)
	stats_label.text = "%s\n%s" % [snap.get("stats", ""), snap.get("assets", "")]
	hint_label.text = String(snap.get("hint", ""))
	map.set_locations(snap.get("locations", []), _selected)
	var loc := _location(snap.get("locations", []), _selected)
	if loc.is_empty():
		place_title.text = ""
		place_blurb.text = ""
		_fill_actions([])
	else:
		_selected = String(loc.id)
		place_title.text = "%s  ·  %s" % [loc.get("name", ""), loc.get("area", "")]
		place_blurb.text = String(loc.get("blurb", ""))
		_fill_actions(loc.get("actions", []))
	var lines: PackedStringArray = []
	for c in _carry:
		lines.append(String(c))
	for line in snap.get("log", []):
		lines.append(String(line))
	log_label.text = "\n".join(lines) if lines.size() > 0 else "今晚还没安排。直接睡觉的话，按早点休息结算。"
	end_button.text = "睡到天亮 ▶" if bool(snap.get("hospital", false)) else "结束今晚，回去睡觉 ▶"
	if heroine:
		heroine.queue_redraw()


func _location(locs: Array, id: String) -> Dictionary:
	for loc in locs:
		if String(loc.get("id", "")) == id:
			return loc
	if not locs.is_empty():
		return locs[0]
	return {}


func _fill_actions(actions: Array) -> void:
	for child in actions_box.get_children():
		actions_box.remove_child(child)
		child.free()
	for action in actions:
		var b := Button.new()
		b.text = String(action.get("name", ""))
		b.disabled = not bool(action.get("enabled", false))
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tip := String(action.get("blurb", ""))
		var detail := String(action.get("detail", ""))
		if detail != "":
			tip += "\n" + detail
		if not bool(action.get("enabled", false)):
			tip = String(action.get("reason", "")) + ("\n" + tip if tip != "" else "")
		b.tooltip_text = tip
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(_on_action.bind(String(action.get("id", ""))))
		actions_box.add_child(b)


func _on_action(id: String) -> void:
	var result := GameState.perform_evening_action(id)
	_refresh()
	var lines: Array = result.get("lines", [])
	if not lines.is_empty():
		_show_lines(lines)


func _on_end() -> void:
	var result := GameState.finish_evening()
	if bool(result.get("another", false)):
		_carry = result.get("notes", [])
		_selected = "home"
		_refresh()
		var tut: Dictionary = result.get("tutorial", {})
		if not tut.is_empty():
			_show_lines(tut.get("lines", []))
		return
	close("done")


func _show_lines(lines: Array) -> void:
	if lines.is_empty():
		return
	var d := DialogScene.instantiate()
	d.setup(lines)
	add_child(d)
	d.closed.connect(func(_r): d.queue_free())
