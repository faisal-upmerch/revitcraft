import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// HOME: Recent as a thumbnail grid with kind badges and a filter (All / Projects / Furniture / Families).

struct HomeRecentsPane: View {
    @Bindable var model: HomeModel
    static let columns = [GridItem(.adaptive(minimum: 176, maximum: 232), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Recent").font(.system(size: 22, weight: .semibold))
                Spacer()
                PillSegmented(selection: $model.recentFilter, [(HomeDocumentKind?.none, "All")] + HomeDocumentKind.allCases.map { (HomeDocumentKind?.some($0), $0.filterTitle) },
                              size: .large, label: "Show") // PILLS
                .disabled(model.recents.isEmpty)
                .accessibilityLabel("Show recent files of kind")
            }
            .padding(.horizontal, HomeStyle.pad)
            .padding(.bottom, 16)
            let items = model.filteredRecents
            if items.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                        ForEach(items, id: \.self) { url in
                            HomeRecentTile(url: url) { model.open(url) }
                        }
                    }
                    .padding(.horizontal, HomeStyle.pad)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder var emptyState: some View {
        VStack(spacing: 16) {
            HStack(spacing: -12) {
                HomeIllustration(card: .architectural, size: 56).rotationEffect(.degrees(-8)).offset(y: 4)
                HomeIllustration(card: .furniture, size: 64).zIndex(1).shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                HomeIllustration(card: .family, size: 56).rotationEffect(.degrees(8)).offset(y: 4)
            }
            .padding(.bottom, 8)
            if let k = model.recentFilter, !model.recents.isEmpty {
                Text("No recent \(k.filterTitle.lowercased())").font(.system(size: 15, weight: .semibold))
                Button("Show All") { model.recentFilter = nil }.buttonStyle(.link)
            } else {
                Text("No recent files").font(.system(size: 15, weight: .semibold))
                Text("Projects, furniture and families you open appear here.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Sample Project") { model.openSample() }
                    .controlSize(.large)
                    .disabled(model.openingSample)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 48)
        .accessibilityElement(children: .contain)
    }
}

/// One recent file: thumbnail with its kind badge, name and when it was last edited.
struct HomeRecentTile: View {
    let url: URL
    let open: () -> Void
    @State private var hovered = false

    var kind: HomeDocumentKind? { HomeDocumentKind(url: url) }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var modified: Date? { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.cardCornerRadius, style: .continuous)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                RecentThumbnail(url: url, placeholder: kind.map(HomeRecentTile.card) ?? .architectural)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(hovered ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.10), lineWidth: hovered ? 2 : 1))
                    .overlay(alignment: .topLeading) { HomeKindBadge(kind: kind, url: url).padding(8) }
                    .shadow(color: .black.opacity(hovered ? 0.14 : 0.06), radius: hovered ? 8 : 3, y: hovered ? 3 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Group {
                        if !exists { Text("File not found") }
                        else if let modified { Text("Edited \(modified.formatted(.relative(presentation: .named)))") }
                        else { Text(url.deletingLastPathComponent().lastPathComponent) }
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .opacity(exists ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .arcusAnimation(hovered)
        .help(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(!exists)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(kind?.rawValue ?? url.pathExtension.uppercased())")
        .accessibilityValue(exists ? (modified.map { "Edited \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "") : "File not found")
        .accessibilityAddTraits(.isButton)
    }

    static func card(_ k: HomeDocumentKind) -> HomeCard {
        switch k {
        case .project: .architectural
        case .furniture: .furniture
        case .family: .family
        }
    }
}

/// The kind badge over a recent thumbnail: Project, Furniture or Family (or the file's extension).
struct HomeKindBadge: View {
    let kind: HomeDocumentKind?
    let url: URL
    var body: some View {
        let tint = kind.map { HomeRecentTile.card($0).tint } ?? .gray
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(kind?.rawValue ?? url.pathExtension.uppercased()).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

/// A file's saved preview (`ArcusPackage.readThumbnail`), or its kind's illustration while there is none.
struct RecentThumbnail: View {
    let url: URL
    var placeholder: HomeCard = .architectural
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color(nsColor: Tokens.canvas)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [placeholder.tint.opacity(0.10), placeholder.tint.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                HomeIllustration(card: placeholder, size: 56)
            }
        }
        .task(id: url) {
            let u = url
            let data = await Task.detached { ArcusPackage.readThumbnail(u) }.value
            image = data.flatMap(NSImage.init(data:))
        }
        .accessibilityHidden(true)
    }
}
