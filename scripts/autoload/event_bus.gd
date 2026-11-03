extends Node
## 全局信号。界面脚本只监听这些信号并读取 GameState，不直接修改别的界面。

## 新游戏开始或读档完成。
signal game_loaded
## 开盘（day 为当天日序号）。
signal market_opened(day: int)
## 每个 tick 推进后。
signal tick_advanced(tick: int)
## 收盘结算后。summary 见 GameState.close_market()。
signal market_closed(summary: Dictionary)
## 进入新的一天（开盘前）。
signal day_started(day: int)
## 成交（result 为 Portfolio.execute 的返回值）。
signal trade_executed(result: Dictionary)
## 当前选中的股票改变。
signal stock_selected(id: String)
## 在“新闻与消息”面板显示一条消息。kind: info / trade / warn / news / breaking / precursor / rumor / noelle / predict
signal message_posted(text: String, kind: String)
## 开盘前的晨报准备好了（paper 见 GameState.paper）。
signal morning_paper_ready(paper: Dictionary)
## 盘中突发快讯（item 见 events.gd 的条目格式）。
signal breaking_news(item: Dictionary)
## 主角的体力、压力、情绪或身体状态变化。
signal player_changed
## 走势预测完成（pred 见 predict.gd）。
signal prediction_made(pred: Dictionary)
## 还款后负债变化。
signal debt_changed(debt: float)
## 第一章结束：提前还清，或期限那天收盘结算。result 见 GameState._finish_chapter()。
signal chapter_finished(result: Dictionary)
## 需要播放一段教学 / 剧情对话（id 为 data/dialogues/tutorial.json 里的键）。
signal tutorial_requested(id: String)
## 存档完成。
signal game_saved(path: String, is_auto: bool)
## 播放速度改变（0 = 暂停）。
signal speed_changed(speed: int)
