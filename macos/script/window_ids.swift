// Lists on-screen window ids and titles for a pid (for QA screenshots with screencapture -l).
import CoreGraphics
let pid = Int(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("\(w[kCGWindowNumber as String] ?? 0)\t\(w[kCGWindowName as String] ?? "")\t\(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
}
