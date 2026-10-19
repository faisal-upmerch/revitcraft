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
    /// FM9: the selected piece (room and file) and the room the grid is limited to (nil = All Pieces).
    @State private var selected: String?
    @State private var room: String?
    @State private var all: [FurnitureLibraryCatalog.Item] = []
    @FocusState private var searchFocused: Bool

    var rooms: [FurnitureLibraryCatalog.Room] { FurnitureRoomList.rooms(all, room: room, query: query) }
    var visible: [FurnitureLibraryCatalog.Item] { rooms.flatMap(\.items) }
    var selectedItem: FurnitureLibraryCatalog.Item? { visible.first { $0.id == selected } ?? visible.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if !all.isEmpty {
                    FurnitureRoomList(items: all, room: $room).frame(width: 196)
                    Divider()
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let s = selectedItem {
                    Divider()
                    FurniturePieceDetail(item: s).frame(width: 280)
                }
            }
            Divider()
            footer
        }
        .frame(width: 1120, height: 680)
        .onAppear {
            all = items ?? FurnitureLibraryCatalog.all()
            searchFocused = true
        }
        .onChange(of: room) { _, _ in selected = visible.first?.id }
        .onChange(of: query) { _, _ in if !visible.contains(where: { $0.id == selected }) { selected = visible.first?.id } }
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 12) {
            DialogIconTile(symbol: "chair.lounge", tint: .brown) // DIALOGS
            VStack(alignment: .leading, spacing: 1) {
                Text("Load Furniture").font(.title3.weight(.semibold))
                let pieces = Set(all.map(\.url)).count
                Text("\(pieces) piece\(pieces == 1 ? "" : "s") · Furniture Library and your templates · loads as a family")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search pieces, rooms or materials", text: $query)
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
            .frame(width: 300)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: Grid

    @ViewBuilder var content: some View {
        if all.isEmpty {
            emptyState(symbol: "books.vertical", title: "No furniture yet",
                       message: "Pieces you save with File ▸ Save as Furniture Template appear here, by room. Browse… loads any furniture file.")
                .overlay(alignment: .bottom) { ClaudeFurnitureHint().padding(.bottom, 24).padding(.horizontal, 24) } // MCP
        } else if rooms.isEmpty {
            emptyState(symbol: "magnifyingglass", title: "No pieces match “\(query)”", message: "Try another name, room or material.")
        } else {
            ScrollView {
                FurnitureLibraryGrid(rooms: rooms, selectedID: selectedItem?.id, onSelect: { selected = $0.id }, onOpen: { place($0.url) })
                    .padding(18)
            }
        }
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
            Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction).dialogButton()
            Button("Place") { placeSelected() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(selectedItem == nil).dialogButton()
        }
        .padding(.horizontal, DialogStyle.outer).padding(.vertical, DialogStyle.footerPaddingV) // DIALOGS: the dialog footer
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
