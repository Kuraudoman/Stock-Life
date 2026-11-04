extends SceneTree
## 拍主角新立绘：对话（平静、恐慌）、日结算（发烧）、城市地图（平静和发烧）。
## godot --path . --script res://tools/shot_evening.gd 一样，需要显示，不能 --headless。

func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	gs.new_game(20261104, "希雅", false)
	gs.open_market()
	gs.finish_day()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_set_state(gs, "calm", "healthy")
	await _shot_dialog("smile", "今天的盘面很安静。", "heroine-dialog-calm")
	await _shot_dialog("panic", "五、五万？！", "heroine-dialog-panic")
	_set_state(gs, "panic", "healthy")
	await _shot_summary("heroine-summary-panic")
	_set_state(gs, "pessimistic", "healthy")
	await _shot_summary("heroine-summary-frown")
	_set_state(gs, "calm", "fever")
	await _shot_summary("heroine-summary-fever")
	_set_state(gs, "calm", "healthy")
	await _shot_city("heroine-city-calm")
	_set_state(gs, "calm", "fever")
	await _shot_city("heroine-city-fever")
	_set_state(gs, "calm", "healthy")
	await _shot_paper("heroine-paper-calm")
	await _shot_closeup("heroine-outline-closeup")
	await _shot_ending("heroine-ending-ecstatic")
	quit()


func _set_state(gs: Node, mood: String, body: String) -> void:
	gs.player.mood = mood
	gs.player.body = body
	root.get_node("EventBus").player_changed.emit()


func _shot_dialog(expr: String, text: String, name: String) -> void:
	var d = load("res://scenes/dialog.tscn").instantiate()
	d.setup([{"who": "heroine", "expr": expr, "text": text}], [])
	root.add_child(d)
	for _i in 4:
		await process_frame
	_save(name)
	d.queue_free()
	await process_frame


func _shot_summary(name: String) -> void:
	var gs: Node = root.get_node("GameState")
	var summary: Dictionary = gs.last_summary.duplicate(true)
	summary.mood_before = "calm"
	summary.mood_after = String(gs.player.mood)
	summary.body_before = "healthy"
	summary.body_after = String(gs.player.body)
	var s = load("res://scenes/ui/day_summary.tscn").instantiate()
	s.setup(summary)
	root.add_child(s)
	for _i in 4:
		await process_frame
	_save(name)
	s.queue_free()
	await process_frame


func _shot_city(name: String) -> void:
	var gs: Node = root.get_node("GameState")
	if gs.phase != gs.Phase.EVENING:
		gs.open_evening("weekday")
	var map = load("res://scenes/city_map.tscn").instantiate()
	root.add_child(map)
	for _i in 5:
		await process_frame
	_save(name)
	map.queue_free()
	await process_frame


func _shot_paper(name: String) -> void:
	var gs: Node = root.get_node("GameState")
	var p = load("res://scenes/ui/morning_paper.tscn").instantiate()
	p.setup(gs.paper, false)
	root.add_child(p)
	for _i in 4:
		await process_frame
	_save(name)
	p.queue_free()
	await process_frame


func _shot_closeup(name: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(1.0, 0.97, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_right = 1280
	bg.offset_bottom = 720
	root.add_child(bg)
	var pv = load("res://scripts/ui/portrait_view.gd").new()
	pv.who = "heroine"
	pv.expr = "smile"
	pv.custom_minimum_size = Vector2(460, 620)
	pv.position = Vector2(410, 40)
	pv.size = Vector2(460, 620)
	root.add_child(pv)
	for _i in 4:
		await process_frame
	_save(name)
	pv.queue_free()
	bg.queue_free()
	await process_frame


func _shot_ending(name: String) -> void:
	var c = load("res://scenes/ui/chapter_end.tscn").instantiate()
	c.setup({
		"success": true, "early": true, "day": 12, "date": "4月12日",
		"cash": 52000, "debt": 0, "net_worth": 52000, "realized": 12000, "fees": 180,
		"pred_made": 8, "pred_resolved": 6, "pred_hits": 4, "affection": 20,
	})
	root.add_child(c)
	for _i in 4:
		await process_frame
	_save(name)
	c.queue_free()
	await process_frame


func _save(name: String) -> void:
	var dir := "/opt/cursor/artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("saved %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
