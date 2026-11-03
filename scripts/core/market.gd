extends RefCounted
## 市场与价格模型（GDD 第 5 节）。纯逻辑，不依赖任何场景节点，可在无界面模式下测试。
##
## 每个 tick：
##   P(t+1) = P(t) × (1 + μ_macro + μ_sector + κ·(V−P)/P + σ·ε + S + I)
## - μ_macro：大盘趋势，来自章节阶段（M1 之后加入铸币局利率）
## - μ_sector：行业趋势，每个交易日抽取一次，同行业股票共享
## - κ：均值回归强度，让价格长期向基本面价值 V 靠拢
## - σ·ε：随机波动，ε 由“大盘共同因子 + 个股因子”合成，形成联动
## - S：事件冲击（add_shock，由新闻系统 events.gd 调用）
## - I：玩家与大户下单造成的价格冲击
## 单日涨跌幅限制 ±15%。所有随机数来自同一个带种子的 RandomNumberGenerator，同一种子 + 同样操作 = 同一局行情。

const Calendar := preload("res://scripts/core/calendar.gd")

const TICKS_PER_DAY := 36
const LIMIT := 0.15
const LOT := 10
const FEE_RATE := 0.003
const SELL_TAX_RATE := 0.001
## ε 中大盘共同因子的权重（0 = 各股独立，1 = 完全同涨同跌）。
const MARKET_FACTOR_WEIGHT := 0.45
## 行业日漂移的标准差 = 个股日波动率 × 该比例。
const SECTOR_DRIFT_RATIO := 0.25
## 隔夜跳空的标准差 = 个股日波动率 × 该比例 × sqrt(间隔天数)。
const OVERNIGHT_SIGMA_RATIO := 0.3
## 滑点 = SLIPPAGE_K × 下单量 / 流动性；价格冲击 = IMPACT_K × 下单量 / 流动性。
const SLIPPAGE_K := 0.5
const IMPACT_K := 1.0
## 开局前生成的历史行情（日历天数，约 60 个交易日），让 K 线一开始就有内容。
const PREHISTORY_CALENDAR_DAYS := 84
const MAX_CANDLES := 400

## 经济阶段：大盘日漂移、均值回归倍率。狂热期调低 κ，泡沫因此形成。
const PHASES := {
	"dawn": {"name": "黎明", "macro_drift": 0.0008, "kappa_mult": 1.0},
	"boom": {"name": "繁荣", "macro_drift": 0.0015, "kappa_mult": 0.8},
	"mania": {"name": "狂热", "macro_drift": 0.003, "kappa_mult": 0.3},
	"crash": {"name": "崩盘", "macro_drift": -0.004, "kappa_mult": 0.6},
}

var rng := RandomNumberGenerator.new()
var seed_value := 0
var configs: Dictionary = {}
var order: Array[String] = []
var stocks: Dictionary = {}
var phase := "dawn"
var current_day := 0
var last_close_day := 0
var is_open := false
var tick := 0


# ---------------------------------------------------------------- 初始化

func setup(companies: Array, p_seed: int, first_day: int = 1) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	_load_configs(companies)
	stocks.clear()
	for id in order:
		var c: Dictionary = configs[id]
		var p := float(c.price)
		stocks[id] = {
			"price": p, "value": float(c.value),
			"prev_close": p, "ref_close": p,
			"open": p, "high": p, "low": p, "volume": 0,
			"intraday": [p], "intraday_volume": [0],
			"candles": [], "pending_impact": 0.0, "player_volume": 0,
			"sector_drift": 0.0, "shocks": [], "volume_boost": 1.0,
		}
	# 开局前的历史行情
	var start := first_day - PREHISTORY_CALENDAR_DAYS
	last_close_day = start - 1
	for d in range(start, first_day):
		if Calendar.is_trading_day(d):
			open_day(d)
			for _i in TICKS_PER_DAY:
				step_tick()
			close_day()
	current_day = last_close_day


func _load_configs(companies: Array) -> void:
	configs.clear()
	order.clear()
	for c in companies:
		configs[String(c.id)] = c
		order.append(String(c.id))


func set_phase(p_phase: String) -> void:
	if PHASES.has(p_phase):
		phase = p_phase


# ---------------------------------------------------------------- 交易日流程

## 开盘：更新基本面、抽取行业漂移、计算隔夜跳空。
func open_day(day: int) -> void:
	var gap := maxi(1, day - last_close_day)
	var ph: Dictionary = PHASES[phase]
	var sector_drift := {}
	for id in order:
		var c: Dictionary = configs[id]
		var s: Dictionary = stocks[id]
		var sigma := float(c.sigma)
		# 基本面价值：每个交易日随机游走一次
		s.value = float(s.value) * exp(float(c.value_drift) + float(c.value_vol) * rng.randfn())
		# 行业趋势：同行业共享
		var sector := String(c.sector)
		if not sector_drift.has(sector):
			sector_drift[sector] = rng.randfn() * sigma * SECTOR_DRIFT_RATIO
		s.sector_drift = sector_drift[sector]
		# 隔夜跳空：周末 / 节日后间隔越长，跳空越大（“周一开盘惊吓”）
		var prev := float(s.prev_close)
		var gap_ret := rng.randfn() * sigma * OVERNIGHT_SIGMA_RATIO * sqrt(gap)
		gap_ret += float(c.kappa) * float(ph.kappa_mult) * 0.25 * (float(s.value) - prev) / prev
		gap_ret += _open_shocks(s)
		s.ref_close = prev
		var o := _clamp_price(s, prev * (1.0 + gap_ret))
		s.price = o
		s.open = o
		s.high = o
		s.low = o
		s.volume = 0
		s.intraday = [o]
		s.intraday_volume = [0]
	current_day = day
	tick = 0
	is_open = true


## 推进一个 tick（10 分钟）。
func step_tick() -> void:
	if not is_open or tick >= TICKS_PER_DAY:
		return
	var ph: Dictionary = PHASES[phase]
	var m := rng.randfn()
	var w := MARKET_FACTOR_WEIGHT
	var wi := sqrt(1.0 - w * w)
	# 成交量的 U 型日内分布：开盘和收盘附近更活跃
	var x := (float(tick) / float(TICKS_PER_DAY - 1) - 0.5) * 2.0
	var u_shape := 0.75 + 0.75 * x * x
	for id in order:
		var c: Dictionary = configs[id]
		var s: Dictionary = stocks[id]
		var p := float(s.price)
		var eps := w * m + wi * rng.randfn()
		var sig_t := float(c.sigma) / sqrt(float(TICKS_PER_DAY))
		var mu := (float(ph.macro_drift) + float(s.sector_drift)) / TICKS_PER_DAY
		var rev := float(c.kappa) * float(ph.kappa_mult) / TICKS_PER_DAY * (float(s.value) - p) / p
		var shock := _shock_this_tick(s)
		var impact := float(s.pending_impact)
		s.pending_impact = 0.0
		var r := mu + rev + sig_t * eps + shock + impact
		var np := _clamp_price(s, p * (1.0 + r))
		# 有消息的时段成交放大（盘面异动）：前兆日的 volume_boost + 冲击越大量越大
		var news_mult := float(s.get("volume_boost", 1.0)) * (1.0 + minf(3.0, absf(shock) * 150.0))
		var vol := int(float(c.base_volume) / TICKS_PER_DAY * u_shape
				* (0.6 + 0.45 * absf(eps)) * (0.7 + 0.6 * rng.randf()) * news_mult)
		vol += int(s.player_volume)
		s.player_volume = 0
		s.price = np
		s.high = maxf(float(s.high), np)
		s.low = minf(float(s.low), np)
		s.volume = int(s.volume) + vol
		(s.intraday as Array).append(np)
		(s.intraday_volume as Array).append(vol)
	tick += 1


## 收盘：生成日 K、事件冲击衰减。
func close_day() -> void:
	for id in order:
		var s: Dictionary = stocks[id]
		var candles: Array = s.candles
		candles.append({
			"d": current_day, "o": s.open, "h": s.high, "l": s.low,
			"c": s.price, "v": s.volume,
		})
		while candles.size() > MAX_CANDLES:
			candles.pop_front()
		s.prev_close = s.price
		s.volume_boost = 1.0
		_close_shocks(s)
	last_close_day = current_day
	is_open = false


func is_day_finished() -> bool:
	return tick >= TICKS_PER_DAY


# ---------------------------------------------------------------- 事件冲击（新闻系统使用）

## 对某支股票施加事件冲击。portions[i] 是第 i 个交易日的冲击幅度（收益率）。
## mode 决定第一份怎么体现，之后的每一份都平摊到对应交易日的 36 个 tick：
##   "gap"    下一次开盘时以跳空体现（盘前、休市期间的消息）
##   "spread" 平摊到当天剩余的 tick（开盘前调用则平摊到整天）
##   "burst"  集中在接下来 burst_ticks 个 tick 里（盘中突发快讯）；收盘时没走完的部分变成次日跳空
func add_shock(id: String, portions: Array, mode: String = "spread", burst_ticks: int = 4) -> void:
	if not stocks.has(id) or portions.is_empty():
		return
	var left := 0
	if mode == "burst" and not is_open:
		mode = "gap"
	if is_open and mode == "spread":
		left = maxi(1, TICKS_PER_DAY - tick)
	elif is_open and mode == "burst":
		left = maxi(1, burst_ticks)
	var list: Array = []
	for v in portions:
		list.append(float(v))
	(stocks[id].shocks as Array).append({"portions": list, "mode": mode, "left": left})


## 旧接口：总幅度 total 平均分摊到 days 个交易日；overnight=true 时第一份在下一次开盘跳空。
func apply_shock(id: String, total: float, days: int = 1, overnight: bool = false) -> void:
	var n := maxi(1, days)
	var portions: Array = []
	for _i in n:
		portions.append(total / n)
	add_shock(id, portions, "gap" if overnight else "spread")


## 盘前 / 休市期间的消息让成交放大（前兆日的“盘面异动”），收盘后恢复。
func boost_volume(id: String, mult: float) -> void:
	if stocks.has(id):
		stocks[id].volume_boost = maxf(float(stocks[id].get("volume_boost", 1.0)), mult)


## 开盘：结算跳空冲击，并让其余冲击开始平摊当天的份额。返回跳空幅度。
func _open_shocks(s: Dictionary) -> float:
	var gap := 0.0
	var keep: Array = []
	for sh in s.shocks:
		var portions: Array = sh.portions
		var gapped := false
		if String(sh.mode) == "gap" and not portions.is_empty():
			gap += float(portions.pop_front())
			sh.mode = "spread"
			gapped = true
		if portions.is_empty():
			continue
		# 今天已经跳空过的冲击，下一份从明天开始
		sh.left = 0 if gapped else TICKS_PER_DAY
		keep.append(sh)
	s.shocks = keep
	return gap


func _shock_this_tick(s: Dictionary) -> float:
	var sum := 0.0
	for sh in s.shocks:
		var left := int(sh.left)
		var portions: Array = sh.portions
		if left <= 0 or portions.is_empty():
			continue
		var part := float(portions[0]) / left
		sum += part
		portions[0] = float(portions[0]) - part
		sh.left = left - 1
		if left - 1 == 0:
			portions.pop_front()
			sh.mode = "spread"
	return sum


## 收盘：没走完的冲击（盘中快讯的尾巴）变成次日跳空，走完的丢掉。
func _close_shocks(s: Dictionary) -> void:
	var keep: Array = []
	for sh in s.shocks:
		if int(sh.left) > 0:
			sh.mode = "gap"
			sh.left = 0
		if not (sh.portions as Array).is_empty():
			keep.append(sh)
	s.shocks = keep


# ---------------------------------------------------------------- 报价与成交

func limit_up(id: String) -> float:
	return floorf(float(stocks[id].ref_close) * (1.0 + LIMIT) * 100.0) / 100.0


func limit_down(id: String) -> float:
	return maxf(0.01, ceilf(float(stocks[id].ref_close) * (1.0 - LIMIT) * 100.0) / 100.0)


func _clamp_price(s: Dictionary, p: float) -> float:
	var ref := float(s.ref_close)
	var hi := floorf(ref * (1.0 + LIMIT) * 100.0) / 100.0
	var lo := maxf(0.01, ceilf(ref * (1.0 - LIMIT) * 100.0) / 100.0)
	return clampf(snappedf(p, 0.01), lo, hi)


func price(id: String) -> float:
	return float(stocks[id].price)


## 当日涨跌幅（相对昨收）。
func day_change(id: String) -> float:
	var ref := float(stocks[id].ref_close)
	return float(stocks[id].price) / ref - 1.0 if ref > 0.0 else 0.0


## 预估一笔交易：成交均价、滑点、手续费、交易税、总额。side 为 "buy" 或 "sell"。
func quote(id: String, side: String, qty: int) -> Dictionary:
	var c: Dictionary = configs[id]
	var p := price(id)
	var frac := float(qty) / maxf(1.0, float(c.liquidity))
	var slip := SLIPPAGE_K * frac
	var avg := p * (1.0 + slip) if side == "buy" else p * (1.0 - slip)
	avg = clampf(avg, limit_down(id), limit_up(id))
	var gross := avg * qty
	var fee := gross * FEE_RATE
	var tax := gross * SELL_TAX_RATE if side == "sell" else 0.0
	var total := gross + fee if side == "buy" else gross - fee - tax
	return {
		"id": id, "side": side, "qty": qty, "price": p, "avg_price": avg,
		"slippage": slip, "gross": gross, "fee": fee, "tax": tax, "total": total,
	}


## 成交后登记价格冲击与成交量，在下一个 tick 生效。
func register_trade(id: String, side: String, qty: int) -> void:
	var c: Dictionary = configs[id]
	var s: Dictionary = stocks[id]
	var frac := float(qty) / maxf(1.0, float(c.liquidity))
	s.pending_impact = float(s.pending_impact) + (IMPACT_K * frac if side == "buy" else -IMPACT_K * frac)
	s.player_volume = int(s.player_volume) + qty


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	var st := {}
	for id in order:
		st[id] = (stocks[id] as Dictionary).duplicate(true)
	return {
		"seed": seed_value,
		# 64 位随机数状态用字符串保存，避免 JSON 浮点数丢失精度
		"rngState": str(rng.state),
		"phase": phase,
		"currentDay": current_day,
		"lastCloseDay": last_close_day,
		"isOpen": is_open,
		"tick": tick,
		"stocks": st,
	}


## 复制一份市场（预测推演用）。with_history=false 时不复制 K 线，推演更快。
func clone(with_history: bool = true) -> RefCounted:
	var m: RefCounted = get_script().new()
	m.seed_value = seed_value
	m.rng.seed = seed_value
	m.rng.state = rng.state
	m.configs = configs
	m.order = order.duplicate()
	m.phase = phase
	m.current_day = current_day
	m.last_close_day = last_close_day
	m.is_open = is_open
	m.tick = tick
	for id in order:
		var s: Dictionary = stocks[id]
		if with_history:
			m.stocks[id] = s.duplicate(true)
		else:
			var candles: Array = s.candles
			s.candles = []
			m.stocks[id] = s.duplicate(true)
			s.candles = candles
	return m


func from_dict(d: Dictionary, companies: Array) -> void:
	_load_configs(companies)
	seed_value = int(d.seed)
	rng.seed = seed_value
	rng.state = String(d.rngState).to_int()
	phase = String(d.get("phase", "dawn"))
	current_day = int(d.currentDay)
	last_close_day = int(d.lastCloseDay)
	is_open = bool(d.isOpen)
	tick = int(d.tick)
	stocks.clear()
	var saved: Dictionary = d.stocks
	for id in order:
		var s: Dictionary = (saved[id] as Dictionary).duplicate(true)
		# JSON 读回的整数是 float，这里统一转换
		s.volume = int(s.volume)
		s.player_volume = int(s.get("player_volume", 0))
		var iv: Array = []
		for v in s.intraday_volume:
			iv.append(int(v))
		s.intraday_volume = iv
		for cd in s.candles:
			cd.d = int(cd.d)
			cd.v = int(cd.v)
		s.volume_boost = float(s.get("volume_boost", 1.0))
		s.shocks = _migrate_shocks(s.get("shocks", []))
		stocks[id] = s


## 存档版本 1 的冲击是 {per_day, days, overnight}，转换成现在的 {portions, mode, left}。
func _migrate_shocks(list: Array) -> Array:
	var out: Array = []
	for sh in list:
		if sh.has("portions"):
			sh.left = int(sh.get("left", 0))
			out.append(sh)
			continue
		var portions: Array = []
		for _i in int(sh.days):
			portions.append(float(sh.per_day))
		var mode := "gap" if bool(sh.get("overnight", false)) else "spread"
		out.append({"portions": portions, "mode": mode,
				"left": TICKS_PER_DAY - tick if is_open and mode == "spread" else 0})
	return out
