extends RefCounted
## 晚间行动与城市地图（GDD 第 6、7 节）。纯逻辑，不依赖场景节点。
##
## 行动点：工作日晚间 2 点，每个休市日 4 点；疲劳 −1；交通最多再 +2。发烧只能休息，住院不能出门。
## 什么都不做直接睡觉，等同于旧版的「早点休息」（见 Life.sleep 的字典分支）。
## 做过任何行动就不再自动休息——外出、进修、应酬都会少睡一会儿。
##
## 钩子（这版不产生情报、不加调查度、不让对手下单）：
##   rumor       拜访米娅、酒馆听传闻
##   investigate 实地看看公司
##   insider     向渡鸦夫人买内幕（按钮锁着，heat 写在数据里供以后用）
##   rival       贵族沙龙里谈维多利亚
##   invite      住所够大后请客
## 成功执行后会把 flags["hook_<钩子>_<目标>"] 加一，后续系统读这个计数即可。

const DATA_PATH := "res://data/evening.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


static func rules() -> Dictionary:
	return data().get("rules", {})


static func action_def(id: String) -> Dictionary:
	return data().get("actions", {}).get(id, {})


static func track_list(track: String) -> Array:
	var raw: Variant = data().get(track, [])
	return raw if typeof(raw) == TYPE_ARRAY else []


static func tier(player: Dictionary, track: String) -> Dictionary:
	var list := track_list(track)
	if list.is_empty():
		return {}
	var id := String(player.get(track, ""))
	for item in list:
		if String(item.get("id", "")) == id:
			return item
	return list[0]


static func next_tier(player: Dictionary, track: String) -> Dictionary:
	var list := track_list(track)
	var cur := String(tier(player, track).get("id", ""))
	var found := false
	for item in list:
		if found:
			return item
		if String(item.get("id", "")) == cur:
			found = true
	return {}


## 今晚的行动点。kind 为 "weekday" 或 "offday"。住院返回 0。
static func action_points(player: Dictionary, kind: String) -> int:
	var ap: Dictionary = data().get("ap", {})
	if String(player.get("body", "")) == "hospital":
		return 0
	var base := int(ap.get("offday" if kind == "offday" else "weekday", 2))
	if String(player.get("body", "")) == "tired":
		base -= int(ap.get("tired_penalty", 1))
	var bonus := mini(int(tier(player, "transport").get("ap", 0)), int(ap.get("transport_cap", 2)))
	return maxi(int(ap.get("min_ap", 1)), base + bonus)


static func begin(player: Dictionary, kind: String) -> Dictionary:
	var ap := action_points(player, kind)
	return {
		"active": true,
		"kind": kind,
		"ap": ap,
		"ap_max": ap,
		"done": [],
		"rests": 0,
		"hp_delta": 0,
		"stress_delta": 0,
		"log": [],
	}


## 交给 Life.sleep 的结算记录。什么都没做时 auto_rest，相当于休息了一次。
static func sleep_log(session: Dictionary) -> Dictionary:
	var done: Array = session.get("done", [])
	return {
		"rests": int(session.get("rests", 0)),
		"auto_rest": done.is_empty(),
		"hp_delta": int(session.get("hp_delta", 0)),
		"stress_delta": int(session.get("stress_delta", 0)),
	}


## 不能做时返回 {ok: false, code, reason}；能做时 ok 为 true，reason 为空。
static func check(session: Dictionary, player: Dictionary, cash: float, action_id: String) -> Dictionary:
	var spec := action_def(action_id)
	if spec.is_empty():
		return {"ok": false, "code": "unknown", "reason": "没有这个行动"}
	var body := String(player.get("body", ""))
	if body == "hospital":
		return {"ok": false, "code": "hospital", "reason": "还在住院，今晚只能睡觉"}
	if body == "fever" and String(spec.get("kind", "")) != "rest":
		return {"ok": false, "code": "fever", "reason": "在发烧，今晚只能休息"}
	var gate := _lock_reason(player, spec)
	if gate != "":
		return {"ok": false, "code": "locked", "reason": gate}
	if bool(spec.get("once", false)) and action_id in session.get("done", []):
		return {"ok": false, "code": "once", "reason": "今晚已经做过了"}
	if String(spec.get("kind", "")) == "upgrade" and next_tier(player, String(spec.get("track", ""))).is_empty():
		return {"ok": false, "code": "maxed", "reason": "已经是最高一档了"}
	if String(spec.get("kind", "")) == "study" and int(player.get("exp", 0)) >= int(rules().get("exp_cap", 100)):
		return {"ok": false, "code": "exp_cap", "reason": "学院里能教的，你已经都会了"}
	if int(session.get("ap", 0)) < int(spec.get("ap", 1)):
		return {"ok": false, "code": "no_ap", "reason": "行动点不够了"}
	var gold := _gold_cost(player, spec)
	if gold > 0 and cash + 0.001 < float(gold):
		return {"ok": false, "code": "gold", "reason": "金币不够（需要 %d）" % gold}
	return {"ok": true, "code": "ok", "reason": ""}


## 执行行动。改 session、player、portfolio.cash、affection、flags。
## 体力和压力先记在 session 里，睡觉时一并结算，避免和 Life.sleep 的恢复算两次。
## 返回 {ok, code, reason, kind, hook, log, lines}。lines 留给界面填对话。
static func perform(session: Dictionary, player: Dictionary, portfolio, affection: Dictionary, flags: Dictionary, action_id: String) -> Dictionary:
	var cash := float(portfolio.cash)
	var gate := check(session, player, cash, action_id)
	if not bool(gate.ok):
		return gate
	var spec := action_def(action_id)
	var kind := String(spec.get("kind", ""))
	var gold := _gold_cost(player, spec)
	portfolio.cash = cash - float(gold)
	session.ap = int(session.ap) - int(spec.get("ap", 1))
	var done: Array = session.done
	done.append(action_id)
	var log := ""
	match kind:
		"rest":
			session.rests = int(session.rests) + 1
			log = String(spec.get("log", ""))
		"study":
			var gain := int(spec.get("exp", 0))
			var cap := int(rules().get("exp_cap", 100))
			var before := int(player.get("exp", 0))
			player.exp = mini(cap, before + gain)
			gain = int(player.exp) - before
			_add_deltas(session, spec)
			log = String(spec.get("log", "")).replace("{exp}", str(gain))
		"upgrade":
			log = _apply_upgrade(player, spec)
		_:
			_add_deltas(session, spec)
			_add_fame(player, int(spec.get("fame", 0)))
			_add_affection(player, affection, spec)
			log = String(spec.get("log", ""))
	var hook := String(spec.get("hook", ""))
	if hook != "":
		_count_hook(flags, hook, String(spec.get("target", "")))
		var resolved := resolve_hook(hook, {
			"action": action_id,
			"target": String(spec.get("target", "")),
			"player": player,
			"flags": flags,
		})
		if bool(resolved.get("implemented", false)) and String(resolved.get("text", "")) != "":
			log = String(resolved.text)
	if log != "":
		(session.log as Array).append(log)
	return {"ok": true, "code": "ok", "reason": "", "kind": kind, "hook": hook, "log": log, "lines": []}


## 后续 M2 系统替换这里。现在一律 implemented=false，调用方就用数据里的占位台词。
static func resolve_hook(_hook: String, _ctx: Dictionary) -> Dictionary:
	return {"hook": _hook, "implemented": false, "text": ""}


# ---------------------------------------------------------------- 界面用的描述

## 城区插画。background_track 为 "housing" 时，用当前住所等级上的 background；
## 该等级没写图，就回退到城区自己的 background（阁楼那张）。
static func background_path(loc: Dictionary, player: Dictionary = {}) -> String:
	var track := String(loc.get("background_track", ""))
	if track != "":
		var from_tier := String(tier(player, track).get("background", ""))
		if from_tier != "":
			return from_tier
	return String(loc.get("background", ""))


static var _backgrounds: Dictionary = {}


## 线性过滤由界面在绘制时设置。这里只负责按路径加载。
static func load_background(path: String) -> Texture2D:
	if path == "":
		return null
	if _backgrounds.has(path):
		var cached: Variant = _backgrounds[path]
		return cached if cached is Texture2D else null
	var res: Variant = load(path) if FileAccess.file_exists(path) else null
	var tex: Texture2D = res if res is Texture2D else null
	_backgrounds[path] = tex
	return tex


static func snapshot(session: Dictionary, player: Dictionary, cash: float) -> Dictionary:
	var kind := String(session.get("kind", "weekday"))
	var locs: Array = []
	for loc in data().get("locations", []):
		var actions: Array = []
		for id in loc.get("actions", []):
			actions.append(action_view(session, player, cash, String(id)))
		var copy: Dictionary = loc.duplicate(true)
		copy.actions = actions
		copy.background = background_path(loc, player)
		copy.erase("background_track")
		locs.append(copy)
	var cap := int(rules().get("exp_cap", 100))
	var hp_delta := int(session.get("hp_delta", 0))
	var stress_delta := int(session.get("stress_delta", 0))
	var pending := ""
	if hp_delta != 0 or stress_delta != 0:
		pending = "（睡觉时再结算 体力 %+d  压力 %+d）" % [hp_delta, stress_delta]
	var body := String(player.get("body", ""))
	var hint := "什么都不做直接睡觉，等于早点休息一次。出去转过之后，就没有这份休息了。"
	if body == "hospital":
		hint = "还在住院。今晚睡到天亮就好，市场照常开。"
	elif body == "fever":
		hint = "在发烧，今晚只能休息。硬撑着出门会在睡觉时加重。"
	elif body == "tired":
		hint = "有点累，今晚的行动点少了 1 个。"
	return {
		"kind": kind,
		"ap": int(session.get("ap", 0)),
		"ap_max": int(session.get("ap_max", 0)),
		"title": "休市日" if kind == "offday" else "晚间",
		"stats": "体力 %d  压力 %d  名声 %d  进修 %d/%d%s" % [
			int(player.get("hp", 0)), int(player.get("stress", 0)), int(player.get("fame", 0)),
			int(player.get("exp", 0)), cap, pending],
		"assets": "%s · %s · %s" % [tier(player, "housing").get("name", ""), tier(player, "transport").get("name", ""), tier(player, "wardrobe").get("name", "")],
		"locations": locs,
		"log": session.get("log", []),
		"hint": hint,
		"hospital": body == "hospital",
		"fever": body == "fever",
	}


static func action_view(session: Dictionary, player: Dictionary, cash: float, action_id: String) -> Dictionary:
	var spec := action_def(action_id)
	var gate := check(session, player, cash, action_id)
	var name := String(spec.get("name", action_id))
	var blurb := String(spec.get("blurb", ""))
	var detail := _detail(player, spec)
	if String(spec.get("kind", "")) == "upgrade":
		var nxt := next_tier(player, String(spec.get("track", "")))
		if nxt.is_empty():
			name = "%s（已满）" % name
		else:
			name = "%s：%s → %s" % [name, tier(player, String(spec.get("track", ""))).get("name", ""), nxt.get("name", "")]
			blurb = String(nxt.get("blurb", blurb))
			detail = "1 行动点 · %d 金币" % int(nxt.get("cost", 0))
			if int(nxt.get("ap", -1)) >= 0:
				detail += " · 行动点加成 +%d" % mini(int(nxt.get("ap", 0)), int(data().get("ap", {}).get("transport_cap", 2)))
			if int(nxt.get("sleep_hp", 0)) > 0:
				detail += " · 每晚体力 +%d" % int(nxt.sleep_hp)
	return {
		"id": action_id,
		"name": name,
		"blurb": blurb,
		"detail": detail,
		"enabled": bool(gate.ok),
		"reason": String(gate.reason),
		"locked": String(gate.code) == "locked",
	}


# ---------------------------------------------------------------- 内部

static func _gold_cost(player: Dictionary, spec: Dictionary) -> int:
	if String(spec.get("kind", "")) == "upgrade":
		return int(next_tier(player, String(spec.get("track", ""))).get("cost", 0))
	return int(spec.get("gold", 0))


static func _detail(player: Dictionary, spec: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("%d 行动点" % int(spec.get("ap", 1)))
	var gold := _gold_cost(player, spec)
	if gold > 0:
		parts.append("%d 金币" % gold)
	if int(spec.get("exp", 0)) != 0:
		parts.append("进修 %+d" % int(spec.exp))
	if int(spec.get("hp", 0)) != 0:
		parts.append("体力 %+d" % int(spec.hp))
	if int(spec.get("stress", 0)) != 0:
		parts.append("压力 %+d" % int(spec.stress))
	if int(spec.get("fame", 0)) != 0:
		parts.append("名声 %+d" % int(spec.fame))
	if spec.has("affection"):
		parts.append("好感上升")
	if int(spec.get("heat", 0)) != 0 and bool(spec.get("locked", false)):
		parts.append("以后：调查度 %+d" % int(spec.heat))
	return " · ".join(parts)


static func _lock_reason(player: Dictionary, spec: Dictionary) -> String:
	if bool(spec.get("requires_invite", false)) and not bool(tier(player, "housing").get("invite", false)):
		return String(spec.get("lock_reason_small", spec.get("lock_reason", "还不行")))
	if bool(spec.get("locked", false)):
		return String(spec.get("lock_reason", "还没开放"))
	if spec.has("requires_fame") or bool(spec.get("requires_salon_wardrobe", false)):
		var fame_ok := int(player.get("fame", 0)) >= int(spec.get("requires_fame", 9999))
		var cloth_ok := bool(spec.get("requires_salon_wardrobe", false)) and bool(tier(player, "wardrobe").get("salon", false))
		if not fame_ok and not cloth_ok:
			return String(spec.get("lock_reason", "还进不去"))
	return ""


static func _add_deltas(session: Dictionary, spec: Dictionary) -> void:
	session.hp_delta = int(session.get("hp_delta", 0)) + int(spec.get("hp", 0))
	session.stress_delta = int(session.get("stress_delta", 0)) + int(spec.get("stress", 0))


static func _add_fame(player: Dictionary, amount: int) -> void:
	if amount == 0:
		return
	var cap := int(rules().get("fame_cap", 100))
	player.fame = clampi(int(player.get("fame", 0)) + amount, 0, cap)


static func _add_affection(player: Dictionary, affection: Dictionary, spec: Dictionary) -> void:
	var gain: Dictionary = spec.get("affection", {})
	if gain.is_empty():
		return
	var bonus := 0
	if bool(spec.get("social", false)) and String(player.get("mood", "")) == "optimistic":
		bonus = int(rules().get("optimistic_social_bonus", 0))
	for who in gain:
		affection[who] = clampi(int(affection.get(who, 0)) + int(gain[who]) + bonus, 0, 100)


static func _apply_upgrade(player: Dictionary, spec: Dictionary) -> String:
	var track := String(spec.get("track", ""))
	var nxt := next_tier(player, track)
	if nxt.is_empty():
		return ""
	var prev := String(tier(player, track).get("name", ""))
	player[track] = String(nxt.get("id", ""))
	_add_fame(player, int(nxt.get("fame", 0)))
	return "换成了%s（原先是%s）。" % [nxt.get("name", ""), prev]


static func _count_hook(flags: Dictionary, hook: String, target: String) -> void:
	var key := "hook_%s" % hook if target == "" else "hook_%s_%s" % [hook, target]
	flags[key] = int(flags.get(key, 0)) + 1
