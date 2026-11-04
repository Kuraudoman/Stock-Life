extends SceneTree
## 把晚间大地图画下来：空闲、悬停金穗大道、悬停住所、港区卡片、进入港区。
## 无头模式没有画面，需要有显示。
## godot --path . --script res://tools/shot_evening.gd

func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	gs.new_game(20261103, "希雅", false)
	gs.open_market()
	gs.finish_day()
	gs.open_evening("weekday")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var map = load("res://scenes/city_map.tscn").instantiate()
	root.add_child(map)
	for _i in 8:
		await process_frame
	_save("city-map-idle")
	map.get_node("%Map").preview_hover("avenue")
	await process_frame
	await process_frame
	_save("city-map-hover-avenue")
	map.get_node("%Map").preview_hover("home")
	await process_frame
	await process_frame
	_save("city-map-hover-home")
	map.get_node("%Map").preview_hover("")
	map.open_card("harbor")
	await create_timer(0.25).timeout
	_save("city-map-modal-harbor")
	map.enter_district("harbor")
	for _i in 4:
		await process_frame
	_save("city-map-district-harbor")
	quit()


func _save(name: String) -> void:
	var dir := "/opt/cursor/artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("saved %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
