# Water Sort / Jelly Sort B1F1

Canonical source: `getcher123/water_sort`, branch `main`. This repository contains a real Godot 4.6.3 / GDScript game, not a JavaScript recreation. The selected B1F1 reference is in `design/B1F1-reference.jpg`. Keep the game strictly 2D: flat bottle profiles, polygon-clipped liquid, horizontal liquid surfaces while a bottle rotates.

## Scope and safety

- Work in this repository. Do not change the separate Sites project, upstream VibeGame checkout, or the user's Windows installation.
- Build and test in the cloud or GitHub Actions. Do not start heavy workloads on the user's laptop.
- Preserve three solvable levels, select/pour, undo, restart, pause/help and next-level flow. No ads, tracking, payments, real SDK integration or native APK claims.
- Use `apply_patch` for authored files. Never commit credentials, `.env`, `.godot`, `.local`, export templates or generated `dist` files.
- Preserve unrelated/concurrent changes. No force pushes. A permission/protection failure is a stop condition, not a reason to bypass the control.

## Build and verification

- Godot **4.6.3 stable** with matching **4.6.3.stable Web export templates**. Set `GODOT_BIN` when the executable is not on PATH.
- Node.js **24** is used in CI; Node.js **22+** is supported locally. There are no npm package dependencies.
- `npm test`: import the project and run the real model + scene/controller tests.
- `npm run build`: run those same tests, export Web, package the engine and verify asset limits.
- `npm run test:loader`: test loader transport and failure cases with a mocked Engine. This is **not** graphical browser gameplay verification.
- `npm run serve`: serve `dist` at `http://127.0.0.1:4173/`; `/water_sort/` is also supported for subpath testing.
- `.github/workflows/pages.yml` builds from source on push to main or manually and deploys to GitHub Pages. Pull requests build/test only. Keep minimal job permissions and full-SHA official action pins.
- `scripts/install-godot-ci.sh` downloads the pinned official release and checks SHA-256 before extraction. Do not weaken verification.
- Web export is single-threaded and needs WebAssembly + WebGL 2, but not SharedArrayBuffer/COOP/COEP. Browser verification must use the real exported engine.

## Core contracts

`SortBoard` extends `RefCounted`. `bottles` is an array of integer arrays, bottom-to-top; capacity is 4. API: `load_level`, `can_pour`, `preview_pour`, `pour`, `undo`, `restart`, `is_solved`, `has_moves`, `snapshot`, static `levels`. Transfers are contiguous top-color blocks. Invalid moves must not change the state or history.

`BottleView` extends `Node2D`, bottom-center origin, width 150, height 360. API: `configure`, `set_layers`, `set_selected`, `set_completed`, `set_hint`, `get_mouth_local`, `get_liquid_surface_local`. Fractional animated fill is represented by `visual_units`. Use separate glass highlights; no 3D perspective or liquid ellipses.

The main scene owns input targets, animations and modal states. Board moves commit atomically and input locks during pouring. Keep stale-touch regression tests across pause/restart/level changes. Tests must preserve existing player progress.

## Handoff

Update `state.md` after each meaningful wave with actual results, remaining gaps and next steps. Keep README and `docs/` commands aligned with scripts. Report automated logic/loader tests separately from browser visual checks. Do not mark deployment or native SDK support verified without evidence.
