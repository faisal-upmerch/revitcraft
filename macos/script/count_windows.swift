// Prints the number of on-screen windows owned by a pid: normal windows (layer 0) and modal panels/alerts (layer 8),
// e.g. the crash-recovery prompt. Uses window metadata only; no screen capture.
import CoreGraphics
let pid = Int(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
print(list.filter { w in
    guard (w[kCGWindowOwnerPID as String] as? Int) == pid, let layer = w[kCGWindowLayer as String] as? Int else { return false }
    return layer == 0 || layer == Int(CGWindowLevelForKey(.modalPanelWindow))
}.count)
