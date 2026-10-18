# ArcusCanvasMetal — GPU renderer for 2D view canvases

Retained-mode Metal 4 renderer for Arcus's plans, sections, elevations, drafting views and sheets. It draws the same
`ViewGraphics` display lists as `GraphicsRenderer` (CoreGraphics), with the same visual semantics, at display refresh
rate: after a one-off scene build, a pan/zoom frame costs ~0.05 ms of CPU and ~0.5 ms of GPU for a 20 000-element plan
at 2560×1600. CoreGraphics remains the renderer for PDF export and printing.

## Architecture

```
ViewGraphics (Sendable)                         any thread                       main thread
      │   MetalCanvasScene.build / make  ──►  SceneBuilder ─► SceneData ─► MTLBuffers + MTLResidencySet
      │                                         │  FillTessellator (Triangulator, even-odd nesting, edge flags)
      │                                         │  TextShaper (GraphicsRenderer's TextLayout/FontCache)
      │                                         └─ GlyphAtlas (process-wide, locked; exact outline SDFs)
      ▼
MetalCanvasScene (immutable, shareable)  ──►  MetalCanvasRenderer (per canvas)  ──►  MetalCanvasView (CAMetalLayer)
                                                ├─ colour table   (options → dark map)      re-uploaded on change
                                                ├─ item table     (highlight/hidden/halftone) re-uploaded on change
                                                ├─ overlay SceneData (tool previews)         re-uploaded on change
                                                └─ 112-byte uniforms per pass                every frame
```

* **One ordered primitive stream.** Every primitive becomes a fixed-size 64-byte `GPURecord` (stroke segment, analytic
  sub-arc, fill triangle or glyph) in display-list order. A single uber-pipeline expands each record to a quad (or a
  triangle) in the vertex shader and shades it by kind in the fragment shader. Because a draw call blends in submission
  order, painter's order (and therefore layer order) is exactly GraphicsRenderer's, with no depth tricks.
* **Few draw calls.** Records are grouped into chunks of 1 024 with conservative view-space bounds; per frame the CPU
  culls chunks against the viewport and merges consecutive visible chunks into runs → typically 1–5 draw calls.
* **No re-tessellation on pan/zoom.** Everything zoom-dependent is evaluated on the GPU from the uniforms: pen widths
  (paper mm × pixels-per-paper-meter, `thinLines`, `minimumDevicePixel`), dash phases, arc curvature (analytic, exact at
  any zoom), pattern density and fallback tint, text size and the sub-pixel text cut-off.
* **Precision.** Positions are stored as float hi/lo pairs relative to the scene centre; the vertex shader subtracts the
  camera (also hi/lo) first, so geometry 100 km from the origin at 1 µm/pt is still sub-pixel exact
  (`deepZoomFarFromOrigin`). Polyline neighbours are stored as small deltas.
* **Anti-aliasing** is analytic in the fragment shader (no MSAA): stroke and edge coverage uses the exact projection of
  the pixel square on the edge normal (a trapezoid CDF), so it is phase-independent at every angle like CoreGraphics'
  area coverage. Pens ≤ 1 device pixel use a separable "hairline" model with butt ends — CoreGraphics draws them that
  way (measured). Thicker pens use distance-based coverage with round caps; polyline joints are owned by the nearest
  segment, so a polyline is composited once (union semantics, round joins, no double blending).
* **Fills** are triangulated once. Loops are nested by containment depth (even-odd), triangulated with
  `ArcusGeometry.Triangulator` in a local frame, and each triangle flags which edges are on the region boundary: only
  those are anti-aliased (pushed out one pixel in the vertex shader), so interior diagonals and shared edges of
  adjacent pieces never show seams. Background, pattern and transparency composite exactly like GraphicsRenderer's
  successive `fillPath`s under `setAlpha`. Masks paint the canvas colour.
* **Patterns** are GraphicsRenderer's `FillPatterns` generators re-expressed as distance fields in the fragment shader,
  with the *same* lattice hash (64-bit, bit-identical), spacings (read from `FillPatterns.spacing`), anchoring at the
  view origin, drafting-vs-model scaling, pen-1 line width, "closer than 2 device pixels → tint" rule and (optionally,
  default on) the 40 000-mark budget tint.
* **Text** is laid out once per unique string with GraphicsRenderer's own `TextLayout`/`FontCache` at a reference cap
  height (layout is linear in size; verified within 1 px at 3–30 pt) and drawn from a process-wide signed-distance-field
  atlas (48 px/em, ±6 px, R16Float) generated from the exact glyph outlines (`CTFontCreatePathForGlyph`), including
  fallback fonts. Crisp at any zoom; rotation/alignment/anchor/wrap/bold match.
* **Colour rules.** `CanvasColors` is a line-by-line port of `RenderPass.canvas/darkMap` (unit-tested against it). The
  dark mapping is applied per unique colour on the CPU when options change; halftone (per style, per option amount or
  forced per element), highlight tinting (strokes/text replace, fills blend 65 %) and hidden/overlay-layer visibility
  are applied in the shader from the small per-item table.

### Metal 4

Encoding uses Metal 4 throughout: `MTL4CommandQueue`, one `MTL4CommandAllocator` + two `MTL4ArgumentTable`s per frame
slot (3 slots, reused only after an `MTLSharedEvent` says the GPU finished the slot's previous frame), `MTLResidencySet`s
(one per scene, one per renderer for dynamic buffers/targets, the `CAMetalLayer.residencySet` on the queue),
`waitForDrawable`/`signalDrawable` for presentation and `MTL4CommitFeedback` for GPU timings. Shaders are compiled at
runtime from source with `MTL4Compiler` (math mode *safe*, so the hi/lo arithmetic is not re-associated) and pipelines
are cached per pixel format. All buffers are `storageModeShared` + untracked hazards (unified memory; writes are
fenced by the slot ring). Verified reliable on Apple M5 Pro / macOS 27 (all tests, including the drawable path).
`MetalCanvasContext.shared` is nil (and `isSupported` false) when there is no device, no Metal 4 family support or
shader compilation fails — nothing force-unwraps.

## API

```swift
// Shared GPU state
MetalCanvasContext.isSupported            // false → keep the CoreGraphics canvas
MetalCanvasContext.shared                 // device, Metal 4 queue, pipelines, glyph atlas

// Retained scene (any thread; immutable; share between canvases of the same view)
let scene = await MetalCanvasScene.make(graphics, context: ctx)          // detached background task
let scene = MetalCanvasScene.build(graphics, context: ctx, isCancelled: { … })   // synchronous
scene.statistics                          // items, records, triangles, glyphs, bytes, buildSeconds

// View (NSView + CAMetalLayer + NSView.displayLink, draws only on change)
let v = MetalCanvasView(frame: …)         // v.renderer == nil when unsupported
v.setGraphics(g)                          // async build, latest request wins, old scene stays until ready
v.setScene(scene)                         // or install a scene you built/shared yourself
v.viewToDevice = viewToDevice             // same transform GraphicsRenderer receives (view units → points)
v.pointsPerPaperMeter = zoom * scale
v.options = renderOptions                 // thinLines, darkCanvas, background, halftoneAmount, minimumDevicePixel, …
v.highlight = [id: colour]                // selection / preselection (item table only)
v.overlayOptions = previewOptions         // background is forced nil: overlays never clear what is underneath
v.setOverlay(primitives: previews, scale: g.scale)   // tool / drag previews, per frame
v.paintsBackground = false                // transparent clear, canvas colour still used for masks/halftone
v.requestRedraw()
v.onFrame = { stats in … }                // CPU encode ms, draw calls, records

// Renderer (per canvas; also used for offscreen rendering)
let r = MetalCanvasRenderer(context: ctx)
r.setScene(scene); r.options = …; r.halftoneElements = […]; r.setOverlay(…)
let stats = r.encode(to: texture, viewToDevice: t, pointsPerPaperMeter: ppm, pixelsPerPoint: 2,
                     passes: .all /* .scene, .overlay */, load: .clear /* .load */, drawable: nil)
r.waitUntilCompleted(stats).gpuMilliseconds
MetalCanvasRenderer.readPixels(texture)   // BGRA premultiplied, same layout as a CG bitmap
```

The view is layer-backed with `CAMetalLayer` (sRGB-tagged `bgra8Unorm`, so Core Animation colour-matches to P3
displays; blending happens in encoded sRGB exactly like CoreGraphics bitmaps), tracks `backingScaleFactor`, resizes
its drawable (and draws synchronously during live resize), requests 120 Hz from its display link, pauses the link when
idle and never draws while hidden, windowless, zero-sized or occluded. It ignores events (`hitTest` → nil).

## Integrating into Canvas2DView

1. **Gate:** if `MetalCanvasContext.isSupported`, create a `MetalCanvasView` filling the canvas; otherwise keep
   today's CoreGraphics path unchanged.
2. **Layering:** a subview draws above its parent's `draw(_:)`, so move the CoreGraphics overlays (temporary dimensions,
   grips, snap markers, selection/zoom rectangles, temporary-visibility frame, "Building view…") into a transparent
   overlay `NSView` above the Metal view (return nil from its `hitTest` too), and let `Canvas2DView` keep handling
   events. Hit testing stays CPU-side on the existing `SpatialGrid`/`SnapIndex`.
3. **Graphics:** in `setGraphics(_:)` call `metalView.setGraphics(g)`; or build `MetalCanvasScene.make` next to the
   `ViewGraphicsBuilder` task in `GraphicsStore` and share one scene per view between canvases.
4. **Camera:** whenever `zoom`, `center` or `bounds` change, set `metalView.viewToDevice = viewToDevice` and
   `metalView.pointsPerPaperMeter = zoom * scaleDenominator` instead of `needsDisplay = true`.
5. **Options:** build the same `RenderOptions` as `draw(_:)` does today (thin lines, dark canvas, background, Increase
   Contrast halftone/minimum width, highlight from selection/preselection/tool) and assign `metalView.options` from the
   selection observation. Only the item/colour tables change.
6. **Previews:** `metalView.overlayOptions = po` (dark flag as today) and
   `metalView.setOverlay(primitives: tool.preview.primitives + selectTool.preview.primitives, scale: g.scale)` when the
   tool preview changes; the remaining CG overlays redraw in the overlay view only when they change.
7. **Sheets and underlays:** draw the sheet backdrop/paper shadow and `UnderlayRenderer` output in a CG layer *below*
   the Metal view and set `metalView.paintsBackground = false` (masks and halftone still use `options.background`).
   Note: in today's CoreGraphics path `RenderPass` fills the whole clip with the background before drawing, which
   paints over the underlay and the sheet shadow drawn earlier in `Canvas2DView.draw(_:)`.
8. **PDF/print** keep using `GraphicsRenderer`.

## Parity (tests: `ParityTests`, CoreGraphics bitmap at 2× vs Metal offscreen)

Metrics: *mismatch* = share of pixels whose 3×3-blurred colours differ by > 15 %; *ink* = Metal ÷ CG total deviation
from the background; *meanAbs* = mean channel difference. On failure (or with `ARCUS_PARITY_DUMP=1`) `cg.png`,
`metal.png`, `diff.png` go to `$TMPDIR/ArcusCanvasMetalParity/<case>/`.

| Case | mismatch | ink | Case | mismatch | ink |
|---|---|---|---|---|---|
| line weights 1–16 @1:50/100/200, 4 zooms | 0.000–0.004 % | 1.000 | fills with holes / adjacent pieces | 0.000 % | 1.000 |
| thin lines, minimum device pixel | 0.000 % | 0.997–1.001 | transparency + halftone (0.55, 0.3) | 0.000 % | 0.999–1.000 |
| every dash pattern × 3 pens × 2 zooms | 0.000–0.010 % | 1.001–1.002 | masking (light, dark) | 0.000 % | 1.000 |
| dense dashes → solid | 0.000 % | 0.988 | text (align × anchor × bold, rotation, multi-line, wrap) | 0.000 % | 1.009 |
| arcs (± sweep, full circle, dashed, fat) | 0.002–0.014 % | 0.998–1.000 | dark canvas (2 backgrounds) | 0.000 % | 1.001 |
| solid / hatch / crosshatch / grid fills | 0.000 % | 0.97–1.00 | highlight + hidden | 0.000 % | 1.000 |
| concrete / sand / wood / brick | 0.000 % | 0.97–1.04 | overlay layer shown/hidden | 0.000 % | 1.000 |
| insulation / earth | 0.000 % | 0.94–1.07 | overlay pass (dark) + overlay-only `.load` pass keeps pixels | 0.000 % | 1.000 |
| pattern tint fallback | 0.000 % | 1.000 | rotated 30°/90°, mirrored transforms | 0.000 % | 0.975–0.992 |
| deep zoom 100 km from origin | 0.000 % | 1.000 | Courtyard plan fit / detail / dark | 0.000 % | 1.001–1.004 |
| Courtyard sheet A-series | 0.002 % | 1.012 | text vs CG *pixel-snapped* glyphs | 4.7 % | 1.002 |

## Performance (`PerformanceTests`, Apple M5 Pro, 2560×1600 px, 90-frame pan/zoom path from fit to 8× and back)

Release build (`swift test -c release -Xswiftc -enable-testing --filter PerformanceTests`):

| Display list | items | GPU records | scene build | CPU encode / frame (p50 / p95) | GPU / frame (p50 / p95) | CoreGraphics / frame |
|---|---|---|---|---|---|---|
| Courtyard House ground plan | 548 | 6 754 | 1.8–2.9 ms | 0.03–0.07 / 0.08–0.09 ms | 0.25–0.46 / 0.9–1.2 ms | 7.3–7.9 ms |
| Stress 20 000 elements | 20 004 | 120 160 | 39–44 ms | 0.05–0.06 / 0.09–0.11 ms | 0.49–0.51 / 1.25–1.33 ms | 14.5–15.9 ms |

(Ranges over repeated runs; GPU p95 is the zoom-to-fit end of the path where everything is visible.) Debug build
(`swift test`): scene build 11 / 300–370 ms, encode ≤ 0.1 ms, GPU unchanged, CoreGraphics 7.3 / 30–42 ms.

## Known differences vs CoreGraphics

* **Glyph positions:** CoreGraphics bitmap contexts snap glyph origins to whole device pixels unless sub-pixel
  positioning is enabled; Metal always uses exact fractional positions (smoother while zooming). With sub-pixel
  positioning enabled on the CG side text parity is exact; against pixel-snapped CG, glyphs differ by up to ~1 px.
* **SDF text:** single-channel SDF rounds glyph corners slightly at extreme magnification (cap height ≫ 300 px); very
  small text (cap < ~4 px) can be a few percent heavier/lighter than CoreGraphics.
* **Even-odd:** loops of one fill that *cross* each other render as their union rather than the XOR (nested loops,
  i.e. holes and islands, are exact). Holes smaller than `Tolerance.area` are dropped by the triangulator.
* **Pattern AA:** pattern marks use distance-based coverage; ink is within ±7 % of CoreGraphics (sub-2-px insulation
  arcs and earth strokes are the extremes), geometry and placement are identical. Pattern anchoring is float: beyond
  ~10 km from the view origin at extreme zoom the hatch phase may shift sub-pixel.
* **Translucent strokes:** a polyline is composited once (like CG), but CoreGraphics also merges *consecutive
  primitives with identical style* into one path; overlapping translucent strokes of different primitives are darker in
  Metal where they overlap.
* **Transforms:** arcs assume a similarity `viewToDevice` (uniform scale, rotation, mirroring); non-uniform scale or
  shear would draw circles where CoreGraphics draws ellipses (Arcus canvases never use such transforms).
* **Culling:** CoreGraphics skips off-screen items and texts; the GPU culls 1 024-record chunks — no visual difference.

## Tests

`cd .agents/metal2d && swift build && swift test` (or `--filter ParityTests|SceneTests|ViewTests|PerformanceTests`).
`ViewTests.windowedViewPresentsFramesOnDemand` only performs its on-screen checks when the test process can show a
visible window (a GUI session); otherwise it verifies that nothing is drawn into the invisible window.
