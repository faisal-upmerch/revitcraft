import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// HOME: the details of each Start card (name, template or category, gallery) above the Create bar.

/// A labelled row of a card's options: the label column is 88 pt wide.
struct HomeFormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

/// The name field shared by the three cards.
struct HomeNameField: View {
    let placeholder: String
    @Binding var text: String
    var onEdit: () -> Void = {}
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .frame(width: 320)
            .onChange(of: text) { _, _ in onEdit() }
            .accessibilityLabel("Name")
    }
}

// MARK: - Architectural

struct HomeArchitecturalPane: View {
    @Bindable var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeFormRow(label: "Name") { HomeNameField(placeholder: "Project name", text: $model.projectName) }
            HomeFormRow(label: "Template") { templateMenu }
            HomeFormRow(label: "Units") {
                Text("Imperial: feet and inches, 1/16\"").font(.system(size: 13))
                    .help("Architectural projects start in Imperial. Change it later in Manage ▸ Project Units.")
            }
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title: model.isUserTemplate ? "From Your Template" : "Includes")
                if model.isUserTemplate {
                    HomeIncludesTile(symbol: "doc.on.doc", text: userTemplateSummary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        HomeIncludesTile(symbol: "square.3.layers.3d", text: "Wall, floor, roof and ceiling types")
                        HomeIncludesTile(symbol: "door.left.hand.open", text: "Door, window and column families")
                        HomeIncludesTile(symbol: "map", text: "3 levels with plans, 4 elevations and 3D")
                        HomeIncludesTile(symbol: "tablecells", text: "5 schedules and an ARCH D sheet")
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    var userTemplateSummary: String {
        guard case .user(let url) = model.template else { return "" }
        let when = model.userTemplates.first { $0.url == url }.map { " Saved \($0.modified.formatted(date: .abbreviated, time: .omitted))." } ?? ""
        return "Its types, families, views, sheets and settings. Model elements are left out." + when
    }

    var templateMenu: some View {
        Menu {
            Button { model.template = .builtIn(.architectural) } label: { check("Architectural", model.template == .builtIn(.architectural)) }
            if !model.userTemplates.isEmpty {
                Section("My Templates") {
                    ForEach(model.userTemplates) { t in
                        Button { model.template = .user(t.url) } label: { check(t.name, model.template == .user(t.url)) }
                    }
                }
            }
            if !model.browsedTemplates.isEmpty {
                Section("Other Templates") {
                    ForEach(model.browsedTemplates, id: \.self) { u in
                        Button { model.template = .user(u) } label: { check(u.deletingPathExtension().lastPathComponent, model.template == .user(u)) }
                    }
                }
            }
            Divider()
            Button("Choose Template File…") { model.browseTemplate() }
            if case .user(let url) = model.template {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if model.userTemplates.contains(where: { $0.url == url }) {
                    Button("Move Template to Trash") { model.trashTemplate(url) }
                }
            }
            if UserTemplates.directory != nil {
                Button("Open Templates Folder") { model.openTemplatesFolder() }
            }
        } label: {
            Text(model.templateTitle)
        }
        .menuStyle(.button)
        .controlSize(.large)
        .fixedSize()
        .help("Start from the Architectural template or one of yours")
        .accessibilityLabel("Template, \(model.templateTitle)")
    }

    @ViewBuilder func check(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// One line of what a template includes, on a quiet tile.
struct HomeIncludesTile: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(HomeCard.architectural.tint).frame(width: 20)
            Text(text).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Tokens.thumbnailCornerRadius, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Furniture

struct HomeFurniturePane: View {
    @Bindable var model: HomeModel
    static let columns = [GridItem(.adaptive(minimum: 112, maximum: 148), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeFormRow(label: "Name") { HomeNameField(placeholder: "Piece name", text: $model.furnitureName) }
            HomeFormRow(label: "Category") {
                Picker("Category", selection: $model.furnitureCategory) {
                    Text("Furniture").tag(FamilyTemplate.furniture)
                    Text("Casework").tag(FamilyTemplate.casework)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Furniture for loose pieces; Casework for built-in cabinets and millwork")
            }
            HStack {
                HomeSectionHeader(title: "Start From")
                Spacer()
                if !model.library.isEmpty {
                    TextField("Search pieces or rooms", text: $model.furnitureSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 216)
                        .accessibilityLabel("Search the furniture library")
                }
            }
            .padding(.top, 8)
            gallery
        }
    }

    @ViewBuilder var gallery: some View {
        let rooms = model.libraryRooms
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                HomeGalleryTile(title: "Blank", subtitle: model.furnitureCategory.rawValue, selected: model.furnitureTemplate == nil) {
                    HomeBlankThumbnail()
                } action: { model.furnitureTemplate = nil }
            }
            if model.library.isEmpty {
                HomeEmptyState(symbol: "books.vertical", title: "No library pieces yet",
                               message: "Start from Blank. Pieces you save as furniture templates appear here.",
                               actionTitle: "Open Furniture Templates Folder") { model.openFurnitureTemplatesFolder() }
            } else if rooms.isEmpty {
                HomeEmptyState(symbol: "magnifyingglass", title: "No pieces match “\(model.furnitureSearch)”", message: "Try another name or room.")
            } else {
                ForEach(rooms) { room in
                    VStack(alignment: .leading, spacing: 8) {
                        HomeSectionHeader(title: room.name)
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                            ForEach(room.items) { item in
                                HomeGalleryTile(title: item.name, subtitle: item.isUser ? "My template" : nil, selected: model.furnitureTemplate == item.url) {
                                    RecentThumbnail(url: item.url, placeholder: .furniture)
                                } action: {
                                    model.furnitureTemplate = item.url
                                    if model.furnitureName == "Untitled Furniture" { model.furnitureName = item.name }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A gallery tile: a thumbnail over a name, selectable.
struct HomeGalleryTile<Thumb: View>: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    var tint: Color = HomeCard.furniture.tint
    @ViewBuilder var thumbnail: Thumb
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbnailCornerRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                .padding(.horizontal, 4)
            }
            .padding(4)
            .padding(.bottom, 4)
            .homeCard(selected: selected, tint: tint, outlined: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The Blank piece: a dashed outline with a plus.
struct HomeBlankThumbnail: View {
    var body: some View {
        ZStack {
            Color.primary.opacity(0.03)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(14)
            Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

/// A quiet empty state: symbol, title, message and an optional action.
struct HomeEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).buttonStyle(.link).font(.system(size: 12)).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Tokens.cardCornerRadius, style: .continuous).fill(Color.primary.opacity(0.035)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Family

struct HomeFamilyPane: View {
    @Bindable var model: HomeModel
    static let columns = [GridItem(.adaptive(minimum: 136, maximum: 180), spacing: 8, alignment: .top)]
    static let modelTemplates: [FamilyTemplate] = [.door, .window, .furniture, .casework, .genericModel, .column, .structuralColumn, .structuralFraming,
                                          .plumbingFixture, .lightingFixture, .electricalFixture, .mechanicalEquipment, .specialtyEquipment,
                                          .planting, .entourage, .parking, .site]
    static let annotation: [FamilyTemplate] = [.tag, .genericAnnotation, .titleBlock, .profile, .detailComponent]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeFormRow(label: "Name") {
                HomeNameField(placeholder: "Family name", text: $model.familyName) {
                    if model.familyName != HomeModel.defaultFamilyName(model.familyCategory) { model.familyNameEdited = true }
                }
            }
            HomeFormRow(label: "Project") {
                Text(projectLine).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            section("Model", Self.modelTemplates).padding(.top, 8)
            section("Annotation and Detail", Self.annotation)
        }
    }

    var projectLine: String {
        if let s = HomeFamilyStart.openProject, let name = s.document?.displayName {
            return "Load into Project loads it into “\(name)”."
        }
        return "Load into Project opens a new Imperial project with it."
    }

    func section(_ title: String, _ templates: [FamilyTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: title)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(templates, id: \.self) { t in
                    HomeCategoryTile(template: t, selected: model.familyCategory == t) { model.familyCategory = t }
                }
            }
        }
    }
}

/// A family category template: its symbol and name.
struct HomeCategoryTile: View {
    let template: FamilyTemplate
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let tint = HomeCard.family.tint
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(template))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? tint : .secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? tint.opacity(0.16) : Color.primary.opacity(0.05)))
                Text(template.rawValue).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(height: 32)
            .padding(6)
            .homeCard(selected: selected, tint: tint, radius: Tokens.cardCornerRadius - 2, outlined: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    static func symbol(_ t: FamilyTemplate) -> String {
        switch t {
        case .door: "door.left.hand.open"
        case .window: "window.casement"
        case .furniture: "sofa"
        case .casework: "cabinet"
        case .genericModel: "cube"
        case .column: "building.columns"
        case .structuralColumn: "rectangle.portrait"
        case .structuralFraming: "rectangle.split.3x1"
        case .plumbingFixture: "sink"
        case .tag: "tag"
        case .genericAnnotation: "signpost.right"
        case .titleBlock: "doc.text"
        case .profile: "square.on.square.dashed"
        case .detailComponent: "pencil.and.ruler"
        case .lightingFixture: "lamp.ceiling"
        case .electricalFixture: "powerplug"
        case .mechanicalEquipment: "fan"
        case .specialtyEquipment: "wrench.and.screwdriver"
        case .planting: "leaf"
        case .entourage: "figure.stand"
        case .parking: "car.side"
        case .site: "mountain.2"
        }
    }
}
