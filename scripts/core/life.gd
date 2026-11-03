extends RefCounted
## 体力、压力、情绪与身体状态（GDD 第 7 节）。纯逻辑，所有函数都直接修改传入的 player 字典。
##
## - 盯盘一天消耗体力，每次走势预测再消耗一点；睡觉恢复，休市日恢复得更多。
## - 情绪在收盘时按近 3 个交易日的盈亏和压力判定，睡一觉后单日的大起大落会淡去（狂热 / 恐慌通常只持续 1–3 天）。
## - 身体：健康 / 疲劳（体力 < 50）/ 感冒（随机，疲劳时更容易）/ 发烧（感冒还硬撑）/ 住院（体力归零，3 个交易日不能交易）。
## - 晚间安排（M1 先只有两项，完整的城市地图在 M2）：早点休息，或和诺艾尔复盘。

const TRADING_DAY_HP := 12
const FEVER_EXTRA_HP := 6
const PREDICT_HP := 5
const SLEEP_HP := 16
const OFF_DAY_HP := 20
const REST_BONUS_HP := 10
const REVIEW_HP := 3
const HOSPITAL_DAYS := 3
const RELEASE_HP := 60

## 情绪的基础正确率与身体状态的修正（GDD 第 6 节“主角的走势预测”）。
const MOOD_ACCURACY := {"calm": 0.70, "optimistic": 0.60, "pessimistic": 0.60, "manic": 0.35, "panic": 0.35}
const BODY_ACCURACY := {"healthy": 0.0, "tired": -0.10, "cold": -0.15}

const MOOD_NOTES := {
	"calm": "头脑清醒，判断最可靠。",
	"optimistic": "心情不错，看什么都觉得会涨。",
	"pessimistic": "有点丧气，看什么都觉得会跌。",
	"manic": "眼睛里闪着金币的光……她现在的话要打个折扣。",
	"panic": "手心冒冷汗，判断容易走极端。",
}
const BODY_NOTES := {
	"healthy": "",
	"tired": "有点累，涨跌的力度经常看走眼。",
	"cold": "感冒了，今天只能预测 1 次。",
	"fever": "烧得迷迷糊糊，说什么都像在掷骰子。",
	"hospital": "正在住院，不能交易，也没法预测。",
}


static func new_player(p_name: String) -> Dictionary:
	var p := {
		"name": p_name, "hp": 100, "stress": 20, "fame": 0, "heat": 0,
		"mood": "calm", "body": "healthy", "predictionsLeft": 3,
	}
	normalize(p)
	return p


## 补齐 M1 新增的字段（读旧存档时也会调用），并把 JSON 读回的数字转回整数。
static func normalize(p: Dictionary) -> void:
	var defaults := {"hp": 100, "stress": 20, "fame": 0, "heat": 0, "predictionsLeft": 3, "exp": 0, "hospitalDays": 0}
	for k in defaults:
		p[k] = int(p.get(k, defaults[k]))
	p.mood = String(p.get("mood", "calm"))
	p.body = String(p.get("body", "healthy"))
	p.illness = String(p.get("illness", ""))
	p.name = String(p.get("name", "希雅"))
	var rets: Array = []
	for r in p.get("dayReturns", []):
		rets.append(float(r))
	p.dayReturns = rets


# ---------------------------------------------------------------- 查询

static func can_trade(p: Dictionary) -> bool:
	return String(p.body) != "hospital"


static func predictions_per_day(p: Dictionary) -> int:
	match String(p.body):
		"hospital":
			return 0
		"cold":
			return 1
	return 3


## 不能预测时返回原因，可以预测时返回空字符串。
static func predict_block_reason(p: Dictionary) -> String:
	if String(p.body) == "hospital":
		return "hospital"
	if int(p.predictionsLeft) <= 0:
		return "no_left"
	if int(p.hp) < PREDICT_HP:
		return "too_tired"
	return ""


## 预测正确率 p（界面上不显示这个数字）。
static func accuracy(p: Dictionary) -> float:
	if String(p.body) == "fever":
		return 0.5
	var base := float(MOOD_ACCURACY.get(String(p.mood), 0.7))
	var delta := float(BODY_ACCURACY.get(String(p.body), 0.0))
	var exp_bonus := clampf(float(p.get("exp", 0)) / 100.0, 0.0, 0.10)
	return clampf(base + delta + exp_bonus, 0.05, 0.95)


static func note(p: Dictionary) -> String:
	var n := String(MOOD_NOTES.get(String(p.mood), ""))
	var b := String(BODY_NOTES.get(String(p.body), ""))
	return (n + b) if b != "" else n


# ---------------------------------------------------------------- 变化

static func spend_prediction(p: Dictionary) -> void:
	p.predictionsLeft = maxi(0, int(p.predictionsLeft) - 1)
	p.hp = maxi(0, int(p.hp) - PREDICT_HP)


## 收盘：盯盘的体力消耗、压力变化、情绪判定。day_ret 是当日盈亏占开盘时（现金 + 持仓）的比例。
## days_left 是距还款期限的交易日数（已还清时传 -1）。返回 {mood_before, mood_after, hospital}。
static func end_trading_day(p: Dictionary, day_ret: float, days_left: int) -> Dictionary:
	var before := String(p.mood)
	var drain := TRADING_DAY_HP + (FEVER_EXTRA_HP if String(p.body) == "fever" else 0)
	if String(p.body) == "hospital":
		p.hospitalDays = maxi(0, int(p.hospitalDays) - 1)  # 在医院里度过了一个交易日
	else:
		p.hp = maxi(0, int(p.hp) - drain)
	var stress := float(p.stress)
	if day_ret < 0.0:
		stress += minf(15.0, -day_ret * 150.0)
	elif day_ret > 0.0:
		stress -= minf(8.0, day_ret * 80.0)
	if days_left >= 0 and days_left <= 5:
		stress += 3.0
	if stress > 20.0:
		stress -= 1.0
	p.stress = clampi(roundi(stress), 0, 100)
	var rets: Array = p.dayReturns
	rets.append(day_ret)
	while rets.size() > 5:
		rets.pop_front()
	var hospital := false
	if int(p.hp) <= 0 and String(p.body) != "hospital":
		_hospitalize(p)
		hospital = true
	p.mood = evaluate_mood(p, day_ret)
	return {"mood_before": before, "mood_after": String(p.mood), "hospital": hospital}


## 睡觉（进入下一个交易日前）。off_days 是中间隔着的休市天数，choice 是 "rest" 或 "review"。
## rng 用当天派生的种子，结果可复现。返回发生的变化（用于消息）：["cold", "fever", "recovered", "released"]
static func sleep(p: Dictionary, rng: RandomNumberGenerator, off_days: int, choice: String) -> Array:
	var events: Array = []
	var illness := String(p.illness)
	var gain := float(SLEEP_HP + OFF_DAY_HP * off_days)
	if choice == "rest":
		gain += REST_BONUS_HP
	elif choice == "review":
		gain -= REVIEW_HP
	if illness == "cold":
		gain *= 0.5
	elif illness == "fever":
		gain = 4.0 + OFF_DAY_HP * 0.5 * off_days
	p.hp = clampi(int(p.hp) + roundi(gain), 0, 100)
	var stress := int(p.stress) - (8 if choice == "rest" else 2) - 5 * off_days
	p.stress = clampi(stress, 0, 100)
	# 住院：住满 3 个交易日后出院，出院时体力至少恢复到 60
	if String(p.body) == "hospital":
		if int(p.hospitalDays) <= 0:
			p.hp = maxi(int(p.hp), RELEASE_HP)
			p.illness = ""
			events.append("released")
		else:
			p.mood = evaluate_mood(p, 0.0)
			return events
	elif illness == "fever":
		# 发烧只能休息，一晚之后退回感冒
		p.illness = "cold"
		events.append("fever_down")
	elif illness == "cold":
		if int(p.hp) < 30 and choice != "rest" and off_days == 0 and rng.randf() < 0.5:
			p.illness = "fever"
			events.append("fever")
		elif int(p.hp) >= 50 and rng.randf() < 0.35 + (0.3 if choice == "rest" else 0.0) + 0.2 * off_days:
			p.illness = ""
			events.append("recovered")
	else:
		var chance := 0.03
		if int(p.hp) < 50:
			chance += 0.07
		if int(p.stress) >= 70:
			chance += 0.04
		if rng.randf() < chance:
			p.illness = "cold"
			events.append("cold")
	p.body = evaluate_body(p)
	# 睡一觉，单日的大起大落淡去
	p.mood = evaluate_mood(p, 0.0)
	return events


static func _hospitalize(p: Dictionary) -> void:
	p.body = "hospital"
	p.hospitalDays = HOSPITAL_DAYS
	p.illness = ""


static func evaluate_body(p: Dictionary) -> String:
	if String(p.body) == "hospital" and int(p.hospitalDays) > 0:
		return "hospital"
	if String(p.body) == "hospital":
		p.body = "healthy"
	match String(p.illness):
		"fever":
			return "fever"
		"cold":
			return "cold"
	return "tired" if int(p.hp) < 50 else "healthy"


## 情绪：单日大亏或压力 ≥ 80 → 恐慌；连续大赚或 3 日累计大赚 → 狂热；3 日累计盈 / 亏 → 乐观 / 悲观。
static func evaluate_mood(p: Dictionary, today_ret: float) -> String:
	var rets: Array = p.dayReturns
	var s3 := 0.0
	for i in range(maxi(0, rets.size() - 3), rets.size()):
		s3 += float(rets[i])
	var prev := float(rets[-2]) if rets.size() >= 2 else 0.0
	if today_ret <= -0.07 or int(p.stress) >= 80:
		return "panic"
	if (today_ret >= 0.07 and prev >= 0.03) or s3 >= 0.15:
		return "manic"
	if s3 >= 0.01:
		return "optimistic"
	if s3 <= -0.01:
		return "pessimistic"
	return "calm"
