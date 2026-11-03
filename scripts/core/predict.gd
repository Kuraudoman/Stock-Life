extends RefCounted
## 主角的走势预测（GDD 第 6 节）。纯逻辑。
##
## 1. 复制当前的市场和事件日程，用同一个随机数状态向后推演“玩家不干预”的走势，得到真实的方向和力度。
## 2. 按主角当时的情绪和身体状态算出正确率 p（life.gd），以概率 p 说出真实结果，否则说反；
##    狂热时几乎总说“大涨”，恐慌时几乎总说“大跌”，疲劳时力度经常说错，发烧时纯属随机。
## 3. 预测结果不保存真实答案（免得翻存档就能看到），到期后用实际收盘价回顾说中没有。

const Calendar := preload("res://scripts/core/calendar.gd")
const Life := preload("res://scripts/core/life.gd")

const TICKS := 36
const HORIZONS := ["today", "tomorrow", "3days"]
const HORIZON_NAMES := {"today": "今天收盘前", "tomorrow": "到明天收盘", "3days": "未来 3 个交易日"}
const DIR_NAMES := {"up": "涨", "down": "跌", "flat": "横盘"}
const MAG_NAMES := {"small": "小幅", "big": "大幅"}


## 推演未来：返回 {"today": {id: 收盘价}（今天还没收盘时）, "days": [{day, closes: {id: 收盘价}}, ...]}。
## phase 为 "pre_open" / "trading" / "closed"。
static func simulate(market: RefCounted, events: RefCounted, day: int, phase: String, n_days: int) -> Dictionary:
	var m: RefCounted = market.clone(false)
	var e: RefCounted = events.clone()
	var out := {"today": {}, "days": []}
	if phase == "pre_open":
		e.before_open(m, day)
		m.open_day(day)
	if phase == "pre_open" or phase == "trading":
		while m.tick < TICKS:
			e.on_tick(m, day, m.tick)
			m.step_tick()
		m.close_day()
		out.today = _closes(m)
	var d := day
	for _i in n_days:
		d = Calendar.next_trading_day(d)
		e.before_open(m, d)
		m.open_day(d)
		while m.tick < TICKS:
			e.on_tick(m, d, m.tick)
			m.step_tick()
		m.close_day()
		out.days.append({"day": d, "closes": _closes(m)})
	return out


static func _closes(m: RefCounted) -> Dictionary:
	var c := {}
	for id in m.order:
		c[id] = m.price(id)
	return c


## 某个时间跨度能不能预测（已收盘时不能预测“今天收盘前”）。
static func horizon_available(horizon: String, phase: String) -> bool:
	return horizon != "today" or phase != "closed"


## 时间跨度对应的“天数”，用于按波动率划分小幅 / 大幅。
static func horizon_days(horizon: String, phase: String, tick: int) -> float:
	var today_left := 0.0
	if phase == "pre_open":
		today_left = 1.0
	elif phase == "trading":
		today_left = float(TICKS - tick) / TICKS
	match horizon:
		"today":
			return maxf(today_left, 0.1)
		"tomorrow":
			return today_left + 1.0
	return today_left + 3.0


## 目标交易日：今天、下一个交易日、之后第 3 个交易日（已收盘时从明天算起）。
static func target_day(horizon: String, day: int, phase: String) -> int:
	if horizon == "today":
		return day
	var n := 1 if horizon == "tomorrow" else 3
	var d := day
	for _i in n:
		d = Calendar.next_trading_day(d)
	return d


## 把收益率分成 涨 / 跌 / 横盘 与 小幅 / 大幅。阈值按个股波动率和时间跨度缩放。
static func classify(ret: float, sigma: float, days: float) -> Dictionary:
	var scale := sigma * sqrt(maxf(days, 0.1))
	var a := absf(ret)
	if a < maxf(0.005, 0.3 * scale):
		return {"dir": "flat", "mag": "small"}
	return {"dir": "up" if ret > 0.0 else "down", "mag": "big" if a >= maxf(0.03, 1.2 * scale) else "small"}


## 发起一次预测。返回 {id, horizon, target_day, base_price, dir, mag, expr, made_day, made_tick}。
## key 用来派生随机数（同一时刻对同一支股票重复预测得到同样的答案，读档重来也一样）。
static func predict(market: RefCounted, events: RefCounted, player: Dictionary, day: int, phase: String,
		id: String, horizon: String, key: Array) -> Dictionary:
	var td := target_day(horizon, day, phase)
	var n_days := 0
	if horizon != "today":
		n_days = 1 if horizon == "tomorrow" else 3
	var sim := simulate(market, events, day, phase, n_days)
	var target := 0.0
	if horizon == "today":
		target = float(sim.today[id])
	else:
		target = float((sim.days[-1] as Dictionary).closes[id])
	var base := float(market.price(id))
	var sigma := float(market.configs[id].sigma)
	var days := horizon_days(horizon, phase, int(market.tick))
	var truth := classify(target / base - 1.0, sigma, days)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var said := decide(truth, player, rng)
	said.merge({
		"id": id, "horizon": horizon, "target_day": td, "base_price": base, "days": days,
		"made_day": day, "made_tick": int(market.tick) if phase == "trading" else -1,
		"mood": String(player.mood), "body": String(player.body),
	})
	return said


## 按状态决定说出口的结果。
static func decide(truth: Dictionary, player: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var p := Life.accuracy(player)
	var dir := String(truth.dir)
	var mag := String(truth.mag)
	if rng.randf() >= p:
		match dir:
			"up":
				dir = "down"
			"down":
				dir = "up"
			_:
				dir = "up" if rng.randf() < 0.5 else "down"
		mag = "big" if rng.randf() < 0.5 else "small"
	match String(player.mood):
		"manic":
			if rng.randf() < 0.7:
				dir = "up"
				mag = "big"
		"panic":
			if rng.randf() < 0.7:
				dir = "down"
				mag = "big"
		"optimistic":
			if dir == "flat" and rng.randf() < 0.5:
				dir = "up"
		"pessimistic":
			if dir == "flat" and rng.randf() < 0.5:
				dir = "down"
	if String(player.body) == "tired" and dir != "flat" and rng.randf() < 0.4:
		mag = "small" if mag == "big" else "big"
	if dir == "flat":
		mag = "small"
	return {"dir": dir, "mag": mag}


## 回顾：实际涨跌是否和她说的一致（方向一致即算说中）。
static func review(pred: Dictionary, close_price: float, sigma: float) -> Dictionary:
	var ret := close_price / float(pred.base_price) - 1.0
	var actual := classify(ret, sigma, float(pred.get("days", 1.0)))
	return {"ret": ret, "dir": String(actual.dir), "hit": String(actual.dir) == String(pred.dir)}


static func label(pred: Dictionary) -> String:
	var d := String(pred.dir)
	if d == "flat":
		return "横盘"
	return "%s%s" % [MAG_NAMES.get(String(pred.mag), ""), DIR_NAMES.get(d, d)]


static func arrow(pred: Dictionary) -> String:
	match String(pred.dir):
		"up":
			return "↑↑" if String(pred.mag) == "big" else "↑"
		"down":
			return "↓↓" if String(pred.mag) == "big" else "↓"
	return "→"
