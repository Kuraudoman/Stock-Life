extends "res://scripts/ui/overlay.gd"
## 第一章结局画面（GDD 第 8 节）：成功（提前还清 / 期限结算还清）或失败（席位被收走）。
## 关闭时返回 "continue"（还清后继续自由交易）或 "title"。

const UI := preload("res://scripts/ui/ui_style.gd")
const Portfolio := preload("res://scripts/core/portfolio.gd")

@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var heroine: Control = %Heroine
@onready var stats: RichTextLabel = %Stats
@onready var title_button: Button = %TitleButton
@onready var continue_button: Button = %ContinueButton

var result := {}


func setup(p_result: Dictionary) -> void:
	result = p_result


func _ready() -> void:
	var ok := bool(result.get("success", false))
	var start := float(GameState.chapter.get("start_cash", 0))
	var debt := float(GameState.chapter.get("debt", 0))
	if ok:
		title.text = "第一章 · 黎明  完"
		subtitle.text = "提前还清了 %s 金币的债务！" % Portfolio.fmt_money(debt) if bool(result.get("early", false)) \
				else "在期限当天还清了 %s 金币的债务！" % Portfolio.fmt_money(debt)
		heroine.set_character("heroine", "ecstatic", ["sparkle", "v_sign"])
	else:
		title.text = "第一章 · 席位被收走"
		subtitle.text = "期限到了，还差 %s 金币……" % Portfolio.fmt_money(float(result.get("debt", 0)))
		subtitle.add_theme_color_override("font_color", UI.DOWN)
		heroine.set_character("heroine", "cry", [])
		heroine.tint = Color(0.5, 0.5, 0.5, 0.3)
	var hits := int(result.get("pred_hits", 0))
	var resolved := int(result.get("pred_resolved", 0))
	var lines := [
		"结束日期：%s（第 %d 天）" % [String(result.get("date", "")), int(result.get("day", 0))],
		"起始现金：%s　债务：%s" % [Portfolio.fmt_money(start), Portfolio.fmt_money(debt)],
		"结算后现金：%s" % Portfolio.fmt_money(float(result.get("cash", 0))),
		"净资产：[color=#%s]%s[/color]" % [UI.change_color(float(result.get("net_worth", 0))).to_html(false), Portfolio.fmt_money(float(result.get("net_worth", 0)))],
		"已实现盈亏：%s　手续费与税：%s" % [Portfolio.fmt_money(float(result.get("realized", 0))), Portfolio.fmt_money(float(result.get("fees", 0)))],
		"%s的预测：%d 次，回顾 %d 次，说中 %d 次" % [String(GameState.player.get("name", "希雅")), int(result.get("pred_made", 0)), resolved, hits],
		"诺艾尔好感：%d" % int(result.get("affection", 0)),
		"",
		("第二章 · 繁荣尚未开放。可以继续自由交易。好感传闻、内幕调查、对手大户、杠杆和做空会在之后的版本加入。" if ok
				else "标题画面的「继续」会回到期限当天开盘前（失败时不会覆盖自动存档），可以再试一次。"),
	]
	stats.text = "\n".join(lines)
	continue_button.visible = ok
	title_button.pressed.connect(func(): close("title"))
	continue_button.pressed.connect(func(): close("continue"))
