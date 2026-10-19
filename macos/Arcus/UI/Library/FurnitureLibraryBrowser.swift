import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// FM8: Insert ▸ Load Furniture. The Furniture Library (bundled pieces by room and the user's Furniture Templates) as a
// searchable grid of previews; double-click, Return or Place loads the piece as a family (compiled on load) and starts
// placing it, as the Component Library does. Browse… loads any .arcusfurniture file.

struct FurnitureLibraryBrowser: View {
    let state: DocumentState
    /// The pieces shown (tests and QA pass their own; the app scans the library).
    var items: [FurnitureLibraryCatalog.Item]? = nil

    @State private var query = ""
    @State private var selected: URL?
    @State private var all: [FurnitureLibraryCatalog.Item] = []
    @FocusState private var searchFocused: Bool

    static let columns = [GridItem(.adaptive(minimum: 148, maximum: 168), spacing: 14, alignment: .top)]
    static let thumbnail = CGSize(width: 148, height: 108)

    var rooms: [FurnitureLibraryCatalog.Room] { FurnitureLibraryCatalog.rooms(all, matching: query) }
    var visible: [FurnitureLibraryCatalog.Item] { rooms.flatMap(\.items) }
    var selectedItem: FurnitureLibraryCatalog.Item? { visible.first { $0.url == selected } ?? visible.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 900, height: 620)
        .onAppear {
            all = items ?? FurnitureLibraryCatalog.all()
            searchFocused = true
        }
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chair.lounge").font(.system(size: 20)).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Load Furniture").font(.title3.weight(.semibold))
                Text("\(all.count) piece\(all.count == 1 ? "" : "s") · Furniture Library and your templates · loads as a family")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search pieces or rooms", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { placeSelected() }
                    .accessibilityLabel("Search the furniture library")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .frame(width: 280)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: Grid

    @ViewBuilder var content: some View {
        if all.isEmpty {
            emptyState(symbol: "books.vertical", title: "No furniture yet",
                       message: "Pieces you save with File ▸ Save as Furniture Template appear here, by room. Browse… loads any furniture file.")
        } else if rooms.isEmpty {
            emptyState(symbol: "magnifyingglass", title: "No pieces match “\(query)”", message: "Try another name or room.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(rooms) { room in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(room.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                                ForEach(room.items) { item in tile(item) }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    func tile(_ item: FurnitureLibraryCatalog.Item) -> some View {
        let isSelected = selectedItem?.url == item.url
        return VStack(alignment: .leading, spacing: 6) {
            FurnitureFileThumbnail(url: item.url, size: Self.thumbnail)
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.isUser ? "My template" : item.room).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: Self.thumbnail.width)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selected = item.url; place(item.url) }
        .onTapGesture { selected = item.url }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.room)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    func emptyState(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    var footer: some View {
        HStack(spacing: 10) {
            Button("Browse…") { browse() }
                .help("Load a furniture piece or family from a file")
            Button("Open Templates Folder") { openTemplatesFolder() }
                .help("Show your Furniture Templates in Finder")
            Spacer()
            if let s = selectedItem { Text(s.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
            Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction)
            Button("Place") { placeSelected() }.keyboardShortcut(.defaultAction).disabled(selectedItem == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    func placeSelected() { if let s = selectedItem { place(s.url) } }

    func place(_ url: URL) {
        state.presented = nil
        // After the sheet closes, so the Component tool starts in the document window.
        DispatchQueue.main.async { FurnitureFileLoad.place(url, in: state) }
    }

    func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusFurniture, .arcusFamily]
        panel.message = "Choose a furniture piece (.arcusfurniture) or a family (.arcusfamily) to load and place."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        place(url)
    }

    func openTemplatesFolder() {
        guard let root = FurnitureLibraryCatalog.userRoot else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}

/// A furniture file's preview: its saved thumbnail, or one rendered from the piece when the file has none.
struct FurnitureFileThumbnail: View {
    let url: URL
    var size: CGSize
    @State private var image: CGImage?
    @State private var done = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 2).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(6)
            } else if done {
                Image(systemName: "chair.lounge").font(.system(size: 28)).foregroundStyle(.tertiary)
            } else {
                ProgressView().controlSize(.small).opacity(0.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: url) {
            image = await FurnitureThumbnailCache.shared.image(url, width: Int(size.width * 2), height: Int(size.height * 2))
            done = true
        }
        .accessibilityHidden(true)
    }
}

/// Furniture file previews in memory, by file and modification date. Reading and rendering run off the main actor.
@MainActor
final class FurnitureThumbnailCache {
    static let shared = FurnitureThumbnailCache()
    private var images: [String: LibraryPreviewImage] = [:]

    func image(_ url: URL, width: Int, height: Int) async -> CGImage? {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(date)|\(width)x\(height)"
        if let hit = images[key] { return hit.image }
        let rendered = await Task.detached(priority: .userInitiated) { () -> LibraryPreviewImage? in
            if let data = ArcusPackage.readThumbnail(url), let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return LibraryPreviewImage(image: img) }
            guard let m = try? ArcusPackage.read(from: url).model else { return nil }
            return FurnitureThumbnail.image(m, width: width, height: height).map(LibraryPreviewImage.init)
        }.value
        if let rendered { images[key] = rendered }
        return rendered?.image
    }
}
