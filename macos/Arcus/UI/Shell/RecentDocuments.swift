import AppKit

/// The recent documents Home and File ▸ Open Recent list: `NSDocumentController.recentDocumentURLs` without files in
/// temporary folders (QA runs, previews and other scratch copies aren't documents the user returns to).
enum RecentDocuments {
    static func urls() -> [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { !isTemporary($0) }
    }

    static func isTemporary(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        return p.hasPrefix("/private/tmp/") || p.hasPrefix("/tmp/") || p.hasPrefix("/private/var/folders/") || p.hasPrefix(tmp + "/")
    }

    /// The full recent list, to put back with `restore` (QA runs open and save their own projects).
    static func snapshot() -> [URL] { NSDocumentController.shared.recentDocumentURLs }
    static func restore(_ urls: [URL]) {
        let dc = NSDocumentController.shared
        dc.clearRecentDocuments(nil)
        for u in urls.reversed() { dc.noteNewRecentDocumentURL(u) } // the last one noted is listed first
    }
}
