extends Control
## 看板娘立绘（占位版）：显示所选公司的看板娘，表情随当日涨跌变化（GDD 第 9 节）。

const UI := preload("res://scripts/ui/ui_style.gd")
const Painter := preload("res://scripts/ui/portrait_painter.gd")
const PortraitView := preload("res://scripts/ui/portrait_view.gd")

var _portrait: Control


func _ready() -> void:
	EventBus.game_loaded.connect(queue_redraw)
	EventBus.stock_selected.connect(func(_id): queue_redraw())
	EventBus.tick_advanced.connect(func(_t): queue_redraw())
	EventBus.market_opened.connect(func(_d): queue_redraw())
	EventBus.day_started.connect(func(_d): queue_redraw())
	_portrait = PortraitView.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.z_index = -1
	add_child(_portrait)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_portrait()
		queue_redraw()


func _draw() -> void:
	var id := GameState.selected_id
	if id == "" or not GameState.market.stocks.has(id):
		return
	var font := get_theme_default_font()
	var c: Dictionary = GameState.company(id)
	var m := GameState.market
	var chg := m.day_change(id)
	var p := m.price(id)
	var expr := UI.mascot_expression(chg, p >= m.limit_up(id) and chg > 0.1, p <= m.limit_down(id) and chg < -0.1)
	var frame := _layout_portrait()
	var layers := Painter.mascot_layers(String(expr.name))
	var pv: Control = _portrait
	pv.who = id
	# 涨跌色调乘在角色身上。跌停不再盖一块灰底，改成更重的灰色。
	var wash: Color = expr.tint
	if String(expr.name) == "崩溃":
		wash = Color(0.45, 0.45, 0.48, 0.55)
	pv.tint = wash
	pv.set_character(id, layers.expr, layers.overlays, false)
	# look 由 portrait_view 按公司 id 取，描边用公司主题色。
	pv.queue_redraw()
	draw_string(font, Vector2(frame.end.x + 12.0, 20), "看板娘", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)
	# 文字
	var bold := get_theme_font("font", "RibbonLabel")
	var x := frame.end.x + 12.0
	var w := size.x - x
	draw_string(bold, Vector2(x, 44), String(c.get("mascot", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 22, UI.ACCENT)
	draw_string(font, Vector2(x, 64), String(c.get("mascot_title", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI.MUTED)
	draw_string(font, Vector2(x, 84), String(c.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 13, UI.TEXT)
	draw_string(font, Vector2(x, 122), "表情：%s" % expr.name, HORIZONTAL_ALIGNMENT_LEFT, w, 16, UI.TEXT)
	draw_string(bold, Vector2(x, 150), UI.pct(chg), HORIZONTAL_ALIGNMENT_LEFT, w, 24, UI.change_color(chg))
	draw_string(font, Vector2(x, size.y - 26), String(c.get("sector_name", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 11, UI.MUTED)
	draw_string(font, Vector2(x, size.y - 8), String(c.get("trait", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 11, UI.MUTED)


func _layout_portrait() -> Rect2:
	var frame := Rect2(0, 0, size.x * 0.52, size.y)
	if _portrait:
		_portrait.position = frame.position
		_portrait.size = frame.size
	return frame
