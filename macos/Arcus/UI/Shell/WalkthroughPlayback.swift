import AppKit
import AVFoundation
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// F810: View ▸ 3D View ▸ Walkthrough playback (Play, again to stop) and Export (PNG frames, or a QuickTime movie written
// with AVFoundation on this Mac), as RevitCraft's WalkPlay / WalkExport do.

/// Plays a walkthrough in its open 3D view: the camera steps one frame per tick without touching the undo history; the
/// frame reached is saved (one undoable change) when playback stops.
@MainActor
final class WalkthroughPlayer {
    static let framesPerSecond = 30.0
    private static var players: [ObjectIdentifier: WalkthroughPlayer] = [:]

    let viewID: ElementID
    weak var state: DocumentState?
    private var timer: Timer?
    private var frame: Int
    private var savedCameraHandler: ((Camera3D) -> Void)?

    private init(state: DocumentState, viewID: ElementID, frame: Int) { self.state = state; self.viewID = viewID; self.frame = frame }

    static func isPlaying(_ state: DocumentState) -> Bool { players[ObjectIdentifier(state)] != nil }

    /// Play (from the start when at the end), or stop when playing.
    static func toggle(_ state: DocumentState) {
        if isPlaying(state) { stop(state); return }
        guard let v = state.activeViewID, let w = state.model[v]?.view?.walkthrough, let host = state.canvases[v] as? Viewport3DHost else {
            state.show("Open a walkthrough view to play it.", error: true); return
        }
        let p = WalkthroughPlayer(state: state, viewID: v, frame: w.frame >= w.frames ? 1 : w.frame)
        players[ObjectIdentifier(state)] = p
        p.savedCameraHandler = host.viewport.onCameraChanged
        host.viewport.onCameraChanged = nil // playback is not navigation: nothing is saved per frame
        p.timer = Timer.scheduledTimer(withTimeInterval: 1 / framesPerSecond, repeats: true) { [weak p] _ in MainActor.assumeIsolated { p?.tick() } }
        state.show("Playing \(state.model[v]?.name ?? "the walkthrough"). Play again to stop.")
    }

    /// Stops playback and saves the frame reached.
    static func stop(_ state: DocumentState) {
        guard let p = players.removeValue(forKey: ObjectIdentifier(state)) else { return }
        p.timer?.invalidate()
        if let host = state.canvases[p.viewID] as? Viewport3DHost { host.viewport.onCameraChanged = p.savedCameraHandler }
        guard state.model[p.viewID]?.view?.walkthrough != nil else { return }
        let v = p.viewID, f = p.frame
        state.session.perform("Play Walkthrough") { tx in try Walkthroughs.setFrame(f, of: v, tx) }
    }

    private func tick() {
        guard let state, state.activeViewID == viewID, let vd = state.model[viewID]?.view, let w = vd.walkthrough,
              let host = state.canvases[viewID] as? Viewport3DHost else {
            if let state { Self.stop(state) }
            return
        }
        host.viewport.camera = w.camera3D(frame: frame, base: vd.camera)
        state.hoverDescription = "Frame \(frame) of \(w.frames)"
        if frame >= w.frames { Self.stop(state); return }
        frame += 1
    }
}

/// Export of a walkthrough's frames: PNG images named "<view>_0001.png"… in a folder, or one QuickTime movie.
@MainActor
struct WalkthroughExport {
    let state: DocumentState
    static let size = (width: 1280, height: 720)

    enum Format: Int, CaseIterable { case png, movie
        var title: String { self == .png ? "PNG images (one per frame)" : "QuickTime movie (.mov, H.264)" }
    }

    func run() {
        guard let v = state.activeViewID, let e = state.model[v], e.view?.walkthrough != nil, state.canvases[v] is Viewport3DHost else {
            state.show("Open a walkthrough view to export it.", error: true); return
        }
        WalkthroughPlayer.stop(state)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for the walkthrough frames (\(Self.size.width) × \(Self.size.height))."
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Format.allCases.map(\.title))
        let label = NSTextField(labelWithString: "Format:")
        let row = NSStackView(views: [label, popup])
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = row
        panel.isAccessoryViewDisclosed = true
        let state = state
        let done: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let dir = panel.url else { return }
            let format = Format(rawValue: popup.indexOfSelectedItem) ?? .png
            WalkthroughExport(state: state).export(v, to: dir, format: format)
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Renders each frame offscreen in the view's visual style and hands it to `body` (the view's saved frame is kept).
    func forEachFrame(_ v: ElementID, _ body: (Int, CGImage) throws -> Void) rethrows -> Int {
        guard let vd = state.model[v]?.view, let w = vd.walkthrough, let host = state.canvases[v] as? Viewport3DHost else { return 0 }
        let vp = host.viewport
        let keep = vp.camera, handler = vp.onCameraChanged
        vp.onCameraChanged = nil
        defer { vp.camera = keep; vp.onCameraChanged = handler }
        var count = 0
        for f in 1...max(1, w.frames) {
            vp.camera = w.camera3D(frame: f, base: vd.camera)
            guard let img = vp.snapshot(size: CGSize(width: Self.size.width, height: Self.size.height)) else { continue }
            try body(f, img)
            count += 1
        }
        return count
    }

    func export(_ v: ElementID, to dir: URL, format: Format) {
        let name = state.model[v]?.name ?? "Walkthrough"
        let access = dir.startAccessingSecurityScopedResource()
        defer { if access { dir.stopAccessingSecurityScopedResource() } }
        switch format {
        case .png:
            var written = 0
            _ = forEachFrame(v) { f, img in
                guard let data = RenderEngine.png(img) else { return }
                let file = dir.appendingPathComponent(String(format: "%@_%04d.png", name, f))
                if (try? data.write(to: file, options: .atomic)) != nil { written += 1 }
            }
            state.show(written > 0 ? "Exported \(written) frames to \(dir.lastPathComponent)." : "The walkthrough could not be rendered.", error: written == 0)
        case .movie:
            let url = dir.appendingPathComponent("\(name).mov")
            do {
                let movie = try MovieWriter(url: url, width: Self.size.width, height: Self.size.height, framesPerSecond: Int32(WalkthroughPlayer.framesPerSecond))
                let n = try forEachFrame(v) { _, img in try movie.append(img) }
                try movie.finish()
                state.show("Exported \(url.lastPathComponent) (\(n) frames).")
            } catch {
                state.show("The movie couldn't be written: \(error.localizedDescription)", error: true)
            }
        }
    }
}

/// Writes frames as an H.264 QuickTime movie with AVFoundation (local; no network).
final class MovieWriter {
    struct Failure: LocalizedError { let errorDescription: String? }
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32
    private var count = 0

    init(url: URL, width: Int, height: Int, framesPerSecond: Int32) throws {
        self.width = width & ~1; self.height = height & ~1; fps = framesPerSecond
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: self.width, AVVideoHeightKey: self.height])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: self.width, kCVPixelBufferHeightKey as String: self.height,
        ])
        guard writer.canAdd(input) else { throw Failure(errorDescription: "The movie format is not available.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure(errorDescription: "The movie couldn't be started.") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ img: CGImage) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        guard let pool = adaptor.pixelBufferPool else { throw Failure(errorDescription: "No pixel buffers.") }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { throw Failure(errorDescription: "No pixel buffer.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(count), timescale: fps)) else {
            throw writer.error ?? Failure(errorDescription: "A frame couldn't be written.")
        }
        count += 1
    }

    func finish() throws {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? Failure(errorDescription: "The movie couldn't be finished.") }
    }
}
