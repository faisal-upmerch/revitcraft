import AppKit
import ArcusOutput

// F1: launch-time setup for RevitCraft port batch F1.
extension AppDelegate {
    /// Installs the CoreText glyph outliner that Model Text builds its 3D letters from.
    static func f1Launch() {
        GlyphOutliner.install()
    }
}
