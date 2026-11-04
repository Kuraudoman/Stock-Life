extends Control
## 主角状态立绘：表情反映情绪，外观反映身体状态，旁边是状态标签与体力 / 压力。
## 角色本身由 portrait_view 画，没有底框。点击发起走势预测。

signal portrait_clicked

const UI := preload("res://scripts/ui/ui_style.gd")
const Life := preload("res://scripts/core/life.gd")
const PortraitView := preload("res://scripts/ui/portrait_view.gd")

var _hover := false
var _portrait: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	EventBus.game_loaded.connect(_refresh)
	EventBus.day_started.connect(func(_d): _refresh())
	EventBus.market_closed.connect(func(_s): _refresh())
	EventBus.player_changed.connect(_refresh)
	_portrait = PortraitView.new()
	_portrait.follow_state = true
	_portrait.who = "heroine"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.z_index = -1
	add_child(_portrait)
	_refresh()


func _refresh() -> void:
	if GameState.has_game:
		tooltip_text = "%s\n点击发起走势预测" % Life.note(GameState.player)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		portrait_clicked.emit()
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout_portrait()
			queue_redraw()
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()


func _draw() -> void:
	if not GameState.has_game:
		return
	var font := get_theme_default_font()
	var p: Dictionary = GameState.player
	var mood := String(p.get("mood", "calm"))
	var body := String(p.get("body", "healthy"))
	var mc: Color = UI.MOOD_COLORS.get(mood, UI.MOOD_COLORS.calm)
	var frame := _layout_portrait()

	# 右侧文字
	var bold := get_theme_font("font", "RibbonLabel")
	var x := frame.end.x + 10.0
	var w := size.x - x
	draw_string(bold, Vector2(x, 20), String(p.get("name", "希雅")), HORIZONTAL_ALIGNMENT_LEFT, w, 19, UI.ACCENT)
	draw_string(font, Vector2(x, 38), "见习交易员", HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.MUTED)
	# 状态标签，如“狂热 · 感冒”
	var tag := "%s · %s" % [UI.MOOD_NAMES.get(mood, mood), UI.BODY_NAMES.get(body, body)]
	var tag_rect := Rect2(x, 48, minf(w, 120.0), 26)
	draw_rect(tag_rect, Color(mc, 0.25), true)
	draw_rect(tag_rect, mc.darkened(0.3), false, 2.0)
	draw_string(bold, Vector2(x, 66), tag, HORIZONTAL_ALIGNMENT_CENTER, tag_rect.size.x, 14, mc.darkened(0.5))
	# 体力 / 压力条
	_draw_bar(font, Vector2(x, 94), w, "体力", float(p.get("hp", 100)), UI.HP_COLOR)
	_draw_bar(font, Vector2(x, 124), w, "压力", float(p.get("stress", 0)), UI.STRESS_COLOR)
	var aff := int(GameState.affection.get("noelle", 0))
	draw_string(font, Vector2(x, 154), "诺艾尔好感 %d" % aff, HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.DOWN)
	if body == "hospital":
		draw_string(font, Vector2(x, size.y - 26), "住院中（%d 天）" % int(p.get("hospitalDays", 0)), HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.WARN)
	else:
		draw_string(font, Vector2(x, size.y - 26), "今日可预测 %d 次" % int(p.get("predictionsLeft", 3)),
				HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.MUTED)
	draw_string(bold, Vector2(x, size.y - 8), "▶ 点我预测走势", HORIZONTAL_ALIGNMENT_LEFT, w, 13,
			UI.ACCENT.lightened(0.15) if _hover else UI.ACCENT)


func _layout_portrait() -> Rect2:
	var frame := Rect2(0, 0, minf(size.x * 0.5, 150.0), size.y)
	if _portrait:
		_portrait.position = frame.position
		_portrait.size = frame.size
	return frame


func _draw_bar(font: Font, pos: Vector2, w: float, label: String, v: float, color: Color) -> void:
	draw_string(font, pos, "%s %d" % [label, int(v)], HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.TEXT)
	UI.draw_bar(self, Rect2(pos.x + 1, pos.y + 6, minf(w, 120.0) - 2, 8), v / 100.0, color)
