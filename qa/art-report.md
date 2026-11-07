# B1F1 procedural art implementation

Selected reference viewed: design/B1F1-reference.jpg. The user chose the first flat concept, with bright coral / gold / teal / purple fills, lavender-blue glass lines, a broad left glint and two right highlights.

Implemented in code-native Godot 2D geometry, not a raster screenshot. `BottleView` uses one shared U-shaped interior for every vessel/state, clipped horizontal liquid bands, independently painted glass glints and fixed contour. The top is open with small flat lip tabs; the generated reference's visually closed top bar was corrected for a functioning pouring vessel.

The liquid normal tracks global rotation, preserving world-horizontal surfaces while the bottle tilts. Cumulative volume thresholds are obtained by 20-step polygon-area bisection. Every unit occupies the same 2D cross-section area, including rounded-bottom compensation. Fractional units support smooth transfer. This is lightweight stylized geometry, not 3D or particle fluid physics.

API: `configure(colors, capacity=4)` accepts bottom-to-top integer colors; `set_layers([{color, amount}, ...])` accepts fractional layers; `set_selected`, `set_completed`, `set_hint`; `visual_units` can also be assigned directly. `get_mouth_local()` is the opening center. Extra `get_pour_lip_local(side=1)` returns the left/right lip: use `to_global(...)` for the stream origin. Parent owns motion and input.

Added `get_liquid_surface_local() -> Vector2` for the receiving stream endpoint. It uses exactly the renderer's current fractional `visual_units`, unit area and world-horizontal threshold, then finds the midpoint of the surface's chord through the convex cavity. Thus it also works when rotated. Empty vessels return the cavity's lowest point. Use `bottle.to_global(bottle.get_liquid_surface_local())`; do not approximate surface height with linear units/height, which misses the headspace and rounded-bottom correction. A full upright bottle's actual surface is at local y=-308 for default height360.

Default width=150, height=360, origin bottom-center. Root may resize or tween rotation; `queue_redraw()` is sufficient, and a cheap rotation-change watcher also catches it. Upright surfaces are exactly horizontal. No visible top ellipse or cylindrical layer shading. `JellyBackdrop` paints the fixed 720×1280 background with a subtle gradient, cropped broad rings and quiet decorative bubbles.

Validation: both scripts passed Godot 4.6.3 `--headless --path godot --script scripts/bottle_view.gd --check-only` and the equivalent `backdrop.gd` command, each exit 0 with no parser errors. Rendered/browser QA remains with root after the controller and web export are connected.
