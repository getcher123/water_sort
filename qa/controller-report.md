# Controller / real Tween integration report

Date: 2026-11-07. Project: Lumeriq Jelly Sort, Godot B1F1 prototype.

## Final result

**PASS — 513 assertions, zero failures, exit code 0.**

Final release-build rerun by root: 6,296 ms (after stream endpoint correction). Runtime: Godot `4.6.3.stable.official.7d41c59c4`, cloud,
headless renderer. The test instantiated the actual `scenes/main.tscn`, its
controller and six actual BottleView nodes. Engine Tweens processed normally;
they were not mocked, manually advanced or replaced with immediate mutations.

Verified controller SHA-256:

`90498aec04916d4e6c05f9b2a9d7ee2a7da5c05455d9cd4384337c641b67528d`

The test verifies that this source hash does not change during the run.

Command:

```bash
godot --headless --path godot --script tests/test_controller.gd
```

The script uses `Engine.time_scale = 8` to keep the test short. Pause/focus-loss
checks explicitly use timers with `ignore_time_scale = true`, so their freeze
checks wait 220 ms and 160 ms of actual wall-clock time. A hard 25-second process
limit and bounded per-animation waits prevent unbounded runtime.

The existing `user://progress.cfg`, if present, is preserved and restored
byte-for-byte. If absent before testing, only the test-created progress file is
removed. An existing progress file adds one extra restore assertion, so a run
can report 514 rather than 513 assertions without changing gameplay coverage.
Do not run this suite concurrently with another native instance that writes
the same project's progress file.

## Covered behavior

Normal gameplay uses actual screen-coordinate `Main._tap` calls. The only
direct setup transition is `_go_level(0)` to avoid saved progress affecting the
starting level. No game board arrays are modified directly by the test.

- Scene creation, six actual bottle views and initial idle state.
- Source selection, same-bottle deselection, background deselection.
- Empty-source selection and full/wrong-color destination rejection.
- Rejection of a different-color destination that is only partially full.
- Destination hint flags and invalid-action feedback.
- Help overlay and return to gameplay.
- Atomic logical transfer committed once at animation start.
- Pre-transfer visual state at start, actual Tween completion, final model/view
  agreement, stream cleanup and neutral bottle transforms.
- Rapid repeated bottle taps, undo and level-selector taps while busy cannot
  create another transfer, cancel the current animation or change levels.
- Undo after an animated move restores exact board, move count and views.
- Pause during the stream, frozen bottle position/rotation/liquid interpolation,
  blocked background actions, and continuation of the same Tween.
- Restart confirmation pauses the current Tween; cancel resumes it unchanged.
- Confirmed mid-pour restart kills the Tween, invalidates its epoch, clears
  transfer/busy/history/moves, and restores both logical and visual state.
- After the old Tween would have completed, no stale callback changes the reset
  game. Restart through the pause menu is also exercised.
- Level selectors load the correct layouts and reset selection/history/moves.
- All three complete solutions are played through screen taps with real
  animations: 6, 9 and 14 moves.
- Victory is logically reached on the final transfer, but the win overlay waits
  for that animation to finish. Premature taps cannot skip the winning animation.
- All four completed-bottle flags, recorded completion, blocked background
  actions on the win screen, next-level buttons and level-three replay wrap.

## Touch and focus regression findings

The extended tests also dispatch `InputEventScreenTouch` objects through the
real controller `_input` method. They cover primary cancellation, secondary
finger ownership and stale releases crossing state transitions.

Two defects were reproduced before the owner patch on controller hash
`a48b2100142343f7d8e27d01cee776548077c7c12ea6234d7ba52c3e498e6e3e`:

1. Press at `(360,840)`, open pause using key P, then release the old touch at
   the same coordinate. The stale release activated the newly displayed Continue
   button and immediately unpaused the game.
2. Press bottle 0, change the level, then release the old touch. The old gesture
   selected bottle 0 on the new board.

That run finished with 489 assertions, two failures and exit code 1; all normal
Tween/level walkthrough checks still passed. The test agent did not patch the
controller. The Site owner added pointer reset on animation cancellation,
overlay opening and resume, plus focus-loss handling.

After that correction, both original repros pass. Additional checks dispatch
`NOTIFICATION_APPLICATION_FOCUS_OUT` while idle and mid-pour:

- The notification opens pause when playing.
- Held primary touch state is cleared.
- The old release cannot activate Continue.
- A running Tween, bottle transform and liquid interpolation stay frozen over a
  real-time wait.
- A fresh Continue tap resumes the same single committed move.

## Limits of this evidence

This is a headless controller integration test, not pixel/screenshot QA or a
physical mobile-device test. It does not prove browser WebAssembly loading,
responsive canvas coordinates, browser-generated touch behavior, actual OS/tab
focus delivery, sound, accessibility announcements, or production hosting.
Those require the owner's separate browser/deployment checks.

No paid model calls, native Windows-device tasks or dependency installs were
performed. Only `godot/tests/test_controller.gd` and this report were authored
for this integration task. `main.gd` remained owned and edited by the root agent.
