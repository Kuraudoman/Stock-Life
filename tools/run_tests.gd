extends SceneTree
## 自动测试：价格模型可复现、涨跌停、交易规则、存档往返；M1：新闻、状态、预测、诺艾尔、第一章、存档迁移；M2：晚间行动点、城区背景、主角立绘、版本 2 → 3。
## 用法：godot --headless --path . --script res://tools/run_tests.gd

const Calendar := preload("res://scripts/core/calendar.gd")
const Market := preload("res://scripts/core/market.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")
const Events := preload("res://scripts/core/events.gd")
const Life := preload("res://scripts/core/life.gd")
const Evening := preload("res://scripts/core/evening.gd")
const Predict := preload("res://scripts/core/predict.gd")
const Painter := preload("res://scripts/ui/portrait_painter.gd")
const Noelle := preload("res://scripts/core/noelle.gd")

var failures := 0
var passes := 0


func _initialize() -> void:
	var companies: Array = _load_companies()
	_test_calendar()
	_test_determinism(companies)
	_test_limits(companies)
	_test_trading(companies)
	_test_market_serialization(companies)
	_test_shocks(companies)
	_test_events(companies)
	_test_life()
	_test_evening_logic()
	_test_city_backgrounds()
	_test_heroine_portraits()
	_test_predict_decide()
	_test_noelle(companies)
	await process_frame
	_test_save_roundtrip()
	_test_forecast_matches_reality()
	_test_chapter()
	_test_save_v2_and_migration()
	_test_evening_flow()
	_test_save_v3()
	print("")
	print("通过 %d 项，失败 %d 项" % [passes, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  ✓ ", label)
	else:
		failures += 1
		printerr("  ✗ ", label)


func _load_companies() -> Array:
	var f := FileAccess.open("res://data/companies.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()).companies


func _gs() -> Node:
	return root.get_node_or_null("GameState")


## 测试用的临时存档目录，不碰 saves/ 里玩家的真实存档。
func _use_test_saves() -> String:
	var sm: Node = root.get_node("SaveManager")
	var real_dir: String = sm.save_dir
	sm.save_dir = ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(sm.save_dir)
	return real_dir


func _run_days(m: Market, from_day: int, days: int, p: Portfolio = null) -> void:
	var d := from_day
	var done := 0
	while done < days:
		if Calendar.is_trading_day(d):
			m.open_day(d)
			for t in Market.TICKS_PER_DAY:
				if p != null and t == 5:
					p.execute(m, "elder", "buy", 100)
				m.step_tick()
			m.close_day()
			done += 1
		d += 1


func _test_calendar() -> void:
	print("日历")
	check(Calendar.weekday(1) == 0, "第 1 天是周一")
	check(not Calendar.is_trading_day(6) and not Calendar.is_trading_day(7), "周六、周日休市")
	check(Calendar.next_trading_day(5) == 8, "周五之后的交易日是下周一")
	check(Calendar.format_tick(0) == "09:00" and Calendar.format_tick(36) == "15:00", "交易时间 9:00–15:00")
	check(Calendar.format_date(1).begins_with("4月1日"), "开局日期 4 月 1 日")


func _test_determinism(companies: Array) -> void:
	print("价格模型")
	var a := Market.new()
	var b := Market.new()
	a.setup(companies, 20261028)
	b.setup(companies, 20261028)
	_run_days(a, 1, 30)
	_run_days(b, 1, 30)
	var same := true
	for id in a.order:
		if a.price(id) != b.price(id):
			same = false
	check(same, "同一种子 → 同一局行情")
	var c := Market.new()
	c.setup(companies, 7)
	_run_days(c, 1, 30)
	var differs := false
	for id in a.order:
		if a.price(id) != c.price(id):
			differs = true
	check(differs, "不同种子 → 不同行情")
	check((a.stocks.elder.candles as Array).size() >= 80, "开局前生成了历史 K 线")
	var positive := true
	for id in a.order:
		if a.price(id) <= 0.0:
			positive = false
	check(positive, "价格始终为正")


func _test_limits(companies: Array) -> void:
	var m := Market.new()
	m.setup(companies, 99)
	m.open_day(1)
	m.apply_shock("guild", 1.0, 1)  # 极端利好，必须被涨停限制住
	for t in Market.TICKS_PER_DAY:
		m.step_tick()
	var chg := m.day_change("guild")
	check(chg <= Market.LIMIT + 0.001 and chg > 0.10, "单日涨幅被限制在 +15%%（实际 %+.2f%%）" % (chg * 100.0))
	m.close_day()
	m.open_day(2)
	m.apply_shock("guild", -1.0, 1)
	for t in Market.TICKS_PER_DAY:
		m.step_tick()
	chg = m.day_change("guild")
	check(chg >= -Market.LIMIT - 0.001 and chg < -0.10, "单日跌幅被限制在 −15%%（实际 %+.2f%%）" % (chg * 100.0))


func _test_trading(companies: Array) -> void:
	print("交易规则")
	var m := Market.new()
	m.setup(companies, 1234)
	var p := Portfolio.new()
	p.cash = 10000.0
	check(p.validate(m, "elder", "buy", 10) != "", "收盘时不能交易")
	m.open_day(1)
	check(p.validate(m, "elder", "buy", 15) != "", "必须是 10 股的整数倍")
	check(p.validate(m, "elder", "sell", 10) != "", "没有持股不能卖")
	var price := m.price("elder")
	var q := m.quote("elder", "buy", 100)
	var r := p.execute(m, "elder", "buy", 100)
	check(bool(r.ok), "买入 100 股成功")
	check(absf(float(q.fee) - float(q.gross) * 0.003) < 0.0001, "手续费 0.3%")
	check(float(q.avg_price) > price, "买入有滑点（均价高于现价）")
	check(p.qty_of("elder") == 100, "持仓 100 股")
	check(absf(p.cash - (10000.0 - float(q.total))) < 0.01, "现金正确扣除")
	var max_q := p.max_buy_qty(m, "elder")
	check(max_q % 10 == 0 and float(m.quote("elder", "buy", max_q).total) <= p.cash
			and float(m.quote("elder", "buy", max_q + 10).total) > p.cash, "最大可买数量正确（%d 股）" % max_q)
	m.step_tick()
	var sq := m.quote("elder", "sell", 100)
	check(absf(float(sq.tax) - float(sq.gross) * 0.001) < 0.0001, "卖出另收 0.1% 交易税")
	var cash_before := p.cash
	var r2 := p.execute(m, "elder", "sell", 100)
	check(bool(r2.ok) and p.qty_of("elder") == 0 and p.cash > cash_before, "卖出全部持仓")
	var big := Market.new()
	big.setup(companies, 1234)
	big.open_day(1)
	var p_small := big.quote("elder", "buy", 100)
	var p_big := big.quote("elder", "buy", 50000)
	check(float(p_big.slippage) > float(p_small.slippage) * 100.0, "大单滑点更大")


func _test_market_serialization(companies: Array) -> void:
	print("存档往返（市场）")
	# 跑 10 天 → 存 → 读 → 再跑 10 天，结果必须和不中断地跑 20 天完全一致
	var a := Market.new()
	a.setup(companies, 555)
	var pa := Portfolio.new()
	pa.cash = 50000.0
	_run_days(a, 1, 10, pa)
	var d1: Variant = JSON.parse_string(JSON.stringify(a.to_dict(), "", false, true))
	var b := Market.new()
	b.from_dict(d1, companies)
	var pb := Portfolio.new()
	pb.from_dict(JSON.parse_string(JSON.stringify(pa.to_dict(), "", false, true)))
	var next := Calendar.next_trading_day(a.last_close_day)
	_run_days(a, next, 10, pa)
	_run_days(b, next, 10, pb)
	var same := true
	for id in a.order:
		if absf(a.price(id) - b.price(id)) > 1e-9:
			same = false
	check(same, "读档后继续的行情与不中断时完全一致")
	check(absf(pa.cash - pb.cash) < 1e-6 and pa.qty_of("elder") == pb.qty_of("elder"), "读档后持仓与现金一致")


func _test_save_roundtrip() -> void:
	print("存档系统")
	var gs: Node = root.get_node_or_null("GameState")
	var sm: Node = root.get_node_or_null("SaveManager")
	if gs == null or sm == null:
		check(false, "Autoload 可用")
		return
	# 存到临时目录，不碰 saves/ 里玩家的真实存档（尤其是会被覆盖的 autosave）
	var real_dir: String = sm.save_dir
	sm.save_dir = ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(sm.save_dir)
	gs.new_game(4242)
	gs.open_market()
	for i in 10:
		gs.advance_tick()
	gs.trade("guild", "buy", 200)
	check(sm.save_game("test_roundtrip"), "写入存档")
	var path: String = sm.path_for("test_roundtrip")
	check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "存档是独立文件，临时文件已清理")
	var before: Dictionary = gs.to_save_data()
	gs.new_game(1)
	check(sm.load_game(path), "读取存档")
	var after: Dictionary = gs.to_save_data()
	check(int(after.day) == int(before.day) and int(after.tick) == int(before.tick), "日期与时间一致")
	check(absf(float(after.cash) - float(before.cash)) < 0.001, "现金一致")
	check(int(after.holdings.guild.qty) == 200, "持仓一致")
	gs.finish_day()
	check(FileAccess.file_exists(sm.path_for("autosave")), "收盘后自动存档")
	# 校验：损坏的文件、别的 JSON 文件
	var bad: String = sm.save_dir.path_join("test_bad.stocklife.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{ 这不是 JSON")
	f.close()
	check(not sm.load_game(bad) and sm.last_error != "", "损坏的存档给出提示：%s" % sm.last_error)
	f = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"format\": \"other-game\"}")
	f.close()
	check(not sm.load_game(bad), "不是本游戏的存档：%s" % sm.last_error)
	for name in ["test_roundtrip", "test_bad", "autosave"]:
		DirAccess.remove_absolute(sm.path_for(name))
	DirAccess.remove_absolute(sm.save_dir)
	sm.save_dir = real_dir


# ---------------------------------------------------------------- M1

func _test_shocks(companies: Array) -> void:
	print("事件冲击")
	var a := Market.new()
	var b := Market.new()
	a.setup(companies, 31)
	b.setup(companies, 31)
	a.add_shock("elder", [0.10], "gap")
	a.open_day(1)
	b.open_day(1)
	var r := a.price("elder") / b.price("elder")
	check(absf(r - 1.10) < 0.012, "盘前消息在开盘时跳空（%.3f 倍）" % r)
	for t in 10:
		a.step_tick()
		b.step_tick()
	var base := a.price("guild") / b.price("guild")
	a.add_shock("guild", [0.08], "burst", 4)
	for t in 4:
		a.step_tick()
		b.step_tick()
	r = a.price("guild") / b.price("guild") / base
	check(r > 1.06 and r < 1.10, "盘中快讯在 4 个 tick 内急涨（%.3f 倍）" % r)
	# 两天的冲击：第一天跳空，第二天平摊
	var c := Market.new()
	var d := Market.new()
	c.setup(companies, 77)
	d.setup(companies, 77)
	c.add_shock("morningstar", [0.05, 0.05], "gap")
	for m in [c, d]:
		m.open_day(1)
		for t in Market.TICKS_PER_DAY:
			m.step_tick()
		m.close_day()
	var r1 := c.price("morningstar") / d.price("morningstar")
	for m in [c, d]:
		m.open_day(2)
		for t in Market.TICKS_PER_DAY:
			m.step_tick()
		m.close_day()
	var r2 := c.price("morningstar") / d.price("morningstar")
	check(r1 > 1.03 and r1 < 1.07 and r2 > r1 + 0.03, "多日冲击逐日体现（第 1 天 %.3f，第 2 天 %.3f）" % [r1, r2])
	check((c.stocks.morningstar.shocks as Array).is_empty(), "冲击走完后清除")
	var e := Market.new()
	e.setup(companies, 5)
	e.apply_shock("elder", 0.06, 2, true)
	check(((e.stocks.elder.shocks as Array)[0].portions as Array).size() == 2, "apply_shock 旧接口仍可用")


func _schedule_sig(e: Events) -> String:
	var parts: Array = []
	for inst in e.schedule:
		parts.append("%s/%d/%s/%s" % [inst.uid, inst.day, inst.variant, inst.stage])
	return ",".join(parts)


func _test_events(companies: Array) -> void:
	print("新闻与前兆")
	var a := Events.new()
	var b := Events.new()
	a.setup(companies, 20261028)
	b.setup(companies, 20261028)
	a.ensure(30)
	# 分几次生成，结果必须和一次生成一样
	b.ensure(10)
	b.ensure(60)
	b.schedule = b.schedule.filter(func(x): return int(x.day) <= 30)
	check(_schedule_sig(a) == _schedule_sig(b), "同一种子 → 同一份事件日程")
	var c := Events.new()
	c.setup(companies, 9)
	c.ensure(30)
	check(_schedule_sig(a) != _schedule_sig(c), "不同种子 → 不同的事件日程")
	var counts: Array = []
	var bad_pre := 0
	var early_ok := 0
	var earnings_ok := true
	for sd in range(1, 41):
		var e := Events.new()
		e.setup(companies, sd)
		e.ensure(30)
		var n := 0
		var earn := {}
		for inst in e.schedule:
			if int(inst.day) > 30:
				continue
			n += 1
			if String(inst.kind) == "earnings":
				earn[String(inst.main)] = int(inst.day)
				var k := 0
				var dd := 0
				while dd < int(inst.day):
					dd = Calendar.next_trading_day(dd)
					k += 1
				if k < 5 or k > 15:
					earnings_ok = false
			if String(inst.uid) == "b0-e0" and int(inst.day) in [3, 4]:
				var dir_pre := false
				for pre in inst.precursors:
					if not (pre.signs as Dictionary).is_empty():
						dir_pre = true
				if dir_pre and (inst.signs as Dictionary).values().has(1):
					early_ok += 1
			for pre in inst.precursors:
				if int(pre.day) >= int(inst.day) or int(pre.day) < 1 or not Calendar.is_trading_day(int(pre.day)):
					bad_pre += 1
		counts.append(n)
		if earn.size() != companies.size():
			earnings_ok = false
	counts.sort()
	check(counts[0] >= 10, "第一章 30 天里至少有 10 条消息（40 个种子最少 %d 条，最多 %d 条）" % [counts[0], counts[-1]])
	check(bad_pre == 0, "前兆都出现在事件之前的交易日")
	check(earnings_ok, "每家公司在季末后第 5–15 个交易日公布财报")
	check(early_ok == 40, "开局第 3–4 天保证有一次带前兆的利好（%d/40）" % early_ok)
	# 消息只生效一次
	var m := Market.new()
	m.setup(companies, 20261028)
	var target := {}
	for inst in a.schedule:
		if String(inst.stage) == "pre_open" and not (inst.signs as Dictionary).is_empty() and String(inst.main) != "all":
			target = inst
			break
	var d := 1
	while d < int(target.day):
		if Calendar.is_trading_day(d):
			a.before_open(m, d)
			m.open_day(d)
			while m.tick < Market.TICKS_PER_DAY:
				a.on_tick(m, d, m.tick)
				m.step_tick()
			m.close_day()
		d += 1
	var items := a.before_open(m, d)
	var fired := items.filter(func(x): return String(x.uid) == String(target.uid))
	check(fired.size() == 1 and bool(target.fired), "当天的盘前消息出现在晨报里（%s）" % target.title)
	var again := a.before_open(m, d)
	check(again.filter(func(x): return String(x.uid) == String(target.uid)).is_empty(), "同一条消息不会重复生效")
	check(not a.markers(String(target.main)).is_empty(), "已发生的消息会标在 K 线上")
	var copy := Events.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(a.to_dict(), "", false, true)), companies, 20261028)
	check(_schedule_sig(copy) == _schedule_sig(a) and bool(copy.instance(String(target.uid)).fired), "事件日程存档往返一致")


func _test_life() -> void:
	print("主角状态")
	var p := Life.new_player("测试")
	check(Life.accuracy(p) > 0.69 and Life.accuracy(p) < 0.71, "平静 + 健康：正确率 70%")
	p.hp = 40
	p.body = Life.evaluate_body(p)
	check(p.body == "tired" and absf(Life.accuracy(p) - 0.6) < 0.001, "体力 < 50 → 疲劳，正确率 −10%")
	p.illness = "cold"
	p.body = Life.evaluate_body(p)
	check(Life.predictions_per_day(p) == 1, "感冒：每天只能预测 1 次")
	p.illness = "fever"
	p.body = Life.evaluate_body(p)
	p.mood = "manic"
	check(absf(Life.accuracy(p) - 0.5) < 0.001, "发烧：正确率直接变成 50%")
	var q := Life.new_player("测试")
	Life.end_trading_day(q, -0.09, 10)
	check(q.mood == "panic", "单日大亏 → 恐慌")
	var r := Life.new_player("测试")
	for ret in [0.06, 0.05, 0.06]:
		Life.end_trading_day(r, ret, 10)
	check(r.mood == "manic", "3 天累计大赚 → 狂热")
	var o := Life.new_player("测试")
	Life.end_trading_day(o, 0.02, 10)
	check(o.mood == "optimistic", "小赚 → 乐观")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	Life.sleep(o, rng, 0, "rest")
	check(o.mood == "optimistic", "睡一觉后，近 3 天的盈亏仍然影响情绪")
	var h := Life.new_player("测试")
	h.hp = 10
	var res := Life.end_trading_day(h, 0.0, 10)
	check(bool(res.hospital) and h.body == "hospital" and not Life.can_trade(h), "体力归零 → 住院，不能交易")
	var days_in := 0
	for i in 6:
		Life.sleep(h, rng, 0, "rest")
		if h.body != "hospital":
			break
		days_in += 1
		Life.end_trading_day(h, 0.0, 10)
	check(days_in == Life.HOSPITAL_DAYS and int(h.hp) >= Life.RELEASE_HP, "住院 %d 个交易日后出院" % days_in)
	var t := Life.new_player("测试")
	for i in 3:
		Life.spend_prediction(t)
	check(int(t.predictionsLeft) == 0 and int(t.hp) == 100 - 3 * Life.PREDICT_HP and Life.predict_block_reason(t) == "no_left",
			"每次预测消耗体力，每天最多 3 次")


func _test_evening_logic() -> void:
	print("晚间行动")
	var fresh := Life.new_player("测试")
	check(Evening.action_points(fresh, "weekday") == 2 and Evening.action_points(fresh, "offday") == 4, "工作日 2 点，休市日 4 点")
	fresh.body = "tired"
	check(Evening.action_points(fresh, "weekday") == 1 and Evening.action_points(fresh, "offday") == 3, "疲劳时行动点 −1")
	fresh.body = "healthy"
	fresh.transport = "carriage"
	check(Evening.action_points(fresh, "weekday") == 3, "马车 +1 行动点")
	fresh.transport = "dragon"
	check(Evening.action_points(fresh, "weekday") == 4, "飞龙不再超过 +2")
	fresh.transport = "walk"
	fresh.body = "hospital"
	check(Evening.action_points(fresh, "offday") == 0, "住院不能出门")
	var fever := Life.new_player("测试")
	fever.body = "fever"
	var session := Evening.begin(fever, "weekday")
	var pf := Portfolio.new()
	pf.cash = 1000.0
	var aff := {}
	var flags := {}
	var blocked: Dictionary = Evening.perform(session, fever, pf, aff, flags, "study")
	check(not bool(blocked.ok) and String(blocked.code) == "fever", "发烧时只能休息")
	check(bool(Evening.perform(session, fever, pf, aff, flags, "rest").ok), "发烧时可以休息")
	# 什么都不做 = 旧版早点休息
	var left := Life.new_player("甲")
	var right := Life.new_player("乙")
	Life.end_trading_day(left, 0.0, 10)
	Life.end_trading_day(right, 0.0, 10)
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 7
	rng_b.seed = 7
	Life.sleep(left, rng_a, 0, "rest")
	var blank := Evening.begin(right, "weekday")
	Life.sleep(right, rng_b, 0, Evening.sleep_log(blank))
	check(int(left.hp) == int(right.hp) and int(left.stress) == int(right.stress) and left.mood == right.mood and left.body == right.body,
			"什么都不做直接睡觉，和旧版「早点休息」一样")
	# 复盘的体力和压力也对齐旧接口
	var rev_new := Life.new_player("丙")
	var rev_old := Life.new_player("丁")
	pf.cash = 5000.0
	var srev := Evening.begin(rev_new, "weekday")
	Evening.perform(srev, rev_new, pf, aff, flags, "review")
	rng_a.seed = 9
	rng_b.seed = 9
	Life.sleep(rev_new, rng_a, 0, Evening.sleep_log(srev))
	Life.sleep(rev_old, rng_b, 0, "review")
	check(int(rev_new.hp) == int(rev_old.hp) and int(rev_new.stress) == int(rev_old.stress), "复盘的体力压力和旧接口一致")
	check(int(aff.get("noelle", 0)) == int(Evening.action_def("review").affection.noelle), "复盘增加诺艾尔好感")
	# 进修、上限、第二次不行
	var student := Life.new_player("戊")
	var study := Evening.begin(student, "weekday")
	var tuition := int(Evening.action_def("study").gold)
	pf.cash = 400.0
	var did: Dictionary = Evening.perform(study, student, pf, aff, flags, "study")
	check(bool(did.ok) and int(student.exp) == int(Evening.action_def("study").exp) and absf(pf.cash - (400.0 - tuition)) < 0.01, "进修花钱、加经验")
	var again: Dictionary = Evening.perform(study, student, pf, aff, flags, "study")
	check(not bool(again.ok) and String(again.code) == "once", "同一晚不能进修两次")
	student.exp = 100
	var capped := Evening.begin(student, "weekday")
	check(String(Evening.perform(capped, student, pf, aff, flags, "study").code) == "exp_cap", "进修到顶就不再加")
	var genius := Life.new_player("己")
	genius.exp = 100
	check(absf(Life.accuracy(genius) - 0.80) < 0.001, "经验 100：正确率 +10%，到此为止")
	genius.exp = 250
	check(absf(Life.accuracy(genius) - 0.80) < 0.001, "经验超过 100 也不会再加")
	# 乐观时社交好感多 1
	var sunny := Life.new_player("庚")
	sunny.mood = "optimistic"
	var aff2 := {"mia": 0}
	var visit := Evening.begin(sunny, "weekday")
	Evening.perform(visit, sunny, pf, aff2, flags, "visit_mia")
	check(int(aff2.mia) == 3 and int(flags.get("hook_rumor_mia", 0)) == 1, "乐观时拜访米娅，好感多 1，并记下传闻钩子")
	# 内幕锁着，调查度不动
	var heat_before := int(sunny.heat)
	var insider: Dictionary = Evening.perform(visit, sunny, pf, aff2, flags, "insider")
	check(not bool(insider.ok) and String(insider.code) == "locked" and int(sunny.heat) == heat_before, "内幕还没开，调查度不变")
	check(not bool(Evening.resolve_hook("rival", {}).implemented), "对手大户的钩子还是空的")
	# 沙龙要名声或礼服
	var poor := Life.new_player("辛")
	var salon := Evening.begin(poor, "weekday")
	check(String(Evening.perform(salon, poor, pf, aff2, flags, "salon").code) == "locked", "名声不够进不了沙龙")
	poor.fame = 25
	check(bool(Evening.perform(salon, poor, pf, aff2, flags, "salon").ok) and int(flags.get("hook_rival_victoria", 0)) == 1, "名声够了可以进沙龙，只记一笔，不下单")
	# 升级交通，下一晚行动点变多；住所让觉更好睡
	var up := Life.new_player("壬")
	up.hp = 40
	pf.cash = 20000.0
	var shop := Evening.begin(up, "weekday")
	check(bool(Evening.perform(shop, up, pf, aff2, flags, "upgrade_transport").ok) and String(up.transport) == "carriage", "可以买马车")
	check(Evening.action_points(up, "weekday") == 3, "买完马车，下一晚行动点变多")
	var sleeper := Life.new_player("癸")
	sleeper.hp = 40
	var homebody := Life.new_player("子")
	homebody.hp = 40
	homebody.housing = "apartment"
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 3
	rb.seed = 3
	Life.sleep(sleeper, ra, 0, Evening.sleep_log(Evening.begin(sleeper, "weekday")))
	Life.sleep(homebody, rb, 0, Evening.sleep_log(Evening.begin(homebody, "weekday")))
	check(int(homebody.hp) == int(sleeper.hp) + 6, "公寓每晚多恢复 6 点体力")
	# 多休息一次，恢复更多
	var nap := Life.new_player("丑")
	nap.hp = 40
	nap.stress = 40
	var twice := Evening.begin(nap, "offday")
	Evening.perform(twice, nap, pf, aff2, flags, "rest")
	Evening.perform(twice, nap, pf, aff2, flags, "rest")
	var once_p := Life.new_player("寅")
	once_p.hp = 40
	once_p.stress = 40
	ra.seed = 4
	rb.seed = 4
	Life.sleep(nap, ra, 1, Evening.sleep_log(twice))
	Life.sleep(once_p, rb, 1, Evening.sleep_log(Evening.begin(once_p, "offday")))
	check(int(nap.hp) > int(once_p.hp) and int(nap.stress) < int(once_p.stress), "休市日多休息一次，体力更多、压力更低")
	# 悲观时亏钱，压力升得更快；大赚涨名声
	var calm_p := Life.new_player("卯")
	var sad_p := Life.new_player("辰")
	sad_p.mood = "pessimistic"
	Life.end_trading_day(calm_p, -0.04, 10)
	Life.end_trading_day(sad_p, -0.04, 10)
	check(int(sad_p.stress) > int(calm_p.stress), "悲观时，同样的亏损压力更高")
	var rich := Life.new_player("巳")
	Life.end_trading_day(rich, 0.06, 10)
	check(int(rich.fame) == int(Evening.rules().fame_profit_gain), "大赚的一天会涨一点名声")
	check(String(rich.body) == "healthy" or String(rich.body) == "tired", "收盘会重新判定身体")
	var worn := Life.new_player("午")
	worn.hp = 55
	Life.end_trading_day(worn, 0.0, 10)
	check(String(worn.body) == "tired", "收盘后体力低于 50 就是疲劳")


func _test_city_backgrounds() -> void:
	print("城区背景")
	var seen := {}
	var home := {}
	for loc in Evening.data().get("locations", []):
		var path := Evening.background_path(loc, {"housing": "attic"})
		var id := String(loc.id)
		check(path != "" and not seen.has(path), "每块城区一张自己的图（%s）" % id)
		seen[path] = true
		check(FileAccess.file_exists(path), "背景文件在（%s）" % path.get_file())
		var tex := Evening.load_background(path)
		var w := tex.get_width() if tex != null else 0
		var h := tex.get_height() if tex != null else 0
		check(tex != null and w >= 640 and h >= 360 and w > h, "背景能加载，而且是横图（%s %dx%d）" % [id, w, h])
		if id == "home":
			home = loc
	var attic := Evening.background_path(home, {"housing": "attic"})
	var mansion := Evening.background_path(home, {"housing": "mansion"})
	check(attic.ends_with("home_attic.jpg") and mansion == attic, "宅邸还没单独的图，回退到阁楼")


func _test_heroine_portraits() -> void:
	print("主角立绘")
	var moods := ["calm", "optimistic", "pessimistic", "manic", "panic"]
	var bodies := ["healthy", "tired", "cold", "fever", "hospital"]
	var expect := {
		"healthy": {"calm": "smile", "optimistic": "grin", "pessimistic": "frown", "manic": "coin", "panic": "panic"},
		"tired": {"calm": "sleepy", "optimistic": "sleepy", "pessimistic": "sleepy", "manic": "sleepy", "panic": "sleepy"},
		"cold": {"calm": "cold", "optimistic": "cold", "pessimistic": "cold", "manic": "cold", "panic": "cold"},
		"fever": {"calm": "dizzy", "optimistic": "dizzy", "pessimistic": "dizzy", "manic": "dizzy", "panic": "dizzy"},
		"hospital": {"calm": "hospital", "optimistic": "hospital", "pessimistic": "hospital", "manic": "hospital", "panic": "hospital"},
	}
	for body in bodies:
		for mood in moods:
			var layers: Dictionary = Painter.heroine_layers(mood, body)
			var name := String(layers.expr)
			check(name == String(expect[body][mood]) and (layers.overlays as Array).is_empty(),
					"%s / %s → %s，不再叠占位道具" % [mood, body, name])
			var tex := Painter.base_texture("heroine", name, layers.overlays)
			check(tex != null and tex.get_width() == 864 and tex.get_height() == 1152,
					"%s.png 能加载" % name)
	var cry := Painter.texture("heroine", "cry")
	var ecstatic := Painter.texture("heroine", "ecstatic")
	check(cry != null and cry.get_width() == 864 and Painter.base_texture("heroine", "cry", []) == cry, "对话里的 cry 用 cry.png")
	check(ecstatic != null and Painter.base_texture("heroine", "ecstatic", ["sparkle", "v_sign"]) == ecstatic, "结局的 ecstatic 用 ecstatic.png")
	var chars: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json")).characters
	var want := {"heroine": "#3b6fb6", "noelle": "#2f7d62", "raven": "#b23a48", "mia": "#f0a35e"}
	for id in want:
		var hex := String(chars[id].get("outline", "")).to_lower()
		var col := Color.html(hex)
		check(hex == String(want[id]) and col.a > 0.99, "%s 的描边颜色 %s" % [id, hex])
		var look := Painter.look_of(chars[id], id)
		check((look.outline as Color).is_equal_approx(col), "%s 的描边进了立绘配色" % id)
	check(Painter.base_texture("heroine", "smile", ["blanket", "mask"]) == Painter.texture("heroine", "cold"),
			"感冒的整图排在表情名前面")


func _test_evening_flow() -> void:
	print("晚间流程")
	var gs := _gs()
	var real_dir := _use_test_saves()
	gs.new_game(4242, "晚风", false)
	# 周一晚上什么都不做，和 choose_evening("rest") + next_day 走到同一天、同一价格
	gs.open_market()
	gs.finish_day()
	# 只有一个 GameState。先把「新流程」跑完记下来，再重开用旧接口走同一晚。
	var hp_before := int(gs.player.hp)
	gs.open_evening("weekday")
	check(gs.phase == gs.Phase.EVENING and int(gs.evening.ap) == 2, "收盘后进入晚间，2 个行动点")
	var done: Dictionary = gs.finish_evening()
	check(not bool(done.another) and gs.day == 2 and gs.phase == gs.Phase.PRE_OPEN, "周一晚上睡醒是周二开盘前")
	check(int(gs.player.hp) >= hp_before, "直接睡觉恢复了体力")
	var price_new := float(gs.market.price("elder"))
	gs.new_game(4242, "晚风", false)
	gs.open_market()
	gs.finish_day()
	gs.choose_evening("rest")
	gs.next_day()
	check(gs.day == 2 and absf(gs.market.price("elder") - price_new) < 1e-6, "新晚间和旧「早点休息」走到同一开盘价")
	# 周五收盘后要连续过周六、周日
	gs.new_game(4242, "晚风", false)
	while gs.day < 5:
		gs.open_market()
		gs.finish_day()
		gs.choose_evening("rest")
		gs.next_day()
	gs.open_market()
	gs.finish_day()
	check(gs.day == 5, "第 5 天是周五")
	gs.open_evening("weekday")
	var steps := 0
	var saw_off := false
	while true:
		var r: Dictionary = gs.finish_evening()
		steps += 1
		if bool(r.another):
			saw_off = true
			check(int(gs.evening.ap_max) == 4, "休市日有 4 个行动点")
		else:
			break
		if steps > 5:
			break
	check(saw_off and gs.day == 8 and gs.phase == gs.Phase.PRE_OPEN, "过完周末回到周一（第 8 天）")
	# 进修会进存档
	gs.open_evening("weekday")
	var studied: Dictionary = gs.perform_evening_action("study")
	check(bool(studied.ok) and int(gs.player.exp) > 0 and int(gs.evening.ap) == 1, "在城区里进修，花掉 1 点行动点")
	var sm: Node = root.get_node("SaveManager")
	check(sm.save_game("evening_slot"), "晚间中途可以存档")
	var exp := int(gs.player.exp)
	var cash := float(gs.portfolio.cash)
	var ap := int(gs.evening.ap)
	gs.new_game(1, "", false)
	check(sm.load_game(sm.path_for("evening_slot")), "读回晚间存档")
	check(gs.phase == gs.Phase.EVENING and int(gs.player.exp) == exp and absf(gs.portfolio.cash - cash) < 0.01 and int(gs.evening.ap) == ap,
			"行动点、金币和进修都还在")
	DirAccess.remove_absolute(sm.path_for("evening_slot"))
	DirAccess.remove_absolute(sm.path_for("autosave"))
	_restore_saves(real_dir)


func _test_save_v3() -> void:
	print("存档（M2，版本 2 → 3）")
	var gs := _gs()
	var sm: Node = root.get_node("SaveManager")
	var real_dir := _use_test_saves()
	gs.new_game(13579, "旧档", false)
	gs.open_market()
	gs.finish_day()
	gs.choose_evening("rest")
	gs.next_day()
	var data: Dictionary = gs.to_save_data()
	data.erase("evening")
	data.player.erase("housing")
	data.player.erase("transport")
	data.player.erase("wardrobe")
	var v2 := {
		"format": sm.FORMAT, "saveVersion": 2, "gameVersion": "0.2.0",
		"savedAt": "2026-11-01T12:00:00", "label": "第一章 · 第 2 天 开盘前", "data": data,
	}
	var path: String = sm.path_for("test_v2_evening")
	sm.write_json_atomic(path, v2)
	check(sm.load_game(path), "读取版本 2 的存档并升级到版本 3")
	check(String(gs.player.housing) == "attic" and String(gs.player.transport) == "walk" and String(gs.player.wardrobe) == "plain",
			"旧存档补上阁楼、步行和平民服")
	check(not bool(gs.evening.get("active", true)), "旧存档的当晚还没开始")
	gs.open_market()
	gs.finish_day()
	gs.open_evening("weekday")
	check(bool(gs.perform_evening_action("study").ok), "升级后的存档可以进修")
	check(sm.save_game("test_v3"), "写成版本 3")
	var doc: Dictionary = sm.read_json(sm.path_for("test_v3"))
	check(int(doc.get("saveVersion", 0)) == 3 and bool(doc.data.evening.active), "新存档版本号是 3，并且记下了正在进行的晚间")
	for name in ["test_v2_evening", "test_v3", "autosave"]:
		DirAccess.remove_absolute(sm.path_for(name))
	_restore_saves(real_dir)


func _test_predict_decide() -> void:
	print("走势预测")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rates := {}
	for state in [["calm", "healthy"], ["calm", "tired"], ["calm", "fever"]]:
		var p := Life.new_player("测试")
		p.mood = state[0]
		p.body = state[1]
		var hit := 0
		for i in 4000:
			var truth := {"dir": "up" if i % 2 == 0 else "down", "mag": "small"}
			if String(Predict.decide(truth, p, rng).dir) == truth.dir:
				hit += 1
		rates["%s/%s" % state] = hit / 4000.0
	check(absf(float(rates["calm/healthy"]) - 0.70) < 0.03, "平静时说中方向约 70%%（%.0f%%）" % (float(rates["calm/healthy"]) * 100))
	check(absf(float(rates["calm/tired"]) - 0.60) < 0.03, "疲劳时约 60%%（%.0f%%）" % (float(rates["calm/tired"]) * 100))
	check(absf(float(rates["calm/fever"]) - 0.50) < 0.03, "发烧时约 50%%（%.0f%%）" % (float(rates["calm/fever"]) * 100))
	var manic := Life.new_player("测试")
	manic.mood = "manic"
	var big_up := 0
	for i in 2000:
		var said := Predict.decide({"dir": "down", "mag": "big"}, manic, rng)
		if said.dir == "up" and said.mag == "big":
			big_up += 1
	check(big_up > 1400, "狂热时几乎总说“大涨”（真实是大跌时 %d/2000）" % big_up)
	var c1 := Predict.classify(0.002, 0.02, 1.0)
	var c2 := Predict.classify(0.05, 0.02, 1.0)
	var c3 := Predict.classify(-0.01, 0.02, 1.0)
	check(c1.dir == "flat" and c2.dir == "up" and c2.mag == "big" and c3.dir == "down" and c3.mag == "small", "涨跌与力度按波动率划分")


func _test_noelle(companies: Array) -> void:
	print("诺艾尔")
	var lines := Noelle.load_lines()
	var right_high := 0
	var total := 0
	var vague_only := true
	for sd in range(1, 61):
		var e := Events.new()
		e.setup(companies, sd)
		e.ensure(40)
		for inst in e.schedule:
			for pre in inst.precursors:
				pre.shown = int(pre.day) <= 10
		for inst in e.upcoming_clues(10, 3):
			var sign := int((inst.signs as Dictionary).get(String(inst.main), 0))
			if sign == 0 or String(inst.kind) == "rumor_result":
				continue
			total += 1
			for aff in [10, 90]:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([sd, inst.uid, aff])
				var tip: String = Noelle.tips(lines, [inst], 10, aff, e.shorts, rng)[0]
				var said_up := tip.contains("利好") or tip.contains("好消息")
				var said_down := tip.contains("利空") or tip.contains("小心")
				if aff == 10 and (said_up or said_down):
					vague_only = false
				if aff == 90 and ((sign > 0 and said_up) or (sign < 0 and said_down)):
					right_high += 1
	check(total > 20, "有足够的样本（%d 条带方向的风声）" % total)
	check(vague_only, "好感低时只提醒“风声多”，不给方向")
	check(float(right_high) / maxi(1, total) > 0.8, "好感高时判断大多正确（%d/%d）" % [right_high, total])


func _test_forecast_matches_reality() -> void:
	print("预测推演")
	var gs := _gs()
	var real_dir := _use_test_saves()
	gs.new_game(1357, "", false)
	var sim := Predict.simulate(gs.market, gs.events, gs.day, gs.phase_name(), 3)
	var closes: Array = [sim.today]
	for x in sim.days:
		closes.append(x.closes)
	var same := true
	for i in 4:
		gs.open_market()
		gs.finish_day()
		for id in gs.market.order:
			if absf(gs.market.price(id) - float(closes[i][id])) > 1e-9:
				same = false
		gs.choose_evening("rest")
		gs.next_day()
	check(same, "“玩家不干预”的推演与之后的真实行情完全一致（4 个交易日）")
	var pred: Dictionary = gs.predict("guild", "3days")
	check(pred.has("dir") and int(gs.player.predictionsLeft) == 2 and String(pred.line) != "", "发起预测：消耗次数，得到台词与结果")
	var again: Dictionary = gs.predict("guild", "3days")
	check(again.dir == pred.dir, "同一时刻重复预测得到同样的答案（不能靠重问刷结果）")
	_restore_saves(real_dir)


func _test_chapter() -> void:
	print("第一章胜负")
	var gs := _gs()
	var real_dir := _use_test_saves()
	gs.new_game(2468, "", false)
	check(gs.deadline_day() == 30 and gs.trading_days_left() == 21, "期限第 30 天，开局距期限 21 个交易日")
	var results: Array = []
	var cb := func(r): results.append(r)
	root.get_node("EventBus").chapter_finished.connect(cb)
	gs.portfolio.cash = 70000.0
	gs.repay(20000.0)
	check(gs.chapter_state == "active" and absf(gs.portfolio.debt - 30000.0) < 0.01, "部分还款")
	gs.repay(99999.0)
	check(gs.chapter_state == "cleared" and results.size() == 1 and bool(results[0].success), "还清债务 → 第一章通关")
	root.get_node("EventBus").chapter_finished.disconnect(cb)
	# 期限那天收盘：卖掉持仓也不够 → 失败
	gs.new_game(2468, "", false)
	gs.day = 30
	gs.open_market()
	gs.trade("elder", "buy", 100)
	gs.finish_day()
	check(gs.chapter_state == "failed" and gs.portfolio.holdings.is_empty(), "期限收盘还不清 → 卖出持仓后仍不够，失败")
	check(not FileAccess.file_exists(root.get_node("SaveManager").path_for("autosave")), "失败时不覆盖自动存档（可以再试一次）")
	gs.next_day()
	check(gs.day == 30, "失败后不能继续推进")
	# 期限那天收盘：卖掉持仓够还 → 成功
	gs.new_game(2468, "", false)
	gs.portfolio.cash = 80000.0
	gs.day = 30
	gs.open_market()
	gs.trade("goldwheat", "buy", 3000)
	gs.finish_day()
	check(gs.chapter_state == "cleared" and gs.portfolio.debt == 0.0 and gs.portfolio.holdings.is_empty(), "期限收盘：卖出持仓还清 → 成功")
	gs.choose_evening("rest")
	gs.next_day()
	check(gs.day > 30 and gs.phase == gs.Phase.PRE_OPEN, "通关后可以继续自由交易")
	_restore_saves(real_dir)


func _test_save_v2_and_migration() -> void:
	print("存档（M1）")
	var gs := _gs()
	var sm: Node = root.get_node("SaveManager")
	var real_dir := _use_test_saves()
	gs.new_game(97531, "露娜", true)
	for i in 3:
		gs.open_market()
		gs.finish_day()
		gs.choose_evening("review")
		gs.next_day()
	gs.open_market()
	for i in 12:
		gs.advance_tick()
	gs.trade("guild", "buy", 300)
	gs.predict("elder", "tomorrow")
	check(sm.save_game("test_v2"), "写入存档（版本 %d）" % sm.SAVE_VERSION)
	var path: String = sm.path_for("test_v2")
	var cont := func() -> Dictionary:
		gs.finish_day()
		for i in 5:
			gs.choose_evening("rest")
			gs.next_day()
			gs.open_market()
			gs.finish_day()
		var out := {}
		for id in gs.market.order:
			out[id] = gs.market.price(id)
		out["cash"] = gs.portfolio.cash
		out["hp"] = gs.player.hp
		return out
	var expect: Dictionary = cont.call()
	check(sm.load_game(path), "读取存档")
	check(String(gs.player.name) == "露娜" and int(gs.affection.noelle) > 10 and gs.predictions.size() >= 1, "主角名字、好感、预测记录都在")
	var got: Dictionary = cont.call()
	var same := true
	for k in expect:
		if absf(float(expect[k]) - float(got[k])) > 1e-6:
			same = false
	check(same, "读档后继续的行情、新闻、主角状态与不中断时完全一致")
	# 版本 1 的存档：没有事件日程、旧格式的冲击、旧的主角字段
	gs.new_game(8642, "", true)
	gs.open_market()
	gs.finish_day()
	gs.choose_evening("rest")
	gs.next_day()
	var data: Dictionary = gs.to_save_data()
	for k in ["events", "predictions", "predStats", "chapterState", "chapterResult", "lastSummary", "paper", "paperRead", "dayStartEquity", "eveningChoice", "tradedToday"]:
		data.erase(k)
	for id in data.market.stocks:
		data.market.stocks[id].erase("volume_boost")
		data.market.stocks[id].shocks = [{"per_day": 0.02, "days": 2, "overnight": true}]
	data.player = {"name": "希雅", "hp": 80, "stress": 30, "fame": 0, "heat": 0, "mood": "calm", "body": "healthy", "predictionsLeft": 3}
	var v1 := {"format": sm.FORMAT, "saveVersion": 1, "gameVersion": "0.1.0", "savedAt": "2026-10-29T14:50:35", "label": "第一章 · 第 2 天 开盘前", "data": data}
	var v1_path: String = sm.path_for("test_v1")
	sm.write_json_atomic(v1_path, v1)
	check(sm.load_game(v1_path), "读取版本 1 的存档并升级")
	check(not gs.events.schedule.is_empty() and gs.has_seen("intro") and gs.chapter_state == "active", "旧存档补上了事件日程，跳过开场剧情")
	var past_ok := true
	for inst in gs.events.schedule:
		if int(inst.day) < gs.day and not bool(inst.fired):
			past_ok = false
	check(past_ok, "旧存档里已经过去的消息不会再触发")
	check(int(gs.player.hp) == 80 and gs.player.has("dayReturns"), "主角的新字段已补齐")
	gs.open_market()
	gs.finish_day()
	check(gs.phase == gs.Phase.CLOSED, "升级后的存档可以继续游玩")
	for name in ["test_v2", "test_v1"]:
		DirAccess.remove_absolute(sm.path_for(name))
	_restore_saves(real_dir)


func _restore_saves(real_dir: String) -> void:
	var sm: Node = root.get_node("SaveManager")
	DirAccess.remove_absolute(sm.path_for("autosave"))
	sm.save_dir = real_dir
