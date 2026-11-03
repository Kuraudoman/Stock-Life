extends SceneTree
## 把晚间城市地图画下来，供核对占位界面。无头模式没有画面，需要有显示。
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
	for _i in 6:
		await process_frame
	_save("city-map-home")
	map._on_location("academy")
	for _i in 3:
		await process_frame
	_save("city-map-academy")
	map._on_location("downtown")
	for _i in 3:
		await process_frame
	_save("city-map-downtown")
	map._on_location("avenue")
	for _i in 3:
		await process_frame
	_save("city-map-avenue")
	quit()


func _save(name: String) -> void:
	var dir := "/opt/cursor/artifacts/screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("saved %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
