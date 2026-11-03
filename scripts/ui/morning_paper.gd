extends "res://scripts/ui/overlay.gd"
## 《金穗日报》晨报（GDD 第 6 节）：每天开盘前 3–5 条。栏目：要闻（已发生，开盘跳空）、市场（前兆）、
## 街谈巷议（传闻，真假参半）、杂谈（花边，无影响）。关闭时返回 "open"（顺便开盘）或 null。

const UI := preload("res://scripts/ui/ui_style.gd")
const Calendar := preload("res://scripts/core/calendar.gd")
const SECTION_ORDER := ["要闻", "市场", "传闻", "杂谈"]
const SECTION_LABELS := {"要闻": "要闻", "市场": "市场", "传闻": "街谈巷议", "杂谈": "杂谈"}

@onready var date_label: Label = %DateLabel
@onready var items_box: VBoxContainer = %Items
@onready var close_button: Button = %CloseButton
@onready var open_button: Button = %OpenButton

var paper := {}
var can_open := true


func setup(p_paper: Dictionary, p_can_open: bool) -> void:
	paper = p_paper
	can_open = p_can_open


func _ready() -> void:
	close_button.pressed.connect(func(): close())
	open_button.pressed.connect(func(): close("open"))
	open_button.visible = can_open
	var d := int(paper.get("day", GameState.day))
	date_label.text = "帝国历 %s · 第 %d 天" % [Calendar.format_date(d), d]
	var items: Array = paper.get("items", [])
	var sorted := items.duplicate()
	sorted.sort_custom(func(a, b): return SECTION_ORDER.find(String(a.section)) < SECTION_ORDER.find(String(b.section)))
	for it in sorted:
		items_box.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var section := String(it.get("section", "杂谈"))
	var col: Color = UI.SECTION_COLORS.get(section, UI.MUTED)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var tag := Label.new()
	tag.text = SECTION_LABELS.get(section, section)
	tag.custom_minimum_size = Vector2(72, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	tag.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_content_margin_all(3)
	sb.set_border_width_all(1)
	sb.border_color = col.darkened(0.35)
	tag.add_theme_stylebox_override("normal", sb)
	hb.add_child(tag)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var title := Label.new()
	var t := String(it.get("title", ""))
	if String(it.get("kind", "")) == "rumor":
		t = t.trim_prefix("街谈巷议：")
	title.text = t
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UI.TEXT if section != "杂谈" else UI.MUTED)
	vb.add_child(title)
	var body := String(it.get("body", ""))
	if body != "":
		var b := Label.new()
		b.text = body
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UI.MUTED)
		vb.add_child(b)
	return hb
