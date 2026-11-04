extends Control
## 晚间大地图。一张鸟瞰图铺满这块控件（保持比例，不够的地方留边），
## 多边形跟着画出来的矩形走。鼠标移上去高亮，点一下交给外面打开卡片。

const UI := preload("res://scripts/ui/ui_style.gd")
const Evening := preload("res://scripts/core/evening.gd")
const Geom := preload("res://scripts/ui/city_geom.gd")

signal location_picked(id: String)

var locations: Array = []
var blocked: Dictionary = {}
var hover := ""
var _polys: Dictionary = {}
var _tex: Texture2D
var _map_rect := Rect2()


func set_state(locs: Array, blocked_ids: Dictionary) -> void:
	locations = locs
	blocked = blocked_ids
	queue_redraw()


func preview_hover(id: String) -> void:
	hover = id
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_polys = Geom.polygons()
	_tex = Evening.load_background(Geom.overview_path())
	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		if hover != "":
			hover = ""
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := _id_at(event.position)
		if id != hover:
			hover = id
			var open := id != "" and not blocked.has(id)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _id_at(event.position)
		if id != "" and not blocked.has(id):
			location_picked.emit(id)
			accept_event()


func _id_at(local: Vector2) -> String:
	if _map_rect.size.x < 2.0 or not _map_rect.has_point(local):
		return ""
	var uv := (local - _map_rect.position) / _map_rect.size
	return Geom.hit(uv, _polys)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	draw_rect(r, Color(0.07, 0.06, 0.09))
	_map_rect = _fitted(r)
	if _tex != null:
		draw_texture_rect(_tex, _map_rect, false)
	else:
		draw_rect(_map_rect, Color(0.2, 0.24, 0.32))
	for loc in locations:
		var id := String(loc.get("id", ""))
		if not _polys.has(id) or not blocked.has(id):
			continue
		_paint_poly(_polys[id], Color(0.04, 0.03, 0.06, 0.52), Color(0, 0, 0, 0), 0.0)
	if hover != "" and _polys.has(hover):
		if blocked.has(hover):
			_paint_poly(_polys[hover], Color(0.15, 0.12, 0.1, 0.18), Color(0.85, 0.7, 0.45, 0.7), 2.0)
		else:
			_paint_poly(_polys[hover], Color(1.0, 0.82, 0.45, 0.30), Color(1.0, 0.95, 0.78, 0.95), 3.0)
	_draw_home_pin()
	_draw_label()


func _fitted(area: Rect2) -> Rect2:
	var aspect := 16.0 / 9.0
	if _tex != null and _tex.get_height() > 0:
		aspect = float(_tex.get_width()) / float(_tex.get_height())
	var scale := minf(area.size.x / aspect, area.size.y)
	var drawn := Vector2(scale * aspect, scale)
	return Rect2(area.position + (area.size - drawn) * 0.5, drawn)


func _paint_poly(poly: PackedVector2Array, fill: Color, line: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(_map_rect.position + Vector2(p.x, p.y) * _map_rect.size)
	if fill.a > 0.001 and pts.size() >= 3:
		draw_colored_polygon(pts, fill)
	if width > 0.0 and pts.size() >= 2:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, width, true)


func _draw_home_pin() -> void:
	if not _polys.has("home"):
		return
	var uv: Vector2 = Geom.interior_point(_polys["home"])
	var c := _map_rect.position + uv * _map_rect.size
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 280.0)
	draw_circle(c, 16.0 + pulse * 6.0, Color(1.0, 0.72, 0.28, 0.18 + pulse * 0.14))
	draw_circle(c, 8.0, Color(0.42, 0.22, 0.08, 0.92))
	var roof := PackedVector2Array([c + Vector2(-7, -1), c + Vector2(0, -9), c + Vector2(7, -1)])
	draw_colored_polygon(roof, Color(1.0, 0.86, 0.42))
	draw_rect(Rect2(c + Vector2(-5, -1), Vector2(10, 8)), Color(1.0, 0.94, 0.78))
	draw_rect(Rect2(c + Vector2(-1.5, 2), Vector2(3, 5)), Color(0.45, 0.26, 0.1))


func _draw_label() -> void:
	if hover == "" or not _polys.has(hover):
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var loc := _loc(hover)
	var name := String(loc.get("name", hover))
	var reason := String(blocked.get(hover, ""))
	var uv: Vector2 = Geom.interior_point(_polys[hover])
	var c := _map_rect.position + uv * _map_rect.size
	var title_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var reason_size := font.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 13) if reason != "" else Vector2.ZERO
	var box := Vector2(maxf(title_size.x, reason_size.x) + 16.0, 26.0 + (18.0 if reason != "" else 0.0))
	var origin := c + Vector2(-box.x * 0.5, -box.y - 18.0)
	origin.x = clampf(origin.x, _map_rect.position.x + 4.0, _map_rect.end.x - box.x - 4.0)
	origin.y = clampf(origin.y, _map_rect.position.y + 4.0, _map_rect.end.y - box.y - 4.0)
	draw_rect(Rect2(origin, box), Color(0.12, 0.08, 0.05, 0.88))
	draw_rect(Rect2(origin, box), UI.WOOD, false, 1.0)
	draw_string(font, origin + Vector2(8, 18), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.96, 0.88))
	if reason != "":
		draw_string(font, origin + Vector2(8, 36), reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.82, 0.55))


func _loc(id: String) -> Dictionary:
	for loc in locations:
		if String(loc.get("id", "")) == id:
			return loc
	return {}
