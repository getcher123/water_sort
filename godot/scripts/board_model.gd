class_name SortBoard
extends RefCounted
## Pure deterministic Water Sort rules. Bottle arrays are ordered bottom-to-top.
## Presentation, animation, input locks and persistence belong to the controller.

const DEFAULT_CAPACITY: int = 4

var bottles: Array = []
var capacity: int = DEFAULT_CAPACITY
var moves: int = 0
var history: Array = []
var level_index: int = 0
var _initial_board: Array = []


func _init(start_level: int = 0) -> void:
	load_level(start_level)


static func levels() -> Array:
	# New nested arrays on every call prevent callers from modifying the level data.
	return [
		{
			"id": "first_drops",
			"title": "Первые капли",
			"board": [
				[0, 0, 0, 1], [1, 1, 1, 0], [2, 2, 2, 3],
				[3, 3, 3, 2], [], []
			]
		},
		{
			"id": "color_rhythm",
			"title": "Цветовой ритм",
			"board": [
				[0, 0, 1, 1], [1, 2, 2, 3], [2, 3, 3, 0],
				[3, 0, 2, 1], [], []
			]
		},
		{
			"id": "jelly_flow",
			"title": "Поток цвета",
			"board": [
				[3, 2, 1, 0], [1, 0, 2, 3], [2, 3, 0, 1],
				[0, 1, 3, 2], [], []
			]
		}
	]


func load_level(index: int) -> void:
	var definitions: Array = levels()
	level_index = clampi(index, 0, definitions.size() - 1)
	capacity = DEFAULT_CAPACITY
	_initial_board = definitions[level_index]["board"].duplicate(true)
	bottles = _initial_board.duplicate(true)
	moves = 0
	history.clear()


func can_pour(source: int, target: int) -> bool:
	if source < 0 or target < 0 or source >= bottles.size() or target >= bottles.size():
		return false
	if source == target or capacity <= 0:
		return false
	var from_bottle: Array = bottles[source]
	var to_bottle: Array = bottles[target]
	if from_bottle.is_empty() or to_bottle.size() >= capacity:
		return false
	return to_bottle.is_empty() or from_bottle.back() == to_bottle.back()


func preview_pour(source: int, target: int) -> Dictionary:
	if not can_pour(source, target):
		return {}
	var from_bottle: Array = bottles[source]
	var to_bottle: Array = bottles[target]
	var color: int = int(from_bottle.back())
	var contiguous: int = 0
	for i in range(from_bottle.size() - 1, -1, -1):
		if int(from_bottle[i]) != color:
			break
		contiguous += 1
	var amount: int = mini(contiguous, capacity - to_bottle.size())
	return {"from": source, "to": target, "color": color, "amount": amount}


func pour(source: int, target: int) -> Dictionary:
	var transfer: Dictionary = preview_pour(source, target)
	if transfer.is_empty():
		return {}
	history.append({"board": bottles.duplicate(true), "moves": moves})
	var from_bottle: Array = bottles[source]
	var to_bottle: Array = bottles[target]
	for _unit in range(int(transfer["amount"])):
		to_bottle.append(from_bottle.pop_back())
	moves += 1
	return transfer


func undo() -> bool:
	if history.is_empty():
		return false
	var previous: Dictionary = history.pop_back()
	bottles = previous["board"].duplicate(true)
	moves = int(previous["moves"])
	return true


func restart() -> void:
	bottles = _initial_board.duplicate(true)
	capacity = DEFAULT_CAPACITY
	moves = 0
	history.clear()


func is_solved() -> bool:
	var has_liquid: bool = false
	for bottle in bottles:
		if bottle.is_empty():
			continue
		has_liquid = true
		if bottle.size() != capacity:
			return false
		var color: int = int(bottle[0])
		for unit in bottle:
			if int(unit) != color:
				return false
	return has_liquid


func has_moves() -> bool:
	for source in range(bottles.size()):
		for target in range(bottles.size()):
			if can_pour(source, target):
				return true
	return false


func snapshot() -> Dictionary:
	return {
		"board": bottles.duplicate(true),
		"capacity": capacity,
		"moves": moves,
		"level": level_index,
		"solved": is_solved(),
		"can_undo": not history.is_empty()
	}
