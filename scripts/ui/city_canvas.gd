extends Control
## 晚间城区。每块区域铺 data/evening.json 里的插画（线性过滤），名字压在底部暗条上。
## 点一块区域就选中它。坐标是 0–1，相对这块地图。

const UI := preload("res://scripts/ui/ui_style.gd")
const Evening := preload("res://scripts/core/evening.gd")

signal location_selected(id: String)

var locations: Array = []
var selected := "home"
var _rects := {}


func set_locations(locs: Array, sel: String) -> void:
	locations = locs
	selected = sel
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 插画不是像素图。项目默认最近邻，这里单独用线性 + mipmap。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id in _rects:
			var rect: Rect2 = _rects[id]
			if rect.has_point(event.position):
				selected = String(id)
				location_selected.emit(selected)
				queue_redraw()
				accept_event()
				return


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	_rects.clear()
	draw_rect(r, Color(0.55, 0.74, 0.88))
	# 夜色往下沉一点
	draw_rect(Rect2(0, r.size.y * 0.62, r.size.x, r.size.y * 0.38), Color(0.40, 0.52, 0.70, 0.28))
	_draw_moon(r)
	_draw_stars(r)
	var river := Rect2(0, r.size.y * 0.48, r.size.x, 22)
	draw_rect(river, Color(0.33, 0.58, 0.74))
	draw_rect(Rect2(river.position.x, river.position.y + 3, river.size.x, 3), Color(0.75, 0.88, 0.94, 0.55))
	# 一条贯穿的石板路
	draw_rect(Rect2(r.size.x * 0.32, 0, 10, r.size.y), Color(0.78, 0.70, 0.56))
	draw_rect(Rect2(0, r.size.y * 0.70, r.size.x, 8), Color(0.78, 0.70, 0.56))
	var font := get_theme_default_font()
	for loc in locations:
		var rect := _rect_of(r, loc)
		_rects[String(loc.id)] = rect
		_draw_district(rect, loc, String(loc.id) == selected, font)


func _rect_of(r: Rect2, loc: Dictionary) -> Rect2:
	var pad := 8.0
	var inner := r.grow(-pad)
	return Rect2(
		inner.position.x + float(loc.get("x", 0)) * inner.size.x,
		inner.position.y + float(loc.get("y", 0)) * inner.size.y,
		float(loc.get("w", 0.2)) * inner.size.x,
		float(loc.get("h", 0.2)) * inner.size.y,
	)


func _draw_district(rect: Rect2, loc: Dictionary, is_sel: bool, font: Font) -> void:
	var base := Color(String(loc.get("color", "#e4c98a")))
	draw_rect(rect, base.darkened(0.15))
	var inner := rect.grow(-2)
	var tex := Evening.load_background(String(loc.get("background", "")))
	if tex != null:
		draw_texture_rect_region(tex, inner, _cover_src(tex.get_size(), inner.size))
		# 压暗一点，木框和名字才站得住
		var shade := 0.10 if is_sel else 0.22
		draw_rect(inner, Color(0.10, 0.07, 0.05, shade))
	else:
		draw_rect(inner, base)
	var bar_h := minf(22.0, inner.size.y * 0.34)
	var bar := Rect2(inner.position.x, inner.end.y - bar_h, inner.size.x, bar_h)
	draw_rect(bar, Color(0.16, 0.10, 0.06, 0.78))
	var border := UI.UP if is_sel else UI.WOOD_DARK
	draw_rect(rect, border, false, 3.0 if is_sel else 1.0)
	if font == null:
		return
	var label := String(loc.get("name", ""))
	draw_string(font, bar.position + Vector2(7, bar_h - 6), label, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 12, 15, Color(1, 0.96, 0.88))


## 把 16:9 的插画裁成铺满格子的一块（居中 cover）。
static func _cover_src(tex_size: Vector2, dest_size: Vector2) -> Rect2:
	if tex_size.x <= 1.0 or tex_size.y <= 1.0 or dest_size.x <= 1.0 or dest_size.y <= 1.0:
		return Rect2(Vector2.ZERO, tex_size)
	var scale := maxf(dest_size.x / tex_size.x, dest_size.y / tex_size.y)
	var visible := dest_size / scale
	return Rect2((tex_size - visible) * 0.5, visible)


func _draw_moon(r: Rect2) -> void:
	var c := Vector2(r.size.x - 42, 32)
	draw_circle(c, 13, Color(0.98, 0.96, 0.86))
	draw_circle(c + Vector2(-6, -3), 11, Color(0.55, 0.74, 0.88))


func _draw_stars(r: Rect2) -> void:
	var dots := [Vector2(24, 18), Vector2(70, 40), Vector2(120, 16), Vector2(180, 34), Vector2(240, 14), Vector2(300, 28)]
	for i in dots.size():
		var p: Vector2 = dots[i]
		if p.x < r.size.x - 70:
			draw_rect(Rect2(p, Vector2(2, 2)), Color(1, 1, 1, 0.85))
