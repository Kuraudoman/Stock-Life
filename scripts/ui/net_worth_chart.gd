extends Control
## 净资产曲线（日结算用）。虚线是“还清线”：净资产 = 0 时，卖掉持仓正好够还债。

const UI := preload("res://scripts/ui/ui_style.gd")
const Calendar := preload("res://scripts/core/calendar.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")

var start_value := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_value = float(GameState.chapter.get("start_cash", 0)) - float(GameState.chapter.get("debt", 0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), UI.CHART_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.WOOD, 0.45), false, 1.0)
	var hist: Array = GameState.net_worth_history
	var vals: Array = [start_value]
	for h in hist:
		vals.append(float(h.nw))
	var lo := 0.0
	var hi := 0.0
	for v in vals:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span := maxf(hi - lo, 1000.0)
	lo -= span * 0.12
	hi += span * 0.12
	var plot := Rect2(8, 8, size.x - 70, size.y - 16)
	var y_of := func(v: float) -> float: return plot.end.y - (v - lo) / (hi - lo) * plot.size.y
	# 还清线
	var zy: float = y_of.call(0.0)
	draw_dashed_line(Vector2(plot.position.x, zy), Vector2(plot.end.x, zy), UI.UP, 1.0, 4.0)
	draw_string(font, Vector2(plot.end.x + 4, zy + 4), "还清线", HORIZONTAL_ALIGNMENT_LEFT, 60, 11, UI.UP)
	var n := vals.size()
	# 第一章进行中时，横轴留出到期限为止的空位
	var left := GameState.trading_days_left() if GameState.chapter_state == "active" else 0
	var slots := maxf(float(n - 1 + left), 1.0)
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2(plot.position.x + plot.size.x * float(i) / slots, y_of.call(float(vals[i]))))
	if pts.size() >= 2:
		draw_polyline(pts, UI.BLUE, 2.0, true)
	for p in pts:
		draw_circle(p, 2.5, UI.BLUE)
	var last := float(vals[-1])
	draw_string(font, Vector2(plot.end.x + 4, clampf(pts[-1].y + 4, 12, size.y - 4)), Portfolio.fmt_money(last),
			HORIZONTAL_ALIGNMENT_LEFT, 64, 11, UI.change_color(last))
