extends Control
## 弹出层基类：半透明遮罩 + 居中面板。弹出层打开时主界面的游戏时钟暂停（main.gd 的弹出层队列）。

signal closed(result: Variant)

var _closed := false


func close(result: Variant = null) -> void:
	if _closed:
		return
	_closed = true
	closed.emit(result)
