extends Control
## 盘中演出（GDD 第 9 节“演出与反馈”）：所选股票涨停时金币从屏幕上方落下；
## 所选股票跌停、或持仓市值一个 tick 内大跌时，屏幕轻微震动、色调变灰。

const UI := preload("res://scripts/ui/ui_style.gd")
const COIN_COUNT := 48
const CRASH_TICK_DROP := 0.04

@export var shake_target: NodePath

var _coins: Array = []
var _grey := 0.0
var _shown := {}
var _last_equity := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	set_process(false)
	EventBus.market_opened.connect(func(_d):
		_shown.clear()
		_last_equity = GameState.equity())
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.trade_executed.connect(func(_r): _last_equity = GameState.equity())


func _on_tick(_t: int) -> void:
	var m := GameState.market
	var id := GameState.selected_id
	if id != "" and m.stocks.has(id):
		var chg := m.day_change(id)
		if m.price(id) >= m.limit_up(id) and chg > 0.1 and not _shown.has("up_" + id):
			_shown["up_" + id] = true
			coin_rain()
		elif m.price(id) <= m.limit_down(id) and chg < -0.1 and not _shown.has("down_" + id):
			_shown["down_" + id] = true
			crash()
	var eq := GameState.equity()
	if _last_equity > 0.0 and eq / _last_equity - 1.0 <= -CRASH_TICK_DROP and not GameState.portfolio.holdings.is_empty():
		crash()
	_last_equity = eq


func coin_rain() -> void:
	for i in COIN_COUNT:
		_coins.append({
			"p": Vector2(_rng.randf_range(0.0, size.x), _rng.randf_range(-size.y * 0.6, -10.0)),
			"v": Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(140.0, 260.0)),
			"r": _rng.randf_range(6.0, 11.0), "phase": _rng.randf() * TAU,
		})
	set_process(true)


func crash() -> void:
	_grey = 0.35
	set_process(true)
	var target := get_node_or_null(shake_target) as Control
	if target == null:
		return
	var base := target.position
	var tw := create_tween()
	for i in 6:
		var amp := 6.0 * (1.0 - i / 6.0)
		tw.tween_property(target, "position", base + Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp)), 0.04)
	tw.tween_property(target, "position", base, 0.04)


func _process(delta: float) -> void:
	var alive: Array = []
	for c in _coins:
		c.v.y += 260.0 * delta
		c.p += c.v * delta
		c.phase += delta * 8.0
		if c.p.y < size.y + 20.0:
			alive.append(c)
	_coins = alive
	_grey = maxf(0.0, _grey - delta * 0.35)
	queue_redraw()
	if _coins.is_empty() and _grey <= 0.0:
		set_process(false)


func _draw() -> void:
	if _grey > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.45, _grey), true)
	for c in _coins:
		var w: float = absf(cos(float(c.phase))) * float(c.r) + 1.5
		var rect := Rect2(c.p - Vector2(w, c.r), Vector2(w * 2.0, float(c.r) * 2.0))
		draw_rect(rect, Color(0.98, 0.78, 0.22), true)
		draw_rect(rect, Color(0.7, 0.48, 0.08), false, 1.5)
