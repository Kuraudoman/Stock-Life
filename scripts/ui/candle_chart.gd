extends Control
## K 线 / 分时图，在 _draw() 中自绘，无外部依赖（GDD 第 11 节）。
## 日 K：历史日线 + 当日未完成的 K 线，叠加 MA5 / MA20，下方显示成交量；有过新闻的日子在 K 线上方标小三角。
## 分时：当日（或上一交易日）每个 tick 的价格线，以昨收为基准，下方显示每 tick 成交量。

const Calendar := preload("res://scripts/core/calendar.gd")
const UI := preload("res://scripts/ui/ui_style.gd")

enum Mode { DAILY, INTRADAY }

const AXIS_W := 62.0
const PAD := 6.0
const HEADER_H := 18.0
const DATE_H := 16.0
const FONT_SIZE := 11
const MA5_COLOR := Color(0.851, 0.541, 0.11, 0.95)
const MA20_COLOR := Color(0.231, 0.494, 0.773, 0.9)
const CROSSHAIR := Color(0.29, 0.204, 0.141, 0.3)

var mode: Mode = Mode.DAILY
var stock_id := ""
var _hover_x := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	EventBus.tick_advanced.connect(func(_t): queue_redraw())
	EventBus.market_opened.connect(func(_d): queue_redraw())
	EventBus.market_closed.connect(func(_s): queue_redraw())
	EventBus.game_loaded.connect(queue_redraw)


func set_stock(id: String) -> void:
	stock_id = id
	queue_redraw()


func set_mode(m: Mode) -> void:
	mode = m
	_hover_x = -1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = event.position.x
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_x = -1.0
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.CHART_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.WOOD, 0.45), false, 1.0)
	if stock_id == "" or not GameState.market.stocks.has(stock_id):
		return
	var plot_h := (size.y - HEADER_H - DATE_H - PAD * 3) * 0.74
	var plot := Rect2(PAD, HEADER_H + PAD, size.x - AXIS_W - PAD * 2, plot_h)
	var vol := Rect2(PAD, plot.end.y + PAD, plot.size.x, size.y - plot.end.y - PAD * 2 - DATE_H)
	if plot.size.x < 40 or plot.size.y < 40:
		return
	if mode == Mode.DAILY:
		_draw_daily(plot, vol)
	else:
		_draw_intraday(plot, vol)


# ---------------------------------------------------------------- 日 K

func _daily_series() -> Array:
	var m := GameState.market
	var s: Dictionary = m.stocks[stock_id]
	var arr: Array = (s.candles as Array).duplicate()
	if m.is_open:
		arr.append({"d": m.current_day, "o": s.open, "h": s.high, "l": s.low, "c": s.price, "v": s.volume})
	return arr


func _draw_daily(plot: Rect2, vol: Rect2) -> void:
	var font := get_theme_default_font()
	var all := _daily_series()
	if all.is_empty():
		return
	var slot := 9.0
	var n := mini(all.size(), int(plot.size.x / slot))
	var start := all.size() - n
	var view := all.slice(start)
	slot = plot.size.x / maxf(1.0, float(n))
	# 价格范围（含均线）
	var ma5 := _ma(all, 5)
	var ma20 := _ma(all, 20)
	var lo := INF
	var hi := -INF
	var vmax := 1.0
	for i in n:
		var cd: Dictionary = view[i]
		lo = minf(lo, float(cd.l))
		hi = maxf(hi, float(cd.h))
		vmax = maxf(vmax, float(cd.v))
		for ma in [ma5, ma20]:
			var v: float = ma[start + i]
			if v > 0.0:
				lo = minf(lo, v)
				hi = maxf(hi, v)
	var span := maxf(hi - lo, hi * 0.02)
	lo -= span * 0.06
	hi += span * 0.06
	_draw_price_grid(font, plot, lo, hi, false, 0.0)
	var y_of := func(p: float) -> float: return plot.end.y - (p - lo) / (hi - lo) * plot.size.y
	var body_w := maxf(1.0, slot * 0.68)
	for i in n:
		var cd: Dictionary = view[i]
		var cx := plot.position.x + slot * (i + 0.5)
		var o := float(cd.o)
		var c := float(cd.c)
		var col := UI.UP if c >= o else UI.DOWN
		draw_line(Vector2(cx, y_of.call(float(cd.h))), Vector2(cx, y_of.call(float(cd.l))), col, 1.0)
		var top: float = y_of.call(maxf(o, c))
		var bot: float = y_of.call(minf(o, c))
		var r := Rect2(cx - body_w * 0.5, top, body_w, maxf(1.0, bot - top))
		if c >= o:
			draw_rect(r, col, false, 1.0)  # 阳线空心
		else:
			draw_rect(r, col, true)
		# 成交量
		var vh := float(cd.v) / vmax * vol.size.y
		draw_rect(Rect2(cx - body_w * 0.5, vol.end.y - vh, body_w, vh), Color(col, 0.7), true)
	# 新闻标记：利好红三角朝上，利空绿三角朝下，其余灰点
	var marks := {}
	for mk in GameState.events.markers(stock_id):
		var dd := int(mk.day)
		if not marks.has(dd):
			marks[dd] = []
		(marks[dd] as Array).append(mk)
	for i in n:
		var dd := int(view[i].d)
		if not marks.has(dd):
			continue
		var cx := plot.position.x + slot * (i + 0.5)
		var top_y: float = y_of.call(float(view[i].h)) - 5.0
		var sign := 0
		for mk in marks[dd]:
			sign += int(mk.sign)
		var s3 := clampf(slot * 0.4, 3.0, 5.0)
		if sign > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(cx, top_y - s3 * 1.6), Vector2(cx - s3, top_y), Vector2(cx + s3, top_y)]), UI.UP)
		elif sign < 0:
			draw_colored_polygon(PackedVector2Array([Vector2(cx, top_y), Vector2(cx - s3, top_y - s3 * 1.6), Vector2(cx + s3, top_y - s3 * 1.6)]), UI.DOWN)
		else:
			draw_circle(Vector2(cx, top_y - s3 * 0.8), s3 * 0.6, UI.MUTED)
	# 均线
	for pair in [[ma5, MA5_COLOR], [ma20, MA20_COLOR]]:
		var pts := PackedVector2Array()
		for i in n:
			var v: float = pair[0][start + i]
			if v > 0.0:
				pts.append(Vector2(plot.position.x + slot * (i + 0.5), y_of.call(v)))
		if pts.size() >= 2:
			draw_polyline(pts, pair[1], 1.2, true)
	# 日期
	var every := maxi(1, int(70.0 / slot))
	for i in range(0, n, every):
		var cx := plot.position.x + slot * (i + 0.5)
		draw_string(font, Vector2(clampf(cx - 20, 0.0, plot.end.x - 40), size.y - 4), Calendar.format_short_date(int(view[i].d)),
				HORIZONTAL_ALIGNMENT_CENTER, 40, FONT_SIZE, UI.MUTED)
	draw_string(font, Vector2(vol.end.x + 4, vol.position.y + 10), UI.volume(vmax), HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, FONT_SIZE, UI.MUTED)
	# 悬停信息
	var idx := n - 1
	if _hover_x >= plot.position.x and _hover_x <= plot.end.x:
		idx = clampi(int((_hover_x - plot.position.x) / slot), 0, n - 1)
		var hx := plot.position.x + slot * (idx + 0.5)
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, vol.end.y), CROSSHAIR, 1.0)
	var h: Dictionary = view[idx]
	var prev_c := float(all[start + idx - 1].c) if start + idx > 0 else float(h.o)
	var chg := float(h.c) / prev_c - 1.0
	var info := "%s  开 %.2f  高 %.2f  低 %.2f  收 %.2f  %s  量 %s" % [
		Calendar.format_short_date(int(h.d)), float(h.o), float(h.h), float(h.l), float(h.c),
		UI.pct(chg), UI.volume(float(h.v))]
	draw_string(font, Vector2(PAD, 13), info, HORIZONTAL_ALIGNMENT_LEFT, size.x - 130, FONT_SIZE, UI.TEXT)
	# 悬停在有新闻的日子：在图表底部显示标题
	if marks.has(int(h.d)):
		var titles: Array = []
		for mk in marks[int(h.d)]:
			titles.append(String(mk.title))
		var txt := "新闻：" + " / ".join(titles)
		draw_rect(Rect2(plot.position.x + 1, plot.end.y - 20, plot.size.x - 2, 19), Color(UI.PAPER, 0.92), true)
		draw_string(font, Vector2(plot.position.x + 6, plot.end.y - 6), txt, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 10, FONT_SIZE, UI.TEXT)
	draw_string(font, Vector2(size.x - 128, 13), "MA5", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MA5_COLOR)
	draw_string(font, Vector2(size.x - 92, 13), "MA20", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MA20_COLOR)


func _ma(series: Array, k: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(series.size())
	var sum := 0.0
	for i in series.size():
		sum += float(series[i].c)
		if i >= k:
			sum -= float(series[i - k].c)
		out[i] = sum / k if i >= k - 1 else 0.0
	return out


# ---------------------------------------------------------------- 分时

func _draw_intraday(plot: Rect2, vol: Rect2) -> void:
	var font := get_theme_default_font()
	var m := GameState.market
	var s: Dictionary = m.stocks[stock_id]
	var pts_src: Array = s.intraday
	var vols: Array = s.intraday_volume
	var ref := float(s.ref_close)
	var slots := float(Calendar.TICKS_PER_DAY)
	var dev := ref * 0.01
	for p in pts_src:
		dev = maxf(dev, absf(float(p) - ref))
	dev *= 1.15
	var lo := ref - dev
	var hi := ref + dev
	_draw_price_grid(font, plot, lo, hi, true, ref)
	var y_of := func(p: float) -> float: return plot.end.y - (p - lo) / (hi - lo) * plot.size.y
	var x_of := func(i: int) -> float: return plot.position.x + plot.size.x * float(i) / slots
	# 昨收基准线（虚线）
	var ry: float = y_of.call(ref)
	draw_dashed_line(Vector2(plot.position.x, ry), Vector2(plot.end.x, ry), Color(UI.TEXT, 0.35), 1.0, 4.0)
	# 价格线 + 填充 + 均价线
	var line := PackedVector2Array()
	var avg_line := PackedVector2Array()
	var pv := 0.0
	var vv := 0.0
	for i in pts_src.size():
		var p := float(pts_src[i])
		line.append(Vector2(x_of.call(i), y_of.call(p)))
		var v := float(vols[i]) if i < vols.size() else 0.0
		pv += p * maxf(v, 1.0)
		vv += maxf(v, 1.0)
		avg_line.append(Vector2(x_of.call(i), y_of.call(pv / vv)))
	if line.size() >= 2:
		var fill := line.duplicate()
		fill.append(Vector2(line[line.size() - 1].x, plot.end.y))
		fill.append(Vector2(line[0].x, plot.end.y))
		draw_colored_polygon(fill, Color(UI.BLUE, 0.1))
		draw_polyline(avg_line, MA5_COLOR, 1.0, true)
		draw_polyline(line, UI.BLUE, 1.6, true)
	elif line.size() == 1:
		draw_circle(line[0], 2.5, UI.BLUE)
	# 成交量
	var vmax := 1.0
	for v in vols:
		vmax = maxf(vmax, float(v))
	var bw := maxf(1.0, plot.size.x / slots * 0.6)
	for i in range(1, vols.size()):
		var col := UI.UP if float(pts_src[i]) >= float(pts_src[i - 1]) else UI.DOWN
		var vh := float(vols[i]) / vmax * vol.size.y
		draw_rect(Rect2(x_of.call(i) - bw * 0.5, vol.end.y - vh, bw, vh), Color(col, 0.7), true)
	draw_string(font, Vector2(vol.end.x + 4, vol.position.y + 10), UI.volume(vmax), HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, FONT_SIZE, UI.MUTED)
	# 时间刻度
	for t in [0, 9, 18, 27, 36]:
		var x: float = x_of.call(t)
		draw_string(font, Vector2(clampf(x - 22, 0.0, plot.end.x - 22), size.y - 4), Calendar.format_tick(t),
				HORIZONTAL_ALIGNMENT_CENTER, 44, FONT_SIZE, UI.MUTED)
	# 悬停 / 最新
	var idx := pts_src.size() - 1
	if _hover_x >= plot.position.x and _hover_x <= plot.end.x and pts_src.size() > 0:
		idx = clampi(roundi((_hover_x - plot.position.x) / plot.size.x * slots), 0, pts_src.size() - 1)
		var hx: float = x_of.call(idx)
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, vol.end.y), CROSSHAIR, 1.0)
	if idx >= 0:
		var p := float(pts_src[idx])
		var tag := "" if m.is_open or m.current_day == GameState.day else "（上一交易日）"
		var info := "%s %s  价 %.2f  %s  量 %s  %s" % [Calendar.format_short_date(m.current_day),
				Calendar.format_tick(idx), p, UI.pct(p / ref - 1.0),
				UI.volume(float(vols[idx]) if idx < vols.size() else 0.0), tag]
		draw_string(font, Vector2(PAD, 13), info, HORIZONTAL_ALIGNMENT_LEFT, size.x - 100, FONT_SIZE, UI.TEXT)
	draw_string(font, Vector2(size.x - 92, 13), "均价", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MA5_COLOR)


# ---------------------------------------------------------------- 坐标轴

func _draw_price_grid(font: Font, plot: Rect2, lo: float, hi: float, show_pct: bool, ref: float) -> void:
	draw_rect(plot, Color(UI.WOOD_DARK, 0.22), false, 1.0)
	var lines := 4
	for i in lines + 1:
		var t := float(i) / lines
		var y := plot.end.y - t * plot.size.y
		var p := lerpf(lo, hi, t)
		if i > 0 and i < lines:
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), UI.GRID, 1.0)
		var col := UI.MUTED
		if show_pct:
			col = UI.change_color(p - ref)
		draw_string(font, Vector2(plot.end.x + 4, y + 4), "%.2f" % p, HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, FONT_SIZE, col)
		if show_pct and i != 2:
			# 上半部分的百分比写在价格下方，下半部分写在价格上方，避免超出图表
			draw_string(font, Vector2(plot.end.x + 4, y + 16 if i > 2 else y - 10), UI.pct(p / ref - 1.0),
					HORIZONTAL_ALIGNMENT_LEFT, AXIS_W, 10, col)
