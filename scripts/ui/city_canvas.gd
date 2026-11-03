extends Control
## 晚间城区的占位地图：代码画出的色块和房子，配色跟 ui_style 的奶油纸 / 木框一致。
## 点一块区域就选中它。坐标来自 data/evening.json，0–1 相对这块地图。

const UI := preload("res://scripts/ui/ui_style.gd")

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
	draw_rect(rect, base.darkened(0.08))
	draw_rect(rect.grow(-3), base)
	var buildings := 3 if rect.size.x > 120.0 else 2
	var gap := 6.0
	var bw := (rect.size.x - gap * (buildings + 1)) / buildings
	for i in buildings:
		var bh := rect.size.y * (0.34 + 0.08 * (i % 2))
		var bx := rect.position.x + gap + i * (bw + gap)
		var by := rect.position.y + rect.size.y * 0.28
		var wall := base.darkened(0.22 + 0.06 * (i % 2))
		draw_rect(Rect2(bx, by, bw, bh), wall)
		# 屋顶
		var roof := PackedVector2Array([
			Vector2(bx - 2, by),
			Vector2(bx + bw * 0.5, by - 10),
			Vector2(bx + bw + 2, by),
		])
		draw_colored_polygon(roof, wall.darkened(0.15))
		var win := Color(0.98, 0.86, 0.45) if (i + int(rect.position.x)) % 2 == 0 else Color(0.45, 0.55, 0.68)
		draw_rect(Rect2(bx + 4, by + 6, 6, 6), win)
		if bw > 28.0:
			draw_rect(Rect2(bx + bw - 12, by + 6, 6, 6), win)
	var border := UI.UP if is_sel else UI.WOOD_DARK
	draw_rect(rect, border, false, 3.0 if is_sel else 1.0)
	if font == null:
		return
	var label := String(loc.get("name", ""))
	var pos := rect.position + Vector2(6, rect.size.y - 8)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 15, UI.TEXT)


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
