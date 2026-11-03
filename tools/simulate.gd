extends SceneTree
## 无界面批量跑行情与第一章，用于平衡测试（GDD 第 11、13 节）。
## 用法：
##   godot --headless --path . --script res://tools/simulate.gd -- --runs 500
## 参数：
##   --runs N     跑多少局（默认 500）
##   --days D     行情统计用多少个交易日（默认 22，约等于第一章 30 天里的交易日）
##   --seed S     起始种子（默认 1，第 i 局使用 S+i）
##   --cash C     第一章起始现金（默认读 data/chapter1.json）
##   --market 0   不输出行情统计，只跑策略
##   --csv PATH   额外把逐局结果写入 CSV
##
## 输出两部分：
## 1. 行情（含新闻事件）：每支股票的实际日波动率（与配置的 sigma 对比）、平均收益、涨跌停频率、最大回撤。
## 2. 第一章策略对比（GDD 第 13 节“预测功能失衡”）：期限那天收盘时的清算价值与胜率——
##    持有不动、随机买卖、只听预测、反着听预测、读报（只用玩家看得到的前兆与快讯）、读报 + 预测。

const Calendar := preload("res://scripts/core/calendar.gd")
const Market := preload("res://scripts/core/market.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")
const Events := preload("res://scripts/core/events.gd")
const Life := preload("res://scripts/core/life.gd")
const Predict := preload("res://scripts/core/predict.gd")

const STRATEGIES := ["hold", "random", "predict", "contrarian", "news", "news_predict"]
const STRATEGY_NAMES := {
	"hold": "持有不动", "random": "随机买卖", "predict": "只听预测", "contrarian": "反着听预测",
	"news": "读报", "news_predict": "读报+预测",
}

var companies: Array = []
var defs: Dictionary = {}
var chapter: Dictionary = {}


func _initialize() -> void:
	var args := _parse_args()
	var runs: int = args.get("runs", 500)
	var days: int = args.get("days", 22)
	var seed0: int = args.get("seed", 1)
	companies = JSON.parse_string(FileAccess.get_file_as_string("res://data/companies.json")).companies
	defs = Events.load_defs()
	chapter = JSON.parse_string(FileAccess.get_file_as_string("res://data/chapter1.json"))
	if args.has("cash"):
		chapter.start_cash = float(args.cash)
	var t0 := Time.get_ticks_msec()
	if int(args.get("market", 1)) != 0:
		_market_stats(runs, days, seed0, args)
	_strategies(runs, seed0)
	print("")
	print("耗时 %.1f 秒" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


# ---------------------------------------------------------------- 行情统计

func _market_stats(runs: int, days: int, seed0: int, args: Dictionary) -> void:
	var stats := {}
	for c in companies:
		stats[c.id] = {"ret": [], "vol": [], "limit_up": 0, "limit_down": 0, "mdd": [], "days": 0}
	var bh_returns: Array = []
	var csv_lines: Array = ["run,seed," + ",".join(companies.map(func(c): return String(c.id) + "_ret")) + ",buy_hold"]
	for r in runs:
		var m := Market.new()
		m.setup(companies, seed0 + r)
		var ev := Events.new()
		ev.setup(companies, seed0 + r, defs)
		ev.ensure(days * 2 + 10)
		var start := {}
		var peak := {}
		var mdd := {}
		var daily: Dictionary = {}
		for id in m.order:
			start[id] = m.price(id)
			peak[id] = m.price(id)
			mdd[id] = 0.0
			daily[id] = []
		var d := 1
		var done := 0
		while done < days:
			if Calendar.is_trading_day(d):
				ev.before_open(m, d)
				m.open_day(d)
				while m.tick < Market.TICKS_PER_DAY:
					ev.on_tick(m, d, m.tick)
					m.step_tick()
				for id in m.order:
					var chg := m.day_change(id)
					daily[id].append(chg)
					if chg >= Market.LIMIT - 0.002:
						stats[id].limit_up += 1
					elif chg <= -Market.LIMIT + 0.002:
						stats[id].limit_down += 1
					var p := m.price(id)
					peak[id] = maxf(peak[id], p)
					mdd[id] = maxf(mdd[id], 1.0 - p / peak[id])
				m.close_day()
				done += 1
			d += 1
		var bh := 0.0
		var row: Array = [str(r), str(seed0 + r)]
		for id in m.order:
			var ret: float = m.price(id) / start[id] - 1.0
			stats[id].ret.append(ret)
			stats[id].vol.append(_std(daily[id]))
			stats[id].mdd.append(mdd[id])
			stats[id].days += days
			bh += ret / m.order.size()
			row.append("%.5f" % ret)
		bh_returns.append(bh)
		row.append("%.5f" % bh)
		csv_lines.append(",".join(row))

	print("")
	print("行情（含新闻事件）：%d 局 × %d 个交易日（种子 %d–%d）" % [runs, days, seed0, seed0 + runs - 1])
	print("")
	print("%-10s %8s %8s %9s %9s %9s %8s %8s" % ["股票", "σ配置", "σ实际", "平均收益", "收益P10", "收益P90", "最大回撤", "涨/跌停"])
	for c in companies:
		var s: Dictionary = stats[c.id]
		var rets: Array = s.ret.duplicate()
		rets.sort()
		print("%-10s %7.2f%% %7.2f%% %+8.2f%% %+8.2f%% %+8.2f%% %7.2f%% %4.2f%%/%4.2f%%" % [
			c.short, float(c.sigma) * 100.0, _mean(s.vol) * 100.0, _mean(s.ret) * 100.0,
			_pct(rets, 0.1) * 100.0, _pct(rets, 0.9) * 100.0, _mean(s.mdd) * 100.0,
			100.0 * s.limit_up / s.days, 100.0 * s.limit_down / s.days])
	bh_returns.sort()
	print("")
	print("等权买入并持有：平均 %+.2f%%，中位数 %+.2f%%，P10 %+.2f%%，P90 %+.2f%%" % [
		_mean(bh_returns) * 100.0, _pct(bh_returns, 0.5) * 100.0, _pct(bh_returns, 0.1) * 100.0,
		_pct(bh_returns, 0.9) * 100.0])
	if args.has("csv"):
		var out := FileAccess.open(args.csv, FileAccess.WRITE)
		if out:
			out.store_string("\n".join(csv_lines) + "\n")
			print("逐局结果已写入 ", args.csv)


# ---------------------------------------------------------------- 第一章策略

func _strategies(runs: int, seed0: int) -> void:
	var cash := float(chapter.start_cash)
	var debt := float(chapter.debt)
	var deadline := int(chapter.deadline_day)
	print("")
	print("第一章策略对比：%d 局，起始现金 %s，债务 %s，期限第 %d 天收盘（需要 %.2f 倍）" % [
		runs, Portfolio.fmt_money(cash), Portfolio.fmt_money(debt), deadline, debt / cash])
	print("")
	print("%-10s %6s %9s %9s %9s %9s %8s" % ["策略", "胜率", "倍数P10", "中位数", "倍数P90", "最好", "预测准确"])
	for strat in STRATEGIES:
		var mults: Array = []
		var wins := 0
		var hits := 0
		var preds := 0
		for r in runs:
			var res := _play(strat, seed0 + r, cash, deadline)
			mults.append(float(res.value) / cash)
			if float(res.value) >= debt:
				wins += 1
			hits += int(res.hits)
			preds += int(res.preds)
		mults.sort()
		print("%-10s %5.1f%% %8.2fx %8.2fx %8.2fx %8.2fx %8s" % [
			STRATEGY_NAMES[strat], 100.0 * wins / runs, _pct(mults, 0.1), _pct(mults, 0.5),
			_pct(mults, 0.9), mults[-1], ("%.0f%%" % (100.0 * hits / preds)) if preds > 0 else "-"])


## 跑一局第一章，返回 {value: 期限收盘时的清算价值, hits, preds}。
func _play(strat: String, game_seed: int, cash: float, deadline: int) -> Dictionary:
	var m := Market.new()
	m.setup(companies, game_seed)
	var ev := Events.new()
	ev.setup(companies, game_seed, defs)
	ev.ensure(deadline + 40)
	var pf := Portfolio.new()
	pf.cash = cash
	pf.debt = 0.0
	var player := Life.new_player("bot")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([game_seed, strat])
	var reader := strat == "news" or strat == "news_predict"
	# 读报：看到的带方向前兆 uid → {signs, seen, fired}；持仓到 hold_until 那天开盘卖出
	var clues := {}
	var hold_uid := ""
	var hold_until := 0
	var hits := 0
	var preds := 0
	var pending: Array = []
	var d := 1
	while d <= deadline:
		if not Calendar.is_trading_day(d):
			d += 1
			continue
		var equity0 := pf.cash + pf.holdings_value(m)
		_read(ev.before_open(m, d), clues, d)
		m.open_day(d)
		var want := ""
		var sell_all := false
		match strat:
			"hold":
				want = "spread" if d == 1 else ""
			"random":
				sell_all = true
				if rng.randf() < 0.5:
					want = String(m.order[rng.randi_range(0, m.order.size() - 1)])
			"predict", "contrarian":
				sell_all = true
				var best := _ask(m, ev, player, d, strat == "contrarian", pending)
				preds += int(best.asked)
				want = String(best.id)
			_:
				var cur := _held(pf)
				if cur != "":
					if hold_uid != "" and clues.has(hold_uid) and int(clues[hold_uid].fired) >= 0:
						hold_until = mini(hold_until, Calendar.next_trading_day(int(clues[hold_uid].fired)))
					if _negative(clues, cur, d) or d >= hold_until:
						sell_all = true
						cur = ""
				if cur == "":
					var pick := _news_pick(clues, d)
					if String(pick.id) != "":
						var ok := true
						if strat == "news_predict":
							ok = _confirm(m, ev, player, d, String(pick.id), pending)
							preds += 1
						if ok:
							want = String(pick.id)
							hold_uid = String(pick.uid)
							hold_until = _shift(d, 6)
		for t in Market.TICKS_PER_DAY:
			var news := ev.on_tick(m, d, t)
			_read(news, clues, d)
			if t == 0:
				if sell_all:
					_sell_all(pf, m)
				if want == "spread":
					for id in m.order:
						var q := int(pf.cash / (m.order.size() - m.order.find(id)) / m.price(id) / 10.0) * 10
						q = mini(q, pf.max_buy_qty(m, id))
						if q > 0:
							pf.execute(m, id, "buy", q)
				elif want != "":
					var q := pf.max_buy_qty(m, want)
					if q > 0:
						pf.execute(m, want, "buy", q)
			# 读报的策略对盘中快讯也会反应：持仓遇到利空就跑，空仓时追利好
			if reader and not news.is_empty():
				for it in news:
					var signs: Dictionary = it.signs
					var cur := _held(pf)
					if cur != "" and int(signs.get(cur, signs.get("all", 0))) < 0:
						_sell_all(pf, m)
						cur = ""
					if cur == "":
						for id in signs:
							if int(signs[id]) > 0 and id != "all":
								var q := pf.max_buy_qty(m, id)
								if q > 0:
									pf.execute(m, id, "buy", q)
									hold_uid = String(it.uid)
									hold_until = Calendar.next_trading_day(d)
								break
			m.step_tick()
		if strat in ["random", "predict", "contrarian"]:
			_sell_all(pf, m)  # 收盘前卖掉（按收盘价近似）
		m.close_day()
		var still: Array = []
		for pr in pending:
			if int(pr.target_day) == d:
				if bool(Predict.review(pr, m.price(String(pr.id)), float(m.configs[pr.id].sigma)).hit):
					hits += 1
			else:
				still.append(pr)
		pending = still
		var equity1 := pf.cash + pf.holdings_value(m)
		Life.end_trading_day(player, equity1 / equity0 - 1.0 if equity0 > 0.0 else 0.0, -1)
		var nd := Calendar.next_trading_day(d)
		var lrng := RandomNumberGenerator.new()
		lrng.seed = hash([game_seed, d, "life"])
		Life.sleep(player, lrng, nd - d - 1, "rest")
		player.predictionsLeft = Life.predictions_per_day(player)
		d += 1
	var value := pf.cash
	for id in pf.holdings:
		value += float(m.quote(id, "sell", pf.qty_of(id)).total)
	return {"value": value, "hits": hits, "preds": preds}


func _read(items: Array, clues: Dictionary, d: int) -> void:
	for it in items:
		var uid := String(it.uid)
		if uid == "":
			continue
		var signs: Dictionary = it.signs
		match String(it.kind):
			"precursor":
				if not signs.is_empty() and not clues.has(uid):
					clues[uid] = {"signs": signs, "seen": d, "fired": -1}
			"rumor", "filler":
				pass  # 传闻真假参半，读报的策略不追
			_:
				if clues.has(uid):
					clues[uid].fired = d


## 选一支有利好前兆、事件还没发生的股票（最新的线索优先）。利好大盘的线索买高波动的公会联合。
func _news_pick(clues: Dictionary, d: int) -> Dictionary:
	var best := ""
	var best_uid := ""
	var best_seen := -1
	for uid in clues:
		var c: Dictionary = clues[uid]
		if int(c.fired) >= 0:
			continue
		for id in c.signs:
			if int(c.signs[id]) > 0 and int(c.seen) > best_seen:
				best_seen = int(c.seen)
				best = "guild" if String(id) == "all" else String(id)
				best_uid = String(uid)
	return {"id": best, "uid": best_uid}


func _negative(clues: Dictionary, id: String, d: int) -> bool:
	for uid in clues:
		var c: Dictionary = clues[uid]
		if int(c.fired) >= 0 and int(c.fired) < d:
			continue
		if int(c.signs.get(id, c.signs.get("all", 0))) < 0:
			return true
	return false


func _held(pf: Portfolio) -> String:
	for id in pf.holdings:
		return String(id)
	return ""


func _sell_all(pf: Portfolio, m: Market) -> void:
	for id in pf.holdings.keys():
		pf.execute(m, id, "sell", pf.qty_of(id))


func _shift(day: int, k: int) -> int:
	var d := day
	for _i in k:
		d = Calendar.next_trading_day(d)
	return d


## 只听预测：开盘时问 3 支高波动股票“今天收盘前”，挑说“大涨”的，没有就挑“小涨”的。
func _ask(m: Market, ev: Events, player: Dictionary, d: int, contrarian: bool, pending: Array) -> Dictionary:
	var best := ""
	var best_score := 0
	var asked := 0
	for id in ["guild", "elder", "dragonspine"]:
		if Life.predict_block_reason(player) != "":
			break
		var pr := Predict.predict(m, ev, player, d, "trading", id, "today", [m.seed_value, d, id])
		Life.spend_prediction(player)
		asked += 1
		pending.append(pr)
		var dir := String(pr.dir)
		if contrarian:
			dir = {"up": "down", "down": "up"}.get(dir, dir)
		var score := 0
		if dir == "up":
			score = 2 if String(pr.mag) == "big" else 1
		if score > best_score:
			best_score = score
			best = id
	return {"id": best, "asked": asked}


## 读报 + 预测：买之前问一次“到明天收盘”，她说跌（而且状态不差）就放弃。
func _confirm(m: Market, ev: Events, player: Dictionary, d: int, id: String, pending: Array) -> bool:
	if Life.predict_block_reason(player) != "":
		return true
	var pr := Predict.predict(m, ev, player, d, "trading", id, "tomorrow", [m.seed_value, d, id, "c"])
	Life.spend_prediction(player)
	pending.append(pr)
	return String(pr.dir) != "down" or Life.accuracy(player) < 0.5


# ---------------------------------------------------------------- 工具

func _parse_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i].trim_prefix("--")
		if i + 1 < a.size():
			var v := a[i + 1]
			out[k] = v.to_int() if v.is_valid_int() else v
			i += 2
		else:
			i += 1
	return out


func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / arr.size()


func _std(arr: Array) -> float:
	if arr.size() < 2:
		return 0.0
	var m := _mean(arr)
	var s := 0.0
	for v in arr:
		s += (float(v) - m) * (float(v) - m)
	return sqrt(s / (arr.size() - 1))


func _pct(sorted_arr: Array, q: float) -> float:
	if sorted_arr.is_empty():
		return 0.0
	return float(sorted_arr[clampi(int(q * (sorted_arr.size() - 1)), 0, sorted_arr.size() - 1)])
