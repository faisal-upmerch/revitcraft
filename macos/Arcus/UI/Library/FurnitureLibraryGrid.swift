import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// FM9: the Furniture Library as Insert ▸ Load Furniture and the Component Library show it: a room list with counts,
// and a responsive grid of previews by room (name and type count under each), searched by name, room and keywords;
// the selected piece's detail lists its types with their sizes.

/// A responsive grid of library pieces in room sections.
struct FurnitureLibraryGrid: View {
    let rooms: [FurnitureLibraryCatalog.Room]
    /// The selected piece (its id: room and file).
    var selectedID: String?
    var tileWidth: CGFloat = 136
    let onSelect: (FurnitureLibraryCatalog.Item) -> Void
    let onOpen: (FurnitureLibraryCatalog.Item) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: tileWidth), spacing: 14, alignment: .top)]
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
            ForEach(rooms) { room in
                Section {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(room.items) { item in
                            FurniturePieceTile(item: item, selected: item.id == selectedID, width: tileWidth)
                                .onTapGesture(count: 2) { onSelect(item); onOpen(item) }
                                .onTapGesture { onSelect(item) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(room.name).font(.system(size: 12.5, weight: .semibold))
                        Text("\(room.items.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One piece: its preview, name, and type count (or "My template").
struct FurniturePieceTile: View {
    let item: FurnitureLibraryCatalog.Item
    let selected: Bool
    var width: CGFloat = 152

    var body: some View {
        // The tile fills its grid column; the preview keeps a 4:3 frame.
        let thumb = CGSize(width: width + 36, height: ((width + 36) * 0.72).rounded())
        VStack(alignment: .leading, spacing: 6) {
            FurnitureFileThumbnail(url: item.url, size: thumb)
                .frame(maxWidth: .infinity)
                .frame(height: (width * 0.72).rounded())
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(item.summary.isEmpty ? item.name : item.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    var subtitle: String {
        if item.isUser { return "My template" }
        let types = item.typeCountText
        if let c = item.category, c == "Casework" { return types.isEmpty ? c : "\(types) · \(c)" }
        return types.isEmpty ? item.room : types
    }
}

/// The room list beside the grid: All Pieces and each room, with counts.
struct FurnitureRoomList: View {
    let items: [FurnitureLibraryCatalog.Item]
    /// nil = All Pieces.
    @Binding var room: String?

    var body: some View {
        let rooms = FurnitureLibraryCatalog.rooms(items)
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                row(nil, "All Pieces", symbol: "square.grid.2x2", count: Set(items.map(\.url)).count)
                Text("Rooms").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 3)
                ForEach(rooms) { r in row(r.name, r.name, symbol: Self.symbol(r.name), count: r.items.count) }
            }
            .padding(8)
        }
        .background(Color.primary.opacity(0.025))
    }

    func row(_ value: String?, _ label: String, symbol: String, count: Int) -> some View {
        let on = room == value
        return Button { room = value } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(on ? Color.white : Color.accentColor)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.system(size: 12.5, weight: on ? .medium : .regular))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, PillSpec.rowPadding).padding(.vertical, 5) // PILLS: 12 pt either side of the selected row's content
            .pillHighlight(on, .solid(Color.accentColor), cornerRadius: 8)
        }
        .buttonStyle(RibbonPressStyle())
        .accessibilityLabel("\(label), \(count) pieces")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A symbol for a room.
    static func symbol(_ room: String) -> String {
        let r = room.lowercased()
        if r.contains("living") { return "sofa" }
        if r.contains("bed") { return "bed.double" }
        if r.contains("dining") { return "fork.knife" }
        if r.contains("kitchen") { return "refrigerator" }
        if r.contains("office") { return "desktopcomputer" }
        if r.contains("bath") { return "bathtub" }
        if r.contains("entry") || r.contains("hall") { return "door.left.hand.open" }
        if r.contains("kid") || r.contains("nursery") { return "teddybear" }
        if r.contains("outdoor") || r.contains("balcony") { return "sun.max" }
        if r.contains("storage") || r.contains("utility") { return "shippingbox" }
        if r.contains("space") || r.contains("multi") { return "arrow.up.left.and.arrow.down.right" }
        if r.contains("decor") || r.contains("accent") { return "sparkles" }
        if r.contains("template") { return "person.crop.square" }
        return "square.grid.2x2"
    }

    /// The rooms to show for a room filter (nil = all) and a search.
    static func rooms(_ items: [FurnitureLibraryCatalog.Item], room: String?, query: String) -> [FurnitureLibraryCatalog.Room] {
        let all = FurnitureLibraryCatalog.rooms(items, matching: query)
        guard let room else { return all }
        return all.filter { $0.name == room }
    }
}

/// The selected piece: a large preview, its category and rooms, its description, and its types with their sizes.
struct FurniturePieceDetail: View {
    let item: FurnitureLibraryCatalog.Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FurnitureFileThumbnail(url: item.url, size: CGSize(width: 252, height: 184))
                    .frame(maxWidth: .infinity)
                    .frame(height: 196)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 15, weight: .semibold))
                    Text(line).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                if !item.summary.isEmpty {
                    Text(item.summary).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !item.types.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Types").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(item.types, id: \.name) { t in
                            HStack(spacing: 6) {
                                Text(t.name).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Self.size(t)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    var line: String {
        let rooms = item.rooms.isEmpty ? [item.room] : item.rooms
        return ([item.isUser ? "My template" : (item.category ?? "Furniture")] + rooms).joined(separator: " · ")
    }

    /// 72" × 36" × 34" (W × D × H).
    static func size(_ t: FurnitureLibraryIndex.TypeSize) -> String {
        let f = { (v: Double) in FurnitureSizeText.inches(v * 0.0254) }
        return "\(f(t.width)) × \(f(t.depth)) × \(f(t.height))"
    }
}
