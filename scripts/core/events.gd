extends RefCounted
## 新闻、传闻、前兆与事件日程（GDD 第 6 节）。纯逻辑，不依赖任何场景节点。
##
## - 事件定义在 data/events.json：公司财报（每季度）、铸币局利率决议（约每 3 个月）、
##   行业 / 世界事件池、传闻（真假参半）、无影响的花边新闻。
## - 日程按 30 天一块生成。每块的随机数只来自 (种子, 块序号)，所以同一种子一定生成同一份日程，
##   与什么时候生成、读档几次都无关。生成时就抽好实际日期、时刻、结果（利好 / 利空、传闻真假）。
## - 事件发生前 1–5 个交易日出现前兆：模糊的（只说明“快有消息了”）或带方向的（暗示利好 / 利空）。
##   前兆不暴露日期。带方向的前兆当天还有一点点同向漂移和成交放大，即“盘面异动”。
## - 发生时刻：盘前（晨报，开盘跳空，“已被市场部分消化”）或盘中某个 tick 的突发快讯（几个 tick 内急涨急跌）。
##   周一的盘前消息就是“周末消息”。
## - fired / shown 标记保证同一条消息只生效一次；预测推演时复制一份日程（clone）照样跑。
##
## 一天的调用顺序（GameState 和 tools/simulate.gd 相同）：
##   before_open(market, day) → market.open_day(day) → 每个 tick: on_tick(market, day, tick) → market.step_tick()

const Calendar := preload("res://scripts/core/calendar.gd")

const DATA_PATH := "res://data/events.json"
const BLOCK_DAYS := 30
const BURST_TICKS := 4
## 带方向的前兆当天的漂移幅度与成交放大倍数；模糊前兆只放大成交。
const HINT_DRIFT := 0.006
const HINT_VOLUME := 1.6
const VAGUE_VOLUME := 1.3

var seed_value := 0
var ids: Array = []
var names := {}
var shorts := {}
var schedule: Array = []
var generated_blocks := 0
var _defs := {}


static func load_defs() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取 %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s 格式错误" % DATA_PATH)
		return {}
	return parsed


func setup(companies: Array, p_seed: int, defs: Dictionary = {}) -> void:
	seed_value = p_seed
	_set_companies(companies)
	_defs = defs if not defs.is_empty() else load_defs()
	schedule = []
	generated_blocks = 0


func _set_companies(companies: Array) -> void:
	ids = []
	names = {}
	shorts = {}
	for c in companies:
		ids.append(String(c.id))
		names[String(c.id)] = String(c.name)
		shorts[String(c.id)] = String(c.get("short", c.name))


## 保证 until_day 之前的日程都已生成。
func ensure(until_day: int) -> void:
	while generated_blocks * BLOCK_DAYS < until_day:
		_generate_block(generated_blocks)
		generated_blocks += 1


func clone() -> RefCounted:
	var e: RefCounted = get_script().new()
	e.seed_value = seed_value
	e.ids = ids
	e.names = names
	e.shorts = shorts
	e._defs = _defs
	e.schedule = schedule.duplicate(true)
	e.generated_blocks = generated_blocks
	return e


# ---------------------------------------------------------------- 每天的消息

## 开盘前：今天的盘前消息（开盘跳空）与前兆。返回晨报条目。
func before_open(market: RefCounted, day: int) -> Array:
	var items: Array = []
	for inst in schedule:
		if int(inst.day) == day and String(inst.stage) == "pre_open" and not bool(inst.fired):
			_fire(market, inst, "gap")
			items.append(_item(inst, day))
		for pre in inst.precursors:
			if int(pre.day) == day and not bool(pre.shown):
				pre.shown = true
				_apply_precursor(market, inst, pre)
				items.append({
					"section": "市场", "kind": "precursor", "title": String(pre.text), "body": "",
					"signs": (pre.signs as Dictionary).duplicate(), "uid": String(inst.uid),
				})
	return items


## 盘中：在第 tick 个 tick 推进之前调用，返回突发快讯。
func on_tick(market: RefCounted, day: int, tick: int) -> Array:
	var items: Array = []
	for inst in schedule:
		if int(inst.day) == day and String(inst.stage) == "intraday" and int(inst.tick) == tick and not bool(inst.fired):
			_fire(market, inst, "burst")
			items.append(_item(inst, day))
	return items


func _fire(market: RefCounted, inst: Dictionary, mode: String) -> void:
	inst.fired = true
	for e in inst.effects:
		for id in _expand(String(e.id)):
			if not market.stocks.has(id):
				continue
			var dv := float(e.get("value", 0.0))
			if dv != 0.0:
				market.stocks[id].value = float(market.stocks[id].value) * (1.0 + dv)
			market.add_shock(id, e.portions, mode, BURST_TICKS)


func _apply_precursor(market: RefCounted, inst: Dictionary, pre: Dictionary) -> void:
	var signs: Dictionary = pre.signs
	if signs.is_empty():
		for id in _expand(String(inst.main)):
			market.boost_volume(id, VAGUE_VOLUME)
		return
	for key in signs:
		for id in _expand(String(key)):
			market.add_shock(id, [HINT_DRIFT * float(signs[key])], "spread")
			market.boost_volume(id, HINT_VOLUME)


func _item(inst: Dictionary, day: int) -> Dictionary:
	var title := String(inst.title)
	if String(inst.stage) == "pre_open" and not Calendar.is_trading_day(day - 1):
		title = "【休市期间】" + title
	return {
		"section": String(inst.section), "kind": String(inst.kind), "title": title,
		"body": String(inst.body), "signs": (inst.signs as Dictionary).duplicate(),
		"uid": String(inst.uid), "stage": String(inst.stage),
	}


## 无影响的花边新闻，用来把晨报凑到 3–5 条。同一天总是同样几条。
func filler(day: int, n: int) -> Array:
	var pool: Array = _defs.get("filler", [])
	var out: Array = []
	if pool.is_empty() or n <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "filler", day])
	var picked := {}
	while out.size() < mini(n, pool.size()):
		var i := rng.randi_range(0, pool.size() - 1)
		if picked.has(i):
			continue
		picked[i] = true
		var f: Dictionary = pool[i]
		out.append({"section": "杂谈", "kind": "filler", "title": String(f.title),
				"body": String(f.get("body", "")), "signs": {}, "uid": ""})
	return out


# ---------------------------------------------------------------- 查询

func instance(uid: String) -> Dictionary:
	for inst in schedule:
		if String(inst.uid) == uid:
			return inst
	return {}


## 还没发生、但已经露出线索（前兆已出现，或传闻已经传开）的事件，且会在 within 个交易日内发生。
## 诺艾尔的分析报告用它。
func upcoming_clues(day: int, within: int) -> Array:
	var limit := day
	for _i in within:
		limit = Calendar.next_trading_day(limit)
	var out: Array = []
	for inst in schedule:
		if bool(inst.fired) or int(inst.day) <= day or int(inst.day) > limit:
			continue
		var clue := false
		for pre in inst.precursors:
			if bool(pre.shown):
				clue = true
		var link := String(inst.get("link", ""))
		if link != "" and bool(instance(link).get("fired", false)):
			clue = true
		if clue:
			out.append(inst)
	return out


## 已经发生、影响到某支股票的消息（K 线上的标记）。
func markers(id: String) -> Array:
	var out: Array = []
	for inst in schedule:
		if not bool(inst.fired):
			continue
		var signs: Dictionary = inst.signs
		if signs.has(id) or (signs.has("all")):
			out.append({"day": int(inst.day), "sign": int(signs.get(id, signs.get("all", 0))),
					"title": String(inst.title)})
	return out


## 读取旧存档（没有日程）时：day 之前的消息都当作已经发生过；
## include_today=true 时今天的盘前消息也算已发生（已在开盘跳空中体现）。
func mark_past(day: int, include_today: bool) -> void:
	for inst in schedule:
		var d := int(inst.day)
		if d < day or (include_today and d == day and String(inst.stage) == "pre_open"):
			inst.fired = true
		for pre in inst.precursors:
			if int(pre.day) < day or (include_today and int(pre.day) == day):
				pre.shown = true


# ---------------------------------------------------------------- 日程生成

func _generate_block(b: int) -> void:
	var start := b * BLOCK_DAYS + 1
	var end := (b + 1) * BLOCK_DAYS
	var days: Array = []
	for d in range(start, end + 1):
		if Calendar.is_trading_day(d):
			days.append(d)
	if days.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "events", b])
	var taken := {}  # 股票 id → 已安排的事件日，避免同一支股票的事件挤在一起
	var n := 0
	# 第一块：保证开局几天就有一次“前兆 → 利好”，让新手尽快体会读消息的乐趣
	if b == 0:
		var early := _pick_early(rng)
		if not early.is_empty():
			var idx := rng.randi_range(2, 3)
			var inst := _instance(rng, "b%d-e%d" % [b, n], early, _pick_variant(rng, early.variants, true), days[idx], "pool")
			inst.precursors = [
				_precursor(rng, inst, early, days[0], false),
				_precursor(rng, inst, early, days[idx - 1], true),
			]
			_add(inst, taken)
			n += 1
	# 公司季度财报：季末后第 5–15 个交易日
	var earn: Dictionary = _defs.get("earnings", {})
	if not earn.is_empty():
		for q in range(start - BLOCK_DAYS, end + 1):
			if Calendar.day_of_month(q) != Calendar.DAYS_PER_MONTH or Calendar.month(q) % 3 != 0:
				continue
			for id in ids:
				var er := RandomNumberGenerator.new()
				er.seed = hash([seed_value, "earnings", q, id])
				var w: Array = earn.get("window", [5, 15])
				var d := _shift(q, er.randi_range(int(w[0]), int(w[1])))
				if d < start or d > end:
					continue
				var inst := _instance(er, "q%d-%s" % [q, id], earn, _pick_variant(er, earn.variants), d, "earnings", id)
				inst.precursors = _precursors(er, inst, earn)
				_add(inst, taken)
	# 铸币局利率决议：约每 90 天一次，预定日期前后 ±jitter 个交易日
	var rate: Dictionary = _defs.get("rate", {})
	if not rate.is_empty():
		var every := int(rate.get("every", 90))
		var first := int(rate.get("first", 15))
		for base in range(first, end + 1, every):
			if base < start:
				continue
			var rr := RandomNumberGenerator.new()
			rr.seed = hash([seed_value, "rate", base])
			var j := int(rate.get("jitter", 5))
			var d := _shift(_shift(base - 1, 1), rr.randi_range(-j, j))
			if b == 0:
				d = maxi(d, days[1])
			var inst := _instance(rr, "rate-%d" % base, rate, _pick_variant(rr, rate.variants), d, "macro")
			inst.precursors = _precursors(rr, inst, rate)
			_add(inst, taken)
	# 行业 / 世界事件池
	var per: Dictionary = _defs.get("per_block", {})
	var pool_range: Array = per.get("pool", [5, 7])
	var want := rng.randi_range(int(pool_range[0]), int(pool_range[1]))
	var used := {}
	var month := Calendar.month(days[int(days.size() * 0.5)])
	var tries := 0
	while want > 0 and tries < 60:
		tries += 1
		var def := _pick_pool(rng, used, month)
		if def.is_empty():
			break
		var variant := _pick_variant(rng, def.variants)
		var d: int = days[rng.randi_range(2 if b == 0 else 0, days.size() - 1)]
		var inst := _instance(rng, "b%d-e%d" % [b, n], def, variant, d, String(def.get("kind", "world")))
		if _crowded(taken, inst, d):
			continue
		inst.precursors = _precursors(rng, inst, def)
		_add(inst, taken)
		used[String(def.id)] = true
		n += 1
		want -= 1
	# 传闻：先在街头传开（小幅异动），几天后证实或辟谣
	var rumor_range: Array = per.get("rumors", [1, 2])
	var rumors: Array = _defs.get("rumors", [])
	var rumor_want := rng.randi_range(int(rumor_range[0]), int(rumor_range[1]))
	tries = 0
	while rumor_want > 0 and not rumors.is_empty() and tries < 30:
		tries += 1
		var def: Dictionary = _weighted(rng, rumors)
		if used.has(String(def.id)):
			continue
		var delay: Array = def.get("delay", [2, 4])
		var r_idx := rng.randi_range(1 if b == 0 else 0, maxi(1, days.size() - 3))
		var rd: int = days[mini(r_idx, days.size() - 1)]
		var ed := _shift(rd, rng.randi_range(int(delay[0]), int(delay[1])))
		var truth := rng.randf() < float(def.get("truth", 0.5))
		var rumor := _instance(rng, "b%d-r%d" % [b, n], def, def.rumor, rd, "rumor")
		rumor.section = "传闻"
		if _crowded(taken, rumor, rd):
			continue
		var result_v: Dictionary = def["true" if truth else "false"]
		var result := _instance(rng, "b%d-r%d-x" % [b, n], def, result_v, ed, "rumor_result")
		result.variant = "true" if truth else "false"
		result.link = String(rumor.uid)
		_add(rumor, taken)
		_add(result, taken)
		used[String(def.id)] = true
		n += 1
		rumor_want -= 1
	schedule.sort_custom(func(a, c): return int(a.day) < int(c.day) or (int(a.day) == int(c.day) and String(a.uid) < String(c.uid)))


func _instance(rng: RandomNumberGenerator, uid: String, def: Dictionary, variant: Dictionary,
		day: int, kind: String, self_id: String = "") -> Dictionary:
	var effects: Array = []
	var signs := {}
	var main := ""
	var main_mag := -1.0
	for e in variant.get("effects", []):
		var id := String(e.target)
		if id == "self":
			id = self_id
		var portions: Array = []
		var total := 0.0
		for v in e.portions:
			portions.append(float(v))
			total += float(v)
		effects.append({"id": id, "portions": portions, "value": float(e.get("value", 0.0))})
		if absf(total) >= 0.03:
			signs[id] = 1 if total > 0.0 else -1
		if absf(total) > main_mag and id != "all":
			main_mag = absf(total)
			main = id
	if main == "":
		main = self_id if self_id != "" else "all"  # 只影响大盘的宏观事件
	var stage_w: Dictionary = def.get("stage", {"pre_open": 1.0, "intraday": 1.0})
	var pre_w := float(stage_w.get("pre_open", 1.0))
	var intra_w := float(stage_w.get("intraday", 1.0))
	var stage := "pre_open" if rng.randf() * (pre_w + intra_w) < pre_w else "intraday"
	return {
		"uid": uid, "def": String(def.get("id", kind)), "kind": kind,
		"variant": String(variant.get("key", "")), "day": day, "stage": stage,
		"tick": rng.randi_range(2, 30) if stage == "intraday" else 0,
		"title": _fill(String(variant.get("headline", "")), self_id),
		"body": _fill(String(variant.get("body", "")), self_id),
		"section": "要闻", "effects": effects, "signs": signs, "main": main,
		"precursors": [], "fired": false, "link": "",
		"_hints": _fill_all(variant.get("hints", []), self_id),
		"_vague": _fill_all(def.get("vague", []), self_id),
	}


## 前兆：precursors=2 时先在 3–5 天前出现一条（一半是模糊的），再在 1–2 天前出现一条带方向的；
## precursors=1 时在 1–4 天前出现一条（七成带方向）。
func _precursors(rng: RandomNumberGenerator, inst: Dictionary, def: Dictionary) -> Array:
	var count := int(def.get("precursors", 1))
	var d := int(inst.day)
	var out: Array = []
	if count >= 2:
		out.append(_precursor(rng, inst, def, _shift(d, -rng.randi_range(3, 5)), rng.randf() < 0.5))
		out.append(_precursor(rng, inst, def, _shift(d, -rng.randi_range(1, 2)), true))
	elif count == 1:
		out.append(_precursor(rng, inst, def, _shift(d, -rng.randi_range(1, 4)), rng.randf() < 0.7))
	# 开局之前的前兆挪到第一个交易日
	for pre in out:
		if int(pre.day) < 1:
			pre.day = Calendar.next_trading_day(0)
	return out


func _precursor(rng: RandomNumberGenerator, inst: Dictionary, _def: Dictionary, day: int, directional: bool) -> Dictionary:
	var hints: Array = inst._hints
	var vague: Array = inst._vague
	if hints.is_empty():
		directional = false
	if not directional and vague.is_empty():
		directional = not hints.is_empty()
	var text := ""
	var signs := {}
	if directional:
		text = String(hints[rng.randi_range(0, hints.size() - 1)])
		signs = (inst.signs as Dictionary).duplicate()
	elif not vague.is_empty():
		text = String(vague[rng.randi_range(0, vague.size() - 1)])
	return {"day": day, "text": text, "signs": signs, "shown": false}


func _add(inst: Dictionary, taken: Dictionary) -> void:
	inst.erase("_hints")
	inst.erase("_vague")
	# 去掉空的前兆（定义里没有写前兆文字）
	var pres: Array = []
	for pre in inst.precursors:
		if String(pre.text) != "":
			pres.append(pre)
	inst.precursors = pres
	schedule.append(inst)
	var main := String(inst.main)
	if not taken.has(main):
		taken[main] = []
	(taken[main] as Array).append(int(inst.day))


func _crowded(taken: Dictionary, inst: Dictionary, day: int) -> bool:
	for d in taken.get(String(inst.main), []):
		if absi(int(d) - day) <= 3:
			return true
	return false


func _pick_early(rng: RandomNumberGenerator) -> Dictionary:
	var cands: Array = []
	for def in _defs.get("pool", []):
		if bool(def.get("early", false)):
			cands.append(def)
	return _weighted(rng, cands) if not cands.is_empty() else {}


func _pick_pool(rng: RandomNumberGenerator, used: Dictionary, month: int) -> Dictionary:
	var cands: Array = []
	for def in _defs.get("pool", []):
		if used.has(String(def.id)):
			continue
		var months: Array = def.get("months", [])
		if not months.is_empty() and not months.has(float(month)) and not months.has(month):
			continue
		cands.append(def)
	return _weighted(rng, cands) if not cands.is_empty() else {}


func _pick_variant(rng: RandomNumberGenerator, variants: Array, positive_only: bool = false) -> Dictionary:
	if not positive_only:
		return _weighted(rng, variants)
	var pos: Array = []
	for v in variants:
		var total := 0.0
		for e in v.get("effects", []):
			for p in e.portions:
				total += float(p)
		if total > 0.03:
			pos.append(v)
	return _weighted(rng, pos if not pos.is_empty() else variants)


static func _weighted(rng: RandomNumberGenerator, list: Array) -> Dictionary:
	var sum := 0.0
	for x in list:
		sum += float(x.get("weight", 1.0))
	var r := rng.randf() * sum
	for x in list:
		r -= float(x.get("weight", 1.0))
		if r <= 0.0:
			return x
	return list[-1] if not list.is_empty() else {}


## 从 day 起前后移动 k 个交易日（k=0 时返回 day 本身或之后最近的交易日）。
static func _shift(day: int, k: int) -> int:
	var d := day
	if k == 0:
		while not Calendar.is_trading_day(d):
			d += 1
		return d
	var step := 1 if k > 0 else -1
	var left := absi(k)
	while left > 0:
		d += step
		if Calendar.is_trading_day(d):
			left -= 1
	return d


func _expand(id: String) -> Array:
	return ids if id == "all" else [id]


func _fill(text: String, self_id: String) -> String:
	if self_id == "":
		return text
	return text.replace("{name}", String(names.get(self_id, self_id))).replace("{short}", String(shorts.get(self_id, self_id)))


func _fill_all(list: Array, self_id: String) -> Array:
	var out: Array = []
	for t in list:
		out.append(_fill(String(t), self_id))
	return out


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	return {"generatedBlocks": generated_blocks, "schedule": schedule.duplicate(true)}


func from_dict(d: Dictionary, companies: Array, p_seed: int) -> void:
	seed_value = p_seed
	_set_companies(companies)
	if _defs.is_empty():
		_defs = load_defs()
	generated_blocks = int(d.get("generatedBlocks", 0))
	schedule = (d.get("schedule", []) as Array).duplicate(true)
	# JSON 读回的整数是 float
	for inst in schedule:
		inst.day = int(inst.day)
		inst.tick = int(inst.tick)
		for pre in inst.precursors:
			pre.day = int(pre.day)
			var signs := {}
			for id in pre.signs:
				signs[id] = int(pre.signs[id])
			pre.signs = signs
		var s := {}
		for id in inst.signs:
			s[id] = int(inst.signs[id])
		inst.signs = s
