extends Control
## 交易主界面（GDD 第 10 节）：顶栏、主角状态立绘、股票列表、K 线 / 分时、交易面板、看板娘、新闻、速度控制。
## 这里的 _process 是游戏时钟：交易时段每秒推进 速度 个 tick（1x = 1 tick/秒）。
## 晨报、对话、预测、日结算、结局等弹出层排成队列一个一个显示；有弹出层时时钟暂停。

const Calendar := preload("res://scripts/core/calendar.gd")
const Market := preload("res://scripts/core/market.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")
const UI := preload("res://scripts/ui/ui_style.gd")
const CandleChart := preload("res://scripts/ui/candle_chart.gd")
const HeroinePortrait := preload("res://scripts/ui/heroine_portrait.gd")
const DialogScene := preload("res://scenes/dialog.tscn")
const PaperScene := preload("res://scenes/ui/morning_paper.tscn")
const PredictScene := preload("res://scenes/ui/predict_popup.tscn")
const SummaryScene := preload("res://scenes/ui/day_summary.tscn")
const ChapterEndScene := preload("res://scenes/ui/chapter_end.tscn")
const RepayScene := preload("res://scenes/ui/repay_dialog.tscn")

const SPEEDS := [0, 1, 2, 4]
const TITLE_SCENE := "res://scenes/title.tscn"

@onready var date_label: Label = %DateLabel
@onready var time_label: Label = %TimeLabel
@onready var cash_label: Label = %CashLabel
@onready var net_label: Label = %NetLabel
@onready var debt_label: Label = %DebtLabel
@onready var hp_label: Label = %HpLabel
@onready var stress_label: Label = %StressLabel
@onready var heat_label: Label = %HeatLabel
@onready var deadline_label: Label = %DeadlineLabel
@onready var repay_button: Button = %RepayButton
@onready var save_button: Button = %SaveButton
@onready var title_button: Button = %TitleButton
@onready var heroine: HeroinePortrait = %HeroinePortrait
@onready var chart: CandleChart = %CandleChart
@onready var chart_title: Label = %ChartTitle
@onready var daily_button: Button = %DailyButton
@onready var intraday_button: Button = %IntradayButton
@onready var trade_title: Label = %TradeTitle
@onready var holding_label: Label = %HoldingLabel
@onready var qty_spin: SpinBox = %QtySpin
@onready var max_buy_button: Button = %MaxBuyButton
@onready var all_button: Button = %AllButton
@onready var buy_button: Button = %BuyButton
@onready var sell_button: Button = %SellButton
@onready var preview_label: Label = %PreviewLabel
@onready var news_log: RichTextLabel = %NewsLog
@onready var paper_button: Button = %PaperButton
@onready var phase_label: Label = %PhaseLabel
@onready var finish_button: Button = %FinishButton
@onready var action_button: Button = %ActionButton
@onready var quit_dialog: ConfirmationDialog = %QuitDialog
@onready var overlay: Control = %Overlay
@onready var toast: Label = %Toast
@onready var speed_buttons: Array[Button] = [%PauseButton, %Speed1Button, %Speed2Button, %Speed4Button]

var speed := 1
var _acc := 0.0
var _last_speed := 1
## 弹出层队列：{make: Callable 返回弹出层节点, done: Callable(result)}
var _queue: Array = []
var _current: Control = null
var _toast_tween: Tween


func _ready() -> void:
	if not GameState.has_game:
		GameState.new_game()
	# 速度按钮
	var group := ButtonGroup.new()
	for i in speed_buttons.size():
		var b := speed_buttons[i]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(set_speed.bind(SPEEDS[i]))
	# 图表模式
	var chart_group := ButtonGroup.new()
	for b in [daily_button, intraday_button]:
		b.toggle_mode = true
		b.button_group = chart_group
	daily_button.pressed.connect(func(): chart.set_mode(CandleChart.Mode.DAILY))
	intraday_button.pressed.connect(func(): chart.set_mode(CandleChart.Mode.INTRADAY))
	# 交易
	qty_spin.step = Market.LOT
	qty_spin.min_value = Market.LOT
	qty_spin.value_changed.connect(func(_v): _refresh_trade())
	buy_button.pressed.connect(_on_trade.bind("buy"))
	sell_button.pressed.connect(_on_trade.bind("sell"))
	max_buy_button.pressed.connect(_on_max_buy)
	all_button.pressed.connect(_on_all)
	# 流程
	action_button.pressed.connect(_on_action)
	finish_button.pressed.connect(GameState.finish_day)
	save_button.pressed.connect(func(): SaveManager.save_game())
	repay_button.pressed.connect(_show_repay)
	paper_button.pressed.connect(func(): _enqueue(_make_paper, _on_paper_closed))
	title_button.pressed.connect(quit_dialog.popup_centered)
	quit_dialog.confirmed.connect(func(): get_tree().change_scene_to_file(TITLE_SCENE))
	heroine.portrait_clicked.connect(_on_portrait_clicked)
	# 信号
	EventBus.message_posted.connect(_post)
	EventBus.tick_advanced.connect(func(_t): _refresh_all())
	EventBus.market_opened.connect(_on_market_opened)
	EventBus.market_closed.connect(_on_market_closed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.trade_executed.connect(func(_r): _refresh_all())
	EventBus.stock_selected.connect(_on_stock_selected)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.breaking_news.connect(_on_breaking_news)
	EventBus.tutorial_requested.connect(_on_tutorial_requested)
	EventBus.chapter_finished.connect(_on_chapter_finished)
	EventBus.debt_changed.connect(func(_d): _refresh_all())
	EventBus.player_changed.connect(_refresh_top)

	daily_button.set_pressed_no_signal(true)
	set_speed(1)
	_on_game_loaded()


func _process(delta: float) -> void:
	if GameState.phase != GameState.Phase.TRADING or speed <= 0 or _current != null:
		return
	_acc += delta * speed
	while _acc >= 1.0:
		_acc -= 1.0
		if GameState.advance_tick() or _current != null:
			_acc = 0.0
			break


func _unhandled_input(event: InputEvent) -> void:
	# 空格：暂停 / 继续
	if _current == null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		set_speed(_last_speed if speed == 0 else 0)
		get_viewport().set_input_as_handled()


func set_speed(s: int) -> void:
	if s > 0:
		_last_speed = s
	speed = s
	# set_pressed_no_signal 不会取消同组其他按钮，这里逐个同步
	var i := SPEEDS.find(s)
	for k in speed_buttons.size():
		speed_buttons[k].set_pressed_no_signal(k == i)
	EventBus.speed_changed.emit(s)


# ---------------------------------------------------------------- 弹出层队列

func _enqueue(make: Callable, done: Callable = Callable()) -> void:
	_queue.append({"make": make, "done": done})
	_pump.call_deferred()


func _pump() -> void:
	if _current != null or _queue.is_empty():
		return
	var entry: Dictionary = _queue.pop_front()
	var node: Control = entry.make.call()
	if node == null:
		_pump()
		return
	_current = node
	node.closed.connect(_on_overlay_closed.bind(node, entry.done))
	overlay.add_child(node)


func _on_overlay_closed(result: Variant, node: Control, done: Callable) -> void:
	node.queue_free()
	_current = null
	if done.is_valid():
		done.call(result)
	_refresh_all()
	_pump.call_deferred()


func overlay_open() -> bool:
	return _current != null


func _make_dialog(lines: Array, choices: Array = []) -> Control:
	var d := DialogScene.instantiate()
	d.setup(lines, choices)
	return d


func _make_tutorial(id: String) -> Control:
	var t: Dictionary = GameState.dialogues.get(id, {})
	if t.is_empty():
		return null
	return _make_dialog(t.get("lines", []), t.get("choices", []))


func _make_paper() -> Control:
	var p := PaperScene.instantiate()
	p.setup(GameState.paper, GameState.phase == GameState.Phase.PRE_OPEN and GameState.chapter_state != "failed")
	return p


## 开盘前弹出晨报（第一次会先播放读报教学）。
func _enqueue_paper() -> void:
	GameState.request_tutorial("paper")
	_enqueue(_make_paper, _on_paper_closed)


func _on_paper_closed(result: Variant) -> void:
	GameState.paper_read = true
	if result == "open":
		_on_action()


# ---------------------------------------------------------------- 流程

func _on_game_loaded() -> void:
	news_log.clear()
	_clear_queue()
	chart.set_stock(GameState.selected_id)
	_post_paper()
	_refresh_all()
	if GameState.chapter_state == "failed":
		_enqueue(_make_chapter_end.bind(GameState.chapter_result), _on_chapter_end_closed)
		return
	match GameState.phase:
		GameState.Phase.PRE_OPEN:
			if GameState.day == 1 and not GameState.has_seen("intro"):
				GameState.request_tutorial("intro")
			if not GameState.paper_read:
				_enqueue_paper()
		GameState.Phase.TRADING:
			_post("【读档】盘中，%s。" % GameState.time_label(), "info")
		GameState.Phase.CLOSED:
			_post("【读档】今天已收盘。", "info")
			if not GameState.last_summary.is_empty():
				_enqueue(_make_summary.bind(GameState.last_summary), _on_summary_closed)


func _clear_queue() -> void:
	_queue.clear()
	if _current != null:
		_current.queue_free()
		_current = null


func _on_day_started(_day: int) -> void:
	toast.visible = false
	_post_paper()
	_refresh_all()
	_enqueue_paper()


## 把今天的晨报也贴到消息栏，随时可以回看。
func _post_paper() -> void:
	var items: Array = GameState.paper.get("items", [])
	if items.is_empty():
		return
	_post("—— 《金穗日报》%s ——" % Calendar.format_date(int(GameState.paper.get("day", GameState.day))), "stamp")
	for it in items:
		var kind := String(it.kind)
		var log_kind := "news"
		if kind in ["precursor", "rumor", "filler"]:
			log_kind = kind
		_post(GameState.news_text(it), log_kind)


func _on_action() -> void:
	match GameState.phase:
		GameState.Phase.PRE_OPEN:
			_acc = 0.0
			GameState.open_market()
		GameState.Phase.CLOSED:
			if GameState.last_summary.is_empty():
				GameState.next_day()
			else:
				_enqueue(_make_summary.bind(GameState.last_summary), _on_summary_closed)


func _on_market_opened(_d: int) -> void:
	_refresh_all()
	GameState.request_tutorial("open")


func _on_market_closed(summary: Dictionary) -> void:
	_refresh_all()
	GameState.request_tutorial("summary")
	_enqueue(_make_summary.bind(summary), _on_summary_closed)


func _make_summary(summary: Dictionary) -> Control:
	var s := SummaryScene.instantiate()
	s.setup(summary)
	return s


func _on_summary_closed(result: Variant) -> void:
	match result:
		"final":
			var r: Dictionary = GameState.chapter_result
			var id := "cleared" if bool(r.get("success", false)) else "failed"
			_enqueue(func(): return _make_tutorial(id))
			_enqueue(_make_chapter_end.bind(r), _on_chapter_end_closed)
		"review":
			var tips := GameState.choose_evening("review")
			var nl: Dictionary = GameState.noelle_lines
			var lines: Array = [{"who": "noelle", "expr": "normal", "text": _pick(nl.get("review_open", ["……"]))}]
			for tip in tips:
				lines.append({"who": "noelle", "expr": "normal", "text": String(tip)})
			lines.append({"who": "noelle", "expr": "smile", "text": _pick(nl.get("review_close", ["……"]))})
			_enqueue(_make_dialog.bind(lines), func(_r): GameState.next_day())
		"rest":
			GameState.choose_evening("rest")
			GameState.next_day()


func _pick(list: Array) -> String:
	return String(list[randi() % list.size()]) if not list.is_empty() else ""


func _make_chapter_end(result: Dictionary) -> Control:
	var c := ChapterEndScene.instantiate()
	c.setup(result)
	return c


func _on_chapter_end_closed(result: Variant) -> void:
	if result == "continue":
		if GameState.phase == GameState.Phase.CLOSED:
			GameState.choose_evening("rest")
			GameState.next_day()
		return
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_chapter_finished(result: Dictionary) -> void:
	set_speed(0)
	if bool(result.get("success", false)):
		_enqueue(func(): return _make_tutorial("cleared"))
	_enqueue(_make_chapter_end.bind(result), _on_chapter_end_closed)


func _on_tutorial_requested(id: String) -> void:
	if id == "breaking":
		set_speed(0)
	_enqueue(func(): return _make_tutorial(id))


func _on_breaking_news(item: Dictionary) -> void:
	# 突发快讯：暂停，顶部横幅提示
	set_speed(0)
	_show_toast(GameState.news_text(item).split("　")[0], UI.RUMOR if String(item.kind) == "rumor" else UI.BREAKING)
	GameState.request_tutorial("breaking")


func _show_toast(text: String, color: Color) -> void:
	toast.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(2)
	sb.border_color = color.darkened(0.4)
	sb.set_content_margin_all(8)
	toast.add_theme_stylebox_override("normal", sb)
	toast.visible = true
	toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(4.0)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.8)
	_toast_tween.tween_callback(func(): toast.visible = false)


func _on_stock_selected(id: String) -> void:
	chart.set_stock(id)
	_refresh_all()


func _on_portrait_clicked() -> void:
	if GameState.chapter_state == "failed":
		return
	set_speed(0)
	GameState.request_tutorial("predict")
	_enqueue(func(): return PredictScene.instantiate())


func _show_repay() -> void:
	_enqueue(func(): return RepayScene.instantiate(), func(r):
		if r != null and float(r) > 0.0:
			GameState.repay(float(r)))


# ---------------------------------------------------------------- 交易

func _qty() -> int:
	return int(qty_spin.value)


func _on_trade(side: String) -> void:
	GameState.trade(GameState.selected_id, side, _qty())


func _on_max_buy() -> void:
	var q := GameState.portfolio.max_buy_qty(GameState.market, GameState.selected_id)
	qty_spin.value = maxi(q, Market.LOT)


func _on_all() -> void:
	var q := GameState.portfolio.qty_of(GameState.selected_id)
	if q > 0:
		qty_spin.value = q


# ---------------------------------------------------------------- 刷新

func _refresh_all() -> void:
	_refresh_top()
	_refresh_trade()
	_refresh_bottom()
	_refresh_chart_title()


func _refresh_top() -> void:
	var p := GameState.player
	date_label.text = Calendar.format_date(GameState.day)
	date_label.tooltip_text = GameState.chapter_label()
	time_label.text = GameState.time_label()
	cash_label.text = "现金 %s" % Portfolio.fmt_money(GameState.portfolio.cash)
	var nw := GameState.net_worth()
	net_label.text = "净资产 %s" % Portfolio.fmt_money(nw)
	net_label.add_theme_color_override("font_color", UI.UP if nw >= 0 else UI.TEXT)
	debt_label.text = "负债 %s" % Portfolio.fmt_money(GameState.portfolio.debt)
	hp_label.text = "体力 %d" % int(p.get("hp", 100))
	stress_label.text = "压力 %d" % int(p.get("stress", 0))
	heat_label.text = "调查度 %d" % int(p.get("heat", 0))
	match GameState.chapter_state:
		"active":
			var left := GameState.trading_days_left()
			deadline_label.text = "期限 %s · 剩 %d 个交易日" % [Calendar.format_short_date(GameState.deadline_day()), left]
			deadline_label.add_theme_color_override("font_color", UI.BREAKING if left <= 5 else UI.WARN)
			deadline_label.tooltip_text = "%s收盘前还清 %s 金币。按现价卖掉全部持仓还差 %s。" % [
				Calendar.format_date(GameState.deadline_day()), Portfolio.fmt_money(float(GameState.chapter.get("debt", 0))),
				Portfolio.fmt_money(maxf(0.0, GameState.debt_gap()))]
		"cleared":
			deadline_label.text = "债务已还清 · 自由交易"
			deadline_label.add_theme_color_override("font_color", UI.DOWN)
		_:
			deadline_label.text = "席位已被收走"
			deadline_label.add_theme_color_override("font_color", UI.MUTED)
	repay_button.disabled = GameState.portfolio.debt <= 0.0 or GameState.portfolio.cash <= 0.0 or GameState.chapter_state == "failed"


func _refresh_chart_title() -> void:
	var id := GameState.selected_id
	var c := GameState.company(id)
	var chg := GameState.market.day_change(id)
	chart_title.text = "%s  %.2f  %s" % [c.get("name", id), GameState.market.price(id), UI.pct(chg)]
	chart_title.add_theme_color_override("font_color", UI.change_color(chg))


func _refresh_trade() -> void:
	var id := GameState.selected_id
	if id == "":
		return
	var m := GameState.market
	var pf := GameState.portfolio
	var c := GameState.company(id)
	trade_title.text = "交易 · %s" % c.get("name", id)
	var held := pf.qty_of(id)
	if held > 0:
		var upnl := pf.unrealized_pnl(m, id)
		holding_label.text = "持有 %d 股 · 成本 %.2f · 浮动盈亏 %s%s" % [held, pf.avg_cost_of(id),
				"+" if upnl >= 0 else "", Portfolio.fmt_money(upnl)]
		holding_label.add_theme_color_override("font_color", UI.change_color(upnl))
	else:
		holding_label.text = "未持有"
		holding_label.add_theme_color_override("font_color", UI.MUTED)
	var trading := GameState.can_trade()
	var qty := _qty()
	buy_button.disabled = not trading
	sell_button.disabled = not trading or held < Market.LOT
	max_buy_button.disabled = not trading
	all_button.disabled = held <= 0
	if not trading:
		if GameState.phase == GameState.Phase.TRADING and String(GameState.player.get("body", "")) == "hospital":
			preview_label.text = "%s正在住院，这几天不能交易。持仓会照常随行情涨跌。" % GameState.player.name
		else:
			preview_label.text = "开盘时间 9:00–15:00 才能下单。最小单位 %d 股，手续费 0.3%%，卖出另收 0.1%% 交易税。" % Market.LOT
		preview_label.add_theme_color_override("font_color", UI.MUTED)
		return
	var qb := m.quote(id, "buy", qty)
	var qs := m.quote(id, "sell", qty)
	var lines := "买入 %d 股：均价 %.2f（滑点 %.2f%%）手续费 %s，合计支付 %s" % [
		qty, float(qb.avg_price), float(qb.slippage) * 100.0, Portfolio.fmt_money(float(qb.fee)),
		Portfolio.fmt_money(float(qb.total))]
	lines += "\n卖出 %d 股：均价 %.2f（滑点 %.2f%%）手续费+税 %s，合计收入 %s" % [
		qty, float(qs.avg_price), float(qs.slippage) * 100.0,
		Portfolio.fmt_money(float(qs.fee) + float(qs.tax)), Portfolio.fmt_money(float(qs.total))]
	preview_label.text = lines
	var err := pf.validate(m, id, "buy", qty)
	preview_label.add_theme_color_override("font_color", UI.WARN if err != "" else UI.TEXT)
	buy_button.disabled = err != ""
	buy_button.tooltip_text = err


func _refresh_bottom() -> void:
	match GameState.phase:
		GameState.Phase.PRE_OPEN:
			phase_label.text = "开盘前"
			action_button.text = "开盘 ▶"
			action_button.disabled = GameState.chapter_state == "failed"
			finish_button.visible = false
		GameState.Phase.TRADING:
			phase_label.text = "盘中 %s / 15:00" % Calendar.format_tick(GameState.market.tick)
			action_button.text = "交易中…"
			action_button.disabled = true
			finish_button.visible = true
		GameState.Phase.CLOSED:
			phase_label.text = "已收盘"
			action_button.text = "收盘结算 ▶" if not GameState.last_summary.is_empty() else "进入下一天 ▶"
			action_button.disabled = GameState.chapter_state == "failed"
			finish_button.visible = false


func _post(text: String, kind: String = "info") -> void:
	var color: Color = UI.LOG_COLORS.get(kind, UI.TEXT)
	var stamp := GameState.time_label() if GameState.phase == GameState.Phase.TRADING else Calendar.format_short_date(GameState.day)
	if kind == "stamp":
		news_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])
		return
	var bold := kind == "breaking"
	news_log.append_text("[color=#%s][lb]%s[rb][/color] [color=#%s]%s%s%s[/color]\n" % [
			UI.LOG_COLORS.stamp.to_html(false), stamp, color.to_html(false),
			"[b]" if bold else "", text, "[/b]" if bold else ""])
