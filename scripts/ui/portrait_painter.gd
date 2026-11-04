extends RefCounted
## 立绘绘制：有正式立绘就画图，没有就按角色配色画 Q 版占位半身像（GDD 第 9 节“MVP 占位”）。
## 正式立绘放在 assets/portraits/<角色 id 或公司 id>/ 下：
##   <表情名>.png          不带描边
##   <表情名>_outline.png  画好描边的同一张
## 用哪一套由 data/ui.json 的 portrait_outline 决定。选中的那张没有，就换另一套，
## 再退回 smile / normal，整个目录都没有图时退回占位画法。
## 主角按身体优先：hospital / dizzy / cold / sleepy，否则按情绪 smile / grin / frown / coin / panic。
## 整张图已经包含道具，不再叠 fx_。fx_<叠加层>.png 只给占位画法用。

const UI := preload("res://scripts/ui/ui_style.gd")

const PORTRAIT_DIR := "res://assets/portraits"
const UI_PATH := "res://data/ui.json"
## 缺表情时依次尝试的默认表情。
const DEFAULT_EXPRS := ["smile", "normal"]

static var _textures := {}
static var _ui_loaded := false
static var _ui: Dictionary = {}

const SKIN := Color(1.0, 0.91, 0.83)
const SKIN_SHADE := Color(0.93, 0.76, 0.66)
const INK := Color(0.29, 0.2, 0.15)
const MOUTH := Color(0.72, 0.3, 0.3)
const BLUSH := Color(0.95, 0.48, 0.48, 0.45)
const TEAR := Color(0.45, 0.72, 0.95, 0.9)
const GOLD := Color(0.98, 0.78, 0.22)


## 角色配色：从 characters.json 的条目（html 颜色字符串）转成 Color。id 用来找正式立绘。
static func look_of(c: Dictionary, id: String = "", fallback_hair: String = "#c8a070") -> Dictionary:
	return {
		"id": id,
		"hair": Color.html(String(c.get("hair", fallback_hair))),
		"eyes": Color.html(String(c.get("eyes", "#4a6a9a"))),
		"outfit": Color.html(String(c.get("outfit", "#6a6a8a"))),
		"accent": Color.html(String(c.get("accent", "#e0c080"))),
		"feature": String(c.get("feature", "")),
	}


## 看板娘：发色用公司主题色。
static func mascot_look(company: Dictionary, feature: String) -> Dictionary:
	var col := Color.html(String(company.get("color", "#cccccc")))
	return {
		"id": String(company.get("id", "")),
		"hair": col.darkened(0.1), "eyes": col.darkened(0.45), "outfit": col.darkened(0.3),
		"accent": col.lightened(0.45), "feature": feature,
	}


## frown.png 的人物比其他几张低大约 90 像素，裁切时把这截空白让掉，头才对齐。
const TOP_PAD := {"frown": 90.0}


## 主角的情绪 / 身体状态 → 整张立绘。身体优先于情绪；有图就不加占位用的叠加层。
static func heroine_layers(mood: String, body: String) -> Dictionary:
	var expr := _heroine_expr(mood, body)
	var resolved := resolve_texture("heroine", expr, [])
	if resolved.tex != null:
		return {"expr": String(resolved.name), "overlays": []}
	return _heroine_placeholder(mood, body)


static func _heroine_expr(mood: String, body: String) -> String:
	match body:
		"hospital":
			return "hospital"
		"fever":
			return "dizzy"
		"cold":
			return "cold"
		"tired":
			return "sleepy"
	match mood:
		"optimistic":
			return "grin"
		"pessimistic":
			return "frown"
		"manic":
			return "coin"
		"panic":
			return "panic"
	return "smile"


## 没有正式立绘时的占位组合（Q 版 + 道具）。
static func _heroine_placeholder(mood: String, body: String) -> Dictionary:
	var expr := "smile"
	var overlays: Array = []
	match mood:
		"optimistic":
			expr = "grin"
			overlays.append("v_sign")
		"pessimistic":
			expr = "frown"
			overlays.append("sigh")
		"manic":
			expr = "coin"
			overlays.append_array(["flush", "fist", "sparkle"])
		"panic":
			expr = "panic"
			overlays.append_array(["sweat", "hands_head"])
	match body:
		"tired":
			if expr == "smile":
				expr = "sleepy"
			overlays.append("eyebags")
		"cold":
			overlays.append_array(["blanket", "mask"])
		"fever":
			expr = "dizzy"
			overlays = ["flush_full", "icepack", "blanket"]
		"hospital":
			expr = "sleepy"
			overlays = ["pajama"]
	return {"expr": expr, "overlays": overlays}


## 看板娘表情名（ui_style.mascot_expression 的 name）→ 表情与叠加层。
static func mascot_layers(name: String) -> Dictionary:
	match name:
		"狂喜":
			return {"expr": "ecstatic", "overlays": ["sparkle", "flush"]}
		"开心":
			return {"expr": "happy", "overlays": []}
		"担忧":
			return {"expr": "worried", "overlays": ["sweat"]}
		"哭泣":
			return {"expr": "cry", "overlays": []}
		"崩溃":
			return {"expr": "broken", "overlays": []}
	return {"expr": "smile", "overlays": []}


static func ui_config() -> Dictionary:
	if not _ui_loaded:
		_ui_loaded = true
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(UI_PATH))
		_ui = raw if typeof(raw) == TYPE_DICTIONARY else {}
	return _ui


## data/ui.json 的 portrait_outline。true 时优先带描边的文件。
static func wants_outline() -> bool:
	return bool(ui_config().get("portrait_outline", false))


## 同一个表情的两套文件名。outlined 为 true 时 _outline 排在前面。
static func variant_stems(expr: String, outlined: bool) -> PackedStringArray:
	var plain := expr
	var lined := "%s_outline" % expr
	if outlined:
		return PackedStringArray([lined, plain])
	return PackedStringArray([plain, lined])


## 正式立绘：assets/portraits/<who>/<name>.png，没有返回 null。name 可以已经带 _outline。结果会缓存。
static func texture(who: String, name: String) -> Texture2D:
	var path := "%s/%s/%s.png" % [PORTRAIT_DIR, who, name]
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## 选整张立绘。住院、感冒的整图排在表情名前面（感冒以前只靠毯子和口罩叠加）。
## 没有对应文件时退回 smile / normal。
static func base_texture(who: String, expr: String, overlays: Array = []) -> Texture2D:
	return resolve_texture(who, expr, overlays).tex


static func resolve_texture(who: String, expr: String, overlays: Array = []) -> Dictionary:
	return resolve_prefer(who, expr, overlays, wants_outline())


## outlined 显式指定要不要描边版，测试用。游戏里走 resolve_texture。
## 返回 name 是表情名（frown，不是 frown_outline），file 是实际加载的文件名。
static func resolve_prefer(who: String, expr: String, overlays: Array, outlined: bool) -> Dictionary:
	if who == "":
		return {"tex": null, "name": "", "file": ""}
	var names: Array = []
	if overlays.has("pajama") or expr == "hospital":
		names.append("hospital")
	if expr == "cold" or (overlays.has("mask") and overlays.has("blanket")):
		names.append("cold")
	names.append(expr)
	names.append_array(DEFAULT_EXPRS)
	var seen := {}
	for n in names:
		var key := String(n)
		if seen.has(key):
			continue
		seen[key] = true
		for stem in variant_stems(key, outlined):
			var tex := texture(who, stem)
			if tex:
				return {"tex": tex, "name": key, "file": stem}
	return {"tex": null, "name": "", "file": ""}


## 在 r 里画一个角色。dim=true 时把角色本身压暗（不铺底色块）。
## tint 是看板娘涨跌的色调，乘在角色上，不再画在背景上。
static func draw(ci: CanvasItem, r: Rect2, look: Dictionary, expr: String, overlays: Array = [], dim: bool = false, tint: Color = Color(0, 0, 0, 0)) -> void:
	_apply_modulate(ci, dim, tint)
	var who := String(look.get("id", ""))
	var resolved := resolve_texture(who, expr, overlays)
	var base: Texture2D = resolved.tex
	if base:
		var prev_filter := ci.texture_filter
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ci.material = null
		_draw_fitted(ci, r, base, float(TOP_PAD.get(String(resolved.name), 0.0)))
		ci.texture_filter = prev_filter
		return
	ci.material = null
	var R :=minf(r.size.x * 0.27, r.size.y * 0.2)
	var c := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.42)
	var hair: Color = look.hair
	var outfit: Color = look.outfit
	var accent: Color = look.accent
	var feature := String(look.get("feature", ""))
	if overlays.has("pajama"):
		outfit = Color(0.66, 0.8, 0.92)
	# 后发
	_blob(ci, c + Vector2(0, R * 0.1), R * 1.2, R * 1.25, hair.darkened(0.12))
	ci.draw_rect(Rect2(c.x - R * 1.2, c.y, R * 2.4, R * 1.55), hair.darkened(0.12), true)
	# 身体
	var neck_y := c.y + R * 0.85
	var bottom := r.end.y
	ci.draw_rect(Rect2(c.x - R * 0.22, neck_y, R * 0.44, R * 0.5), SKIN_SHADE, true)
	var body := PackedVector2Array([
		Vector2(c.x - R * 1.05, neck_y + R * 0.4), Vector2(c.x + R * 1.05, neck_y + R * 0.4),
		Vector2(c.x + R * 1.9, bottom), Vector2(c.x - R * 1.9, bottom),
	])
	ci.draw_colored_polygon(body, outfit)
	ci.draw_polyline(PackedVector2Array([body[3], body[0], body[1], body[2]]), outfit.darkened(0.35), 1.5)
	if overlays.has("pajama"):
		var x := c.x - R * 1.6
		while x < c.x + R * 1.7:
			ci.draw_line(Vector2(x, neck_y + R * 0.7), Vector2(x, bottom), Color(1, 1, 1, 0.7), 2.0)
			x += R * 0.4
	else:
		# 领口
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - R * 0.5, neck_y + R * 0.4), Vector2(c.x + R * 0.5, neck_y + R * 0.4), Vector2(c.x, neck_y + R * 1.05),
		]), accent)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - R * 0.28, neck_y + R * 0.4), Vector2(c.x + R * 0.28, neck_y + R * 0.4), Vector2(c.x, neck_y + R * 0.75),
		]), SKIN_SHADE)
	# 精灵耳 / 猫耳在头后面
	if feature == "elf":
		for s in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * R * 0.85, -R * 0.1), c + Vector2(s * R * 1.65, -R * 0.55), c + Vector2(s * R * 0.9, R * 0.3),
			]), SKIN_SHADE)
	if feature == "cat":
		for s in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * R * 0.35, -R * 0.85), c + Vector2(s * R * 0.95, -R * 1.45), c + Vector2(s * R * 1.0, -R * 0.45),
			]), hair)
	if feature == "horns":
		for s in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * R * 0.45, -R * 0.8), c + Vector2(s * R * 0.95, -R * 1.5), c + Vector2(s * R * 0.75, -R * 0.65),
			]), Color(0.93, 0.88, 0.76))
	# 头
	ci.draw_circle(c, R, SKIN)
	ci.draw_arc(c, R, 0.0, TAU, 40, INK.lightened(0.3), 1.0, true)
	if overlays.has("flush_full"):
		ci.draw_circle(c + Vector2(0, R * 0.15), R * 0.85, Color(0.95, 0.35, 0.3, 0.28))
	# 刘海
	var bangs := PackedVector2Array()
	for i in 13:
		var a := lerpf(PI * 1.02, PI * 1.98, float(i) / 12.0)
		bangs.append(c + Vector2(cos(a), sin(a)) * R * 1.08)
	var teeth := 5
	for i in range(teeth * 2, -1, -1):
		var t := float(i) / (teeth * 2)
		var x := lerpf(c.x - R * 1.02, c.x + R * 1.02, t)
		var y := c.y - R * (0.15 if i % 2 == 0 else 0.42)
		bangs.append(Vector2(x, y))
	ci.draw_colored_polygon(bangs, hair)
	# 表情
	_face(ci, c, R, look, expr)
	# 腮红
	if overlays.has("flush") or overlays.has("flush_full") or expr in ["grin", "happy", "ecstatic", "coin"]:
		var a := 0.75 if overlays.has("flush") or overlays.has("flush_full") else 0.45
		for s in [-1.0, 1.0]:
			_blob(ci, c + Vector2(s * R * 0.55, R * 0.42), R * 0.17, R * 0.09, Color(BLUSH, a))
	# 头饰
	_feature(ci, c, R, look, feature)
	# 身体状态叠加层
	for o in overlays:
		_overlay(ci, c, R, r, look, String(o))
## 不说话时压暗角色本身。看板娘的涨跌色调也乘在角色上，不再铺一块底。
static func _apply_modulate(ci: CanvasItem, dim: bool, tint: Color) -> void:
	var m := Color.WHITE
	if dim:
		m = Color(0.62, 0.64, 0.7, 0.88)
	if tint.a > 0.001:
		m = m.lerp(Color(tint.r, tint.g, tint.b, 1.0), clampf(tint.a, 0.0, 0.75))
	ci.modulate = m


## 把立绘铺满 r：等比放大到盖住整个框，水平居中。top_pad 是这张图顶部多出来的空白，
## 裁切从那里开始，头才和别的表情齐。多出来的部分裁掉。
static func _draw_fitted(ci: CanvasItem, r: Rect2, tex: Texture2D, top_pad: float = 0.0) -> void:
	var ts := tex.get_size()
	var pad := clampf(top_pad, 0.0, ts.y * 0.25)
	var usable_h := ts.y - pad
	var scale := maxf(r.size.x / ts.x, r.size.y / usable_h)
	var src_size := Vector2(minf(r.size.x / scale, ts.x), minf(r.size.y / scale, usable_h))
	var origin := Vector2((ts.x - src_size.x) * 0.5, pad)
	ci.draw_texture_rect_region(tex, r, Rect2(origin, src_size))


static func _face(ci: CanvasItem, c: Vector2, R: float, look: Dictionary, expr: String) -> void:
	var eye_col: Color = look.eyes
	var el := c + Vector2(-R * 0.38, R * 0.15)
	var er := c + Vector2(R * 0.38, R * 0.15)
	var mouth := c + Vector2(0, R * 0.55)
	var w := maxf(1.2, R * 0.06)
	match expr:
		"grin", "happy", "ecstatic":
			for e in [el, er]:
				ci.draw_arc(e + Vector2(0, R * 0.05), R * 0.13, PI * 1.1, PI * 1.9, 10, INK, w, true)
			_open_mouth(ci, mouth, R * 0.2, R * 0.16)
			if expr == "ecstatic":
				for e in [el, er]:
					_star(ci, e + Vector2(0, -R * 0.05), R * 0.08, GOLD)
		"frown", "worried":
			for e in [el, er]:
				_eye(ci, e + Vector2(0, R * 0.04), R, eye_col, 0.6)
			ci.draw_line(el + Vector2(-R * 0.15, -R * 0.2), el + Vector2(R * 0.12, -R * 0.28), INK, w)
			ci.draw_line(er + Vector2(R * 0.15, -R * 0.2), er + Vector2(-R * 0.12, -R * 0.28), INK, w)
			if expr == "worried":
				_wave(ci, mouth + Vector2(0, R * 0.02), R * 0.18, R * 0.03, INK, w)
			else:
				ci.draw_arc(mouth + Vector2(0, R * 0.14), R * 0.15, PI * 1.2, PI * 1.8, 10, INK, w, true)
		"coin":
			for e in [el, er]:
				ci.draw_circle(e, R * 0.15, GOLD)
				ci.draw_arc(e, R * 0.15, 0.0, TAU, 16, Color(0.75, 0.5, 0.05), w, true)
				ci.draw_line(e + Vector2(0, -R * 0.09), e + Vector2(0, R * 0.09), Color(0.75, 0.5, 0.05), w)
				ci.draw_circle(e + Vector2(-R * 0.05, -R * 0.06), R * 0.03, Color.WHITE)
			_open_mouth(ci, mouth, R * 0.22, R * 0.15)
		"panic":
			for e in [el, er]:
				ci.draw_circle(e, R * 0.14, Color.WHITE)
				ci.draw_arc(e, R * 0.14, 0.0, TAU, 16, INK, w * 0.8, true)
				ci.draw_circle(e, R * 0.04, INK)
			ci.draw_line(el + Vector2(-R * 0.14, -R * 0.24), el + Vector2(R * 0.12, -R * 0.3), INK, w)
			ci.draw_line(er + Vector2(R * 0.14, -R * 0.24), er + Vector2(-R * 0.12, -R * 0.3), INK, w)
			_blob(ci, mouth + Vector2(0, R * 0.04), R * 0.1, R * 0.13, MOUTH.darkened(0.3))
		"cry":
			for e in [el, er]:
				ci.draw_arc(e, R * 0.12, PI * 0.1, PI * 0.9, 10, INK, w, true)
				ci.draw_rect(Rect2(e.x - R * 0.05, e.y + R * 0.08, R * 0.1, R * 0.55), TEAR, true)
			_open_mouth(ci, mouth + Vector2(0, R * 0.04), R * 0.16, R * 0.12)
		"sleepy":
			for e in [el, er]:
				ci.draw_line(e + Vector2(-R * 0.13, 0), e + Vector2(R * 0.13, 0), INK, w)
				ci.draw_arc(e + Vector2(0, -R * 0.02), R * 0.13, PI * 0.15, PI * 0.85, 8, INK, w * 0.8, true)
			_blob(ci, mouth + Vector2(0, R * 0.03), R * 0.07, R * 0.09, MOUTH.darkened(0.2))
		"dizzy":
			for e in [el, er]:
				_spiral(ci, e, R * 0.14, INK, w * 0.8)
			_wave(ci, mouth, R * 0.16, R * 0.035, INK, w)
		"smug", "annoyed":
			for e in [el, er]:
				_eye(ci, e, R, eye_col, 0.0)
				ci.draw_rect(Rect2(e.x - R * 0.16, e.y - R * 0.22, R * 0.32, R * 0.16), SKIN, true)
				ci.draw_line(e + Vector2(-R * 0.15, -R * 0.06), e + Vector2(R * 0.15, -R * 0.06), INK, w)
			if expr == "smug":
				ci.draw_arc(mouth + Vector2(R * 0.04, -R * 0.06), R * 0.12, PI * 0.15, PI * 0.75, 8, INK, w, true)
			else:
				ci.draw_line(mouth + Vector2(-R * 0.1, 0), mouth + Vector2(R * 0.1, 0), INK, w)
				ci.draw_line(el + Vector2(-R * 0.14, -R * 0.3), el + Vector2(R * 0.14, -R * 0.24), INK, w)
				ci.draw_line(er + Vector2(R * 0.14, -R * 0.3), er + Vector2(-R * 0.14, -R * 0.24), INK, w)
		"surprised":
			for e in [el, er]:
				_eye(ci, e, R * 1.15, eye_col, 0.0)
			ci.draw_arc(mouth + Vector2(0, R * 0.03), R * 0.08, 0.0, TAU, 12, INK, w, true)
		"broken":
			for e in [el, er]:
				ci.draw_arc(e, R * 0.12, 0.0, TAU, 14, INK, w, true)
			_wave(ci, mouth + Vector2(0, R * 0.03), R * 0.2, R * 0.05, INK, w)
		"normal":
			for e in [el, er]:
				_eye(ci, e, R, eye_col, 0.0)
			ci.draw_line(mouth + Vector2(-R * 0.08, 0), mouth + Vector2(R * 0.08, 0), INK, w)
		_:  # smile
			for e in [el, er]:
				_eye(ci, e, R, eye_col, 0.0)
			ci.draw_arc(mouth + Vector2(0, -R * 0.1), R * 0.14, PI * 0.2, PI * 0.8, 10, INK, w, true)


## 睁开的眼睛：彩色椭圆 + 高光 + 上眼线。look_down 让瞳孔往下（垂头丧气）。
static func _eye(ci: CanvasItem, e: Vector2, R: float, col: Color, look_down: float) -> void:
	_blob(ci, e, R * 0.11, R * 0.15, col)
	_blob(ci, e + Vector2(0, R * 0.04 * (1.0 + look_down)), R * 0.06, R * 0.08, col.darkened(0.45))
	ci.draw_circle(e + Vector2(-R * 0.04, -R * 0.06), R * 0.035, Color.WHITE)
	ci.draw_arc(e, R * 0.14, PI * 1.15, PI * 1.85, 8, INK, maxf(1.2, R * 0.06), true)


static func _open_mouth(ci: CanvasItem, m: Vector2, w: float, h: float) -> void:
	var pts := PackedVector2Array([m + Vector2(-w, -h * 0.3), m + Vector2(w, -h * 0.3)])
	for i in 9:
		var a := lerpf(0.0, PI, float(i) / 8.0)
		pts.append(m + Vector2(cos(a) * w, -h * 0.3 + sin(a) * h * 1.2))
	ci.draw_colored_polygon(pts, MOUTH.darkened(0.25))
	_blob(ci, m + Vector2(0, h * 0.55), w * 0.5, h * 0.3, Color(0.95, 0.55, 0.55))


static func _feature(ci: CanvasItem, c: Vector2, R: float, look: Dictionary, feature: String) -> void:
	var accent: Color = look.accent
	match feature:
		"ribbon":
			var k := c + Vector2(R * 0.7, -R * 0.75)
			ci.draw_colored_polygon(PackedVector2Array([k, k + Vector2(-R * 0.35, -R * 0.25), k + Vector2(-R * 0.35, R * 0.22)]), accent)
			ci.draw_colored_polygon(PackedVector2Array([k, k + Vector2(R * 0.35, -R * 0.25), k + Vector2(R * 0.35, R * 0.22)]), accent)
			ci.draw_circle(k, R * 0.09, accent.darkened(0.2))
		"elf":
			# 眼镜
			for s in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(s * R * 0.38, R * 0.15), R * 0.2, 0.0, TAU, 16, accent.darkened(0.3), maxf(1.2, R * 0.05), true)
			ci.draw_line(c + Vector2(-R * 0.18, R * 0.12), c + Vector2(R * 0.18, R * 0.12), accent.darkened(0.3), maxf(1.0, R * 0.04))
		"veil":
			var pts := PackedVector2Array()
			for i in 11:
				var a := lerpf(PI * 1.05, PI * 1.95, float(i) / 10.0)
				pts.append(c + Vector2(cos(a), sin(a)) * R * 1.25)
			pts.append(c + Vector2(R * 1.3, R * 0.05))
			pts.append(c + Vector2(-R * 1.3, R * 0.05))
			ci.draw_colored_polygon(pts, Color(0.1, 0.06, 0.12, 0.55))
			ci.draw_circle(c + Vector2(R * 0.75, -R * 0.85), R * 0.14, accent)
		"goggles":
			ci.draw_rect(Rect2(c.x - R * 1.0, c.y - R * 0.62, R * 2.0, R * 0.14), Color(0.35, 0.25, 0.18), true)
			for s in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(s * R * 0.4, -R * 0.56), R * 0.2, Color(0.55, 0.8, 0.9))
				ci.draw_arc(c + Vector2(s * R * 0.4, -R * 0.56), R * 0.2, 0.0, TAU, 14, Color(0.6, 0.45, 0.2), maxf(1.5, R * 0.06), true)
		"hat":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-R * 1.35, -R * 0.7), c + Vector2(R * 1.35, -R * 0.7), c + Vector2(R * 0.2, -R * 2.0),
			]), look.outfit)
			ci.draw_rect(Rect2(c.x - R * 1.45, c.y - R * 0.8, R * 2.9, R * 0.18), look.outfit.darkened(0.2), true)
			ci.draw_rect(Rect2(c.x - R * 0.9, c.y - R * 0.95, R * 1.8, R * 0.14), accent, true)
		"kerchief":
			var pts := PackedVector2Array()
			for i in 11:
				var a := lerpf(PI * 1.0, PI * 2.0, float(i) / 10.0)
				pts.append(c + Vector2(cos(a), sin(a) * 0.9) * R * 1.12 + Vector2(0, -R * 0.1))
			ci.draw_colored_polygon(pts, Color(0.86, 0.3, 0.25))
			for i in 4:
				ci.draw_circle(c + Vector2(-R * 0.6 + i * R * 0.4, -R * 0.6), R * 0.06, Color(1, 1, 1, 0.8))
		"headband":
			ci.draw_rect(Rect2(c.x - R * 1.04, c.y - R * 0.55, R * 2.08, R * 0.16), accent.darkened(0.2), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(R * 1.0, -R * 0.5), c + Vector2(R * 1.5, -R * 0.2), c + Vector2(R * 1.35, -R * 0.65),
			]), accent.darkened(0.2))


static func _overlay(ci: CanvasItem, c: Vector2, R: float, r: Rect2, look: Dictionary, o: String) -> void:
	var w := maxf(1.2, R * 0.06)
	match o:
		"eyebags":
			for s in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(s * R * 0.38, R * 0.3), R * 0.12, PI * 0.15, PI * 0.85, 8, Color(0.5, 0.35, 0.6, 0.8), w, true)
		"mask":
			var m := Rect2(c.x - R * 0.62, c.y + R * 0.32, R * 1.24, R * 0.52)
			ci.draw_rect(m, Color(0.97, 0.97, 0.98), true)
			ci.draw_rect(m, Color(0.7, 0.72, 0.78), false, 1.0)
			for i in 3:
				ci.draw_line(Vector2(m.position.x + 3, m.position.y + m.size.y * (0.3 + 0.2 * i)),
						Vector2(m.end.x - 3, m.position.y + m.size.y * (0.3 + 0.2 * i)), Color(0.82, 0.84, 0.88), 1.0)
			for s in [-1.0, 1.0]:
				ci.draw_line(Vector2(c.x + s * R * 0.62, m.position.y + 2), c + Vector2(s * R * 0.95, R * 0.05), Color(0.85, 0.86, 0.9), 1.0)
		"blanket":
			var top := c.y + R * 1.45
			var pts := PackedVector2Array([
				Vector2(c.x - R * 1.4, top), Vector2(c.x + R * 1.4, top),
				Vector2(c.x + R * 2.0, r.end.y), Vector2(c.x - R * 2.0, r.end.y),
			])
			ci.draw_colored_polygon(pts, Color(0.93, 0.74, 0.5))
			var y := top + R * 0.3
			while y < r.end.y:
				ci.draw_line(Vector2(c.x - R * 1.9, y), Vector2(c.x + R * 1.9, y), Color(0.82, 0.5, 0.35, 0.7), 2.0)
				y += R * 0.35
		"icepack":
			var ip := Rect2(c.x - R * 0.5, c.y - R * 0.62, R * 1.0, R * 0.32)
			ci.draw_rect(ip, Color(0.7, 0.88, 0.98), true)
			ci.draw_rect(ip, Color(0.4, 0.62, 0.82), false, 1.0)
			ci.draw_line(ip.position + Vector2(4, 4), Vector2(ip.end.x - 6, ip.position.y + 4), Color(1, 1, 1, 0.9), 1.0)
		"sweat":
			for k in [Vector2(R * 0.95, -R * 0.35), Vector2(-R * 1.0, -R * 0.1)]:
				var p: Vector2 = c + k
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -R * 0.18), p + Vector2(R * 0.08, 0), p + Vector2(-R * 0.08, 0)]), TEAR)
				ci.draw_circle(p, R * 0.08, TEAR)
		"v_sign":
			var h := c + Vector2(R * 1.2, R * 0.6)
			ci.draw_line(h, h + Vector2(-R * 0.15, -R * 0.55), SKIN_SHADE, R * 0.12)
			ci.draw_line(h, h + Vector2(R * 0.15, -R * 0.55), SKIN_SHADE, R * 0.12)
			ci.draw_circle(h + Vector2(0, R * 0.08), R * 0.2, SKIN)
			ci.draw_arc(h + Vector2(0, R * 0.08), R * 0.2, 0.0, TAU, 12, INK.lightened(0.3), 1.0, true)
		"fist":
			var f := c + Vector2(-R * 0.95, R * 1.6)
			ci.draw_circle(f, R * 0.26, SKIN)
			ci.draw_arc(f, R * 0.26, 0.0, TAU, 14, INK.lightened(0.3), 1.0, true)
			for i in 3:
				ci.draw_line(f + Vector2(-R * 0.12 + i * R * 0.1, -R * 0.2), f + Vector2(-R * 0.12 + i * R * 0.1, -R * 0.05), INK.lightened(0.3), 1.0)
		"hands_head":
			for s in [-1.0, 1.0]:
				var hpos := c + Vector2(s * R * 0.85, -R * 0.75)
				ci.draw_circle(hpos, R * 0.24, SKIN)
				ci.draw_arc(hpos, R * 0.24, 0.0, TAU, 12, INK.lightened(0.3), 1.0, true)
		"sparkle":
			_star(ci, c + Vector2(-R * 1.35, -R * 0.9), R * 0.18, GOLD)
			_star(ci, c + Vector2(R * 1.4, -R * 1.1), R * 0.14, GOLD)
			_star(ci, c + Vector2(R * 1.5, R * 0.3), R * 0.11, GOLD)
		"sigh":
			var p := c + Vector2(R * 0.75, R * 0.75)
			for i in 3:
				ci.draw_circle(p + Vector2(i * R * 0.18, -i * R * 0.06), R * (0.07 + i * 0.03), Color(0.75, 0.78, 0.82, 0.85))


static func _blob(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


static func _star(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -s), p + Vector2(s * 0.28, -s * 0.28), p + Vector2(s, 0), p + Vector2(s * 0.28, s * 0.28),
		p + Vector2(0, s), p + Vector2(-s * 0.28, s * 0.28), p + Vector2(-s, 0), p + Vector2(-s * 0.28, -s * 0.28),
	]), col)


static func _wave(ci: CanvasItem, m: Vector2, half: float, amp: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(m + Vector2(lerpf(-half, half, t), sin(t * TAU * 1.5) * amp))
	ci.draw_polyline(pts, col, w, true)


static func _spiral(ci: CanvasItem, p: Vector2, rad: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		var a := t * TAU * 2.0
		pts.append(p + Vector2(cos(a), sin(a)) * rad * t)
	ci.draw_polyline(pts, col, w, true)
