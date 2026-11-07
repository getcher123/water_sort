extends SceneTree

const Model = preload("res://scripts/board_model.gd")
const MAX_SOLVER_STATES: int = 180000
const EXPECTED_SOLUTIONS: Array = [
	[[0, 4], [1, 0], [1, 4], [2, 1], [3, 2], [1, 3]],
	[[0, 4], [2, 0], [1, 2], [3, 4], [3, 1], [3, 0], [2, 3], [1, 2], [1, 4]],
	[[0, 4], [0, 5], [2, 5], [2, 4], [1, 2], [0, 1], [2, 0],
		[1, 2], [1, 4], [1, 5], [3, 2], [3, 0], [3, 5], [3, 4]]
]

var assertions: int = 0
var failures: Array = []
var solutions: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	test_level_definitions()
	test_invalid_actions()
	test_contiguous_pours()
	test_snapshots_history_and_restart()
	test_win_and_dead_end()
	test_level_solutions()
	test_deterministic_random_sequences()
	print(JSON.stringify({
		"suite": "Jelly Sort pure board",
		"assertions": assertions,
		"failures": failures,
		"solutions": solutions,
		"elapsed_ms": Time.get_ticks_msec() - started,
		"success": failures.is_empty()
	}))
	quit(0 if failures.is_empty() else 1)


func test_level_definitions() -> void:
	var definitions: Array = Model.levels()
	check(definitions.size() == 3, "exactly three levels")
	for index in range(definitions.size()):
		var model = Model.new(index)
		check(model.bottles.size() == 6, "level %s has six bottles" % index)
		check(model.capacity == 4, "level %s capacity four" % index)
		check(color_counts(model.bottles) == [4, 4, 4, 4], "level %s balanced colors" % index)
		var empty_count: int = 0
		for bottle in model.bottles:
			if bottle.is_empty():
				empty_count += 1
			else:
				check(bottle.size() == 4, "level %s initial filled bottle has four units" % index)
		check(empty_count == 2, "level %s starts with two empty bottles" % index)
		check(not model.is_solved(), "level %s starts unsolved" % index)
		check(model.has_moves(), "level %s starts with legal moves" % index)
	definitions[0]["board"][0][0] = 99
	check(Model.levels()[0]["board"][0][0] == 0, "level definitions cannot leak mutations")
	var clamped_low = Model.new(-8)
	var clamped_high = Model.new(50)
	check(clamped_low.level_index == 0, "negative level is clamped")
	check(clamped_high.level_index == 2, "out-of-range level is clamped")


func test_invalid_actions() -> void:
	var model = Model.new(0)
	var before: Dictionary = model.snapshot()
	var invalid: Array = [[-1, 0], [0, -1], [6, 0], [0, 6], [0, 0], [4, 0], [4, 5], [0, 1]]
	for move in invalid:
		check(not model.can_pour(move[0], move[1]), "illegal can_pour %s" % str(move))
		check(model.preview_pour(move[0], move[1]).is_empty(), "illegal preview %s" % str(move))
		check(model.pour(move[0], move[1]).is_empty(), "illegal pour %s" % str(move))
		check(model.snapshot() == before, "illegal action leaves snapshot unchanged %s" % str(move))
	check(model.history.is_empty(), "illegal actions add no history")
	check(not model.undo(), "undo with no history is false")
	var preview: Dictionary = model.preview_pour(0, 4)
	check(preview == {"from": 0, "to": 4, "color": 1, "amount": 1}, "correct first transfer preview")
	check(model.snapshot() == before, "preview does not mutate")
	model.pour(0, 4)
	var mismatched_before: Dictionary = model.snapshot()
	check(not model.can_pour(1, 4), "different top colors cannot mix")
	check(model.pour(1, 4).is_empty(), "different-color action is rejected")
	check(model.snapshot() == mismatched_before, "rejected different-color action is a no-op")


func test_contiguous_pours() -> void:
	var model = Model.new(0)
	model.bottles = [[0, 2, 2, 2], [2], [], [], [], []]
	var counts: Array = color_counts(model.bottles)
	check(model.preview_pour(0, 1)["amount"] == 3, "all contiguous top units are transferred")
	var transfer: Dictionary = model.pour(0, 1)
	check(transfer["amount"] == 3, "pour reports all three units")
	check(model.bottles[0] == [0] and model.bottles[1] == [2, 2, 2, 2], "maximal pour result")
	check(model.moves == 1, "multiple units count as one move")
	check(color_counts(model.bottles) == counts, "multiunit pour preserves colors")
	model.bottles = [[1, 1, 1], [1, 1, 1], [], [], [], []]
	check(model.preview_pour(0, 1)["amount"] == 1, "pour is limited by target capacity")
	model.pour(0, 1)
	check(model.bottles[0] == [1, 1] and model.bottles[1].size() == 4, "no target overflow")
	check(not model.can_pour(0, 1), "full target rejects further liquid")
	model.bottles = [[0, 1, 1, 2], [2, 2], [], [], [], []]
	check(model.preview_pour(0, 1)["amount"] == 1, "pour stops at first different source color")
	model.pour(0, 1)
	check(model.bottles[0] == [0, 1, 1], "lower different-color layers stay in source")
	check(not model.can_pour(0, 1), "revealed different color cannot follow automatically")


func test_snapshots_history_and_restart() -> void:
	var model = Model.new(0)
	var original: Dictionary = model.snapshot()
	var detached: Dictionary = model.snapshot()
	detached["board"][0][0] = 99
	check(model.bottles[0][0] == 0, "snapshot board is deep copied")
	model.pour(0, 4)
	var after_one: Dictionary = model.snapshot()
	model.pour(1, 0)
	check(model.moves == 2 and model.history.size() == 2, "history has one entry per successful move")
	check(model.undo(), "first undo succeeds")
	check(model.snapshot() == after_one, "undo restores previous board and move count")
	check(model.undo(), "second undo succeeds")
	check(model.snapshot() == original, "undo all restores initial state")
	check(not model.undo(), "extra undo is harmless")
	model.pour(0, 4)
	model.pour(1, 0)
	model.restart()
	check(model.snapshot() == original, "restart restores initial board, moves and empty history")
	model.pour(0, 4)
	model.load_level(2)
	check(model.level_index == 2 and model.moves == 0 and model.history.is_empty(), "changing level resets progress")
	check(model.bottles == Model.levels()[2]["board"], "load_level loads requested board")
	model.pour(0, 4)
	model.restart()
	check(model.bottles == Model.levels()[2]["board"], "restart retains the current level")


func test_win_and_dead_end() -> void:
	var model = Model.new(0)
	model.bottles = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3], [], []]
	check(model.is_solved(), "four uniform full bottles win")
	model.bottles = [[0, 0], [0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3], []]
	check(not model.is_solved(), "uniform partial bottles do not win")
	model.bottles = [[0, 0, 0, 1], [1, 1, 1, 0], [2, 2, 2, 2], [3, 3, 3, 3], [], []]
	check(not model.is_solved(), "mixed full bottles do not win")
	model.bottles = [[], [], [], [], [], []]
	check(not model.is_solved(), "an empty board is not a win")
	check(not model.has_moves(), "an empty board has no legal moves")
	model.bottles = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 1, 2, 2], [3, 3, 0, 0]]
	check(not model.is_solved() and not model.has_moves(), "full mixed dead end detected")
	model.bottles.append([])
	check(model.has_moves(), "available empty bottle permits a move")


func test_level_solutions() -> void:
	for index in range(Model.levels().size()):
		var model = Model.new(index)
		var original: Dictionary = model.snapshot()
		var proof: Dictionary = solve(model.bottles, model.capacity)
		var path: Array = EXPECTED_SOLUTIONS[index]
		check(proof["found"], "level %s has a BFS solution" % index)
		if not proof["found"]:
			continue
		check(proof["path"].size() == path.size(), "level %s saved solution has optimal BFS length" % index)
		solutions.append({"level": index, "moves": path.size(), "path": path, "visited_states": proof["visited"]})
		for pair in path:
			var before_counts: Array = color_counts(model.bottles)
			var result: Dictionary = model.pour(pair[0], pair[1])
			check(not result.is_empty(), "level %s solution step %s is legal" % [index, str(pair)])
			check(color_counts(model.bottles) == before_counts, "level %s solution conserves colors" % index)
			check(valid_capacities(model.bottles, 4), "level %s solution never overflows" % index)
		check(model.is_solved(), "level %s explicit solution reaches win" % index)
		check(model.moves == path.size(), "level %s solution move count exact" % index)
		for _step in range(path.size()):
			check(model.undo(), "level %s undo every solution move" % index)
		check(model.snapshot() == original, "level %s undo complete solution restores original" % index)


func test_deterministic_random_sequences() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261107
	for index in range(Model.levels().size()):
		var model = Model.new(index)
		for step in range(240):
			var legal: Array = []
			for source in range(model.bottles.size()):
				for target in range(model.bottles.size()):
					if model.can_pour(source, target):
						legal.append([source, target])
			if legal.is_empty():
				model.restart()
				continue
			var before: Dictionary = model.snapshot()
			var pair: Array = legal[rng.randi_range(0, legal.size() - 1)]
			var preview: Dictionary = model.preview_pour(pair[0], pair[1])
			var result: Dictionary = model.pour(pair[0], pair[1])
			check(result == preview, "random transfer matches preview")
			check(color_counts(model.bottles) == [4, 4, 4, 4], "random transfer conserves every color")
			check(valid_capacities(model.bottles, 4), "random transfer respects capacity")
			check(model.moves == int(before["moves"]) + 1, "random move increments exactly once")
			if step % 4 == 0:
				check(model.undo(), "random undo succeeds")
				check(model.snapshot() == before, "random undo restores exact prior snapshot")


func color_counts(board: Array) -> Array:
	var counts: Array = [0, 0, 0, 0]
	for bottle in board:
		for color in bottle:
			if int(color) < 0 or int(color) >= counts.size():
				return []
			counts[int(color)] += 1
	return counts


func valid_capacities(board: Array, limit: int) -> bool:
	for bottle in board:
		if bottle.size() > limit:
			return false
	return true


func solve(initial: Array, limit: int) -> Dictionary:
	# Breadth-first proof. Bottle permutation is only a deduplication key;
	# concrete boards and parent moves retain their original indices.
	var queue: Array = [{"board": initial.duplicate(true), "parent": -1, "move": []}]
	var seen: Dictionary = {canonical_key(initial): true}
	var head: int = 0
	var probe = Model.new(0)
	probe.capacity = limit
	while head < queue.size() and queue.size() <= MAX_SOLVER_STATES:
		var current: Dictionary = queue[head]
		probe.bottles = current["board"]
		if probe.is_solved():
			var path: Array = []
			var position: int = head
			while int(queue[position]["parent"]) >= 0:
				path.push_front(queue[position]["move"])
				position = int(queue[position]["parent"])
			return {"found": true, "path": path, "visited": queue.size()}
		for source in range(probe.bottles.size()):
			for target in range(probe.bottles.size()):
				var transfer: Dictionary = probe.preview_pour(source, target)
				if transfer.is_empty():
					continue
				var next: Array = probe.bottles.duplicate(true)
				for _unit in range(int(transfer["amount"])):
					next[target].append(next[source].pop_back())
				var key: String = canonical_key(next)
				if seen.has(key):
					continue
				seen[key] = true
				queue.append({"board": next, "parent": head, "move": [source, target]})
		head += 1
	return {"found": false, "path": [], "visited": queue.size()}


func canonical_key(board: Array) -> String:
	var encoded: Array[String] = []
	for bottle in board:
		var value: String = ""
		for color in bottle:
			value += str(int(color))
		encoded.append(value)
	encoded.sort()
	return "|".join(encoded)
