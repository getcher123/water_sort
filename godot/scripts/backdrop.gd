class_name JellyBackdrop
extends Node2D
## Quiet, resolution-independent painted background matching selected B1F1.

@export var canvas_size: Vector2 = Vector2(720.0, 1280.0):
	set(value):
		canvas_size = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var start_color := Color("dce5ff")
	var end_color := Color("d6defb")
	var band_height: float = canvas_size.y / 80.0
	for index in range(80):
		var progress: float = float(index) / 79.0
		draw_rect(Rect2(0.0, float(index) * band_height, canvas_size.x, band_height + 1.0), start_color.lerp(end_color, progress))

	# Large rings are cropped by the viewport. They never compete with colors.
	draw_arc(Vector2(-30.0, -47.0), 171.0, 0.0, TAU, 100, Color(0.65, 0.67, 0.91, 0.12), 63.0, true)
	draw_arc(Vector2(764.0, 365.0), 110.0, 0.0, TAU, 90, Color(0.72, 0.68, 0.94, 0.15), 36.0, true)
	draw_arc(Vector2(-65.0, 790.0), 119.0, 0.0, TAU, 90, Color(0.68, 0.69, 0.91, 0.17), 40.0, true)
	draw_arc(Vector2(710.0, 1320.0), 213.0, 0.0, TAU, 110, Color(0.69, 0.65, 0.92, 0.12), 75.0, true)
	draw_arc(Vector2(-44.0, 1276.0), 164.0, 0.0, TAU, 100, Color(0.66, 0.67, 0.91, 0.11), 48.0, true)

	_bubble(Vector2(550.0, 167.0), 26.0, true)
	_bubble(Vector2(579.0, 202.0), 12.0, false)
	_bubble(Vector2(533.0, 65.0), 17.0, false)
	_bubble(Vector2(689.0, 270.0), 19.0, false)
	_bubble(Vector2(63.0, 1100.0), 23.0, true)
	_bubble(Vector2(94.0, 1140.0), 15.0, false)
	_bubble(Vector2(656.0, 1072.0), 22.0, true)
	_bubble(Vector2(685.0, 1031.0), 15.0, false)


func _bubble(center: Vector2, radius: float, shiny: bool) -> void:
	draw_circle(center, radius, Color(0.84, 0.91, 1.0, 0.12), true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 56, Color(0.57, 0.69, 0.90, 0.16), 2.4, true)
	if shiny:
		draw_circle(center + Vector2(-radius * 0.24, -radius * 0.32), radius * 0.23, Color(1.0, 1.0, 1.0, 0.40), true, -1.0, true)
		draw_circle(center + Vector2(radius * 0.20, radius * 0.03), radius * 0.11, Color(1.0, 1.0, 1.0, 0.32), true, -1.0, true)
