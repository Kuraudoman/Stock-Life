extends RefCounted
## 日历、交易时间与休市。纯逻辑，不依赖任何场景节点。
##
## 约定：
## - day 为游戏内的日序号，第 1 天是第一章的开局日（周一）。day <= 0 表示开局前的历史行情。
## - 帝国历每月 30 天、每年 12 个月，一周 7 天，周六、周日休市。
## - 每个交易日 9:00–15:00，每 10 分钟一个 tick，共 36 个 tick。tick=0 为开盘，tick=36 为收盘。

const TICKS_PER_DAY := 36
const OPEN_MINUTES := 9 * 60
const MINUTES_PER_TICK := 10
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
## 第 1 天对应的月份（4 月 1 日，春季开局）。
const START_MONTH := 4
const CHAPTER1_DAYS := 30

const WEEKDAY_NAMES := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

## 帝国节日（休市）。键为“月-日”，M1 之后可移到 data/ 中配置。
const HOLIDAYS := {}


static func weekday(day: int) -> int:
	return posmod(day - 1, 7)


static func _abs_day(day: int) -> int:
	return (START_MONTH - 1) * DAYS_PER_MONTH + day - 1


@warning_ignore("integer_division")
static func month(day: int) -> int:
	return posmod(_abs_day(day), DAYS_PER_MONTH * MONTHS_PER_YEAR) / DAYS_PER_MONTH + 1


static func day_of_month(day: int) -> int:
	return posmod(_abs_day(day), DAYS_PER_MONTH) + 1


static func is_holiday(day: int) -> bool:
	return HOLIDAYS.has("%d-%d" % [month(day), day_of_month(day)])


static func is_trading_day(day: int) -> bool:
	return weekday(day) < 5 and not is_holiday(day)


## 从 day 之后（不含 day）找到下一个交易日。
static func next_trading_day(day: int) -> int:
	var d := day + 1
	while not is_trading_day(d):
		d += 1
	return d


static func format_date(day: int) -> String:
	return "%d月%d日 %s" % [month(day), day_of_month(day), WEEKDAY_NAMES[weekday(day)]]


static func format_short_date(day: int) -> String:
	return "%d/%d" % [month(day), day_of_month(day)]


@warning_ignore("integer_division")
static func format_tick(tick: int) -> String:
	var minutes := OPEN_MINUTES + clampi(tick, 0, TICKS_PER_DAY) * MINUTES_PER_TICK
	return "%02d:%02d" % [minutes / 60, minutes % 60]


static func chapter_label(day: int) -> String:
	return "第一章 · 黎明  第 %d/%d 天" % [day, CHAPTER1_DAYS]
