# Pure board model and solvability report

Date: 2026-11-07. Project: Lumeriq Jelly Sort, selected B1F1 direction.

## Scope

Implemented only `godot/scripts/board_model.gd` and `godot/tests/test_board.gd`.
The model is independent of rendering, input, animation, advertising and storage.
No user-device jobs, paid model calls or dependency installation were used.

Godot verified: `4.6.3.stable.official.7d41c59c4` on the cloud executor.
This report does not claim Android, native Windows, touch-device or browser QA.

## API for the controller

Load with `const Model = preload("res://scripts/board_model.gd")`; create with
`var board = Model.new()` or `Model.new(level_index)`.

| Member | Contract |
| --- | --- |
| `bottles` | Array of six arrays of integer colors, bottom-to-top |
| `capacity` | 4 for every shipped level |
| `moves` | Successful transfers, not units; invalid actions do not increment |
| `level_index` | Zero-based; `load_level` clamps to 0–2 |
| `history` | One deep-copied prior state per successful transfer |
| `levels()` | Three fresh level definitions with `id`, `title`, `board` |
| `load_level(index)` | Load starting layout, reset moves and history |
| `can_pour(source, target)` | Legal iff indices valid, different bottles, nonempty source, nonfull target, and target empty or same top color |
| `preview_pour(source, target)` | Nonmutating `{from, to, color, amount}`; `{}` for invalid action |
| `pour(source, target)` | Move the maximal contiguous top-color run that fits; return transfer record or `{}` |
| `undo()` | Restore exactly one previous board and move count; return false when unavailable |
| `restart()` | Restore the current level and clear history/moves |
| `is_solved()` | At least one nonempty bottle; every nonempty bottle is full and uniform |
| `has_moves()` | At least one legal transfer; controller should check victory separately |
| `snapshot()` | Deep-copied `board`, plus `capacity`, `moves`, `level`, `solved`, `can_undo` |

For animation: call `preview_pour`, retain a deep copy of the old board,
execute one `pour`, and animate visuals between old and new states. Lock UI
actions for the duration in the controller; the pure model does not own an
animation lock. Do not mutate `bottles` for visual interpolation.

## Shipped levels and explicit solutions

All boards have exactly four units of each of the four colors and two initially
empty bottles. Color numbers: 0 coral, 1 gold, 2 teal, 3 purple.

Bottle indices below are zero-based, in screen order: top row 0, 1, 2;
bottom row 3, 4, 5. Arrays are bottom-to-top.

### Level 1 — Первые капли

Board: `[[0,0,0,1],[1,1,1,0],[2,2,2,3],[3,3,3,2],[],[]]`.

Shortest solution: **6 moves**. BFS visited 40 symmetry-reduced states.

`[[0,4],[1,0],[1,4],[2,1],[3,2],[1,3]]`

### Level 2 — Цветовой ритм

Board: `[[0,0,1,1],[1,2,2,3],[2,3,3,0],[3,0,2,1],[],[]]`.

Shortest solution: **9 moves**. BFS visited 255 symmetry-reduced states.

`[[0,4],[2,0],[1,2],[3,4],[3,1],[3,0],[2,3],[1,2],[1,4]]`

### Level 3 — Поток цвета

Board: `[[3,2,1,0],[1,0,2,3],[2,3,0,1],[0,1,3,2],[],[]]`.
This matches the colored layer ordering in the selected concept.

Shortest solution: **14 moves**. BFS visited 1,016 symmetry-reduced states.

`[[0,4],[0,5],[2,5],[2,4],[1,2],[0,1],[2,0],[1,2],[1,4],[1,5],[3,2],[3,0],[3,5],[3,4]]`

The test contains these concrete paths and independently finds a BFS solution.
It verifies that each saved path has the shortest BFS length, every step is
legal, all colors are conserved, no bottle overflows, and the final state wins.
BFS uses bottle permutation only for state deduplication; stored concrete states
retain bottle indices, so their reconstructed moves are playable.

## Verification

Command:

```bash
godot --headless --path godot --script tests/test_board.gd
```

Final suite: **3,473 assertions, zero failures**, exit code 0.

Coverage:

- Level dimensions, color counts, initial empty bottles and unsolved state.
- Out-of-range/self/empty-source/full-target/wrong-color rejection.
- Invalid actions and preview are nonmutating and create no history.
- Maximal same-color pours, source-color boundaries and destination capacity.
- Multiunit transfer counts as one move.
- Snapshot and level-definition deep-copy isolation.
- Single and multiple undo, unavailable undo, restart, level change.
- Full uniform victory versus partial-uniform, mixed and empty states.
- No-moves detection and restoration of a legal move with an empty bottle.
- BFS solvability and replay of all three explicit paths; undo of every path.
- 720 seeded random move attempts across three levels, with periodic undo,
  color-conservation and capacity checks after actual transfers.

No changes to `.openai/hosting.json`, Godot project configuration, controller,
view scripts or source publication were made by this task.
