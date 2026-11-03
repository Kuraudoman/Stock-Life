extends "res://scripts/ui/overlay.gd"
## 日结算（GDD 第 9、10 节）：当日盈亏、净资产曲线、主角状态变化、诺艾尔点评，然后选择晚间安排。
## 关闭时返回 "rest" / "review"，期限那天返回 "final"。

const UI := preload("res://scripts/ui/ui_style.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")

@onready var title: Label = %Title
@onready var state_label: Label = %StateLabel
@onready var pnl_label: Label = %PnlLabel
@onready var grid: GridContainer = %Grid
@onready var deadline_label: Label = %DeadlineLabel
@onready var noelle_text: RichTextLabel = %NoelleText
@onready var evening_label: Label = %EveningLabel
@onready var rest_button: Button = %RestButton
@onready var review_button: Button = %ReviewButton
@onready var final_button: Button = %FinalButton

var summary := {}


func setup(p_summary: Dictionary) -> void:
	summary = p_summary


func _ready() -> void:
	title.text = "%s · 收盘结算" % String(summary.get("date", ""))
	var pnl := float(summary.get("pnl", 0.0))
	pnl_label.text = "当日盈亏 %s%s（%s）" % ["+" if pnl >= 0 else "", Portfolio.fmt_money(pnl), UI.pct(float(summary.get("day_ret", 0.0)))]
	pnl_label.add_theme_color_override("font_color", UI.change_color(pnl))
	var nw := float(summary.get("net_worth", 0.0))
	for pair in [["现金", float(summary.cash)], ["持仓市值", float(summary.holdings_value)],
			["负债", float(summary.debt)], ["净资产", nw]]:
		var k := Label.new()
		k.text = pair[0]
		k.add_theme_color_override("font_color", UI.MUTED)
		k.add_theme_font_size_override("font_size", 13)
		grid.add_child(k)
		var v := Label.new()
		v.text = Portfolio.fmt_money(pair[1])
		v.add_theme_font_size_override("font_size", 15)
		if pair[0] == "净资产":
			v.add_theme_color_override("font_color", UI.change_color(nw))
		grid.add_child(v)
	# 主角状态变化
	var mb := String(UI.MOOD_NAMES.get(String(summary.get("mood_before", "")), ""))
	var ma := String(UI.MOOD_NAMES.get(String(summary.get("mood_after", "")), ""))
	var bb := String(UI.BODY_NAMES.get(String(summary.get("body_before", "")), ""))
	var ba := String(UI.BODY_NAMES.get(String(summary.get("body_after", "")), ""))
	var st := ("%s → %s" % [mb, ma]) if mb != ma else ma
	st += " · " + (("%s → %s" % [bb, ba]) if bb != ba else ba)
	state_label.text = st
	# 诺艾尔
	var t := "[color=#%s]诺艾尔：[/color]「%s」" % [UI.DOWN.to_html(false), String(summary.get("comment", ""))]
	var note := String(summary.get("state_note", ""))
	if note != "":
		t += "\n「%s」" % note
	for r in summary.get("reviews", []):
		t += "\n[color=#%s]%s[/color]" % [UI.LOG_COLORS.predict.to_html(false), String(r)]
	noelle_text.text = t
	var result: Dictionary = summary.get("chapter_result", {})
	deadline_label.text = String(summary.get("deadline", ""))
	deadline_label.visible = deadline_label.text != ""
	if not result.is_empty():
		rest_button.visible = false
		review_button.visible = false
		final_button.visible = true
		evening_label.text = "今天是还款期限。渡鸦夫人的人已经在门口了……"
		final_button.pressed.connect(func(): close("final"))
		return
	var body := String(GameState.player.get("body", "healthy"))
	if body in ["fever", "hospital"]:
		review_button.disabled = true
		review_button.tooltip_text = "现在只能休息"
	rest_button.pressed.connect(func(): close("rest"))
	review_button.pressed.connect(func(): close("review"))
