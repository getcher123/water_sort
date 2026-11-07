extends Node2D
## Presentation and input layer. Rules stay in the pure SortBoard model.

const Board = preload("res://scripts/board_model.gd")
const Bottle = preload("res://scripts/bottle_view.gd")
const Background = preload("res://scripts/backdrop.gd")
const FONT_FILE = preload("res://assets/Nunito.ttf")
const PALETTE: Array[Color] = [Color("ff7c7e"), Color("f5b733"), Color("43c2c7"), Color("9a6ae1")]
const INK = Color("66548e")
const POSITIONS: Array[Vector2] = [Vector2(150, 610), Vector2(360, 610), Vector2(570, 610), Vector2(150, 1030), Vector2(360, 1030), Vector2(570, 1030)]

var board = Board.new()
var bottles: Array = []
var font: FontVariation
var body_font: FontVariation
var selected: int = -1
var busy: bool = false
var mode: String = "playing"
var active_tween: Tween
var epoch: int = 0
var transfer: Dictionary = {}
var before_board: Array = []
var stream_on: bool = false
var stream_progress: float = 0.0
var pour_side: float = 1.0
var notice: String = ""
var notice_time: float = 0.0
var completed: Array = []
var elapsed: float = 0.0
var win_time: float = 0.0
var pressed_at: Vector2 = Vector2.ZERO
var pointer_down: bool = false
var active_touch: int = -1
var last_touch_msec: int = -10000


func _ready() -> void:
	font = FontVariation.new()
	font.base_font = FONT_FILE
	font.variation_opentype = {"wght": 900}
	body_font = FontVariation.new()
	body_font.base_font = FONT_FILE
	body_font.variation_opentype = {"wght": 750}
	var backdrop = Background.new()
	backdrop.z_index = -10
	add_child(backdrop)
	for i in range(6):
		var bottle = Bottle.new()
		bottle.position = POSITIONS[i]
		bottle.z_index = -2
		bottles.append(bottle)
		add_child(bottle)
	var initial_level: int = _read_progress()
	_go_level(initial_level)
	get_viewport().gui_disable_input = false
	RenderingServer.set_default_clear_color(Color("d7dffb"))


func _read_progress() -> int:
	var config = ConfigFile.new()
	if config.load("user://progress.cfg") != OK:
		return 0
	var saved = config.get_value("progress", "completed", [])
	if saved is Array:
		for value in saved:
			if value is int and value >= 0 and value < 3 and not completed.has(value):
				completed.append(value)
	var last = config.get_value("progress", "level", 0)
	return clampi(int(last), 0, 2) if last is int else 0


func _save_progress() -> void:
	var config = ConfigFile.new()
	config.set_value("progress", "level", board.level_index)
	config.set_value("progress", "completed", completed)
	# Storage is best-effort; the game remains playable if it is unavailable.
	config.save("user://progress.cfg")


func _go_level(index: int) -> void:
	_cancel_animation()
	board.load_level(index)
	selected = -1
	mode = "playing"
	notice = ""
	notice_time = 0.0
	_sync_views()
	_save_progress()
	_publish_status()
	queue_redraw()


func _cancel_animation() -> void:
	_reset_pointer()
	epoch += 1
	if is_instance_valid(active_tween):
		active_tween.kill()
	active_tween = null
	busy = false
	stream_on = false
	transfer = {}
	for i in range(bottles.size()):
		bottles[i].rotation = 0.0
		bottles[i].position = POSITIONS[i]
		bottles[i].z_index = -2


func _reset_pointer() -> void:
	pointer_down = false
	active_touch = -1
	pressed_at = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_pointer()
		if is_node_ready() and mode == "playing":
			_open_overlay("pause")


func _sync_views() -> void:
	for i in range(bottles.size()):
		bottles[i].configure(board.bottles[i], board.capacity)
		bottles[i].set_selected(i == selected)
		bottles[i].set_hint(selected >= 0 and board.can_pour(selected, i))
		bottles[i].set_completed(_bottle_complete(board.bottles[i]))
		bottles[i].position = POSITIONS[i] + Vector2(0, -18 if selected == i else 0)
		bottles[i].rotation = 0.0
		bottles[i].queue_redraw()


func _bottle_complete(contents: Array) -> bool:
	if contents.size() != board.capacity:
		return false
	for color in contents:
		if color != contents[0]:
			return false
	return true


func _process(delta: float) -> void:
	elapsed += delta
	if mode == "playing" and notice_time > 0.0:
		notice_time = maxf(0.0, notice_time - delta)
		queue_redraw()
	if busy and mode == "playing":
		if not transfer.is_empty():
			bottles[int(transfer["from"])].queue_redraw()
		queue_redraw()
	if mode == "win":
		win_time += delta
		if win_time < 3.5:
			queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		last_touch_msec = Time.get_ticks_msec()
		if event.pressed and active_touch == -1:
			active_touch = event.index
			pointer_down = true
			pressed_at = event.position
		elif event.index == active_touch:
			var was_pressed: bool = pointer_down
			pointer_down = false
			active_touch = -1
			if was_pressed and not event.canceled and pressed_at.distance_to(event.position) < 26.0:
				_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - last_touch_msec < 700:
			return
		if event.pressed:
			pressed_at = event.position
			pointer_down = true
		else:
			var was_pressed: bool = pointer_down
			pointer_down = false
			if was_pressed and pressed_at.distance_to(event.position) < 26.0:
				_tap(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if mode in ["pause", "help", "restart"]:
				_resume()
			elif mode == "playing":
				_open_overlay("pause")
		elif event.keycode == KEY_ENTER and mode == "win":
			_next_level()
		elif mode == "playing":
			if event.keycode >= KEY_1 and event.keycode <= KEY_6 and not busy:
				_select_bottle(int(event.keycode - KEY_1))
			elif event.keycode == KEY_Z or event.keycode == KEY_BACKSPACE:
				_undo()
			elif event.keycode == KEY_R:
				_open_overlay("restart")
			elif event.keycode == KEY_H or event.keycode == KEY_F1:
				_open_overlay("help")


func _tap(at: Vector2) -> void:
	if mode != "playing":
		if mode == "win":
			if Rect2(150, 750, 420, 85).has_point(at):
				_next_level()
			elif Rect2(150, 850, 420, 65).has_point(at):
				_go_level(board.level_index)
		elif mode == "restart":
			if Rect2(150, 720, 420, 85).has_point(at):
				_go_level(board.level_index)
			elif Rect2(150, 825, 420, 70).has_point(at):
				_resume()
		else:
			if Rect2(150, 800, 420, 90).has_point(at):
				_resume()
			elif mode == "pause" and Rect2(150, 905, 420, 65).has_point(at):
				mode = "restart"
				queue_redraw()
		return
	if at.distance_to(Vector2(650, 104)) < 45.0:
		_open_overlay("pause")
		return
	if at.distance_to(Vector2(70, 104)) < 36.0:
		_open_overlay("help")
		return
	if at.distance_to(Vector2(450, 1160)) < 66.0:
		_open_overlay("restart")
		return
	if at.distance_to(Vector2(270, 1160)) < 66.0:
		_undo()
		return
	if busy:
		return
	for i in range(3):
		if Rect2(291 + i * 48, 154, 42, 40).has_point(at):
			_go_level(i)
			return
	for i in range(6):
		if Rect2(POSITIONS[i] - Vector2(89, 380), Vector2(178, 400)).has_point(at):
			_select_bottle(i)
			return
	selected = -1
	_sync_views()
	queue_redraw()


func _select_bottle(index: int) -> void:
	if busy or mode != "playing":
		return
	if selected == index:
		selected = -1
	elif selected >= 0 and board.can_pour(selected, index):
		_start_pour(selected, index)
		return
	elif board.bottles[index].is_empty():
		_toast("Сначала выберите колбу с жидкостью")
	else:
		if selected >= 0:
			_toast("Переливайте в пустую колбу или на тот же цвет")
		selected = index
	_sync_views()
	_publish_status()
	queue_redraw()


func _start_pour(source: int, target: int) -> void:
	transfer = board.preview_pour(source, target)
	if transfer.is_empty():
		return
	before_board = board.bottles.duplicate(true)
	board.pour(source, target)
	busy = true
	selected = -1
	stream_on = false
	stream_progress = 0.0
	notice_time = 0.0
	for i in range(6):
		bottles[i].set_selected(false)
		bottles[i].set_hint(false)
		bottles[i].set_completed(false)
		bottles[i].position = POSITIONS[i]
	var source_view = bottles[source]
	source_view.z_index = -1
	pour_side = 1.0 if POSITIONS[target].x >= 350.0 else -1.0
	var angle: float = 0.95 * pour_side
	var lip: Vector2 = source_view.get_pour_lip_local(pour_side)
	var target_mouth: Vector2 = POSITIONS[target] + bottles[target].get_mouth_local()
	var destination: Vector2 = target_mouth + Vector2(-pour_side * 14.0, -30.0) - lip.rotated(angle)
	var my_epoch: int = epoch
	active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(source_view, "position", destination, 0.3)
	active_tween.parallel().tween_property(source_view, "rotation", angle, 0.3)
	active_tween.tween_callback(func(): stream_on = true)
	active_tween.tween_method(_animate_liquid, 0.0, 1.0, 0.48 + 0.13 * float(transfer["amount"]))
	active_tween.tween_callback(func(): stream_on = false)
	active_tween.tween_property(source_view, "position", POSITIONS[source], 0.3)
	active_tween.parallel().tween_property(source_view, "rotation", 0.0, 0.3)
	active_tween.tween_callback(_finish_pour.bind(my_epoch))
	_publish_status()
	queue_redraw()


func _units(contents: Array) -> Array:
	var result: Array = []
	for color in contents:
		if not result.is_empty() and result.back()["color"] == color:
			result.back()["amount"] += 1.0
		else:
			result.append({"color": int(color), "amount": 1.0})
	return result


func _animate_liquid(progress: float) -> void:
	if transfer.is_empty():
		return
	stream_progress = progress
	var source: int = transfer["from"]
	var target: int = transfer["to"]
	var amount: float = float(transfer["amount"]) * progress
	var source_layers: Array = _units(before_board[source])
	source_layers.back()["amount"] -= amount
	if source_layers.back()["amount"] <= 0.0001:
		source_layers.pop_back()
	var target_layers: Array = _units(before_board[target])
	if not target_layers.is_empty() and target_layers.back()["color"] == transfer["color"]:
		target_layers.back()["amount"] += amount
	else:
		target_layers.append({"color": transfer["color"], "amount": amount})
	bottles[source].set_layers(source_layers)
	bottles[target].set_layers(target_layers)
	queue_redraw()


func _finish_pour(my_epoch: int) -> void:
	if my_epoch != epoch:
		return
	busy = false
	stream_on = false
	for bottle in bottles:
		bottle.z_index = -2
	_sync_views()
	if board.is_solved():
		_reset_pointer()
		mode = "win"
		win_time = 0.0
		if not completed.has(board.level_index):
			completed.append(board.level_index)
		_save_progress()
	elif not board.has_moves():
		_toast("Ходов нет. Отмените ход или начните заново")
	_publish_status()
	queue_redraw()


func _undo() -> void:
	if busy or mode != "playing":
		return
	if board.undo():
		selected = -1
		_sync_views()
		_toast("Последний ход отменён")
		_publish_status()
	queue_redraw()


func _open_overlay(next_mode: String) -> void:
	if mode != "playing":
		return
	_reset_pointer()
	mode = next_mode
	if is_instance_valid(active_tween) and busy:
		active_tween.pause()
	_publish_status()
	queue_redraw()


func _resume() -> void:
	_reset_pointer()
	mode = "playing"
	if is_instance_valid(active_tween) and busy:
		active_tween.play()
	_publish_status()
	queue_redraw()


func _next_level() -> void:
	_go_level((board.level_index + 1) % 3)


func _toast(text: String) -> void:
	notice = text
	notice_time = 3.0
	queue_redraw()


func _publish_status() -> void:
	if not OS.has_feature("web"):
		return
	var text: String = "Уровень %d из 3. Ходов: %d." % [board.level_index + 1, board.moves]
	if selected >= 0:
		text += " Выбрана колба %d." % (selected + 1)
	if busy:
		text += " Переливание."
	if mode == "win":
		text += " Уровень пройден."
	elif mode in ["pause", "help", "restart"]:
		text += " Игра приостановлена."
	JavaScriptBridge.eval("window.jellyStatus && window.jellyStatus(" + JSON.stringify(text) + ");")


func _draw() -> void:
	if font == null:
		return
	_text("LEVEL %02d" % (board.level_index + 1), Vector2(360, 126), 62, Color.WHITE, true)
	_round_button(Vector2(650, 104), 39, Color("ad8ce3"), "pause", true)
	_round_button(Vector2(70, 104), 28, Color("c5b7ec"), "help", true)
	for i in range(3):
		var r: Rect2 = Rect2(291 + i * 48, 154, 42, 36)
		var current: bool = i == board.level_index
		_panel(r, Color("8c70be") if current else Color(1, 1, 1, 0.45), 16, Color(0, 0, 0, 0), 0)
		_text(str(i + 1), Vector2(r.get_center().x, 180), 22, Color.WHITE if current else INK)
		if completed.has(i):
			draw_circle(Vector2(r.end.x - 2, r.position.y + 2), 5, Color("36b5a8"))
	var instruction: String = "Выберите колбу, затем другую"
	if selected >= 0:
		instruction = "Куда перелить?"
	elif board.moves > 0:
		instruction = "Соберите каждый цвет в свою колбу"
	_text(instruction, Vector2(360, 222), 25, Color("85779f"))
	if stream_on and not transfer.is_empty():
		_draw_stream()
	var small_text: String = "ХОДЫ  %d" % board.moves
	if notice_time > 0.0:
		small_text = notice
	_text(small_text, Vector2(360, 1090), 22 if notice_time <= 0.0 else 19, Color("85779f"))
	_round_button(Vector2(270, 1160), 58, Color("ffae81"), "undo", not busy and not board.history.is_empty())
	_round_button(Vector2(450, 1160), 58, Color("48c9cb"), "restart", true)
	_text("Назад", Vector2(270, 1245), 22, INK)
	_text("Заново", Vector2(450, 1245), 22, INK)
	if mode != "playing":
		_draw_overlay()


func _text(text: String, center_baseline: Vector2, size: int, color: Color, outlined: bool = false) -> void:
	var used_font: Font = font if outlined else body_font
	var width: float = used_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos: Vector2 = center_baseline - Vector2(width * 0.5, 0)
	if outlined:
		draw_string_outline(used_font, pos + Vector2(0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color("a49ac2"))
		draw_string_outline(used_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, INK)
	draw_string(used_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _panel(rect: Rect2, fill: Color, radius: int, stroke: Color, border: int = 2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_width_top = border
	box.border_width_bottom = border
	box.border_width_left = border
	box.border_width_right = border
	box.border_color = stroke
	draw_style_box(box, rect)


func _round_button(center: Vector2, radius: float, color: Color, icon: String, enabled: bool) -> void:
	var opacity: float = 1.0 if enabled else 0.36
	draw_circle(center + Vector2(0, 7), radius + 2, Color(0.42, 0.34, 0.62, 0.16 * opacity))
	draw_circle(center + Vector2(0, 3), radius, Color(color.darkened(0.28), opacity))
	draw_circle(center, radius, Color(color.darkened(0.28), opacity))
	draw_circle(center - Vector2(0, 3), radius - 3, Color(color, opacity))
	draw_arc(center - Vector2(0, 3), radius - 8, PI * 1.04, PI * 1.85, 30, Color(1, 1, 1, 0.22 * opacity), 4, true)
	draw_circle(center + Vector2(-radius * 0.33, -radius * 0.44), radius * 0.13, Color(1, 1, 1, 0.28 * opacity))
	var fg := Color(1, 0.98, 0.94, opacity)
	if icon == "pause":
		_panel(Rect2(center + Vector2(-15, -20), Vector2(10, 33)), fg, 5, Color(0, 0, 0, 0), 0)
		_panel(Rect2(center + Vector2(5, -20), Vector2(10, 33)), fg, 5, Color(0, 0, 0, 0), 0)
	elif icon == "help":
		_text("?", center + Vector2(0, 9), 30, fg)
	elif icon == "undo":
		var points := PackedVector2Array([center + Vector2(22, 23), center + Vector2(25, 12), center + Vector2(23, 0), center + Vector2(16, -11), center + Vector2(4, -17), center + Vector2(-24, -17)])
		draw_polyline(points, Color(0.58, 0.28, 0.21, opacity), 17, true)
		draw_polyline(points, fg, 11, true)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-13, -34), center + Vector2(-35, -17), center + Vector2(-13, 1)]), fg)
	elif icon == "restart":
		draw_arc(center, radius * 0.48, 0.05, PI * 1.75, 40, Color(0.08, 0.44, 0.48, opacity), 17, true)
		draw_arc(center, radius * 0.48, 0.05, PI * 1.75, 40, fg, 11, true)
		draw_colored_polygon(PackedVector2Array([center + Vector2(6, -29), center + Vector2(30, -31), center + Vector2(30, -7)]), fg)


func _draw_stream() -> void:
	var source: int = transfer["from"]
	var target: int = transfer["to"]
	var start: Vector2 = bottles[source].to_global(bottles[source].get_pour_lip_local(pour_side))
	var end: Vector2 = bottles[target].to_global(bottles[target].get_liquid_surface_local())
	var control1: Vector2 = start + Vector2(0, 35)
	var control2: Vector2 = end - Vector2(0, 50)
	var points := PackedVector2Array()
	for i in range(21):
		var t: float = float(i) / 20.0
		var p: Vector2 = pow(1.0 - t, 3) * start + 3.0 * pow(1.0 - t, 2) * t * control1 + 3.0 * (1.0 - t) * t * t * control2 + t * t * t * end
		points.append(p)
	var color: Color = PALETTE[int(transfer["color"])]
	draw_polyline(points, color.darkened(0.1), 10, true)
	draw_polyline(points, color.lightened(0.2), 6, true)
	draw_polyline(points, Color(1, 1, 1, 0.25), 2, true)
	for i in range(3):
		var phase: float = elapsed * 8.0 + float(i) * 2.1
		draw_circle(end + Vector2(sin(phase) * 13, -absf(cos(phase)) * 15), 2.8, color.lightened(0.3))


func _modal_button(rect: Rect2, text: String, primary: bool = true) -> void:
	if primary:
		_panel(Rect2(rect.position + Vector2(0, 5), rect.size), Color("32a3a9"), 26, Color(0, 0, 0, 0), 0)
	_panel(rect, Color("50c6c5") if primary else Color("eee9fa"), 26, Color(0, 0, 0, 0), 0)
	_text(text, Vector2(rect.get_center().x, rect.get_center().y + 11), 28, Color.WHITE if primary else INK)


func _draw_overlay() -> void:
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.28, 0.23, 0.43, 0.35))
	_panel(Rect2(74, 333, 572, 672), Color(0.35, 0.24, 0.51, 0.15), 40, Color(0, 0, 0, 0), 0)
	_panel(Rect2(70, 320, 580, 672), Color("fcf9ff"), 40, Color("d4c9e8"), 3)
	if mode == "help":
		_text("Как играть", Vector2(360, 410), 43, INK)
		_text("1. Выберите колбу с жидкостью.", Vector2(360, 505), 27, INK)
		_text("2. Нажмите на пустую колбу", Vector2(360, 565), 27, INK)
		_text("или колбу с таким же цветом сверху.", Vector2(360, 605), 25, INK)
		_text("3. Соберите каждый цвет отдельно.", Vector2(360, 680), 26, INK)
		_text("Отмена хода всегда под рукой.", Vector2(360, 735), 24, Color("9585ab"))
		_modal_button(Rect2(150, 800, 420, 85), "Понятно")
		_text("Клавиатура: 1–6 · Z — назад · R — заново", Vector2(360, 940), 19, Color("9585ab"))
	elif mode == "pause":
		_text("Пауза", Vector2(360, 440), 50, INK)
		_text("Можно никуда не спешить", Vector2(360, 535), 29, Color("9585ab"))
		_text("Уровень %d  ·  Ходов: %d" % [board.level_index + 1, board.moves], Vector2(360, 620), 28, INK)
		_modal_button(Rect2(150, 800, 420, 85), "Продолжить")
		_modal_button(Rect2(150, 905, 420, 60), "Начать заново", false)
	elif mode == "restart":
		_text("Начать заново?", Vector2(360, 450), 42, INK)
		_text("Колбы вернутся в исходное состояние.", Vector2(360, 555), 25, Color("9585ab"))
		_text("Остальные уровни сохранятся.", Vector2(360, 605), 25, Color("9585ab"))
		_modal_button(Rect2(150, 720, 420, 85), "Да, заново")
		_modal_button(Rect2(150, 825, 420, 65), "Продолжить игру", false)
	elif mode == "win":
		_draw_confetti()
		for i in range(3):
			_draw_star(Vector2(280 + i * 80, 435 - (18 if i == 1 else 0)), 29 if i == 1 else 24, Color("f5bc48"))
		_text("Все цвета на месте!", Vector2(360, 545), 39, INK)
		_text("Уровень %d пройден" % (board.level_index + 1), Vector2(360, 610), 30, Color("9585ab"))
		_text("ХОДЫ  %d" % board.moves, Vector2(360, 670), 26, INK)
		_modal_button(Rect2(150, 750, 420, 85), "Следующий уровень" if board.level_index < 2 else "Сыграть ещё раз")
		_modal_button(Rect2(150, 850, 420, 65), "Повторить этот уровень", false)
		if board.level_index == 2:
			_text("Все 3 уровня пройдены — отлично!" if completed.size() == 3 else "Вы завершили третий уровень!", Vector2(360, 952), 22, Color("9585ab"))


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI / 2.0 + float(i) * PI / 5.0
		points.append(center + Vector2.from_angle(angle) * (radius if i % 2 == 0 else radius * 0.46))
	draw_colored_polygon(points, color)


func _draw_confetti() -> void:
	if win_time > 3.2:
		return
	for i in range(25):
		var x: float = 80.0 + fmod(float(i) * 91.0 + sin(win_time * 2.0 + float(i)) * 24.0, 560.0)
		var y: float = 315.0 + fmod(float(i) * 43.0 + win_time * (65.0 + float(i % 4) * 20.0), 620.0)
		var color: Color = PALETTE[i % 4]
		color.a = clampf((3.2 - win_time) * 1.4, 0.0, 1.0)
		draw_circle(Vector2(x, y), 4.0 + float(i % 3), color)
