extends SceneTree
## 从 Kenney「UI Pack - Pixel Adventure」（CC0）生成浅色主题用到的贴图，输出到 assets/ui/kenney/。
## 只用 Large tiles / Thin outline（32×32）；按钮、输入框的不同状态是对原图做调色板替换得到的。
## 用法：godot --headless --path . --script res://tools/build_ui_assets.gd -- [--pack <素材包目录>]
## 素材包目录默认是项目旁边的 "../UI Pack/kenney_ui-pack-pixel-adventure"。

const OUT_DIR := "res://assets/ui/kenney"

# 素材包原色
const CREAM := "fff1d2"
const ORANGE := "c58747"
const BROWN := "a3703a"
const DARK := "6d4b27"
const STEEL := "94afc6"
const STEEL_MID := "778d9f"
const STEEL_IN := "647685"
const STEEL_DARK := "515f6b"

var _large := ""
var _small := ""


func _initialize() -> void:
	var pack := ProjectSettings.globalize_path("res://").path_join("../UI Pack/kenney_ui-pack-pixel-adventure").simplify_path()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--pack")
	if i >= 0 and i + 1 < args.size():
		pack = args[i + 1]
	_large = pack.path_join("Tiles/Large tiles/Thin outline")
	_small = pack.path_join("Tiles/Small tiles/Thin outline")
	if not FileAccess.file_exists(_tile_path(_large, 0)):
		printerr("找不到素材包：", pack)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 面板：奶油色纸面 + 木框；重点面板带金属包角
	_save("panel", _tile(_large, 0))
	_save("panel_feature", _clean_nine(_tile(_large, 18), 10))
	# 普通按钮
	_save("button_hover", _swap(_tile(_large, 0), {CREAM: "fffaee", ORANGE: "d99b5a"}))
	_save("button_pressed", _tile(_large, 1))
	_save("button_disabled", _swap(_tile(_large, 0), {CREAM: "f6eedd", ORANGE: "dccbb0", BROWN: "cdb999", DARK: "b3a284"}))
	# 买入（红）/ 卖出（绿）：红涨绿跌
	var red := {ORANGE: "e2665b", BROWN: "c6594f", DARK: "8e3f38"}
	_save("button_buy", _swap(_tile(_large, 0), red.merged({CREAM: "ffe3db"})))
	_save("button_buy_hover", _swap(_tile(_large, 0), red.merged({CREAM: "fff0eb"})))
	_save("button_buy_pressed", _swap(_tile(_large, 0), red.merged({CREAM: "f5b0a3"})))
	var green := {ORANGE: "72b84e", BROWN: "5f9e40", DARK: "3d6a2a"}
	_save("button_sell", _swap(_tile(_large, 0), green.merged({CREAM: "e2f2d4"})))
	_save("button_sell_hover", _swap(_tile(_large, 0), green.merged({CREAM: "eff9e7"})))
	_save("button_sell_pressed", _swap(_tile(_large, 0), green.merged({CREAM: "badfa2"})))
	# 输入框：钢框 + 近白底；获得焦点时换成蓝框
	_save("field", _swap(_tile(_large, 2), {STEEL: "fbfdff", STEEL_MID: "b3c4d3", STEEL_IN: "9db0c1", STEEL_DARK: "71859a"}))
	_save("field_focus", _swap(_tile(_large, 2), {STEEL: "fbfdff", STEEL_MID: "5ca2e0", STEEL_IN: "4a8bc6", STEEL_DARK: "3b6891"}))
	# 标题缎带：左端 + 中段 + 右端拼成一张，九宫格拉伸中段
	_save("ribbon", _hstrip([_tile(_large, 43), _tile(_large, 44), _tile(_large, 45)]))
	var big := _hstrip([_tile(_large, 56), _tile(_large, 57), _tile(_large, 58)])
	big.resize(big.get_width() * 2, big.get_height() * 2, Image.INTERPOLATE_NEAREST)
	_save("ribbon_big", big)
	# 窗口关闭按钮（16×16 小图块）
	_save("close", _tile(_small, 4))
	# 场景底色：浅天蓝坐标纸，平铺
	var grid := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	grid.fill(Color.html("d8e9f6"))
	for k in 16:
		grid.set_pixel(k, 0, Color.html("cbdff0"))
		grid.set_pixel(0, k, Color.html("cbdff0"))
	_save("bg_grid", grid)

	var license := pack.path_join("License.txt")
	if FileAccess.file_exists(license):
		DirAccess.copy_absolute(license, ProjectSettings.globalize_path(OUT_DIR.path_join("License.txt")))
	print("已生成到 ", OUT_DIR)
	quit()


func _tile_path(dir: String, id: int) -> String:
	return dir.path_join("tile_%04d.png" % id)


func _tile(dir: String, id: int) -> Image:
	var img := Image.load_from_file(_tile_path(dir, id))
	img.convert(Image.FORMAT_RGBA8)
	return img


## 精确替换颜色（像素画只有少数几种颜色），保留透明度。
func _swap(img: Image, mapping: Dictionary) -> Image:
	var table := {}
	for k in mapping:
		table[Color.html(k).to_rgba32()] = Color.html(mapping[k])
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var key := Color(c.r, c.g, c.b, 1.0).to_rgba32()
			if table.has(key):
				var n: Color = table[key]
				img.set_pixel(x, y, Color(n.r, n.g, n.b, c.a))
	return img


## 九宫格拉伸前清理图块：四条边各取出现最多的那一列（行）铺满，中间填主色，
## 避免边上的小装饰、纸面斑点被拉成长条。m 与主题里的 texture_margin 一致。
func _clean_nine(img: Image, m: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var bands := [[0, m, true], [h - m, h, true], [0, m, false], [w - m, w, false]]
	for band in bands:
		var horizontal: bool = band[2]
		var count := {}
		var span := range(m, (w if horizontal else h) - m)
		for i in span:
			var key := _line(img, i, band[0], band[1], horizontal)
			count[key] = int(count.get(key, 0)) + 1
		var best: Array = count.keys()[0]
		for key in count:
			if count[key] > count[best]:
				best = key
		for i in span:
			for j in range(band[0], band[1]):
				var c: Color = best[j - band[0]]
				if horizontal:
					img.set_pixel(i, j, c)
				else:
					img.set_pixel(j, i, c)
	var fill := {}
	for y in range(m, h - m):
		for x in range(m, w - m):
			var c := img.get_pixel(x, y)
			fill[c] = int(fill.get(c, 0)) + 1
	var main_color: Color = fill.keys()[0]
	for c in fill:
		if fill[c] > fill[main_color]:
			main_color = c
	img.fill_rect(Rect2i(m, m, w - m * 2, h - m * 2), main_color)
	return img


## 第 i 列（horizontal）或第 i 行在 [from, to) 范围内的像素。
func _line(img: Image, i: int, from: int, to: int, horizontal: bool) -> Array:
	var out := []
	for j in range(from, to):
		out.append(img.get_pixel(i, j) if horizontal else img.get_pixel(j, i))
	return out


func _hstrip(parts: Array) -> Image:
	var w := 0
	for p: Image in parts:
		w += p.get_width()
	var out := Image.create_empty(w, parts[0].get_height(), false, Image.FORMAT_RGBA8)
	var x := 0
	for p: Image in parts:
		out.blit_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i(x, 0))
		x += p.get_width()
	return out


func _save(name: String, img: Image) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(name + ".png")))
	if err != OK:
		printerr("写入失败 ", name, "：", error_string(err))
