import AppKit

// HOME: screenshots of the redesigned Home window (hooked from `screenshots()` with one line, light and dark).
extension QAHarness {
    /// Captures Home with Recent (all, then Projects only), then each Start card selected, at the default size and at
    /// the minimum size, and leaves it on Recent.
    static func homeScreenshots(_ suffix: String) async {
        AppDelegate.shared?.showHub(tab: .recent)
        await pause(500)
        guard let m = AppDelegate.shared?.hubModel,
              let w = NSApp.windows.first(where: { $0.title == "Home" && $0.isVisible }) else { return }
        for (size, label) in [(NSSize(width: 1040, height: 660), "default"), (NSSize(width: 920, height: 600), "min")] {
            w.setContentSize(size)
            w.center()
            m.selected = nil
            m.recentFilter = nil
            await pause(400)
            await shot(w, "home-recent-\(label)-\(suffix)")
            for card in HomeCard.allCases {
                m.selected = card
                await pause(400)
                await shot(w, "home-\(card.rawValue)-\(label)-\(suffix)")
            }
        }
        m.selected = nil
        m.recentFilter = .project
        await pause(400)
        await shot(w, "home-recent-projects-\(suffix)")
        m.recentFilter = nil
        w.setContentSize(NSSize(width: 1040, height: 660))
        w.center()
    }
}
