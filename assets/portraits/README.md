# 立绘文件

每个角色一个目录：`assets/portraits/<角色 id>/`。希雅是 `heroine`。没有图的角色仍用代码画的占位半身像。

同一张表情准备两套，构图必须对齐（脸在画面里的位置一样），这样切换时不会跳：

| 文件 | 内容 |
|---|---|
| `<表情>.png` | 不带描边 |
| `<表情>_outline.png` | 描边已经画在图里 |

用哪一套由 `data/ui.json` 的 `portrait_outline` 决定。`true` 先找 `_outline`，`false` 先找不带描边的。选中的那张不存在，就用另一套；这个表情两套都没有，再试 `smile`，然后 `normal`；还是没有，才退回占位画法。

现在仓库里的希雅图是不带描边的一套，所以 `portrait_outline` 先设为 `false`。带描边的文件交来之后，把开关改成 `true` 即可，不用改代码。

## 希雅的 11 张

建议尺寸 **864×1152**，透明背景的 PNG，和现在这套的取景一致（半身，腰以上，脸的位置对齐）。

- `smile.png` / `smile_outline.png` — 平静
- `grin.png` / `grin_outline.png` — 乐观
- `frown.png` / `frown_outline.png` — 悲观
- `coin.png` / `coin_outline.png` — 狂热
- `panic.png` / `panic_outline.png` — 恐慌
- `sleepy.png` / `sleepy_outline.png` — 疲劳
- `cold.png` / `cold_outline.png` — 感冒
- `dizzy.png` / `dizzy_outline.png` — 发烧
- `hospital.png` / `hospital_outline.png` — 住院
- `cry.png` / `cry_outline.png` — 对话里的哭（失败）
- `ecstatic.png` / `ecstatic_outline.png` — 结局里的高兴

`frown` 的人物比其他几张低大约 90 像素。代码会把顶部这截空白让掉（`portrait_painter.gd` 里的 `TOP_PAD`），头才和别的表情齐。新画的悲观图如果还是这个构图，两套都不用改代码；如果头已经对齐，把这个偏移去掉。

身体状态优先于情绪：住院、发烧、感冒、疲劳各用自己的整张图，健康时才按平静 / 乐观 / 悲观 / 狂热 / 恐慌换。

导入时生成 mipmap，绘制时用线性过滤。不是像素素材。
