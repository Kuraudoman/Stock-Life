extends VBoxContainer
## 股票列表：公司名、现价、涨跌幅、看板娘小头像。点击切换选中的股票。

const UI := preload("res://scripts/ui/ui_style.gd")

var _rows := {}
var _group := ButtonGroup.new()


func _ready() -> void:
	EventBus.game_loaded.connect(_rebuild)
	EventBus.tick_advanced.connect(func(_t): refresh())
	EventBus.market_opened.connect(func(_d): refresh())
	EventBus.market_closed.connect(func(_s): refresh())
	EventBus.trade_executed.connect(func(_r): refresh())
	EventBus.stock_selected.connect(func(_id): _sync_selection())
	if GameState.has_game:
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	for id in GameState.market.order:
		_rows[id] = _make_row(id)
	refresh()
	_sync_selection()


func _make_row(id: String) -> Dictionary:
	var c: Dictionary = GameState.company(id)
	var btn := Button.new()
	btn.theme_type_variation = &"StockRow"
	btn.toggle_mode = true
	btn.button_group = _group
	btn.custom_minimum_size = Vector2(0, 52)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(GameState.select_stock.bind(id))
	add_child(btn)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	btn.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)

	# 看板娘小头像（占位：主题色圆形 + 名字首字）
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(36, 36)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	var avatar_color := Color.html(String(c.get("color", "#888888")))
	sb.bg_color = avatar_color.lightened(0.15)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = UI.WOOD_DARK
	avatar.add_theme_stylebox_override("panel", sb)
	var ini := Label.new()
	ini.text = String(c.get("mascot", "?")).left(1)
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ini.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	ini.add_theme_color_override("font_shadow_color", avatar_color.darkened(0.45))
	ini.add_theme_constant_override("shadow_offset_x", 1)
	ini.add_theme_constant_override("shadow_offset_y", 1)
	ini.add_theme_font_size_override("font_size", 16)
	avatar.add_child(ini)
	ini.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_child(avatar)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(names)
	var name_label := _label(String(c.get("short", id)), 15, UI.TEXT)
	names.add_child(name_label)
	var sub := _label("", 11, UI.MUTED)
	names.add_child(sub)

	var nums := VBoxContainer.new()
	nums.alignment = BoxContainer.ALIGNMENT_CENTER
	nums.add_theme_constant_override("separation", 0)
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nums)
	var price := _label("", 15, UI.TEXT)
	price.clip_text = false
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nums.add_child(price)
	var chg := _label("", 12, UI.FLAT)
	chg.clip_text = false
	chg.custom_minimum_size = Vector2(64, 0)
	chg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nums.add_child(chg)
	return {"button": btn, "sub": sub, "price": price, "change": chg}


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	return l


func refresh() -> void:
	var m := GameState.market
	for id in _rows:
		var row: Dictionary = _rows[id]
		var c: Dictionary = GameState.company(id)
		var chg := m.day_change(id)
		var col := UI.change_color(chg)
		row.price.text = "%.2f" % m.price(id)
		row.price.add_theme_color_override("font_color", col)
		row.change.text = UI.pct(chg)
		row.change.add_theme_color_override("font_color", col)
		var held := GameState.portfolio.qty_of(id)
		row.sub.text = "%s · %s" % [c.get("mascot", ""), ("持 %d 股" % held) if held > 0 else c.get("sector_name", "")]


func _sync_selection() -> void:
	for id in _rows:
		(_rows[id].button as Button).set_pressed_no_signal(id == GameState.selected_id)
