class_name BottleView
extends Node2D
## Flat, reusable B1F1 bottle artwork. All liquid is clipped 2D geometry.
## Local origin: bottom center. Color units are ordered bottom-to-top.

const PALETTE: Array[Color] = [
	Color("ff7c7e"), Color("f5b733"), Color("43c2c7"), Color("9a6ae1")
]
const CONTOUR := Color("8b8cbd")
const GLASS := Color("d6e3fc")
const INNER_EDGE := Color("adbde0")
const EPSILON: float = 0.0001

@export var width: float = 150.0:
	set(value):
		width = maxf(value, 64.0)
		_geometry_dirty = true
		queue_redraw()
@export var height: float = 360.0:
	set(value):
		height = maxf(value, width * 1.5)
		_geometry_dirty = true
		queue_redraw()

var capacity: int = 4
var visual_units: Array = []:
	set(value):
		visual_units = value
		queue_redraw()
var selected: bool = false
var completed: bool = false
var hinted: bool = false
## This is intentionally true: rotating the vessel does not rotate gravity.
var keep_surface_world_horizontal: bool = true

var _geometry_dirty: bool = true
var _cavity: PackedVector2Array = PackedVector2Array()
var _wall_path: PackedVector2Array = PackedVector2Array()
var _inner_wall_path: PackedVector2Array = PackedVector2Array()
var _unit_area: float = 0.0
var _last_rotation: float = 0.0


func _ready() -> void:
	_rebuild_geometry()
	_last_rotation = global_rotation
	queue_redraw()


func _process(_delta: float) -> void:
	# Six inexpensive scalar comparisons while idle. No idle mesh rebuilds.
	if keep_surface_world_horizontal and absf(global_rotation - _last_rotation) > 0.00005:
		_last_rotation = global_rotation
		queue_redraw()


func configure(colors: Array, new_capacity: int = 4) -> void:
	capacity = maxi(1, new_capacity)
	_geometry_dirty = true
	var units: Array = []
	for item in colors:
		var color_id: int = int(item)
		if not units.is_empty() and int(units[-1]["color"]) == color_id:
			units[-1]["amount"] = float(units[-1]["amount"]) + 1.0
		else:
			units.append({"color": color_id, "amount": 1.0})
	set_layers(units)


func set_layers(units: Array) -> void:
	var cleaned: Array = []
	for item in units:
		if item is Dictionary:
			var amount: float = maxf(0.0, float(item.get("amount", 0.0)))
			if amount > EPSILON:
				cleaned.append({"color": int(item.get("color", 0)), "amount": amount})
	visual_units = cleaned


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_completed(value: bool) -> void:
	completed = value
	queue_redraw()


func set_hint(value: bool) -> void:
	hinted = value
	queue_redraw()


func get_mouth_local() -> Vector2:
	return Vector2(0.0, -height + 9.0)


func get_pour_lip_local(side: float = 1.0) -> Vector2:
	# Use to_global(get_pour_lip_local(sign(rotation))) for the lower lip.
	return Vector2(signf(side) * (width * 0.5 - 7.0), -height + 9.0)


func get_liquid_surface_local() -> Vector2:
	## Actual center of the rendered top surface, including rounded-bottom volume.
	## For a stream endpoint: to_global(get_liquid_surface_local()).
	if _geometry_dirty:
		_rebuild_geometry()
	var normal: Vector2 = Vector2.DOWN
	if keep_surface_world_horizontal:
		normal = Vector2(sin(global_rotation), cos(global_rotation))
	var amount: float = 0.0
	for item in visual_units:
		if item is Dictionary:
			amount += maxf(0.0, float(item.get("amount", 0.0)))
	amount = clampf(amount, 0.0, float(capacity))
	var bottom: Vector2 = _cavity[0]
	for point in _cavity:
		if normal.dot(point) > normal.dot(bottom):
			bottom = point
	if amount <= EPSILON:
		return bottom
	var threshold: float = _threshold_for_area(amount * _unit_area, normal)
	var intersections: PackedVector2Array = PackedVector2Array()
	for index in range(_cavity.size()):
		var a: Vector2 = _cavity[index]
		var b: Vector2 = _cavity[(index + 1) % _cavity.size()]
		var distance_a: float = normal.dot(a) - threshold
		var distance_b: float = normal.dot(b) - threshold
		if absf(distance_a) <= EPSILON:
			intersections.append(a)
		if distance_a * distance_b < 0.0:
			intersections.append(a.lerp(b, distance_a / (distance_a - distance_b)))
	if intersections.is_empty():
		return bottom
	# The convex cavity gives one chord; choose its ends even at shared vertices.
	var tangent: Vector2 = Vector2(normal.y, -normal.x)
	var first: Vector2 = intersections[0]
	var last: Vector2 = first
	for point in intersections:
		if tangent.dot(point) < tangent.dot(first):
			first = point
		if tangent.dot(point) > tangent.dot(last):
			last = point
	return (first + last) * 0.5


func get_liquid_color(color_id: int) -> Color:
	return PALETTE[posmod(color_id, PALETTE.size())]


func _rebuild_geometry() -> void:
	var wall_half: float = width * 0.5 - 7.0
	var inner_half: float = width * 0.5 - 18.0
	var mouth_y: float = -height + 9.0
	_wall_path = _u_path(wall_half, mouth_y, -7.0, 32)
	_inner_wall_path = _u_path(wall_half - 5.0, mouth_y + 1.0, -12.0, 32)
	_cavity = _u_path(inner_half, mouth_y + 1.0, -15.0, 32)
	# Closing the *mask* across the mouth does not draw a visual lid.
	var max_fill_y: float = -height + 52.0
	var usable: PackedVector2Array = _clip_plane(_cavity, Vector2.DOWN, max_fill_y, true)
	_unit_area = _polygon_area(usable) / float(capacity)
	_geometry_dirty = false


func _u_path(half_width: float, top_y: float, bottom_y: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var radius: float = half_width
	var center_y: float = bottom_y - radius
	points.append(Vector2(-half_width, top_y))
	points.append(Vector2(-half_width, center_y))
	for step in range(1, segments + 1):
		var angle: float = PI - PI * float(step) / float(segments)
		points.append(Vector2(cos(angle) * radius, center_y + sin(angle) * radius))
	points.append(Vector2(half_width, top_y))
	return points


func _draw() -> void:
	if _geometry_dirty:
		_rebuild_geometry()
	if _cavity.size() < 3:
		return

	# Attention is a soft edge around the same silhouette, never fake depth.
	if selected:
		draw_polyline(_wall_path, Color(1.0, 1.0, 1.0, 0.38), 33.0, true)
		draw_polyline(_wall_path, Color(0.61, 0.48, 0.93, 0.18), 24.0, true)
	elif hinted:
		draw_polyline(_wall_path, Color(1.0, 0.91, 0.56, 0.38), 29.0, true)
	elif completed:
		draw_polyline(_wall_path, Color(0.34, 0.78, 0.68, 0.17), 26.0, true)

	# Barely tinted glass makes the two empty bottles visible on the background.
	draw_colored_polygon(_cavity, Color(0.95, 0.97, 1.0, 0.20))
	_draw_liquid()
	_draw_glass_glints()

	# A stable three-stroke wall: lavender keyline, pale glass, slim inner edge.
	var edge_color: Color = CONTOUR
	if selected:
		edge_color = Color("7560a9")
	elif completed:
		edge_color = Color("79a6b3")
	draw_polyline(_wall_path, edge_color, 16.0, true)
	draw_polyline(_wall_path, GLASS, 10.0, true)
	draw_polyline(_inner_wall_path, Color(0.69, 0.76, 0.89, 0.66), 2.0, true)

	# Small flat tabs instead of an ellipse or a bar across the opening.
	var mouth_y: float = -height + 9.0
	var wall_half: float = width * 0.5 - 7.0
	for side in [-1.0, 1.0]:
		var outer: Vector2 = Vector2(side * (wall_half + 5.0), mouth_y)
		var inner: Vector2 = Vector2(side * (wall_half - 1.0), mouth_y)
		_draw_round_line(outer, inner, edge_color, 16.0)
		_draw_round_line(outer, inner, Color("e6edff"), 10.0)

	# A quiet finish cue which does not cover a color or a touch target.
	if completed:
		_draw_sparkle(Vector2(width * 0.5 + 10.0, -height + 39.0), 7.0, Color("f6cc62"))


func _draw_liquid() -> void:
	var normal: Vector2 = Vector2.DOWN
	if keep_surface_world_horizontal:
		normal = Vector2(sin(global_rotation), cos(global_rotation))
	var accumulated: float = 0.0
	var bottom_limit: float = _projection_limits(_cavity, normal).y + 1.0
	for item in visual_units:
		if not item is Dictionary:
			continue
		var amount: float = clampf(float(item.get("amount", 0.0)), 0.0, float(capacity) - accumulated)
		if amount <= EPSILON:
			continue
		accumulated += amount
		var top_limit: float = _threshold_for_area(accumulated * _unit_area, normal)
		var region: PackedVector2Array = _clip_plane(_cavity, normal, top_limit, true)
		region = _clip_plane(region, normal, bottom_limit, false)
		if region.size() >= 3:
			var liquid_color: Color = get_liquid_color(int(item.get("color", 0)))
			draw_colored_polygon(region, liquid_color)
			# A narrow painted side edge, clipped to this exact flat layer.
			var edge: PackedVector2Array = _clip_plane(region, Vector2.RIGHT, width * 0.5 - 21.0, true)
			if edge.size() >= 3:
				draw_colored_polygon(edge, Color(liquid_color.darkened(0.13), 0.28))
		bottom_limit = top_limit
		if accumulated >= float(capacity) - EPSILON:
			break


func _draw_glass_glints() -> void:
	var inner_half: float = width * 0.5 - 18.0
	var top_y: float = -height + 53.0
	var left_x: float = -inner_half + 10.0
	var right_x: float = left_x + 20.0
	var shine: PackedVector2Array = PackedVector2Array()
	# The long white ribbon is a painted flat overlay, not a liquid surface.
	shine.append(Vector2(left_x, top_y + 10.0))
	for step in range(13):
		var angle: float = PI + PI * float(step) / 12.0
		shine.append(Vector2((left_x + right_x) * 0.5 + cos(angle) * 10.0, top_y + 10.0 + sin(angle) * 10.0))
	shine.append(Vector2(right_x, -68.0))
	shine.append(Vector2(right_x + 2.0, -51.0))
	shine.append(Vector2(right_x + 7.0, -37.0))
	shine.append(Vector2(right_x + 15.0, -27.0))
	shine.append(Vector2(right_x + 3.0, -31.0))
	shine.append(Vector2(left_x + 5.0, -44.0))
	shine.append(Vector2(left_x, -61.0))
	var clipped_shines: Array[PackedVector2Array] = Geometry2D.intersect_polygons(shine, _cavity)
	for clipped in clipped_shines:
		if clipped.size() >= 3:
			draw_colored_polygon(clipped, Color(1.0, 1.0, 1.0, 0.26))

	# The two slim right glints repeat the selected concept's visual signature.
	var right_glint_x: float = inner_half - 14.0
	_draw_round_line(Vector2(right_glint_x, top_y + 18.0), Vector2(right_glint_x, top_y + 39.0), Color(1.0, 1.0, 0.97, 0.47), 6.0)
	_draw_round_line(Vector2(right_glint_x, top_y + 55.0), Vector2(right_glint_x, -92.0), Color(1.0, 1.0, 0.97, 0.39), 6.0)


func _draw_round_line(start: Vector2, end: Vector2, color: Color, thickness: float) -> void:
	draw_line(start, end, color, thickness, true)
	draw_circle(start, thickness * 0.5, color, true, -1.0, true)
	draw_circle(end, thickness * 0.5, color, true, -1.0, true)


func _draw_sparkle(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius * 0.29, -radius * 0.29),
		center + Vector2(radius, 0.0), center + Vector2(radius * 0.29, radius * 0.29),
		center + Vector2(0.0, radius), center + Vector2(-radius * 0.29, radius * 0.29),
		center + Vector2(-radius, 0.0), center + Vector2(-radius * 0.29, -radius * 0.29)
	])
	draw_colored_polygon(points, color)


func _projection_limits(polygon: PackedVector2Array, normal: Vector2) -> Vector2:
	var minimum: float = INF
	var maximum: float = -INF
	for point in polygon:
		var projection: float = normal.dot(point)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)


func _threshold_for_area(target_area: float, normal: Vector2) -> float:
	var limits: Vector2 = _projection_limits(_cavity, normal)
	if target_area <= EPSILON:
		return limits.y + 1.0
	if target_area >= _polygon_area(_cavity) - EPSILON:
		return limits.x - 1.0
	var low: float = limits.x
	var high: float = limits.y
	# Twenty iterations are subpixel accurate for this 360-pixel geometry.
	for _iteration in range(20):
		var midpoint: float = (low + high) * 0.5
		var area: float = _polygon_area(_clip_plane(_cavity, normal, midpoint, true))
		if area > target_area:
			low = midpoint
		else:
			high = midpoint
	return (low + high) * 0.5


func _clip_plane(polygon: PackedVector2Array, normal: Vector2, threshold: float, keep_greater: bool) -> PackedVector2Array:
	# Sutherland-Hodgman against one line. The U-shaped interior is convex.
	var result: PackedVector2Array = PackedVector2Array()
	if polygon.is_empty():
		return result
	var previous: Vector2 = polygon[-1]
	var previous_distance: float = normal.dot(previous) - threshold
	var previous_inside: bool = previous_distance >= -EPSILON if keep_greater else previous_distance <= EPSILON
	for current in polygon:
		var current_distance: float = normal.dot(current) - threshold
		var current_inside: bool = current_distance >= -EPSILON if keep_greater else current_distance <= EPSILON
		if current_inside != previous_inside:
			var denominator: float = previous_distance - current_distance
			if absf(denominator) > 0.0000001:
				var fraction: float = clampf(previous_distance / denominator, 0.0, 1.0)
				result.append(previous.lerp(current, fraction))
		if current_inside:
			result.append(current)
		previous = current
		previous_distance = current_distance
		previous_inside = current_inside
	return result


func _polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var twice_area: float = 0.0
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5
