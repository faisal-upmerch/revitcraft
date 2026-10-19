import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusServices

// FM8: Load Furniture (the library browser) and Save as Furniture Template.

enum FM8Dialog: Equatable {
    case loadFurniture
    case saveTemplate
}

struct FM8DialogHost: View {
    let state: DocumentState
    let dialog: FM8Dialog
    var body: some View {
        switch dialog {
        case .loadFurniture: FurnitureLibraryBrowser(state: state)
        case .saveTemplate: SaveFurnitureTemplateDialog(state: state)
        }
    }
}

/// File ▸ Save as Furniture Template…: a name and a room, with the preview the template will show.
struct SaveFurnitureTemplateDialog: View {
    let state: DocumentState
    @State private var name = ""
    @State private var room = ""
    @State private var rooms: [String] = []
    @State private var preview: CGImage?

    var body: some View {
        DialogFrame(title: "Save as Furniture Template", subtitle: "Saves a copy with a preview in your Furniture Templates. It appears on Home ▸ Furniture and in Load Furniture.",
                    okTitle: "Save", okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, state: state, onOK: save) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    FormRow(label: "Name") { TextField("", text: $name).textFieldStyle(.roundedBorder).frame(width: 220) }
                    FormRow(label: "Room") {
                        HStack(spacing: 4) {
                            TextField("", text: $room).textFieldStyle(.roundedBorder).frame(width: 190)
                            Menu {
                                ForEach(rooms, id: \.self) { r in Button(r) { room = r } }
                            } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Choose a room")
                        }
                    }
                    Text(destinationText).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05))
                    if let preview { Image(decorative: preview, scale: 2).resizable().aspectRatio(contentMode: .fit).padding(8) }
                    else { ProgressView().controlSize(.small) }
                }
                .frame(width: 176, height: 132)
                .accessibilityLabel("Preview")
            }
        }
        .frame(width: 560)
        .onAppear {
            name = state.model.furnitureSetup?.name ?? state.documentName
            rooms = FurnitureLibraryCatalog.templateRooms(FurnitureLibraryCatalog.all())
            room = Self.lastRoom.flatMap { rooms.contains($0) ? $0 : nil } ?? FurnitureLibraryCatalog.myTemplatesRoom
            let m = state.model
            Task {
                preview = await Task.detached(priority: .userInitiated) { FurnitureThumbnail.image(m, width: 352, height: 264).map(LibraryPreviewImage.init) }.value?.image
            }
        }
    }

    static var lastRoom: String? {
        get { UserDefaults.standard.string(forKey: "ArcusFurnitureTemplateRoom") }
        set { UserDefaults.standard.set(newValue, forKey: "ArcusFurnitureTemplateRoom") }
    }

    var destinationText: String {
        let r = room.trimmingCharacters(in: .whitespaces)
        return "Furniture Templates ▸ " + (r.isEmpty || r == FurnitureLibraryCatalog.myTemplatesRoom ? "My Templates" : r)
    }

    func save() {
        guard let root = FurnitureLibraryCatalog.userRoot else { return }
        let url = FurnitureLibraryCatalog.templateURL(name: name, room: room, root: root)
        if FileManager.default.fileExists(atPath: url.path) {
            let a = NSAlert()
            a.messageText = "A template named “\(url.deletingPathExtension().lastPathComponent)” already exists in \(destinationText)."
            a.informativeText = "Replace it with this piece?"
            a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try FurnitureTemplateSaver.save(state.model, name: url.deletingPathExtension().lastPathComponent, to: url)
            Self.lastRoom = room
            state.presented = nil
            state.show("Saved “\(url.deletingPathExtension().lastPathComponent)” to \(destinationText).")
        } catch {
            state.show("Couldn't save the template: \(error.localizedDescription)", error: true)
        }
    }
}

/// Writes Furniture templates.
@MainActor
enum FurnitureTemplateSaver {
    /// Saves a copy of the Furniture document `m`, named `name`, as a package at `url` with its 3D preview.
    static func save(_ m: BIMModel, name: String, to url: URL) throws {
        let copy = FurnitureTemplates.copy(m, name: name, category: m.furnitureSetup?.category ?? .furniture) ?? m
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = AppVersionInfo.current.writeInfo(documentID: UUID(), created: Date(), thumbnailPNG: FurnitureThumbnail.png(copy))
        try ArcusPackage.write(copy, to: url, info: info)
    }
}
