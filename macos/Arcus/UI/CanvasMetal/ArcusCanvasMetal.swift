// ArcusCanvasMetal: retained-mode Metal 4 renderer for Arcus's 2D view canvases (plans, sections, sheets).
//
// Entry points: `MetalCanvasContext` (shared device/queue/pipelines, `isSupported`), `MetalCanvasScene` (display list →
// GPU buffers, built off the main thread), `MetalCanvasRenderer` (per-canvas frame encoding, offscreen rendering) and
// `MetalCanvasView` (CAMetalLayer view driven by the NSView display link). See README.md in this directory.
