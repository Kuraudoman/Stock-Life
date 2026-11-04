extends RefCounted
## 大地图的多边形。坐标是 0..1，相对地图实际画出来的那块矩形。
## 住所和金穗大道、下城有一点重叠，命中时先测 home。

const DATA_PATH := "res://data/city_map.json"

static var _parsed: Dictionary = {}


static func parsed() -> Dictionary:
	if _parsed.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_parsed = raw if typeof(raw) == TYPE_DICTIONARY else {}
	return _parsed


static func overview_path() -> String:
	return String(parsed().get("overview", ""))


static func polygons() -> Dictionary:
	var out := {}
	var raw: Dictionary = parsed().get("polygons", {})
	for id in raw:
		out[String(id)] = to_poly(raw[id])
	return out


static func to_poly(points: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in points:
		poly.append(Vector2(float(p[0]), float(p[1])))
	return poly


static func contains(poly: PackedVector2Array, uv: Vector2) -> bool:
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(uv, poly)


## 顶点平均值。凹多边形可能落在外面，落在外面时改用 bbox 里第一个内部点。
static func interior_point(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2(0.5, 0.5)
	var c := Vector2.ZERO
	var mn := poly[0]
	var mx := poly[0]
	for p in poly:
		c += p
		mn = mn.min(p)
		mx = mx.max(p)
	c /= float(poly.size())
	if contains(poly, c):
		return c
	for j in 8:
		for i in 8:
			var uv := Vector2(mn.x + (mx.x - mn.x) * (float(i) + 0.5) / 8.0, mn.y + (mx.y - mn.y) * (float(j) + 0.5) / 8.0)
			if contains(poly, uv):
				return uv
	return c


## home 先测。空字符串表示点在城区外面。
static func hit(uv: Vector2, polys: Dictionary) -> String:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return ""
	if polys.has("home") and contains(polys["home"], uv):
		return "home"
	for id in polys:
		if String(id) == "home":
			continue
		if contains(polys[id], uv):
			return String(id)
	return ""
