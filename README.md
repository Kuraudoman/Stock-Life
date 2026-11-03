# Stock-Life

2D 二次元风格的轻量 PC 股市模拟游戏（工作名）。玩家在赫尔墨斯帝国首都奥鲁姆，扮演背负 50,000 金币债务的见习交易员希雅，靠读新闻、交朋友、低买高卖成为“帝国股神”。

完整设计见 [docs/GDD.md](docs/GDD.md)。

## 当前版本：v0.2.0 · M1 MVP

| M1 目标 | 状态 | 说明 |
|---|---|---|
| 新闻与前兆 | ✅ | 《金穗日报》晨报 3–5 条（要闻 / 市场 / 街谈巷议 / 杂谈）；盘中突发快讯（自动暂停 + 顶部横幅）；事件前 1–5 个交易日出现前兆，带方向的前兆当天有成交放大；季度财报、铸币局利率决议、12 种行业 / 世界事件、4 种真假参半的传闻；事件日期在小范围内随机、按种子可复现；K 线上标出发生过新闻的日子 |
| 诺艾尔对话与教学 | ✅ | 对话框（双方立绘 + 逐字显示 + 选项）；开场剧情与 9 段情境教学（读报、开盘、快讯、前兆应验、预测、结算、周末、状态、期限）；每日点评；晚间「复盘」给出接下来几天的风声分析，好感越高越准、还会提示时间 |
| 状态立绘与走势预测 | ✅ | 主角 5 种情绪 × 5 种身体状态，占位立绘按 GDD 第 9 节画出表情与道具（V 字手势、金币眼、冷汗、黑眼圈、口罩毯子、冰袋、病号服）；点击立绘预测（今天收盘前 / 到明天收盘 / 未来 3 个交易日），用同一随机数状态推演真实走势，再按状态决定说对还是说反；到期自动回顾说中没有；看板娘 6 种表情 |
| 第一章 30 天与胜负 | ✅ | 期限 4 月 30 日收盘；顶栏「还款」随时还债，还清即通关；期限当天自动清算持仓抵债，不够即失败（失败时不覆盖自动存档，可回到前一天重试）；通关后可继续自由交易 |
| 门槛：试玩者愿意玩完 30 天 | ⏳ | 需要真人试玩。`tools/simulate.gd` 的策略对比见下文“平衡” |

另外：日结算（盈亏、净资产曲线与还清线、状态变化）、体力 / 压力 / 感冒 / 发烧 / 住院、主角改名、教学开关、涨停金币雨与暴跌震屏。

主角、诺艾尔、渡鸦夫人和看板娘的立绘仍是代码画的占位图（`scripts/ui/portrait_painter.gd`），正式美术、音效、晚间城市地图、杠杆做空属于 M2 以后。

## 运行

1. 安装 **Godot 4.7.2**（标准版，非 .NET 版）。项目使用 GL Compatibility 渲染器。
2. 用 Godot 打开 `project.godot`，按 F5 运行。

### 怎么玩

- 每天开盘前先读晨报。「要闻」已经反映在开盘价里；「市场」栏的风声才是前兆——真正的消息 1–5 个交易日后出现，但不会说是哪天。传闻真假参半。
- 右下角「开盘」开始一天；空格键暂停 / 继续，「快进到收盘」直接跳到 15:00。盘中出快讯会自动暂停。
- 点左上角的主角立绘请她预测走势。她的准确度取决于状态标签和脸色：平静健康时最靠谱，狂热、恐慌、生病时会离谱甚至说反，界面不显示准确率。每天最多 3 次，每次消耗体力。
- 收盘后选择晚间安排：「早点休息」恢复体力，或「和诺艾尔复盘」听她分析接下来的风声（好感 +3）。
- 顶栏「还款」把现金还给黑鸦商会，还清 50,000 即通关。期限是 4 月 30 日收盘。

颜色约定：**红涨绿跌**。

## 测试与平衡

```bash
# 自动测试（88 项：日历、价格模型、交易规则、事件冲击、新闻日程与前兆、主角状态、走势预测、
# 诺艾尔的分析、第一章胜负、存档往返与版本 1 → 2 迁移）
godot --headless --path . --script res://tools/run_tests.gd

# 批量跑行情（含新闻事件）+ 第一章策略对比
godot --headless --path . --script res://tools/simulate.gd -- --runs 500
godot --headless --path . --script res://tools/simulate.gd -- --runs 300 --market 0 --cash 35000
```

Windows 上把 `godot` 换成 `Godot_v4.7.2-stable_win64_console.exe` 的路径。

### 数据文件

改数值和文案都不用改代码，改完重跑 `simulate.gd` 看效果：

| 文件 | 内容 |
|---|---|
| `data/companies.json` | 5 家公司：价格、波动率 sigma、均值回归 kappa、流动性等 |
| `data/chapter1.json` | 第一章：起始现金、债务、期限、初始好感 |
| `data/events.json` | 新闻事件：财报、利率决议、事件池、传闻、花边新闻；每条的冲击幅度、前兆文字、出现权重 |
| `data/characters.json` | 角色名字与占位立绘配色、看板娘头饰 |
| `data/dialogues/tutorial.json` | 开场剧情、教学、结局对话 |
| `data/dialogues/noelle.json` | 诺艾尔的点评、状态提醒、复盘分析句式 |
| `data/dialogues/heroine.json` | 主角的预测台词（按情绪和结果分组） |

### 平衡

`simulate.gd` 用 6 种机器人各跑第一章（只用玩家看得到的信息），期限收盘时的清算价值 ≥ 50,000 算赢。400 局的结果：

| 策略 | 胜率 | 清算价值中位数 | P90 | 说明 |
|---|---|---|---|---|
| 持有不动 | 9.0% | 1.12 倍 | 1.24 倍 | 开局等权买入 5 支股票 |
| 随机买卖 | 0.0% | 0.94 倍 | 1.07 倍 | 手续费和滑点吃掉一切 |
| 只听预测 | 10.5% | 1.00 倍 | 1.25 倍 | 每天问 3 次“今天收盘前”，买她说涨的；平均说中 60% |
| 反着听预测 | 0.0% | 0.75 倍 | 0.93 倍 | 不看状态一律反着听 |
| 读报 | 76.8% | 1.39 倍 | 1.70 倍 | 看到带方向的前兆就买，消息出来后第二天卖，盘中快讯追利好、躲利空 |
| 读报 + 预测 | 76.3% | 1.37 倍 | 1.64 倍 | 买之前问一次，她说跌就放弃 |

GDD 初稿的起始现金是 10,000（要翻 5 倍）。模拟显示连“读报”机器人的中位数都只有 1.4 倍左右，5 倍在 22 个交易日里几乎不可能，所以起始现金暂定 **40,000**（债务仍是 50,000，需要赚 25%）：会读报的玩家大多能赢，只持有、乱买、只听预测基本赢不了，符合 GDD 第 13 节的目标。数值在 `data/chapter1.json`，试玩后再调。

## 界面素材

界面贴图来自 Kenney 的 [UI Pack - Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure)（CC0，许可见 `assets/ui/kenney/License.txt`），只用 Large tiles / Thin outline，按 1:1 像素显示（项目已设为最近邻采样）。按钮各状态、买入红 / 卖出绿、输入框是对原图做调色板替换生成的。

素材包放在项目旁边的 `UI Pack/kenney_ui-pack-pixel-adventure`，改了配色或换了图块后重新生成：

```bash
godot --headless --path . --script res://tools/build_ui_assets.gd -- --pack "../UI Pack/kenney_ui-pack-pixel-adventure"
```

代码里用到的颜色集中在 `scripts/ui/ui_style.gd`。主题里的变体：`FeaturePanel`（带金属包角的重点面板）、`RibbonLabel` / `RibbonTitle`（红色缎带标题）、`BuyButton` / `SellButton`、`StockRow`。

## 存档

| 运行方式 | saves 文件夹位置 |
|---|---|
| 在 Godot 编辑器中运行 | 项目根目录下的 `saves/` |
| 导出的游戏（Windows / Linux） | 可执行文件所在目录下的 `saves/` |
| macOS 导出版，或游戏目录不可写 | 用户数据目录 `user://saves`（标题界面会显示实际路径） |

- 文件名 `<存档名>.stocklife.json`；顶栏「存档」写入 `slot1`，每天收盘自动写入 `autosave`（第一章失败那天除外）。
- 把存档文件复制到另一台电脑的 saves 文件夹即可继续游戏。
- 存档里保存了随机数状态和事件日程，读档后的行情、新闻与不中断时完全一致。
- 存档版本 2（M1）。M0 的版本 1 存档会自动升级：按种子补上事件日程，已经过去的消息当作发生过，跳过开场剧情（起始现金保持旧存档里的数值）。

## 导出 Windows 版本

1. 编辑器菜单「编辑器 → 管理导出模板」，下载 4.7.2 的导出模板。
2. 「项目 → 导出」，选择已配置好的 **Windows Desktop** 预设，导出到 `build/Stock-Life.exe`（单个 exe，已内嵌 pck）。
3. 发布压缩包时附带一个空的 `saves` 文件夹。

## 项目结构

```text
stock-life/
├── project.godot
├── scenes/
│   ├── title.tscn            # 标题与存档槽
│   ├── main.tscn             # 交易主界面
│   ├── dialog.tscn           # 角色对话
│   └── ui/
│       ├── morning_paper.tscn  # 晨报
│       ├── predict_popup.tscn  # 走势预测
│       ├── day_summary.tscn    # 日结算与晚间安排
│       ├── chapter_end.tscn    # 第一章结局
│       └── repay_dialog.tscn   # 还款
├── scripts/
│   ├── autoload/
│   │   ├── event_bus.gd      # 全局信号
│   │   ├── game_state.gd     # 游戏状态、一天的流程（晨报 → 开盘 → tick → 收盘 → 晚间 → 下一天）、第一章胜负
│   │   └── save_manager.gd   # 存档读写、校验、版本迁移
│   ├── core/                 # 纯逻辑，不依赖场景节点，可无界面测试
│   │   ├── calendar.gd       # 日历、tick、休市
│   │   ├── market.gd         # 价格模型、报价、滑点与冲击（跳空 / 平摊 / 快讯急涨急跌）
│   │   ├── portfolio.gd      # 现金、负债、持仓、成交、还款、清算
│   │   ├── events.gd         # 新闻、传闻、前兆，事件时间窗口调度
│   │   ├── life.gd           # 体力、压力、情绪与身体状态
│   │   ├── predict.gd        # 主角走势预测
│   │   └── noelle.gd         # 诺艾尔的点评与分析
│   └── ui/
│       ├── main.gd           # 主界面、游戏时钟、弹出层队列
│       ├── title.gd          # 标题界面
│       ├── candle_chart.gd   # K 线 / 分时图（_draw 自绘），新闻标记
│       ├── stock_board.gd    # 股票列表
│       ├── heroine_portrait.gd  # 主角状态立绘
│       ├── mascot_view.gd    # 看板娘
│       ├── portrait_painter.gd  # 占位立绘：底图 + 表情层 + 状态叠加层
│       ├── portrait_view.gd  # 可复用的立绘框
│       ├── overlay.gd        # 弹出层基类
│       ├── dialog_box.gd / morning_paper.gd / predict_popup.gd / day_summary.gd / chapter_end.gd / repay_dialog.gd
│       ├── net_worth_chart.gd   # 净资产曲线
│       ├── fx_layer.gd       # 涨停金币雨、暴跌震屏
│       └── ui_style.gd       # 配色与格式化
├── data/                     # 见上文“数据文件”
├── assets/ui/
│   ├── theme.tres            # 浅色像素主题：奶油纸面 + 木框 + 天空蓝底，中文使用系统字体
│   └── kenney/               # 界面贴图，由 tools/build_ui_assets.gd 从 Kenney 素材包生成（CC0）
├── saves/                    # 编辑器运行时的存档（不提交）
├── tools/
│   ├── run_tests.gd          # 自动测试
│   ├── build_ui_assets.gd    # 从 Kenney UI Pack 生成界面贴图
│   └── simulate.gd           # 批量行情模拟与第一章策略对比
└── docs/GDD.md               # 设计文档
```

GDD 里的 `city_map.tscn`（晚间城市地图）、`trade_panel.gd` 属于 M2。

## 给 M2 预留的接口

- `GameState.choose_evening(choice)`：晚间安排，M1 只有 `rest` / `review`，M2 的城市地图在这里加行动。
- `Life.sleep()` / `Life.end_trading_day()`：体力、压力、疾病与情绪的规则集中在 `life.gd`，住所等级等加成从这里接。
- `GameState.affection`：已存档，`add_affection()` 修改；诺艾尔的分析质量随好感变化（`noelle.gd`），米娅的独家消息可以照同样方式接 `events.upcoming_clues()`。
- `Market.set_phase("dawn" | "boom" | "mania" | "crash")`：经济阶段。第二章起在 `data/chapterN.json` 里指定。
- `player.heat`（调查度）、`player.exp`（学院进修，最多 +10% 预测正确率）已在存档里。

## 版本管理

- `main` 分支始终能在编辑器中运行，日常开发在 `dev`。
- 每个里程碑打标签（M0 = `v0.1.0`，M1 = `v0.2.0`），在 GitHub Releases 上传 Windows 压缩包。
- 开源许可尚未确定（见 GDD 待定事项），暂未附 LICENSE。
