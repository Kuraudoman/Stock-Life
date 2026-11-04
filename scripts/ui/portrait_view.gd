extends Control
## 可复用的立绘：只画抠好的角色，底下是什么界面就透出什么。
## who 为 characters.json 里的角色 id，或公司 id（看板娘）。follow_state=true 时主角跟随当前情绪与身体状态。

const Painter := preload("res://scripts/ui/portrait_painter.gd")

@export var who := "heroine"
@export var follow_state := false
@export var show_frame := true
var expr := "smile"
var overlays: Array = []
var dim := false
var tint := Color(0, 0, 0, 0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 头顶的雨云之类要画出槽外。自己和父节点都不要把绘制裁掉。
	_allow_overflow(self)
	if follow_state:
		EventBus.player_changed.connect(queue_redraw)


## 沿父链关掉裁剪，滚动容器除外（它必须裁内容）。
func _allow_overflow(node: Node) -> void:
	var current := node
	while current is CanvasItem and not current is ScrollContainer:
		var ci := current as CanvasItem
		ci.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		current = current.get_parent()


func set_character(p_who: String, p_expr: String = "", p_overlays: Array = [], p_dim: bool = false) -> void:
	who = p_who
	if p_expr != "":
		expr = p_expr
	overlays = p_overlays
	dim = p_dim
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func look() -> Dictionary:
	var c := GameState.character(who)
	if not c.is_empty():
		return Painter.look_of(c, who)
	var feature := String(GameState.characters.get("mascot_features", {}).get(who, ""))
	var l := Painter.mascot_look(GameState.company(who), feature)
	l.id = who
	return l


func _draw() -> void:
	var e := expr
	var o := overlays
	if follow_state and who == "heroine":
		var layers := Painter.heroine_layers(String(GameState.player.get("mood", "calm")), String(GameState.player.get("body", "healthy")))
		e = layers.expr
		o = layers.overlays
	# 角色顶对齐，铺满这块控件的高度。不再铺方格底，也不画木框。
	var inner := Rect2(Vector2.ZERO, size)
	Painter.draw(self, inner, look(), e, o, dim, tint)
