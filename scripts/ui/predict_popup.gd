extends "res://scripts/ui/overlay.gd"
## 预测弹窗（GDD 第 6、10 节）：选股票和时间跨度 → 主角立绘 + 台词 + 方向与力度 → 采纳或忽略。
## 界面不显示准确率，只显示她的状态标签和状态描述，信不信由玩家判断。

const UI := preload("res://scripts/ui/ui_style.gd")
const Life := preload("res://scripts/core/life.gd")
const Predict := preload("res://scripts/core/predict.gd")

@onready var portrait: Control = %Portrait
@onready var state_label: Label = %StateLabel
@onready var stocks_box: HBoxContainer = %Stocks
@onready var horizons_box: HBoxContainer = %Horizons
@onready var line_label: Label = %LineLabel
@onready var result_label: Label = %ResultLabel
@onready var cost_label: Label = %CostLabel
@onready var cancel_button: Button = %CancelButton
@onready var predict_button: Button = %PredictButton
@onready var ignore_button: Button = %IgnoreButton
@onready var adopt_button: Button = %AdoptButton

var _stock := ""
var _horizon := "tomorrow"
var _stock_buttons := {}
var _horizon_buttons := {}


func _ready() -> void:
	_stock = GameState.selected_id
	var sg := ButtonGroup.new()
	for id in GameState.market.order:
		var b := Button.new()
		b.text = GameState.short_name(id)
		b.toggle_mode = true
		b.button_group = sg
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _stock = id)
		stocks_box.add_child(b)
		_stock_buttons[id] = b
	var hg := ButtonGroup.new()
	var ph := GameState.phase_name()
	if not Predict.horizon_available(_horizon, ph):
		_horizon = "tomorrow"
	for h in Predict.HORIZONS:
		var b := Button.new()
		b.text = Predict.HORIZON_NAMES[h]
		b.toggle_mode = true
		b.button_group = hg
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not Predict.horizon_available(h, ph)
		if b.disabled:
			b.tooltip_text = "今天已经收盘了"
		b.pressed.connect(func(): _horizon = h)
		horizons_box.add_child(b)
		_horizon_buttons[h] = b
	(_stock_buttons.get(_stock, _stock_buttons.values()[0]) as Button).set_pressed_no_signal(true)
	(_horizon_buttons[_horizon] as Button).set_pressed_no_signal(true)
	cancel_button.pressed.connect(func(): close())
	predict_button.pressed.connect(_on_predict)
	ignore_button.pressed.connect(func(): close())
	adopt_button.pressed.connect(func():
		GameState.adopt_last_prediction()
		close("adopt"))
	_refresh_state()
	var reason := Life.predict_block_reason(GameState.player)
	var refuse: Dictionary = GameState.heroine_lines.get("refuse", {})
	if reason != "":
		line_label.text = String(refuse.get(reason, "……"))
		predict_button.disabled = true
	else:
		line_label.text = "要我看哪一支？"


func _refresh_state() -> void:
	var p: Dictionary = GameState.player
	state_label.text = "%s · %s：%s" % [UI.MOOD_NAMES.get(String(p.mood), ""), UI.BODY_NAMES.get(String(p.body), ""), Life.note(p)]
	state_label.add_theme_color_override("font_color", (UI.MOOD_COLORS.get(String(p.mood), UI.TEXT) as Color).darkened(0.45))
	cost_label.text = "今日还能预测 %d 次 · 每次消耗体力 %d · 体力 %d" % [int(p.predictionsLeft), Life.PREDICT_HP, int(p.hp)]
	portrait.queue_redraw()


func _on_predict() -> void:
	var pred := GameState.predict(_stock, _horizon)
	if pred.has("error"):
		line_label.text = String(pred.line)
		return
	line_label.text = "「%s」" % String(pred.line)
	result_label.text = "%s · %s：%s %s" % [GameState.short_name(_stock), Predict.HORIZON_NAMES[_horizon], Predict.label(pred), Predict.arrow(pred)]
	var col := UI.FLAT
	if String(pred.dir) == "up":
		col = UI.UP
	elif String(pred.dir) == "down":
		col = UI.DOWN
	result_label.add_theme_color_override("font_color", col)
	for b in _stock_buttons.values() + _horizon_buttons.values():
		(b as Button).disabled = true
	predict_button.visible = false
	cancel_button.visible = false
	ignore_button.visible = true
	adopt_button.visible = true
	_refresh_state()
