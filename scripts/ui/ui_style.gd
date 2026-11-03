extends RefCounted
## 界面共用的颜色与格式化函数。浅色主题：奶油纸面 + 木框（Kenney Pixel Adventure），天空蓝底色。
## 涨跌配色采用“红涨绿跌”，颜色都按奶油底色上的可读性调过。

const BG := Color(0.847, 0.914, 0.965)          # 场景底色
const PAPER := Color(1.0, 0.98, 0.94)           # 图表纸面，比面板更亮
const TEXT := Color(0.29, 0.204, 0.141)         # 深棕墨色
const MUTED := Color(0.549, 0.451, 0.341)
const ACCENT := Color(0.659, 0.345, 0.122)      # 标题、名字
const WOOD := Color(0.773, 0.529, 0.278)        # 木框橙
const WOOD_DARK := Color(0.427, 0.294, 0.153)   # 木框描边
const UP := Color(0.812, 0.231, 0.196)
const DOWN := Color(0.161, 0.541, 0.302)
const FLAT := Color(0.549, 0.49, 0.424)
const WARN := Color(0.722, 0.416, 0.047)
const BLUE := Color(0.231, 0.494, 0.773)
const CHART_BG := PAPER
const GRID := Color(0.427, 0.294, 0.153, 0.1)
const BAR_TRACK := Color(0.937, 0.871, 0.745)
const HP_COLOR := Color(0.447, 0.722, 0.306)
const STRESS_COLOR := Color(0.886, 0.4, 0.357)
const PORTRAIT_BG := Color(0.82, 0.906, 0.976)  # 立绘背景：浅天蓝 + 方格
const PORTRAIT_GRID := Color(1, 1, 1, 0.55)

const RUMOR := Color(0.502, 0.341, 0.659)
const BREAKING := Color(0.741, 0.192, 0.173)
const LOG_COLORS := {
	"info": TEXT, "trade": ACCENT, "warn": WARN, "news": BLUE, "noelle": DOWN, "stamp": MUTED,
	"breaking": BREAKING, "precursor": BLUE, "rumor": RUMOR, "predict": Color(0.769, 0.420, 0.110), "filler": MUTED,
}
## 晨报栏目的颜色。
const SECTION_COLORS := {"要闻": BREAKING, "市场": BLUE, "传闻": RUMOR, "杂谈": MUTED}
const MOOD_NAMES := {"calm": "平静", "optimistic": "乐观", "pessimistic": "悲观", "manic": "狂热", "panic": "恐慌"}
const BODY_NAMES := {"healthy": "健康", "tired": "疲劳", "cold": "感冒", "fever": "发烧", "hospital": "住院"}
const MOOD_COLORS := {
	"calm": Color(0.361, 0.635, 0.878), "optimistic": Color(0.949, 0.651, 0.188),
	"pessimistic": Color(0.494, 0.553, 0.678), "manic": Color(0.918, 0.435, 0.204), "panic": Color(0.6, 0.42, 0.82),
}


static func change_color(chg: float) -> Color:
	if chg > 0.00005:
		return UP
	if chg < -0.00005:
		return DOWN
	return FLAT


static func pct(chg: float) -> String:
	return "%+.2f%%" % (chg * 100.0)


static func volume(v: float) -> String:
	if v >= 100000000.0:
		return "%.2f亿" % (v / 100000000.0)
	if v >= 10000.0:
		return "%.1f万" % (v / 10000.0)
	return "%d" % int(v)


## 像素风进度条：深棕描边 + 浅色槽 + 填充，顶部一行高光。
static func draw_bar(ci: CanvasItem, r: Rect2, ratio: float, color: Color) -> void:
	ci.draw_rect(r, BAR_TRACK, true)
	var fill := Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y))
	if fill.size.x >= 1.0:
		ci.draw_rect(fill, color, true)
		ci.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), color.lightened(0.35), true)
	ci.draw_rect(r.grow(1), WOOD_DARK, false, 1.0)


## 立绘背景：浅天蓝方格纸，外加主题里的木框（PortraitFrame）。
static func draw_portrait_backdrop(ci: Control, r: Rect2, tint: Color = Color(0, 0, 0, 0)) -> void:
	ci.draw_rect(r, PORTRAIT_BG, true)
	var step := 12.0
	var x := r.position.x + step
	while x < r.end.x:
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), PORTRAIT_GRID, 1.0)
		x += step
	var y := r.position.y + step
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), PORTRAIT_GRID, 1.0)
		y += step
	if tint.a > 0.0:
		ci.draw_rect(r, tint, true)


static func draw_portrait_frame(ci: Control, r: Rect2) -> void:
	ci.draw_style_box(ci.get_theme_stylebox("panel", "PortraitFrame"), r)


## 看板娘表情（GDD 第 9 节），阈值待调整。tint 叠加在立绘背景上。
static func mascot_expression(chg: float, at_limit_up: bool, at_limit_down: bool) -> Dictionary:
	if at_limit_up:
		return {"name": "狂喜", "tint": Color(1.0, 0.82, 0.35, 0.45)}
	if at_limit_down:
		return {"name": "崩溃", "tint": Color(0.5, 0.5, 0.5, 0.45)}
	if chg >= 0.03:
		return {"name": "开心", "tint": Color(0.886, 0.4, 0.357, 0.22)}
	if chg > -0.03:
		return {"name": "普通", "tint": Color(1, 1, 1, 0)}
	if chg > -0.08:
		return {"name": "担忧", "tint": Color(0.447, 0.722, 0.306, 0.22)}
	return {"name": "哭泣", "tint": Color(0.361, 0.635, 0.878, 0.3)}
