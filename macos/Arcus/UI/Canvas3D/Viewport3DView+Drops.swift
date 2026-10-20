import AppKit
import ArcusGeometry

// FMG3: files dragged onto a 3D view (furniture pieces and families from Finder): the view hands them to its drop
// handler with the point they're dropped at, which loads and places them there.

/// Takes files dropped on a 3D view.
@MainActor public protocol Viewport3DDropHandler: AnyObject {
    /// True when the handler can load these files (the drag shows Copy).
    func viewport3DAccepts(_ urls: [URL]) -> Bool
    /// Loads and places the files at the view point (points, origin bottom-left); true when something was placed.
    func viewport3DDrop(_ urls: [URL], at point: CGPoint) -> Bool
    /// FMG4: the drag moved over the view (a live placement preview); nil point: it left or ended.
    func viewport3DDragMoved(_ urls: [URL], at point: CGPoint?)
}

public extension Viewport3DDropHandler {
    func viewport3DDragMoved(_ urls: [URL], at point: CGPoint?) {}
}

extension Viewport3DView {
    func droppedFiles(_ sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler?.viewport3DAccepts(droppedFiles(sender)) == true ? .copy : []
    }

    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = droppedFiles(sender)
        guard let h = dropHandler, h.viewport3DAccepts(urls) else { return [] }
        h.viewport3DDragMoved(urls, at: convert(sender.draggingLocation, from: nil)) // FMG4: live preview
        return .copy
    }

    override public func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropHandler?.viewport3DDragMoved([], at: nil) // FMG4
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = droppedFiles(sender)
        dropHandler?.viewport3DDragMoved([], at: nil) // FMG4
        guard let h = dropHandler, h.viewport3DAccepts(urls) else { return false }
        return h.viewport3DDrop(urls, at: convert(sender.draggingLocation, from: nil))
    }
}
