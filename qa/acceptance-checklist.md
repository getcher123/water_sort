# Jelly Sort B1F1 — independent acceptance checklist

Date: 2026-11-07. Scope: the new Godot web prototype, not native Android delivery or SDK integration.

Historical implementation checklist, recorded before the GitHub Pages release. Hosting and browser status below are a snapshot of that earlier stage, not the current deployment status. See [pages-release.md](pages-release.md) for the verified public Pages deployment and real Chrome gameplay; that report supersedes the earlier pending browser/hosting entries.

Unchecked items are **not yet verified**, not implied passes. Checked logic items below are supported by the board/controller agents' actual Godot headless tests; checked transport items use the independent Node loader harness. They are not browser or physical-phone passes. Root owns browser QA, export and publication.

Recorded suites: 3,473 pure-model assertions and 513 controller/Tween assertions, zero failures (root's final rerun); independent loader test 14 cases / 260 assertions, zero failures. The cloud browser does not expose WebGL 2; an actual browser gameplay run remains unverified. The explicit compatibility notice was observed by the root agent, with no policy workaround attempted.

## 1. Release gates

| Gate | Evidence required | Recorded status |
| --- | --- | --- |
| Rules and three levels | Test log with actual replay of each solution, plus conservation/undo/reset checks | PASS — Godot model and headless controller suites |
| Actual interaction | Browser actions change the visible board and move counter; illegal action leaves both unchanged | Headless inputs/Tweens PASS; supported-browser gameplay still pending |
| Presentation | B1F1 palette/gloss retained; bottles and liquid surfaces remain planar; no clipped controls | Source/geometry reviewed; pixel/browser QA pending |
| Single-thread export | Matching engine/templates; Compatibility renderer; no dev bridge; correct static files | Matching 4.6.3 export and Node transport checks PASS; browser engine start pending |
| Hosting | Asset-size audit and successful Sites deployment of the tested source | Asset ceiling PASS; publication belongs to root's separate report |

## 2. Game invariants

- [x] Every initial level has six bottles, capacity four, four units of each of four colors, and two empty bottles.
- [x] Rules transfer the maximal contiguous top-color group, bounded by the destination's free capacity.
- [x] Empty source, same source/destination, full destination and different top color are no-ops: no move, history or volume changes.
- [x] A successful transfer preserves the total amount and count of each color. Each bottle remains within capacity.
- [x] `preview_pour` is read-only. Its result agrees with `pour` on the same state.
- [x] Win requires every nonempty bottle to be full and monochrome; a partially filled monochrome bottle is not sufficient.
- [x] Each of the three supplied solution paths is replayed through the actual model and reaches that win condition.
- [x] Undo restores the complete prior board and move count; repeat until empty history, then confirm harmless no-op.
- [x] Restart restores the original board, zero moves and empty history for the current level.

## 3. Atomic UI and lifecycle

- [x] One accepted input causes at most one model transfer. Rapid double tap and extra taps during animation cannot double-commit.
- [x] A transfer has an explicit busy state and an unambiguous commit point. The visual board reaches the committed model state exactly once.
- [x] Restart/undo/level-switch during a transfer are either disabled until completion or cancel the animation safely. A stale tween callback must never mutate a newly loaded level.
- [x] Pausing during a transfer has defined behavior: pause/resume the animation, or finish the current transaction before showing pause. It must not leave `busy=true` forever.
- [x] Pause/help/win overlays consume input; no click-through into bottles.
- [ ] Mouse and touch do not both execute the same tap. Cancelled touch or releasing outside does not cause an unintended second action.
- [x] Tapping the selected source deselects it; tapping an invalid destination gives clear feedback without losing liquid.
- [x] If hint/highlight exists, it only marks legal destinations and never mutates state. No hints are required for this prototype.
- [x] After the final legal move, a single win state appears. Next advances 1→2→3; level 3 ends with a clear completion/replay action, not a nonexistent level 4.
- [ ] Switching browser tab away and returning mid-pour does not duplicate a move, corrupt fractions or leave controls locked.

## 4. Presentation and input sizes

- [ ] Six bottles match the chosen B1F1's blue-lilac contours, coral/gold/teal/purple fills and decorative white gloss.
- [ ] Bottle mouths and liquid boundaries contain no perspective ellipses. The top reads as open; rim decoration does not become a lid.
- [ ] Empty/selected/completed bottles are distinguishable; decorative highlights do not conceal the liquid colors.
- [ ] The narrowest supported portrait viewport retains all six targets and both bottom controls. No body scrolling, crop or accidental page zoom during taps.
- [ ] Resizing/orientation change preserves hit-target alignment with the rendered bottle; test actual clicks after resize, not only screenshots.
- [ ] Keyboard operation and visible/help instructions match implemented controls. Canvas has a meaningful accessible name.

## 5. Web packaging and hosting

Verified constraints from official Godot 4.6 documentation: browser export requires WebAssembly/WebGL 2.0 and Compatibility rendering. Single-thread export avoids the threading-related cross-origin-isolation requirement; GDExtension support also requires isolation. Keep both off for this lightweight game. Use a custom HTML shell rather than hand-editing generated HTML.

- [x] Export with a template version matching the actual engine. Do not label the cloud 4.6.3 build as a tested 4.7.2 build.
- [x] `variant/thread_support=false`, `variant/extensions_support=false`; no unsupported Thread/low-level networking dependency.
- [ ] No VibeGame TCP/eval development bridge, secrets, test harness or unused concept boards in the exported game pack.
- [ ] Keep generated `.js`, `.wasm`, `.pck` references consistent and include all runtime dependencies. The loader reports a useful error instead of staying blank if startup fails.
- [x] Inspect actual deployed asset limits before upload. Cloudflare Workers static assets currently document a **25 MiB maximum per file**; all 16 final static files pass the audit (largest 20 MiB), with oversized original omitted and gzip/raw identity verified.
- [ ] Verify WASM delivery as `application/wasm` when applicable, correct compression handling and successful engine start in the browser.
- [ ] Default new Site audience remains owner-private. Successful publication does not mean a public share link.

If local progress is implemented, it is a convenience: `user://` relies on IndexedDB and can be unavailable in private/restricted browsing. Validate loaded data and clamp the level index. Storage failure must leave the game playable. Browser tab suspension can stop processing, so gameplay cannot depend on a background timer completing on schedule.

## 6. Claim boundaries and evidence

- Do not infer real Android touch behavior, APK readiness, app-store acceptance or Lumeriq advertising SDK support from a working browser build.
- The earlier VibeGame smoke proved a small native Windows scene and loopback bridge. It did not prove this game's rules, web export, native Android build or ads.
- Record model tests, UI actions, build/export logs, exact engine version and deployed source commit separately. Mark any unrun phone/browser test explicitly.
- Paid generation is not necessary for this implementation; the selected concept is already available. Do not spend on replacement art without a specific need.

## Sources checked

- Godot 4.6: https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html
- Godot 4.6 custom shell: https://docs.godotengine.org/en/4.6/tutorials/platform/web/customizing_html5_shell.html
- Cloudflare Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- Prior project evidence: `Lumeriq_Godot_Pipeline_2026-11-07.md` and `Lumeriq_Godot_Readiness_2026-11-07.md` in the readiness package.

## Independent controller review

Static review of `godot/scripts/main.gd` and `bottle_view.gd` found no model-state corruption in the ordinary transfer path: the model commits once before animation; `busy` gates bottle actions and undo; overlays pause the same tween; restart kills it and advances an epoch; completion checks the actual model after animation. Child z-indices place bottles below the controller's modal draw. These are code-review observations, not browser passes.

- **Visual correction closed in source:** `_draw_stream()` now calls `BottleView.get_liquid_surface_local()` and converts it through `to_global`, replacing a separate linear approximation that ended 27 logical pixels above the full surface. The query uses the same area threshold as the renderer. Browser appearance still needs review.
- **Input regression closed:** the owner added pointer resets on state transitions plus focus-loss pause. The board agent reproduced both stale-release bugs before the patch and verified the fixes with real `InputEventScreenTouch` objects and actual Tweens in headless Godot.
- **Loader guard closed:** missing `Engine` and native-fetch restoration are now covered by the final 14-case / 260-assertion Node test, including its timeout and late-resolution behavior. See `loader-test-report.md`.
- **Geometry sweep:** a read-only numeric sweep of all 30 source/target pairs, 101 interpolation samples each, including the 8-pixel wall stroke, remained within the 720×1280 canvas. Observed bounds: x≈5.98…646, y≈110.37…1031. This checks clipping, not visual overlap or native touch input; the lifted source can overlap the top HUD region and still needs visual review.
- **Persistence boundary:** only selected level and completed-level flags are saved, not an unfinished board. Describe this as remembered level/completions, not full move-by-move resume.

This file is a review checklist, not an assertion that all gates have passed.
