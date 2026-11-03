extends Node
## 游戏状态（Autoload）。持有市场、事件日程、持仓、主角属性，并负责一天的流程：
## 开盘前（晨报）→ 盘中 36 个 tick（突发快讯）→ 收盘结算（主角状态、诺艾尔点评、预测回顾、自动存档）
## → 晚间安排 → 睡觉 → 下一个交易日。第一章期限那天收盘时做最终结算。
## 时间推进的“时钟”在交易主界面（main.gd）里，GameState 只提供 advance_tick() 等操作，
## 这样标题画面不会走时间，测试脚本也可以直接调用。

const Calendar := preload("res://scripts/core/calendar.gd")
const Market := preload("res://scripts/core/market.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")
const Events := preload("res://scripts/core/events.gd")
const Life := preload("res://scripts/core/life.gd")
const Predict := preload("res://scripts/core/predict.gd")
const Noelle := preload("res://scripts/core/noelle.gd")

const COMPANIES_PATH := "res://data/companies.json"
const CHAPTER_PATH := "res://data/chapter1.json"
const CHARACTERS_PATH := "res://data/characters.json"
const TUTORIAL_PATH := "res://data/dialogues/tutorial.json"
const HEROINE_PATH := "res://data/dialogues/heroine.json"
## 晨报最少 / 最多几条（不够时用花边新闻补）。
const PAPER_MIN := 3
const PAPER_MAX := 5
## 诺艾尔复盘时看多少个交易日之内的风声。
const TIP_DAYS := 3

enum Phase { PRE_OPEN, TRADING, CLOSED }

var companies: Array = []
var chapter: Dictionary = {}
var characters: Dictionary = {}
var dialogues: Dictionary = {}
var heroine_lines: Dictionary = {}
var noelle_lines: Dictionary = {}

var seed_value := 0
var day := 1
var phase: Phase = Phase.PRE_OPEN
var market := Market.new()
var events := Events.new()
var portfolio := Portfolio.new()
var player := {}
var affection := {}
var flags := {}
var selected_id := ""
## 每个收盘日的净资产，用于日结算曲线。
var net_worth_history: Array = []
var day_start_net_worth := 0.0
## 开盘时的现金 + 持仓（不含负债），用来算当日收益率与主角情绪。
var day_start_equity := 0.0
## 今天的晨报 {day, items}。
var paper := {}
var paper_read := false
## 走势预测记录（见 predict.gd），到期后回顾。
var predictions: Array = []
var pred_stats := {"made": 0, "resolved": 0, "hits": 0}
## active / cleared（还清，可继续自由交易）/ failed（期限到了没还清）
var chapter_state := "active"
var chapter_result := {}
var last_summary := {}
var evening_choice := ""
var traded_today := false
var has_game := false


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	companies = load_companies()
	chapter = _json(CHAPTER_PATH)
	characters = _json(CHARACTERS_PATH)
	dialogues = _json(TUTORIAL_PATH)
	heroine_lines = _json(HEROINE_PATH)
	noelle_lines = Noelle.load_lines()


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法读取 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s 格式错误" % path)
		return {}
	return parsed


static func load_companies() -> Array:
	var d := _json(COMPANIES_PATH)
	return d.get("companies", [])


## 新游戏。p_seed < 0 时随机生成种子。
func new_game(p_seed: int = -1, p_name: String = "", tutorial: bool = true) -> void:
	if companies.is_empty():
		_load_data()
	if p_seed < 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		p_seed = r.randi_range(1, 2147483646)
	seed_value = p_seed
	day = 1
	market = Market.new()
	market.setup(companies, seed_value, day)
	market.set_phase(String(chapter.get("phase", "dawn")))
	events = Events.new()
	events.setup(companies, seed_value)
	portfolio = Portfolio.new()
	portfolio.cash = float(chapter.get("start_cash", 40000))
	portfolio.debt = float(chapter.get("debt", 50000))
	var n := p_name.strip_edges()
	player = Life.new_player(n if n != "" else String(characters.get("characters", {}).get("heroine", {}).get("name", "希雅")))
	affection = (chapter.get("affection", {"noelle": 10}) as Dictionary).duplicate(true)
	for k in affection:
		affection[k] = int(affection[k])
	flags = {"tutorial": tutorial}
	net_worth_history = []
	predictions = []
	pred_stats = {"made": 0, "resolved": 0, "hits": 0}
	chapter_state = "active"
	chapter_result = {}
	last_summary = {}
	evening_choice = ""
	selected_id = String(companies[0].id) if not companies.is_empty() else ""
	phase = Phase.PRE_OPEN
	has_game = true
	_start_day()
	EventBus.game_loaded.emit()


# ---------------------------------------------------------------- 一天的流程

## 进入开盘前：生成日程、晨报（盘前消息在下一次开盘时以跳空体现）。
func _start_day() -> void:
	events.ensure(day + 45)
	day_start_net_worth = net_worth()
	day_start_equity = equity()
	traded_today = false
	evening_choice = ""
	_build_paper()


## 晨报：今天的盘前消息与前兆（这一步让它们生效），不够 3 条用花边新闻补。
func _build_paper() -> void:
	var items := events.before_open(market, day)
	var want := clampi(items.size() + 1, PAPER_MIN, PAPER_MAX)
	items.append_array(events.filler(day, want - items.size()))
	paper = {"day": day, "items": items}
	paper_read = false
	_check_precursor_hit(items)


func open_market() -> void:
	if phase != Phase.PRE_OPEN or chapter_state == "failed":
		return
	day_start_net_worth = net_worth()
	day_start_equity = equity()
	paper_read = true
	market.open_day(day)
	phase = Phase.TRADING
	EventBus.market_opened.emit(day)
	EventBus.message_posted.emit("【交易所】%s 开盘，钟声响起。" % Calendar.format_date(day), "info")
	if not Life.can_trade(player):
		EventBus.message_posted.emit("【住院】%s还在住院，今天不能交易（还要 %d 个交易日）。" % [player.name, int(player.hospitalDays)], "warn")


## 推进一个 tick；到 15:00 自动收盘。返回是否已收盘。
func advance_tick() -> bool:
	if phase != Phase.TRADING:
		return false
	var items := events.on_tick(market, day, market.tick)
	market.step_tick()
	for it in items:
		EventBus.message_posted.emit(news_text(it), "rumor" if String(it.kind) == "rumor" else "breaking")
		EventBus.breaking_news.emit(it)
	_check_precursor_hit(items)
	EventBus.tick_advanced.emit(market.tick)
	if market.is_day_finished():
		close_market()
		return true
	return false


## 直接推进到收盘。
func finish_day() -> void:
	while phase == Phase.TRADING:
		advance_tick()


func close_market() -> Dictionary:
	if phase != Phase.TRADING:
		return {}
	market.close_day()
	phase = Phase.CLOSED
	var eq := equity()
	var day_ret := eq / day_start_equity - 1.0 if day_start_equity > 0.0 else 0.0
	var mood_before := String(player.mood)
	var body_before := String(player.body)
	var life := Life.end_trading_day(player, day_ret, trading_days_left() if chapter_state == "active" else -1)
	var reviews := _review_predictions()
	var nw := net_worth()
	net_worth_history.append({"d": day, "nw": nw})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, day, "noelle"])
	var summary := {
		"day": day,
		"date": Calendar.format_date(day),
		"net_worth": nw,
		"prev_net_worth": day_start_net_worth,
		"pnl": nw - day_start_net_worth,
		"day_ret": day_ret,
		"cash": portfolio.cash,
		"holdings_value": portfolio.holdings_value(market),
		"debt": portfolio.debt,
		"comment": Noelle.comment(noelle_lines, day_ret, traded_today, rng),
		"state_note": Noelle.state_note(noelle_lines, player, rng),
		"mood_before": mood_before, "mood_after": String(player.mood),
		"body_before": body_before, "body_after": String(player.body),
		"hospital": bool(life.hospital),
		"reviews": reviews,
		"deadline": "",
		"chapter_result": {},
	}
	EventBus.message_posted.emit("【交易所】15:00 收盘。", "info")
	for line in reviews:
		EventBus.message_posted.emit(line, "predict")
	if bool(life.hospital):
		EventBus.message_posted.emit("【住院】%s体力透支，被送进了医院。接下来 %d 个交易日不能交易。" % [player.name, Life.HOSPITAL_DAYS], "warn")
	if chapter_state == "active":
		if day >= deadline_day():
			summary.chapter_result = _final_settlement()
		else:
			summary.deadline = Noelle.deadline_line(noelle_lines, trading_days_left(), debt_gap(),
					Portfolio.fmt_money(debt_gap()))
	last_summary = summary
	EventBus.player_changed.emit()
	# 期限那天失败时不覆盖自动存档：标题画面的「继续」会回到前一天收盘，可以再试一次
	if chapter_state != "failed":
		SaveManager.autosave()
	EventBus.market_closed.emit(summary)
	return summary


## 晚间安排：rest（早点休息）或 review（和诺艾尔复盘）。复盘返回诺艾尔的分析（若干句）。
## 发烧时只能休息。
func choose_evening(choice: String) -> Array:
	if phase != Phase.CLOSED:
		return []
	if String(player.body) in ["fever", "hospital"]:
		choice = "rest"
	evening_choice = choice
	if choice != "review":
		return []
	affection["noelle"] = mini(100, int(affection.get("noelle", 0)) + int(chapter.get("review_affection", 3)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, day, "tips"])
	return Noelle.tips(noelle_lines, events.upcoming_clues(day, TIP_DAYS), day, int(affection.noelle), events.shorts, rng)


## 进入下一个交易日（跳过周末与节日），中间睡觉恢复。
func next_day() -> void:
	if phase != Phase.CLOSED or chapter_state == "failed":
		return
	var next := Calendar.next_trading_day(day)
	var off := next - day - 1
	if off > 0:
		EventBus.message_posted.emit("【日历】%s 至 %s 休市。休市期间的消息会在下一个开盘日集中反映。"
				% [Calendar.format_date(day + 1), Calendar.format_date(next - 1)], "info")
	var mood_before := String(player.mood)
	var body_before := String(player.body)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, day, "life"])
	var changes := Life.sleep(player, rng, off, evening_choice if evening_choice != "" else "rest")
	player.predictionsLeft = Life.predictions_per_day(player)
	day = next
	phase = Phase.PRE_OPEN
	for c in changes:
		var msg: String = {
			"cold": "【身体】%s着凉感冒了。今天只能预测 1 次，体力恢复减半。",
			"fever": "【身体】感冒没休息好，%s发烧了！今晚只能休息。",
			"fever_down": "【身体】%s退烧了，但感冒还没好。",
			"recovered": "【身体】%s的感冒好了。",
			"released": "【身体】%s出院了。",
		}.get(c, "")
		if msg != "":
			EventBus.message_posted.emit(msg % player.name, "warn")
	_start_day()
	EventBus.player_changed.emit()
	EventBus.day_started.emit(day)
	if off > 0:
		request_tutorial("weekend")
	if String(player.mood) != "calm" or String(player.body) != "healthy":
		if mood_before != String(player.mood) or body_before != String(player.body) or String(player.body) != "healthy":
			request_tutorial("state")
	if String(player.body) == "hospital":
		request_tutorial("hospital")
	if chapter_state == "active" and trading_days_left() <= 5 and debt_gap() > 0.0:
		request_tutorial("deadline")


# ---------------------------------------------------------------- 第一章

func deadline_day() -> int:
	var d := int(chapter.get("deadline_day", Calendar.CHAPTER1_DAYS))
	while d > 1 and not Calendar.is_trading_day(d):
		d -= 1
	return d


## 距期限还有几个交易日（不含今天；期限当天为 0）。
func trading_days_left() -> int:
	var n := 0
	var d := day
	while d < deadline_day():
		d = Calendar.next_trading_day(d)
		n += 1
	return n


## 按当前价卖出全部持仓后还差多少债（≤ 0 表示已经够还）。
func debt_gap() -> float:
	return portfolio.debt - portfolio.liquidation_value(market)


func repay(amount: float) -> float:
	if chapter_state == "failed":
		return 0.0
	var a := portfolio.repay(amount)
	if a <= 0.0:
		return 0.0
	EventBus.message_posted.emit("【还款】向黑鸦商会还款 %s 金币，剩余债务 %s。" % [
		Portfolio.fmt_money(a), Portfolio.fmt_money(portfolio.debt)], "trade")
	EventBus.debt_changed.emit(portfolio.debt)
	if portfolio.debt <= 0.0 and chapter_state == "active":
		EventBus.chapter_finished.emit(_finish_chapter(true, true))
	return a


## 期限那天收盘：现金够就直接还；不够就把持仓按收盘价卖掉再还；还是不够即失败。
func _final_settlement() -> Dictionary:
	var sold := 0.0
	if portfolio.cash < portfolio.debt and not portfolio.holdings.is_empty():
		sold = portfolio.liquidate(market)
	var paid := portfolio.repay(portfolio.debt)
	var ok := portfolio.debt <= 0.0
	var result := _finish_chapter(ok, false)
	result.sold = sold
	result.paid = paid
	if sold > 0.0:
		EventBus.message_posted.emit("【清算】诺艾尔按收盘价卖出全部持仓，得到 %s 金币。" % Portfolio.fmt_money(sold), "warn")
	EventBus.message_posted.emit("【期限】向黑鸦商会还款 %s 金币。%s" % [Portfolio.fmt_money(paid),
			"债务全部还清！" if ok else "还差 %s 金币……" % Portfolio.fmt_money(portfolio.debt)], "trade" if ok else "warn")
	EventBus.debt_changed.emit(portfolio.debt)
	return result


func _finish_chapter(success: bool, early: bool) -> Dictionary:
	chapter_state = "cleared" if success else "failed"
	chapter_result = {
		"success": success, "early": early, "day": day, "date": Calendar.format_date(day),
		"net_worth": net_worth(), "cash": portfolio.cash, "debt": portfolio.debt,
		"realized": portfolio.realized_pnl, "fees": portfolio.fees_paid,
		"pred_made": int(pred_stats.made), "pred_resolved": int(pred_stats.resolved), "pred_hits": int(pred_stats.hits),
		"affection": int(affection.get("noelle", 0)),
	}
	return chapter_result


# ---------------------------------------------------------------- 走势预测

## 发起预测。成功返回预测记录（含台词 line、表情 expr）；不能预测时返回 {"error": 原因, "line": 台词}。
func predict(id: String, horizon: String) -> Dictionary:
	var refuse: Dictionary = heroine_lines.get("refuse", {})
	var ph := phase_name()
	if chapter_state == "failed":
		return {"error": "failed", "line": ""}
	var reason := Life.predict_block_reason(player)
	if reason == "" and not Predict.horizon_available(horizon, ph):
		reason = "closed"
	if reason != "":
		return {"error": reason, "line": String(refuse.get(reason, ""))}
	var key := [seed_value, day, ph, market.tick, id, horizon]
	var pred := Predict.predict(market, events, player, day, ph, id, horizon, key)
	Life.spend_prediction(player)
	pred.line = _prediction_line(pred, key)
	pred.adopted = false
	pred.resolved = false
	predictions.append(pred)
	pred_stats.made = int(pred_stats.made) + 1
	EventBus.message_posted.emit("【预测】%s：「%s %s，%s %s」" % [player.name, short_name(id),
			Predict.HORIZON_NAMES[horizon], Predict.label(pred), Predict.arrow(pred)], "predict")
	EventBus.player_changed.emit()
	EventBus.prediction_made.emit(pred)
	return pred


func add_affection(who: String, amount: int) -> void:
	affection[who] = clampi(int(affection.get(who, 0)) + amount, 0, 100)
	EventBus.player_changed.emit()


func adopt_last_prediction() -> void:
	if predictions.is_empty():
		return
	var pred: Dictionary = predictions[-1]
	pred.adopted = true
	select_stock(String(pred.id))


func _prediction_line(pred: Dictionary, key: Array) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + ["line"])
	var dir := String(pred.dir)
	var lines: Array = []
	if String(pred.body) == "fever":
		lines = heroine_lines.get("fever", {}).get(dir, [])
	else:
		var k := "flat" if dir == "flat" else "%s_%s" % [dir, pred.mag]
		lines = heroine_lines.get("predict", {}).get(String(pred.mood), {}).get(k, [])
	var line := String(lines[rng.randi_range(0, lines.size() - 1)]) if not lines.is_empty() else Predict.label(pred)
	var prefix: Array = heroine_lines.get("prefix", {}).get(String(pred.body), [])
	if not prefix.is_empty():
		line = String(prefix[rng.randi_range(0, prefix.size() - 1)]) + line
	return line.replace("{stock}", short_name(String(pred.id))).replace("{horizon}", Predict.HORIZON_NAMES[pred.horizon])


## 收盘时回顾今天到期的预测。
func _review_predictions() -> Array:
	var out: Array = []
	for pred in predictions:
		if bool(pred.resolved) or int(pred.target_day) != day:
			continue
		var id := String(pred.id)
		var rv := Predict.review(pred, market.price(id), float(market.configs[id].sigma))
		pred.resolved = true
		pred.hit = bool(rv.hit)
		pred_stats.resolved = int(pred_stats.resolved) + 1
		if bool(rv.hit):
			pred_stats.hits = int(pred_stats.hits) + 1
		out.append("【预测回顾】%s %s 说「%s %s，%s」，实际 %+.1f%%：%s" % [
			player.name, Calendar.format_short_date(int(pred.made_day)), short_name(id),
			Predict.HORIZON_NAMES[pred.horizon], Predict.label(pred), float(rv.ret) * 100.0,
			"说中了！" if bool(rv.hit) else "没说中。"])
	# 只保留最近的记录，避免存档越来越大
	while predictions.size() > 60:
		predictions.pop_front()
	return out


# ---------------------------------------------------------------- 教学

func tutorial_enabled() -> bool:
	return bool(flags.get("tutorial", true))


## 某段教学还没播放过时发出请求（每段只播放一次）。intro / cleared / failed 不受教学开关影响。
func request_tutorial(id: String) -> void:
	if not dialogues.has(id) or flags.has("tut_" + id):
		return
	if not tutorial_enabled() and not id in ["intro", "cleared", "failed"]:
		return
	flags["tut_" + id] = true
	EventBus.tutorial_requested.emit(id)


func has_seen(id: String) -> bool:
	return flags.has("tut_" + id)


## 某条消息对应的事件之前露过前兆 → “前几天的风声应验了”。
func _check_precursor_hit(items: Array) -> void:
	for it in items:
		if String(it.kind) in ["precursor", "filler", "rumor"]:
			continue
		var inst := events.instance(String(it.uid))
		for pre in inst.get("precursors", []):
			if bool(pre.shown):
				request_tutorial("precursor_hit")
				return


## 对话里的占位符。
func fill_text(text: String) -> String:
	return text.replace("{name}", String(player.get("name", "希雅"))) \
		.replace("{debt}", Portfolio.fmt_money(float(chapter.get("debt", 50000)))) \
		.replace("{cash}", Portfolio.fmt_money(float(chapter.get("start_cash", 40000)))) \
		.replace("{deadline}", Calendar.format_date(deadline_day()))


# ---------------------------------------------------------------- 查询

func net_worth() -> float:
	return portfolio.net_worth(market)


func equity() -> float:
	return portfolio.cash + portfolio.holdings_value(market)


func phase_name() -> String:
	return ["pre_open", "trading", "closed"][phase]


func select_stock(id: String) -> void:
	if id == selected_id or not market.stocks.has(id):
		return
	selected_id = id
	EventBus.stock_selected.emit(id)


func company(id: String) -> Dictionary:
	return market.configs.get(id, {})


func short_name(id: String) -> String:
	if id == "all":
		return "大盘"
	return String(company(id).get("short", id))


func character(id: String) -> Dictionary:
	return characters.get("characters", {}).get(id, {})


func can_trade() -> bool:
	return phase == Phase.TRADING and Life.can_trade(player) and chapter_state != "failed"


func trade(id: String, side: String, qty: int) -> Dictionary:
	var r := {}
	if not Life.can_trade(player):
		r = {"ok": false, "error": "%s正在住院，不能交易" % player.name}
	elif chapter_state == "failed":
		r = {"ok": false, "error": "席位已经被收走了"}
	else:
		r = portfolio.execute(market, id, side, qty)
	if bool(r.ok):
		traded_today = true
		var c := company(id)
		EventBus.message_posted.emit("【成交】%s %s %d 股，均价 %.2f，%s %s 金币" % [
			"买入" if side == "buy" else "卖出", c.get("name", id), qty, float(r.avg_price),
			"支付" if side == "buy" else "收入", Portfolio.fmt_money(float(r.total))], "trade")
	else:
		EventBus.message_posted.emit("【交易失败】%s" % r.error, "warn")
	EventBus.trade_executed.emit(r)
	return r


## 新闻条目在消息栏里的文字。
static func news_text(it: Dictionary) -> String:
	var tag := "【快讯】" if String(it.get("stage", "")) == "intraday" else ""
	match String(it.kind):
		"precursor":
			tag = "【市场】"
		"rumor":
			tag = "【传闻】"
		"filler":
			tag = "【杂谈】"
		_:
			if tag == "":
				tag = "【要闻】"
	var body := String(it.get("body", ""))
	return tag + String(it.title) + ("　" + body if body != "" else "")


func time_label() -> String:
	match phase:
		Phase.PRE_OPEN:
			return "开盘前"
		Phase.CLOSED:
			return "已收盘"
	return Calendar.format_tick(market.tick)


func chapter_label() -> String:
	match chapter_state:
		"cleared":
			return "自由交易  第 %d 天" % day
		"failed":
			return "第一章 · 席位被收走"
	return "%s  第 %d/%d 天" % [String(chapter.get("title", "第一章 · 黎明")), day, int(chapter.get("deadline_day", 30))]


func save_label() -> String:
	return "%s %s" % [chapter_label(), time_label()]


# ---------------------------------------------------------------- 存档数据

## “核心状态”（GDD 第 11 节）。
func to_save_data() -> Dictionary:
	var p := portfolio.to_dict()
	return {
		"seed": seed_value,
		"day": day,
		"tick": market.tick,
		"phase": phase_name(),
		"cash": p.cash,
		"debt": p.debt,
		"holdings": p.holdings,
		"realizedPnl": p.realizedPnl,
		"feesPaid": p.feesPaid,
		"market": market.to_dict(),
		"events": events.to_dict(),
		"player": player.duplicate(true),
		"schedule": [],
		"affection": affection.duplicate(true),
		"flags": flags.duplicate(true),
		"selected": selected_id,
		"netWorthHistory": net_worth_history.duplicate(true),
		"dayStartNetWorth": day_start_net_worth,
		"dayStartEquity": day_start_equity,
		"paper": paper.duplicate(true),
		"paperRead": paper_read,
		"predictions": predictions.duplicate(true),
		"predStats": pred_stats.duplicate(),
		"chapterState": chapter_state,
		"chapterResult": chapter_result.duplicate(true),
		"lastSummary": last_summary.duplicate(true),
		"eveningChoice": evening_choice,
		"tradedToday": traded_today,
	}


func apply_save_data(d: Dictionary) -> void:
	if companies.is_empty():
		_load_data()
	seed_value = int(d.seed)
	day = int(d.day)
	market = Market.new()
	market.from_dict(d.market, companies)
	portfolio = Portfolio.new()
	portfolio.from_dict(d)
	player = d.get("player", {}).duplicate(true)
	Life.normalize(player)
	affection = d.get("affection", {}).duplicate(true)
	for k in affection:
		affection[k] = int(affection[k])
	flags = d.get("flags", {}).duplicate(true)
	net_worth_history = d.get("netWorthHistory", []).duplicate(true)
	day_start_net_worth = float(d.get("dayStartNetWorth", 0.0))
	selected_id = String(d.get("selected", ""))
	if not market.stocks.has(selected_id) and not market.order.is_empty():
		selected_id = market.order[0]
	match String(d.get("phase", "pre_open")):
		"trading":
			phase = Phase.TRADING
		"closed":
			phase = Phase.CLOSED
		_:
			phase = Phase.PRE_OPEN
	day_start_equity = float(d.get("dayStartEquity", equity()))
	predictions = d.get("predictions", []).duplicate(true)
	for pred in predictions:
		for k in ["target_day", "made_day", "made_tick"]:
			pred[k] = int(pred.get(k, 0))
	pred_stats = {}
	var ps: Dictionary = d.get("predStats", {})
	for k in ["made", "resolved", "hits"]:
		pred_stats[k] = int(ps.get(k, 0))
	chapter_state = String(d.get("chapterState", "active"))
	chapter_result = d.get("chapterResult", {}).duplicate(true)
	last_summary = d.get("lastSummary", {}).duplicate(true)
	evening_choice = String(d.get("eveningChoice", ""))
	traded_today = bool(d.get("tradedToday", false))
	events = Events.new()
	var ev: Dictionary = d.get("events", {})
	if ev.is_empty():
		# 版本 1 的存档没有事件日程：按种子重新生成，已经过去的消息当作发生过
		events.setup(companies, seed_value)
		events.ensure(day + 45)
		events.mark_past(day, phase != Phase.PRE_OPEN)
	else:
		events.from_dict(ev, companies, seed_value)
		events.ensure(day + 45)
	paper = d.get("paper", {}).duplicate(true)
	paper_read = bool(d.get("paperRead", true))
	if paper.is_empty() and phase == Phase.PRE_OPEN:
		_build_paper()
	has_game = true
	EventBus.game_loaded.emit()
