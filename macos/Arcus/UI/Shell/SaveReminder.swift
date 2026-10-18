import AppKit
import SwiftUI

// F11: the save reminder (RevitCraft rc-app app.rs `save_reminder_minutes`, "Project Not Saved Recently"): every N
// minutes with unsaved changes, offer to save. Arcus autosaves in place, so this asks only when changes are still
// unsaved after that time. The interval is a per-user setting (Settings ▸ Notifications).

@MainActor
final class SaveReminder {
    static let minutesKey = "saveReminder.minutes"
    static let choices = [0, 15, 30, 60, 120]
    /// Minutes between reminders (0 = never); 30 by default, as RevitCraft.
    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) == nil ? 30 : UserDefaults.standard.integer(forKey: minutesKey) }
        set { UserDefaults.standard.set(newValue, forKey: minutesKey) }
    }

    weak var state: DocumentState?
    private var timer: Timer?
    /// When the project was last saved, or the reminder last answered.
    private var since = Date()
    private var asking = false
    private static var reminders: [ObjectIdentifier: SaveReminder] = [:]

    static func install(on state: DocumentState) {
        guard !CommandLine.arguments.contains("--qa") else { return }
        let r = SaveReminder()
        r.state = state
        reminders[ObjectIdentifier(state)] = r
        r.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak r] _ in MainActor.assumeIsolated { r?.tick() } }
    }

    func tick() {
        guard let state, !state.isTornDown else {
            timer?.invalidate()
            if let state { Self.reminders[ObjectIdentifier(state)] = nil }
            return
        }
        guard let doc = state.document, doc.isDocumentEdited else { since = Date(); return }
        let m = Self.minutes
        guard m > 0, !asking, Date().timeIntervalSince(since) >= Double(m) * 60, let window = state.window, window.attachedSheet == nil else { return }
        ask(window, doc)
    }

    func ask(_ window: NSWindow, _ doc: NSDocument) {
        asking = true
        let alert = NSAlert()
        alert.messageText = "Project Not Saved Recently"
        alert.informativeText = "“\(doc.displayName ?? "This project")” has changes that haven't been saved for \(Self.minutes) minutes."
        alert.addButton(withTitle: "Save the Project")
        alert.addButton(withTitle: "Do Not Save the Project")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for c in Self.choices { popup.addItem(withTitle: c == 0 ? "Never" : "Every \(c) minutes") }
        popup.selectItem(at: Self.choices.firstIndex(of: Self.minutes) ?? 2)
        let row = NSStackView(views: [NSTextField(labelWithString: "Remind me:"), popup])
        row.orientation = .horizontal
        row.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
        alert.accessoryView = row
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self else { return }
            Self.minutes = Self.choices[max(0, popup.indexOfSelectedItem)]
            self.since = Date()
            self.asking = false
            if r == .alertFirstButtonReturn { doc.save(nil) }
        }
    }
}

/// Settings ▸ Notifications: the save reminder interval.
struct SaveReminderSettingsSection: View {
    @AppStorage(SaveReminder.minutesKey) private var minutes = 30
    var body: some View {
        Picker("Save reminder interval", selection: $minutes) {
            ForEach(SaveReminder.choices, id: \.self) { c in Text(c == 0 ? "No reminders" : "\(c) minutes").tag(c) }
        }
        Text("When a project has unsaved changes for this long, Arcus offers to save it.").font(.caption).foregroundStyle(.secondary)
    }
}
