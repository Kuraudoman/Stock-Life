extends "res://scripts/ui/overlay.gd"
## 晚间城市地图。大地图上选城区，弹出卡片，前往之后才进入该城区的行动列表。
## 休市日会连续过：睡完一晚如果下一天不开市，这张地图刷新成下一天，不回到交易界面。

const Calendar := preload("res://scripts/core/calendar.gd")
const Evening := preload("res://scripts/core/evening.gd")
const UI := preload("res://scripts/ui/ui_style.gd")
const DialogScene := preload("res://scenes/dialog.tscn")

@onready var title: Label = %Title
@onready var ap_label: Label = %ApLabel
@onready var stats_label: Label = %StatsLabel
@onready var map = %Map
@onready var district: Control = %District
@onready var backdrop: TextureRect = %Backdrop
@onready var back_button: Button = %BackButton
@onready var place_title: Label = %PlaceTitle
@onready var place_blurb: Label = %PlaceBlurb
@onready var actions_box: VBoxContainer = %Actions
@onready var log_label: RichTextLabel = %Log
@onready var hint_label: Label = %HintLabel
@onready var end_button: Button = %EndButton
@onready var heroine: Control = %Heroine
@onready var modal: Control = %Modal
@onready var card: Control = %Card
@onready var modal_image: TextureRect = %ModalImage
@onready var modal_title: Label = %ModalTitle
@onready var modal_blurb: Label = %ModalBlurb
@onready var modal_note: Label = %ModalNote
@onready var go_button: Button = %GoButton

var _selected := ""
var _card_id := ""
var _in_district := false
var _carry: Array = []
var _tween: Tween


func _ready() -> void:
	end_button.pressed.connect(_on_end)
	back_button.pressed.connect(_show_map)
	go_button.pressed.connect(_on_go)
	map.location_picked.connect(_open_card)
	%Dimmer.gui_input.connect(_on_dimmer_input)
	card.resized.connect(func() -> void: card.pivot_offset = card.size * 0.5)
	_show_map()
	var tut := GameState.consume_tutorial("evening")
	if not tut.is_empty():
		_show_lines(tut.get("lines", []))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _dialog_open():
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE
	var right: bool = event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT
	if not esc and not right:
		return
	if modal.visible:
		_close_modal()
		get_viewport().set_input_as_handled()
	elif _in_district:
		_show_map()
		get_viewport().set_input_as_handled()


func open_card(id: String) -> void:
	_open_card(id)


func enter_district(id: String) -> void:
	_selected = id
	_card_id = id
	_enter_district()


func _dialog_open() -> bool:
	for c in get_children():
		if c.name == "Dialog" and c is CanvasItem and (c as CanvasItem).visible:
			return true
	return false


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_modal()


func _open_card(id: String) -> void:
	var snap := GameState.evening_snapshot()
	var loc := _location(snap.get("locations", []), id)
	if loc.is_empty():
		return
	if Evening.district_closed(id, bool(snap.get("hospital", false)), bool(snap.get("fever", false))) != "":
		return
	_card_id = id
	modal_title.text = String(loc.get("name", ""))
	modal_blurb.text = String(loc.get("blurb", ""))
	modal_note.text = _note(loc, snap)
	var picture := Evening.load_background(String(loc.get("background", "")))
	modal_image.texture = picture
	go_button.disabled = false
	go_button.text = "前往"
	modal.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modal.modulate.a = 0.0
	card.scale = Vector2(0.94, 0.94)
	card.pivot_offset = card.size * 0.5
	_tween = create_tween()
	_tween.tween_property(modal, "modulate:a", 1.0, 0.15)
	_tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _close_modal() -> void:
	if not modal.visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(modal, "modulate:a", 0.0, 0.12)
	_tween.tween_callback(func() -> void: modal.visible = false)


func _on_go() -> void:
	_selected = _card_id
	_enter_district()


func _enter_district() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modal.visible = false
	modal.modulate.a = 1.0
	_in_district = true
	map.visible = false
	district.visible = true
	_refresh()


func _show_map() -> void:
	_in_district = false
	district.visible = false
	map.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modal.visible = false
	_refresh()


func _refresh() -> void:
	var snap := GameState.evening_snapshot()
	title.text = "%s · %s" % [Calendar.format_date(GameState.day), String(snap.get("title", "晚间"))]
	ap_label.text = "行动点 %d / %d" % [int(snap.get("ap", 0)), int(snap.get("ap_max", 0))]
	var ap_color := UI.WARN if int(snap.ap) == 0 else UI.ACCENT
	ap_label.add_theme_color_override("font_color", ap_color)
	stats_label.text = "%s\n%s" % [snap.get("stats", ""), snap.get("assets", "")]
	hint_label.text = String(snap.get("hint", ""))
	map.set_state(snap.get("locations", []), _blocked(snap))
	if _in_district:
		_fill_district(snap)
	end_button.text = "睡到天亮 ▶" if bool(snap.get("hospital", false)) else "结束今晚，回去睡觉 ▶"
	if heroine:
		heroine.queue_redraw()


func _blocked(snap: Dictionary) -> Dictionary:
	var out := {}
	var hospital := bool(snap.get("hospital", false))
	var fever := bool(snap.get("fever", false))
	for loc in snap.get("locations", []):
		var id := String(loc.get("id", ""))
		var reason := Evening.district_closed(id, hospital, fever)
		if reason != "":
			out[id] = reason
	return out


func _fill_district(snap: Dictionary) -> void:
	var loc := _location(snap.get("locations", []), _selected)
	if loc.is_empty():
		_show_map()
		return
	_selected = String(loc.id)
	place_title.text = "%s  ·  %s" % [loc.get("name", ""), loc.get("area", "")]
	place_blurb.text = String(loc.get("blurb", ""))
	var picture := Evening.load_background(String(loc.get("background", "")))
	backdrop.texture = picture
	_fill_actions(loc.get("actions", []))
	var lines: PackedStringArray = []
	for c in _carry:
		lines.append(String(c))
	for line in snap.get("log", []):
		lines.append(String(line))
	log_label.text = "\n".join(lines) if lines.size() > 0 else "今晚还没在这里安排什么。"


func _note(loc: Dictionary, snap: Dictionary) -> String:
	var bits: PackedStringArray = []
	for action in loc.get("actions", []):
		var name := String(action.get("name", ""))
		var detail := String(action.get("detail", ""))
		if not bool(action.get("enabled", false)):
			continue
		bits.append("%s（%s）" % [name, detail] if detail != "" else name)
		if bits.size() >= 3:
			break
	if bits.is_empty():
		return "今晚这里暂时没什么能做的。行动点还剩 %d。" % int(snap.get("ap", 0))
	return "行动点还剩 %d。可做：%s" % [int(snap.get("ap", 0)), "、".join(bits)]


func _location(locs: Array, id: String) -> Dictionary:
	for loc in locs:
		if String(loc.get("id", "")) == id:
			return loc
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
		_show_map()
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
