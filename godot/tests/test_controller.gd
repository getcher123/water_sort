extends SceneTree
## Integration test of the actual scene, controller, views and real engine Tweens.
## Gameplay is driven by screen-coordinate taps, never direct board mutation.

const MainScene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/board_model.gd")
const PROGRESS_PATH: String = "user://progress.cfg"
const BOTTLE_POINTS: Array[Vector2] = [
	Vector2(150, 430), Vector2(360, 430), Vector2(570, 430),
	Vector2(150, 850), Vector2(360, 850), Vector2(570, 850)
]
const BASE_POSITIONS: Array[Vector2] = [
	Vector2(150, 610), Vector2(360, 610), Vector2(570, 610),
	Vector2(150, 1030), Vector2(360, 1030), Vector2(570, 1030)
]
const SOLUTIONS: Array = [
	[[0, 4], [1, 0], [1, 4], [2, 1], [3, 2], [1, 3]],
	[[0, 4], [2, 0], [1, 2], [3, 4], [3, 1], [3, 0], [2, 3], [1, 2], [1, 4]],
	[[0, 4], [0, 5], [2, 5], [2, 4], [1, 2], [0, 1], [2, 0],
		[1, 2], [1, 4], [1, 5], [3, 2], [3, 0], [3, 5], [3, 4]]
]

var game: Node2D
var assertions: int = 0
var failures: Array = []
var events: Array = []
var had_progress: bool = false
var original_progress: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var source_sha256: String = FileAccess.get_sha256("res://scripts/main.gd")
	had_progress = FileAccess.file_exists(PROGRESS_PATH)
	if had_progress:
		original_progress = FileAccess.get_file_as_bytes(PROGRESS_PATH)
	Engine.time_scale = 8.0
	game = MainScene.instantiate()
	root.add_child(game)
	await process_frame
	# The only direct setup transition; later level changes and restarts use taps.
	game._go_level(0)
	check(game.mode == "playing", "scene starts playing")
	check(not game.busy and game.selected == -1, "scene starts idle and unselected")
	check(game.bottles.size() == 6, "six actual BottleView children instantiated")
	check(game.board.bottles == Model.levels()[0]["board"], "initial setup loads level one")

	test_selection_and_invalid_pours()
	test_pointer_transitions()
	await test_pour_atomicity_lock_and_undo()
	await test_pause_and_resume_during_pour()
	await test_focus_loss_during_pour()
	await test_restart_cancels_tween()
	await test_level_selection()
	await test_all_wins_and_next_level()

	game.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	_restore_progress()
	check(FileAccess.get_sha256("res://scripts/main.gd") == source_sha256, "controller source remains unchanged during integration run")
	print(JSON.stringify({
		"suite": "Jelly Sort controller integration",
		"assertions": assertions,
		"failures": failures,
		"events": events,
		"elapsed_ms": Time.get_ticks_msec() - started,
		"engine_time_scale_for_tweens": 8,
		"controller_sha256": source_sha256,
		"pause_waits_use_real_time": true,
		"success": failures.is_empty()
	}))
	quit(0 if failures.is_empty() else 1)


func _restore_progress() -> void:
	if had_progress:
		var file: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
		check(file != null, "can restore pre-test progress file")
		if file != null:
			file.store_buffer(original_progress)
			file.close()
			check(FileAccess.get_file_as_bytes(PROGRESS_PATH) == original_progress, "pre-test progress restored byte-for-byte")
	elif FileAccess.file_exists(PROGRESS_PATH):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH)) == OK, "remove only test-created progress file")


func tap_bottle(index: int) -> void:
	game._tap(BOTTLE_POINTS[index])


func tap_level(index: int) -> void:
	game._tap(Vector2(312 + index * 48, 174))


func restart_via_ui() -> void:
	game._tap(Vector2(450, 1160))
	check(game.mode == "restart", "restart button opens confirmation")
	game._tap(Vector2(360, 760))
	check(game.mode == "playing" and not game.busy, "restart confirmation returns to idle play")


func await_idle(label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 1500
	while game.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	var finished: bool = not game.busy
	check(finished, label + " completes within 1.5 real seconds")
	return finished


func await_stream(label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 1000
	while game.busy and not game.stream_on and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.busy and game.stream_on, label + " reaches real stream animation")
	return game.busy and game.stream_on


func test_selection_and_invalid_pours() -> void:
	var original: Dictionary = game.board.snapshot()
	tap_bottle(0)
	check(game.selected == 0, "bottle tap selects source")
	check(game.bottles[0].selected, "selected source is reflected in view")
	check(game.bottles[4].hinted and game.bottles[5].hinted, "empty destinations are visually hinted")
	tap_bottle(0)
	check(game.selected == -1 and not game.bottles[0].selected, "second tap deselects")
	tap_bottle(4)
	check(game.selected == -1, "empty bottle without source remains unselected")
	check(game.board.snapshot() == original, "empty tap does not change model")
	tap_bottle(0)
	game._tap(Vector2(30, 640))
	check(game.selected == -1, "background tap clears selection")
	tap_bottle(0)
	tap_bottle(1)
	check(game.board.snapshot() == original and not game.busy, "full/wrong-color target cannot change board")
	check(game.selected == 1, "invalid target can become the newly selected source")
	check(game.notice_time > 0.0, "invalid transfer gives feedback")
	tap_bottle(1)
	game._tap(Vector2(70, 104))
	check(game.mode == "help", "help button opens instructions")
	tap_bottle(0)
	check(game.board.snapshot() == original, "instruction overlay blocks bottle taps")
	game._tap(Vector2(360, 840))
	check(game.mode == "playing", "help continue returns to playing")
	events.append("selection, deselection, invalid input and help passed")


func send_touch(index: int, pressed: bool, at: Vector2, canceled: bool = false) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	event.canceled = canceled
	game._input(event)


func test_pointer_transitions() -> void:
	var before: Dictionary = game.board.snapshot()
	send_touch(0, true, BOTTLE_POINTS[0])
	check(game.pointer_down and game.active_touch == 0, "primary touch press is tracked")
	send_touch(0, false, BOTTLE_POINTS[0], true)
	check(game.selected == -1 and game.board.snapshot() == before, "canceled primary touch never triggers a tap")
	check(not game.pointer_down and game.active_touch == -1, "canceled primary touch clears tracking")
	send_touch(0, true, BOTTLE_POINTS[0])
	send_touch(1, true, BOTTLE_POINTS[1])
	send_touch(1, false, BOTTLE_POINTS[1])
	check(game.pointer_down and game.active_touch == 0, "secondary finger cannot steal primary gesture")
	send_touch(0, false, BOTTLE_POINTS[0])
	check(game.selected == 0 and game.board.snapshot() == before, "primary release selects exactly one bottle")
	tap_bottle(0)

	# A release begun on the game must not click a newly appeared modal button.
	var shared_point: Vector2 = Vector2(360, 840)
	send_touch(0, true, shared_point)
	var pause_key: InputEventKey = InputEventKey.new()
	pause_key.keycode = KEY_P
	pause_key.pressed = true
	game._input(pause_key)
	check(game.mode == "pause", "keyboard pause opens while a touch is held")
	send_touch(0, false, shared_point)
	check(game.mode == "pause", "stale touch release cannot activate newly opened pause modal")
	check(game.board.snapshot() == before, "overlay transition does not mutate board")
	if game.mode == "pause":
		game._tap(Vector2(360, 840))

	# A level transition also invalidates a gesture begun on the old board.
	send_touch(0, true, BOTTLE_POINTS[0])
	tap_level(1)
	check(game.board.level_index == 1, "level transition occurs while old touch is held")
	send_touch(0, false, BOTTLE_POINTS[0])
	check(game.selected == -1, "stale touch release cannot select a bottle on new level")
	check(game.board.moves == 0 and not game.busy, "stale level gesture cannot start a move")
	if game.selected >= 0:
		tap_bottle(game.selected)
	tap_level(0)

	send_touch(0, true, shared_point)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.mode == "pause", "application focus loss automatically pauses play")
	check(not game.pointer_down and game.active_touch == -1, "focus loss clears held pointer")
	send_touch(0, false, shared_point)
	check(game.mode == "pause", "stale release after focus loss cannot activate Continue")
	check(game.board.snapshot() == before, "focus loss preserves idle board")
	game._tap(Vector2(360, 840))
	check(game.mode == "playing", "fresh continue resumes after focus loss")
	events.append("touch cancellation, secondary finger and transition-boundary checks executed")


func test_pour_atomicity_lock_and_undo() -> void:
	var original: Dictionary = game.board.snapshot()
	var oracle = Model.new(0)
	var expected_transfer: Dictionary = oracle.pour(0, 4)
	var expected: Dictionary = oracle.snapshot()
	tap_bottle(0)
	tap_bottle(4)
	check(game.busy and game.mode == "playing", "valid destination starts animation")
	check(game.selected == -1, "pour clears selection")
	check(game.transfer == expected_transfer, "controller records correct transfer")
	check(game.board.snapshot() == expected, "logical transfer is committed atomically at animation start")
	check(is_equal_approx(visual_amount(0), 4.0) and is_equal_approx(visual_amount(4), 0.0), "views begin at the pre-transfer contents")
	var initial_epoch: int = game.epoch
	for _spam in range(8):
		tap_bottle(1)
		tap_bottle(0)
		game._tap(Vector2(270, 1160))
		tap_level(2)
	check(game.board.snapshot() == expected, "rapid taps, undo and level selection cannot double-apply while busy")
	check(game.epoch == initial_epoch and game.busy, "rapid input does not replace active animation")
	if not await await_idle("first pour"):
		return
	check(game.board.snapshot() == expected, "animation completion does not commit the move twice")
	check(not game.stream_on, "stream is cleared on completion")
	check_views_match_board("first completed pour")
	check_neutral_transforms("first completed pour")
	tap_bottle(1)
	tap_bottle(4)
	check(game.board.snapshot() == expected, "wrong-color partially filled destination is rejected through taps")
	check(not game.busy and game.mode == "playing", "wrong-color destination cannot start a Tween")
	game._tap(Vector2(270, 1160))
	check(game.board.snapshot() == original, "undo button restores exact pre-transfer model")
	check(game.selected == -1 and not game.busy, "undo returns to clean idle state")
	check_views_match_board("after undo")
	events.append("atomic transfer, real Tween completion, input lock and undo passed")


func test_pause_and_resume_during_pour() -> void:
	tap_bottle(0)
	tap_bottle(4)
	if not await await_stream("pause test"):
		return
	game._tap(Vector2(650, 104))
	check(game.mode == "pause" and game.busy, "pause opens during an active pour")
	check(not game.active_tween.is_running(), "pause actually stops the engine Tween")
	var paused_state: Dictionary = game.board.snapshot()
	var paused_position: Vector2 = game.bottles[0].position
	var paused_rotation: float = game.bottles[0].rotation
	var paused_progress: float = game.stream_progress
	var paused_source_units: Array = game.bottles[0].visual_units.duplicate(true)
	var paused_target_units: Array = game.bottles[4].visual_units.duplicate(true)
	await create_timer(0.22, true, false, true).timeout
	check(game.mode == "pause" and game.busy, "pause remains active after real wall-clock wait")
	check(game.board.snapshot() == paused_state, "paused logical board remains unchanged")
	check(game.bottles[0].position.is_equal_approx(paused_position), "paused bottle position is frozen")
	check(is_equal_approx(game.bottles[0].rotation, paused_rotation), "paused bottle rotation is frozen")
	check(is_equal_approx(game.stream_progress, paused_progress), "paused liquid interpolation is frozen")
	check(game.bottles[0].visual_units == paused_source_units and game.bottles[4].visual_units == paused_target_units, "paused visual amounts do not drift")
	tap_bottle(0)
	game._tap(Vector2(270, 1160))
	check(game.board.snapshot() == paused_state and game.mode == "pause", "pause overlay blocks bottle and undo inputs")
	game._tap(Vector2(360, 840))
	check(game.mode == "playing" and game.busy, "continue resumes the interrupted pour")
	check(game.active_tween.is_running(), "continue restarts the same engine Tween")
	if not await await_idle("resumed pour"):
		return
	check(game.board.snapshot() == paused_state, "resume neither duplicates nor drops transfer")
	check_views_match_board("after pause and resume")
	restart_via_ui()
	check(game.board.bottles == Model.levels()[0]["board"] and game.board.moves == 0, "restart after pause test resets level")
	events.append("pause/resume freezes real Tween geometry and liquid without state drift")


func test_focus_loss_during_pour() -> void:
	tap_bottle(0)
	tap_bottle(4)
	if not await await_stream("focus loss test"):
		return
	var committed: Dictionary = game.board.snapshot()
	var shared_point: Vector2 = Vector2(360, 840)
	send_touch(0, true, shared_point)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.mode == "pause" and game.busy, "focus loss pauses an active pour")
	check(not game.active_tween.is_running(), "focus loss stops the real Tween")
	check(not game.pointer_down and game.active_touch == -1, "focus loss during pour clears held touch")
	var position: Vector2 = game.bottles[0].position
	var progress: float = game.stream_progress
	send_touch(0, false, shared_point)
	check(game.mode == "pause", "old touch release cannot resume focus-paused pour")
	await create_timer(0.16, true, false, true).timeout
	check(game.bottles[0].position.is_equal_approx(position) and is_equal_approx(game.stream_progress, progress), "focus-paused geometry and liquid stay frozen in real time")
	check(game.board.snapshot() == committed, "focus loss preserves one atomic transfer")
	game._tap(Vector2(360, 840))
	check(game.mode == "playing" and game.busy, "fresh tap resumes focus-paused pour")
	if not await await_idle("focus-paused pour"):
		return
	check(game.board.snapshot() == committed, "focus resume does not duplicate transfer")
	check_views_match_board("after focus-loss resume")
	restart_via_ui()
	events.append("focus-loss notification freezes active pour and invalidates stale touch release")


func test_restart_cancels_tween() -> void:
	tap_bottle(0)
	tap_bottle(4)
	await process_frame
	var committed: Dictionary = game.board.snapshot()
	game._tap(Vector2(450, 1160))
	check(game.mode == "restart" and game.busy, "restart confirmation can open mid-pour")
	check(not game.active_tween.is_running(), "restart confirmation pauses the active Tween")
	game._tap(Vector2(360, 855))
	check(game.mode == "playing" and game.busy, "cancel restart resumes existing pour")
	check(game.board.snapshot() == committed, "cancel restart preserves exactly one committed move")
	var old_epoch: int = game.epoch
	game._tap(Vector2(450, 1160))
	game._tap(Vector2(360, 760))
	check(game.mode == "playing" and not game.busy, "confirm restart cancels busy state")
	check(game.epoch > old_epoch, "restart invalidates old animation epoch")
	check(game.active_tween == null and game.transfer.is_empty(), "restart removes active Tween and transfer record")
	check(game.board.bottles == Model.levels()[0]["board"], "mid-pour restart restores original board")
	check(game.board.moves == 0 and game.board.history.is_empty(), "mid-pour restart resets moves and undo")
	check_views_match_board("immediately after mid-pour restart")
	check_neutral_transforms("immediately after mid-pour restart")
	var restarted: Dictionary = game.board.snapshot()
	await create_timer(0.24, true, false, true).timeout
	check(game.board.snapshot() == restarted and game.mode == "playing" and not game.busy, "killed Tween cannot later mutate restarted game")
	check_views_match_board("after old Tween would have finished")
	check_neutral_transforms("after old Tween would have finished")
	game._tap(Vector2(650, 104))
	game._tap(Vector2(360, 935))
	check(game.mode == "restart", "pause menu can enter restart confirmation")
	game._tap(Vector2(360, 760))
	check(game.mode == "playing" and game.board.moves == 0, "restart from pause menu returns to play")
	events.append("restart cancel/confirm and epoch guard prevent late callbacks")


func test_level_selection() -> void:
	tap_bottle(0)
	tap_level(1)
	check(game.board.level_index == 1, "level selector opens second level")
	check(game.selected == -1 and game.board.moves == 0 and game.board.history.is_empty(), "level selector resets selection/moves/history")
	check(game.board.bottles == Model.levels()[1]["board"], "level selector loads correct contents")
	tap_bottle(0)
	tap_bottle(4)
	if not await await_idle("level two opening pour"):
		return
	check(game.board.moves == 1, "level two is playable through taps")
	tap_level(2)
	check(game.board.level_index == 2 and game.board.moves == 0, "third-level selector resets previous progress")
	check(game.board.bottles == Model.levels()[2]["board"] and game.board.history.is_empty(), "third-level selector loads exact third board")
	check_views_match_board("after level change")
	check_neutral_transforms("after level change")
	tap_level(0)
	check(game.board.level_index == 0, "selector returns to first level")
	events.append("level navigation resets logical and visual state")


func test_all_wins_and_next_level() -> void:
	for level in range(SOLUTIONS.size()):
		check(game.board.level_index == level and game.mode == "playing", "level %s ready for full walkthrough" % level)
		var path: Array = SOLUTIONS[level]
		for step in range(path.size()):
			var pair: Array = path[step]
			tap_bottle(pair[0])
			tap_bottle(pair[1])
			check(game.busy, "level %s move %s starts through taps" % [level, step])
			check(game.board.moves == step + 1, "level %s move %s counted once at start" % [level, step])
			if step == path.size() - 1:
				check(game.board.is_solved(), "final logical transfer solves level %s" % level)
				check(game.mode == "playing", "win modal waits for animation on level %s" % level)
				game._tap(Vector2(360, 790))
				check(game.board.level_index == level and game.mode == "playing", "next-button position cannot skip active winning animation")
			if not await await_idle("level %s move %s" % [level, step]):
				return
			check(game.board.moves == step + 1, "level %s move %s counted once after Tween" % [level, step])
			check_views_match_board("level %s move %s" % [level, step])
		check(game.mode == "win" and game.board.is_solved(), "level %s reaches real win modal" % level)
		check(game.completed.has(level), "level %s completion recorded" % level)
		var full_views: int = 0
		for bottle in game.bottles:
			if bottle.completed:
				full_views += 1
		check(full_views == 4, "level %s shows four completed bottles" % level)
		var winning_snapshot: Dictionary = game.board.snapshot()
		tap_bottle(0)
		game._tap(Vector2(270, 1160))
		check(game.board.snapshot() == winning_snapshot and game.mode == "win", "winning overlay blocks background game actions")
		game._tap(Vector2(360, 790))
		var next_index: int = (level + 1) % 3
		check(game.board.level_index == next_index and game.mode == "playing", "next-level button advances/wraps correctly")
		check(not game.busy and game.selected == -1 and game.board.moves == 0 and game.board.history.is_empty(), "next-level button creates clean play state")
		check(game.board.bottles == Model.levels()[next_index]["board"], "next-level button loads exact new board")
		events.append("level %s solved in %s real animated moves; next button passed" % [level + 1, path.size()])
	check(game.completed.has(0) and game.completed.has(1) and game.completed.has(2), "all three completions retained after replay wrap")


func visual_amount(index: int) -> float:
	var total: float = 0.0
	for item in game.bottles[index].visual_units:
		total += float(item["amount"])
	return total


func expected_units(contents: Array) -> Array:
	var grouped: Array = []
	for color in contents:
		if not grouped.is_empty() and grouped.back()["color"] == color:
			grouped.back()["amount"] += 1.0
		else:
			grouped.append({"color": int(color), "amount": 1.0})
	return grouped


func check_views_match_board(label: String) -> void:
	for index in range(6):
		check(game.bottles[index].visual_units == expected_units(game.board.bottles[index]), label + " view %s matches board" % index)


func check_neutral_transforms(label: String) -> void:
	for index in range(6):
		check(game.bottles[index].position.is_equal_approx(BASE_POSITIONS[index]), label + " bottle %s restored position" % index)
		check(is_zero_approx(game.bottles[index].rotation), label + " bottle %s restored rotation" % index)
