extends RefCounted
## 现金、负债、持仓与成交（GDD 第 5 节“交易规则”）。纯逻辑。
##
## 最小交易单位 10 股；手续费 0.3%，卖出另收 0.1% 交易税；滑点与价格冲击由 Market 计算。

const Market := preload("res://scripts/core/market.gd")

var cash := 10000.0
var debt := 50000.0
## { 股票 id: { "qty": int, "avgCost": float } }，avgCost 含手续费。
var holdings: Dictionary = {}
var realized_pnl := 0.0
var fees_paid := 0.0


func qty_of(id: String) -> int:
	return int(holdings[id].qty) if holdings.has(id) else 0


func avg_cost_of(id: String) -> float:
	return float(holdings[id].avgCost) if holdings.has(id) else 0.0


func holdings_value(market: Market) -> float:
	var sum := 0.0
	for id in holdings:
		sum += int(holdings[id].qty) * market.price(id)
	return sum


func net_worth(market: Market) -> float:
	return cash + holdings_value(market) - debt


func unrealized_pnl(market: Market, id: String) -> float:
	if not holdings.has(id):
		return 0.0
	return (market.price(id) - avg_cost_of(id)) * qty_of(id)


## 检查一笔交易是否可以执行；返回空字符串表示可以，否则返回原因。
func validate(market: Market, id: String, side: String, qty: int) -> String:
	if not market.is_open:
		return "现在不是交易时间"
	if not market.stocks.has(id):
		return "没有这支股票"
	if qty <= 0 or qty % Market.LOT != 0:
		return "数量必须是 %d 股的整数倍" % Market.LOT
	if side == "buy":
		var q := market.quote(id, side, qty)
		if float(q.total) > cash + 0.0001:
			return "现金不足（需要 %s）" % fmt_money(float(q.total))
	elif side == "sell":
		if qty > qty_of(id):
			return "持股不足（持有 %d 股）" % qty_of(id)
	else:
		return "未知的交易方向"
	return ""


## 执行交易。返回 { ok, error, quote... }。
func execute(market: Market, id: String, side: String, qty: int) -> Dictionary:
	var err := validate(market, id, side, qty)
	if err != "":
		return {"ok": false, "error": err}
	var q := market.quote(id, side, qty)
	if side == "buy":
		cash -= float(q.total)
		var old_qty := qty_of(id)
		var new_qty := old_qty + qty
		var new_cost := (avg_cost_of(id) * old_qty + float(q.total)) / new_qty
		holdings[id] = {"qty": new_qty, "avgCost": new_cost}
	else:
		cash += float(q.total)
		var cost := avg_cost_of(id) * qty
		realized_pnl += float(q.total) - cost
		var left := qty_of(id) - qty
		if left <= 0:
			holdings.erase(id)
		else:
			holdings[id].qty = left
	fees_paid += float(q.fee) + float(q.tax)
	cash = snappedf(cash, 0.01)
	market.register_trade(id, side, qty)
	q.ok = true
	q.error = ""
	return q


## 用现金还债，返回实际还款额（不超过现金和剩余债务）。
func repay(amount: float) -> float:
	var a := snappedf(clampf(amount, 0.0, minf(cash, debt)), 0.01)
	cash = snappedf(cash - a, 0.01)
	debt = snappedf(debt - a, 0.01)
	if debt < 0.01:
		debt = 0.0
	return a


## 全部持仓按当前价卖出的到手金额（计入滑点、手续费、交易税）。
func liquidation_value(market: Market) -> float:
	var v := cash
	for id in holdings:
		v += float(market.quote(id, "sell", qty_of(id)).total)
	return v


## 期限清算：不管是否开盘，按当前价卖出全部持仓，返回卖出所得。
func liquidate(market: Market) -> float:
	var got := 0.0
	for id in holdings.keys():
		var q := market.quote(id, "sell", qty_of(id))
		got += float(q.total)
		realized_pnl += float(q.total) - avg_cost_of(id) * qty_of(id)
		fees_paid += float(q.fee) + float(q.tax)
	holdings.clear()
	cash = snappedf(cash + got, 0.01)
	return got


## 当前现金最多能买多少股（按 10 股取整，计入滑点与手续费）。
@warning_ignore("integer_division")
func max_buy_qty(market: Market, id: String) -> int:
	var p := market.price(id)
	if p <= 0.0:
		return 0
	var lots_hi := int(cash / (p * (1.0 + Market.FEE_RATE)) / Market.LOT) + 1
	var lo := 0
	var hi := lots_hi
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(market.quote(id, "buy", mid * Market.LOT).total) <= cash:
			lo = mid
		else:
			hi = mid - 1
	return lo * Market.LOT


func to_dict() -> Dictionary:
	return {
		"cash": cash, "debt": debt, "holdings": holdings.duplicate(true),
		"realizedPnl": realized_pnl, "feesPaid": fees_paid,
	}


func from_dict(d: Dictionary) -> void:
	cash = float(d.cash)
	debt = float(d.debt)
	realized_pnl = float(d.get("realizedPnl", 0.0))
	fees_paid = float(d.get("feesPaid", 0.0))
	holdings = {}
	var h: Dictionary = d.get("holdings", {})
	for id in h:
		holdings[id] = {"qty": int(h[id].qty), "avgCost": float(h[id].avgCost)}


static func fmt_money(v: float) -> String:
	var neg := v < 0.0
	var s := "%.0f" % absf(v)
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var rest := n - 1 - i
		if rest > 0 and rest % 3 == 0:
			out += ","
	return ("-" if neg else "") + out
