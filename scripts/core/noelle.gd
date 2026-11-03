extends RefCounted
## 诺艾尔的每日点评与分析报告（GDD 第 6 节“情报来源”）。纯逻辑，台词在 data/dialogues/noelle.json。
##
## 分析报告的质量随好感度提升：
## - 好感 < 25：只提醒最近哪支股票风声多；
## - 好感 ≥ 25：给出利好 / 利空的判断，正确率 55% 起，好感越高越准（最高 92%）；
## - 好感 ≥ 50：还会提示大概什么时候有动静。

const DATA_PATH := "res://data/dialogues/noelle.json"
const HINT_AFFECTION := 25
const TIMING_AFFECTION := 50
const Calendar := preload("res://scripts/core/calendar.gd")


static func load_lines() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取 %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func accuracy(affection: int) -> float:
	return clampf(0.55 + affection / 150.0, 0.55, 0.92)


static func _pick(rng: RandomNumberGenerator, v: Variant) -> String:
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		return String(a[rng.randi_range(0, a.size() - 1)]) if not a.is_empty() else ""
	return String(v) if v != null else ""


## 当日盈亏点评。day_ret 为当日盈亏占开盘时（现金 + 持仓）的比例。
static func comment(lines: Dictionary, day_ret: float, traded: bool, rng: RandomNumberGenerator) -> String:
	var c: Dictionary = lines.get("comment", {})
	if not traded and absf(day_ret) < 0.0005:
		return _pick(rng, c.get("idle"))
	if day_ret >= 0.06:
		return _pick(rng, c.get("big_win"))
	if day_ret > 0.0:
		return _pick(rng, c.get("win"))
	if day_ret <= -0.05:
		return _pick(rng, c.get("big_loss"))
	return _pick(rng, c.get("small_loss"))


## 对主角状态的提醒——这是玩家判断“信不信她的预测”的重要线索。
static func state_note(lines: Dictionary, player: Dictionary, rng: RandomNumberGenerator) -> String:
	var s: Dictionary = lines.get("state", {})
	var body := String(player.body)
	if body != "healthy" and s.has(body):
		return _pick(rng, s[body])
	return _pick(rng, s.get(String(player.mood), ""))


## 分析报告：clues 来自 events.upcoming_clues()。返回若干句提示。
static func tips(lines: Dictionary, clues: Array, day: int, affection: int, shorts: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var t: Dictionary = lines.get("tips", {})
	var out: Array = []
	var seen := {}
	var acc := accuracy(affection)
	var tomorrow := Calendar.next_trading_day(day)
	var day_after := Calendar.next_trading_day(tomorrow)
	for inst in clues:
		var main := String(inst.main)
		if seen.has(main):
			continue
		seen[main] = true
		var short := "大盘" if main == "all" else String(shorts.get(main, main))
		var line := ""
		if affection < HINT_AFFECTION:
			line = _pick(rng, t.get("vague"))
		elif String(inst.kind) == "rumor_result":
			var truth := String(inst.variant) == "true"
			var guess := truth if rng.randf() < acc else not truth
			line = _pick(rng, t.get("rumor_true" if guess else "rumor_false"))
		else:
			var sign := int((inst.signs as Dictionary).get(main, 0))
			if sign == 0:
				line = _pick(rng, t.get("unclear"))
			else:
				var guess := sign if rng.randf() < acc else -sign
				line = _pick(rng, t.get("up" if guess > 0 else "down"))
		if affection >= TIMING_AFFECTION:
			var d := int(inst.day)
			if d == tomorrow:
				line += _pick(rng, t.get("tomorrow"))
			elif d == day_after:
				line += _pick(rng, t.get("soon"))
		out.append(line.replace("{short}", short))
	if out.is_empty():
		out.append(_pick(rng, t.get("none")))
	return out


static func deadline_line(lines: Dictionary, days_left: int, gap: float, gap_text: String) -> String:
	if gap <= 0.0:
		return String(lines.get("deadline_ok", ""))
	if days_left <= 0:
		return String(lines.get("deadline_today", "")).replace("{gap}", gap_text)
	return String(lines.get("deadline", "")).replace("{days}", str(days_left)).replace("{gap}", gap_text)
