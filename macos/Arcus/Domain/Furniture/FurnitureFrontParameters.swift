import Foundation
import ArcusGeometry

// FM5: Properties of bays, bay separators, fronts and their types, and owned hardware. Bays read like rooms (Name,
// Number, the clear opening and what bounds it); fronts like doors (Host, the hardware they take, the hinge side);
// front types like door types (overlay, style, reveals, materials, hardware, drawer box construction).

enum FurnitureFrontParameters {
    typealias P = BuiltInParameter

    static func err(_ s: String) -> ParameterError { ParameterError(s) }
    static func number(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a number.") }
        return d
    }
    static func text(_ v: ParamValue) -> String { v.textValue ?? v.description }
    static func label(_ id: ElementID?, _ m: BIMModel) -> String? {
        guard let e = m[id] else { return nil }
        if !e.mark.isEmpty { return e.mark }
        return e.name.isEmpty ? e.category.singularName : e.name
    }

    // MARK: Bays

    static let bayNumber = P("furniture.bay.number", "Number", .text, .identity, get: { e, _ in e.furnitureBay.map { .text($0.number) } })
    static let bayOpening = P("furniture.bay.opening", "Opening", .text, .dimensions, tooltip: "The clear opening, width by height (by depth seen from above).",
                              get: { e, _ in e.furnitureBay.map { .text(FurnitureBays.sizeText($0)) } })
    static func bayLength(_ id: String, _ name: String, _ f: @escaping @Sendable (BayOpening) -> Double) -> P {
        P("furniture.bay.\(id)", name, .length, .dimensions, get: { e, _ in e.furnitureBay?.opening.map { .double(f($0)) } })
    }
    static let clearWidth = bayLength("width", "Clear Width") { $0.width }
    static let clearHeight = P("furniture.bay.height", "Clear Height", .length, .dimensions,
                               get: { e, _ in e.furnitureBay.flatMap { b in b.opening.map { .double(b.face == .front ? $0.height : $0.depth) } } })
    static let clearDepth = P("furniture.bay.depth", "Clear Depth", .length, .dimensions,
                              get: { e, _ in e.furnitureBay.flatMap { b in b.opening.map { .double(b.face == .front ? $0.depth : $0.height) } } })
    static let bayFace = P("furniture.bay.face", "Seen From", .text, .constraints,
                           get: { e, _ in e.furnitureBay.map { .text($0.face == .top ? $0.face.rawValue : BayFrame($0).name) } }) // FMG3: Front, Back, Left, Right, Angled
    static let bayBounded = P("furniture.bay.bounded", "Enclosed", .bool, .constraints, get: { e, _ in e.furnitureBay.map { .bool($0.opening != nil) } })
    static let bayBoundedBy = P("furniture.bay.boundedBy", "Bounded By", .text, .constraints, tooltip: "The parts round the opening: left, right, bottom, top and back.",
                                get: { e, ctx in
                                    guard let o = e.furnitureBay?.opening else { return .text("") }
                                    let ids: [(String, ElementID?)] = [("L", o.left), ("R", o.right), ("B", o.bottom), ("T", o.top), ("Back", o.back)]
                                    return .text(ids.compactMap { k, id in label(id, ctx.model).map { "\(k): \($0)" } }.joined(separator: ", "))
                                })
    static let bayDivision = P("furniture.bay.division", "Bay Divide", .choice(["None"] + BayDivision.Direction.allCases.map(\.rawValue)), .construction,
                               tooltip: "Split the bay into rows (drawers) or columns, as a curtain grid.",
                               get: { e, _ in e.furnitureBay.map { .text($0.division?.direction.rawValue ?? "None") } },
                               set: { e, v, _ in
                                   guard var b = e.furnitureBay else { return }
                                   if let d = BayDivision.Direction(rawValue: text(v)) {
                                       var div = b.division ?? BayDivision(direction: d, count: 2)
                                       div.direction = d
                                       b.division = div
                                   } else { b.division = nil }
                                   e.furnitureBay = b
                               },
                               locked: { e, _ in e.furnitureBay?.opening == nil ? "The bay isn't enclosed." : nil })
    static let bayCells = P("furniture.bay.cells", "Number of Cells", .integer, .construction,
                            get: { e, _ in e.furnitureBay?.division.map { .int($0.count) } },
                            set: { e, v, _ in
                                guard let n = v.intValue, (1...24).contains(n) else { throw err("Use 1 to 24 cells.") }
                                e.furnitureBay?.division?.count = n
                            },
                            locked: { e, _ in e.furnitureBay?.division == nil ? "Choose Rows or Columns in Bay Divide first." : nil })
    static let bayLayout = P("furniture.bay.layout", "Layout", .choice(BayDivision.Layout.allCases.map(\.rawValue)), .construction,
                             get: { e, _ in e.furnitureBay?.division.map { .text($0.layout.rawValue) } },
                             set: { e, v, _ in
                                 guard let l = BayDivision.Layout(rawValue: text(v)) else { throw err("Choose Equal (EQ) or By Dimension.") }
                                 e.furnitureBay?.division?.layout = l
                             },
                             locked: { e, _ in e.furnitureBay?.division == nil ? "Choose Rows or Columns in Bay Divide first." : nil })
    static let bayFirstCell = P("furniture.bay.firstCell", "First Cell Size", .length, .construction,
                                tooltip: "By Dimension: the bottom (or left) cell's size; the others share the rest equally.",
                                get: { e, _ in e.furnitureBay?.division.flatMap { $0.layout == .fixed ? $0.sizes.first.map { .double($0) } : nil } },
                                set: { e, v, _ in
                                    let d = try number(v, "First Cell Size")
                                    guard d > 0.01 else { throw err("The cell is too small.") }
                                    e.furnitureBay?.division?.sizes = [d]
                                },
                                locked: { e, _ in e.furnitureBay?.division?.layout == .fixed ? nil : "Set Layout to By Dimension first." })

    static func bay(_ e: Element) -> [P] {
        let base: [P] = [BuiltInCatalog.name, bayNumber, bayFace, bayBounded, bayBoundedBy, bayOpening, clearWidth, clearHeight, clearDepth]
        let divide: [P] = e.furnitureBay?.parentID == nil || e.furnitureBay?.division != nil ? [bayDivision, bayCells, bayLayout, bayFirstCell] : [bayDivision]
        return base + divide + [BuiltInCatalog.comments, BuiltInCatalog.phaseCreated, BuiltInCatalog.phaseDemolished]
    }

    // MARK: Separators

    static let separatorLength = P("furniture.separator.length", "Length", .length, .dimensions,
                                   get: { e, _ in e.furnitureBaySeparator.map { .double($0.start.distance(to: $0.end)) } })
    static let separatorFace = P("furniture.separator.face", "Seen From", .text, .constraints,
                                 get: { e, _ in e.furnitureBaySeparator.map { .text($0.face == .top ? $0.face.rawValue : BayFrame(angle: $0.facing ?? 0).name) } }) // FMG3

    // MARK: Fronts

    static let host = P("furniture.front.host", "Host", .text, .constraints, get: { e, ctx in ctx.model[e.hostID].map { .text($0.name) } })
    static let hingeSide = P("furniture.front.hingeSide", "Hinge Side", .choice(["Left", "Right"]), .construction,
                             tooltip: "Flip it with the arrows or Space, as a door's hand.",
                             get: { e, _ in e.furnitureFront.map { .text($0.hingeFlipped ? "Right" : "Left") } },
                             set: { e, v, _ in e.furnitureFront?.hingeFlipped = text(v) == "Right" },
                             locked: { e, ctx in
                                 guard let f = e.furnitureFront else { return nil }
                                 if f.kind != .door { return "Only doors hinge on a side." }
                                 return FurnitureFrontTypes.values(of: e, ctx.model).isPair ? "Pairs hinge on both sides." : nil
                             })
    static func hardwareRef(_ id: String, _ name: String, kind: HardwareKind, get: @escaping @Sendable (FrontData) -> ElementID?,
                            set: @escaping @Sendable (inout FrontData, ElementID?) -> Void, typeValue: @escaping @Sendable (FurnitureFrontTypes.Values) -> ElementID?) -> P {
        P("furniture.front.\(id)", name, .elementRef(.furnitureHardware), .construction, tooltip: "Swap the \(name.lowercased()) of this front (the type's when empty).",
          get: { e, ctx in e.furnitureFront.map { .ref(get($0) ?? typeValue(FurnitureFrontTypes.values(of: e, ctx.model))) } },
          set: { e, v, ctx in
              guard var f = e.furnitureFront else { return }
              if let r = v.refValue {
                  guard FurnitureHardware.Values(ctx.model[r]?.typeData).kind == kind else { throw err("Choose a \(kind.rawValue.lowercased()) type.") }
              }
              set(&f, v.refValue)
              e.furnitureFront = f
          })
    }
    static let handle = hardwareRef("handle", "Handle", kind: .handle, get: { $0.handleTypeID }, set: { $0.handleTypeID = $1 }, typeValue: { $0.handleType })
    static let hinge = hardwareRef("hinge", "Hinge", kind: .hinge, get: { $0.hingeTypeID }, set: { $0.hingeTypeID = $1 }, typeValue: { $0.hingeType })
    static let handlePosition = P("furniture.front.handlePosition", "Handle Position", .choice(HandlePosition.allCases.map(\.rawValue)), .construction,
                                  get: { e, _ in e.furnitureFront.map { .text($0.handlePosition.rawValue) } },
                                  set: { e, v, _ in
                                      guard let f = e.furnitureFront, let p = HandlePosition(rawValue: text(v)), HandlePosition.options(f.kind).contains(p) else {
                                          throw err("Choose one of: \(HandlePosition.options(e.furnitureFront?.kind ?? .door).map(\.rawValue).joined(separator: ", ")).")
                                      }
                                      e.furnitureFront?.handlePosition = p
                                  })
    static let handleOffset = P("furniture.front.handleOffset", "Handle Offset", .length, .construction,
                                tooltip: "Doors: from the edge opposite the hinges to the handle's centre (empty = the type's).",
                                get: { e, ctx in e.furnitureFront.map { .double($0.handleOffset ?? FurnitureFrontTypes.values(of: e, ctx.model).handleOffset) } },
                                set: { e, v, _ in e.furnitureFront?.handleOffset = max(0, try number(v, "Handle Offset")) })
    static let hingeCount = P("furniture.front.hingeCount", "Hinge Count", .integer, .construction, tooltip: "2 up to 40\", 3 up to 60\", 4 up to 80\", then 5.",
                              get: { e, ctx in .int(FurnitureFronts.hardware(e, ctx.model).filter { $0.slot.hasPrefix("hinge") }.count) })
    static let slide = P("furniture.front.slide", "Slide", .text, .construction, tooltip: "The type's slide family at the longest length that fits the bay's depth.",
                         get: { e, ctx in
                             guard e.furnitureFront?.kind == .drawer else { return nil }
                             guard let b = FurnitureFronts.drawerBox(e, ctx.model), let t = ctx.model[b.slideTypeID] else { return .text("None fits") }
                             return .text("\(t.typeData?.familyName ?? ""): \(t.name)")
                         })
    static let drawerBox = P("furniture.front.drawerBox", "Drawer Box", .text, .construction, tooltip: "Width x depth x height of the box.",
                             get: { e, ctx in
                                 guard e.furnitureFront?.kind == .drawer else { return nil }
                                 guard let b = FurnitureFronts.drawerBox(e, ctx.model) else { return .text("") }
                                 let f = { (v: Double) in FurnitureSizeText.inches(v) }
                                 return .text("\(f(b.width)) x \(f(b.depth)) x \(f(b.height))")
                             })
    static let frontSize = P("furniture.front.size", "Size", .text, .dimensions, tooltip: "Width × height of the front (of one leaf of a pair).",
                             get: { e, ctx in .text(FurnitureFrontSolids.sizeText(e, ctx.model)) })
    static let frontWidth = BuiltInCatalog.q("furniture.front.width", "Width", .length) { $0.width }
    static let frontHeight = BuiltInCatalog.q("furniture.front.height", "Height", .length) { $0.height }
    static let frontThickness = BuiltInCatalog.q("furniture.front.thickness", "Thickness", .length) { $0.thickness }
    static let frontArea = BuiltInCatalog.q("furniture.front.area", "Area", .area) { $0.area }

    static func front(_ e: Element) -> [P] {
        let typed = [BuiltInCatalog.familyName, BuiltInCatalog.typeName, BuiltInCatalog.familyAndType]
        var list: [P] = typed + [host]
        switch e.furnitureFront?.kind ?? .door {
        case .door: list += [hingeSide, hinge, hingeCount, handle, handlePosition, handleOffset]
        case .flap: list += [hinge, hingeCount, handle, handlePosition]
        case .drawer: list += [handle, handlePosition, slide, drawerBox]
        }
        return list + [frontSize, frontWidth, frontHeight, frontThickness, frontArea, BuiltInCatalog.mark, BuiltInCatalog.comments,
                       BuiltInCatalog.phaseCreated, BuiltInCatalog.phaseDemolished]
    }

    // MARK: Hardware

    static let owner = P("furniture.hardware.ownerName", "Host", .text, .constraints, tooltip: "The front that places this hardware (it moves and goes with it).",
                         get: { e, ctx in e.params[FurnitureHardware.ownerParam]?.refValue.flatMap { label($0, ctx.model) }.map { .text($0) } })
    static let hwKind = P("furniture.hardware.kindName", "Hardware", .text, .identity, get: { e, ctx in FurnitureHardware.values(of: e, ctx.model).kind.map { .text($0.rawValue) } })
    static let hwCount = P("furniture.hardware.count", "Count", .integer, .identity, tooltip: "Pieces this instance counts as in the Hardware Schedule.",
                           get: { e, _ in e.category == .furnitureHardware ? .int(1) : nil })

    /// Extra Properties of hardware instances (placed after the component's own).
    static func hardwareInstance(_ e: Element) -> [P] {
        guard e.category == .furnitureHardware else { return [] }
        return [hwKind, hwCount] + (e.params[FurnitureHardware.ownerParam] != nil ? [owner] : [])
    }

    // MARK: Types

    typealias FT = FurnitureFrontTypes
    static func typeNumber(_ id: ParameterID, _ name: String, _ group: ParameterGroup = .construction, min: Double = 0) -> P {
        P(id.key, name, .length, group, get: { e, _ in e.typeData?.params[id] },
          set: { e, v, _ in
              let d = try number(v, name)
              guard d >= min else { throw err("“\(name)” is too small.") }
              e.typeData?.params[id] = .double(d)
          })
    }
    static func typeChoice(_ id: ParameterID, _ name: String, _ options: [String], _ group: ParameterGroup = .construction) -> P {
        P(id.key, name, .choice(options), group, get: { e, _ in e.typeData?.params[id] ?? .text(options.first ?? "") },
          set: { e, v, _ in
              guard options.contains(text(v)) else { throw err("Choose one of: \(options.joined(separator: ", ")).") }
              e.typeData?.params[id] = .text(text(v))
          })
    }
    static func typeRef(_ id: ParameterID, _ name: String, _ cat: Category, kind: HardwareKind? = nil) -> P {
        P(id.key, name, .elementRef(cat), cat == .materials ? .materials : .construction, get: { e, _ in e.typeData?.params[id] ?? .ref(nil) },
          set: { e, v, ctx in
              if let r = v.refValue {
                  if cat == .materials, ctx.model[r]?.material == nil { throw err("Not a material.") }
                  if let kind, FurnitureHardware.Values(ctx.model[r]?.typeData).kind != kind { throw err("Choose a \(kind.rawValue.lowercased()) type.") }
              }
              e.typeData?.params[id] = .ref(v.refValue)
          })
    }
    static let tOverlay = typeChoice(FT.overlay, "Overlay", FrontOverlay.allCases.map(\.rawValue))
    static let tLeaves = typeChoice(FT.leaves, "Leaves", ["Single", "Pair"])
    static let tStyle = typeChoice(FT.style, "Style", FrontStyle.allCases.map(\.rawValue))
    static let tThickness = typeNumber(FurniturePartTypes.thickness, "Thickness", min: 0.003)
    static let tReveal = typeNumber(FT.reveal, "Reveal", tooltip: "Gap between neighbouring fronts, and round an inset front.")
    static let tEdgeReveal = typeNumber(FT.edgeReveal, "Edge Reveal", tooltip: "Full overlay: the gap to the carcass's outside edges.")
    static let tEdgeProfile = typeChoice(FT.edgeProfile, "Edge Profile", ["Square", EdgeProfileShape.roundOver.rawValue, EdgeProfileShape.chamfer.rawValue,
                                                                          EdgeProfileShape.ogee.rawValue, EdgeProfileShape.cove.rawValue])
    static let tStile = typeNumber(FT.stileWidth, "Stile Width", .dimensions, min: 0.01)
    static let tRail = typeNumber(FT.railWidth, "Rail Width", .dimensions, min: 0.01)
    static let tPanelThickness = typeNumber(FT.panelThickness, "Panel Thickness", min: 0.002)
    static let tPanelRecess = typeNumber(FT.panelRecess, "Panel Recess")
    static let tPanelMaterial = typeRef(FT.panelMaterial, "Panel Material", .materials)
    static let tLouverPitch = typeNumber(FT.louverPitch, "Louver Spacing", min: 0.01)
    static let tCore = typeRef(FurniturePartTypes.coreMaterial, "Material", .materials)
    static let tFace = typeRef(FurniturePartTypes.faceMaterial, "Face Material", .materials)
    static let tEdge = typeRef(FurniturePartTypes.edgeMaterial, "Edge Band Material", .materials)
    static let tBanding = P(FurniturePartTypes.banding.key, "Edge Banding", .text, .construction,
                            get: { e, _ in e.typeData?.params[FurniturePartTypes.banding] },
                            set: { e, v, _ in e.typeData?.params[FurniturePartTypes.banding] = .text(EdgeBanding(code: text(v)).code) })
    static let tGrain = typeChoice(FurniturePartTypes.grain, "Grain", GrainDirection.allCases.map(\.rawValue))
    static let tHinge = typeRef(FT.hingeType, "Hinge", .furnitureHardware, kind: .hinge)
    static let tHingeInset = typeNumber(FT.hingeInset, "Hinge Inset", tooltip: "From the front's ends to the first and last hinge.")
    static let tHandle = typeRef(FT.handleType, "Handle", .furnitureHardware, kind: .handle)
    static let tHandleOffset = typeNumber(FT.handleOffset, "Handle Offset")
    static let tSlide = typeRef(FT.slideType, "Slide", .furnitureHardware, kind: .slide)
    static let tStay = typeRef(FT.stayType, "Flap Stay", .furnitureHardware, kind: .stay)
    static let tFlap = typeChoice(FT.flapAction, "Opening", FlapAction.allCases.map(\.rawValue))
    static let tBoxSide = typeNumber(FT.boxSide, "Box Side Thickness", min: 0.003)
    static let tBoxBack = typeNumber(FT.boxBack, "Box Front and Back Thickness", min: 0.003)
    static let tBoxBottom = typeNumber(FT.boxBottom, "Box Bottom Thickness", min: 0.002)
    static let tBoxMaterial = typeRef(FT.boxMaterial, "Box Material", .materials)
    static let tBottomMaterial = typeRef(FT.bottomMaterial, "Bottom Material", .materials)
    static let tBoxJoint = typeChoice(FT.boxJoint, "Box Joint", DrawerBoxJoint.allCases.map(\.rawValue))

    static func type(for td: TypeData) -> [P] {
        guard td.instanceCategory == .furnitureFronts else { return [] }
        let kind = FrontKind(rawValue: td.familyName) ?? .door
        var list: [P] = [tOverlay] + (kind == .door ? [tLeaves] : []) + [tStyle, tThickness, tReveal, tEdgeReveal, tEdgeProfile, tStile, tRail, tPanelThickness,
                                                                          tPanelRecess, tLouverPitch, tCore, tFace, tPanelMaterial, tEdge, tBanding, tGrain]
        switch kind {
        case .door: list += [tHinge, tHingeInset, tHandle, tHandleOffset]
        case .flap: list += [tFlap, tHinge, tHingeInset, tStay, tHandle]
        case .drawer: list += [tSlide, tHandle, tBoxSide, tBoxBack, tBoxBottom, tBoxMaterial, tBottomMaterial, tBoxJoint]
        }
        return list
    }

    // MARK: Lists

    static func instance(for e: Element) -> [P] {
        switch e.data {
        case .furnitureBay: return bay(e)
        case .furnitureFront: return front(e)
        case .furnitureBaySeparator: return [separatorFace, separatorLength, BuiltInCatalog.comments]
        default: return []
        }
    }

    /// Every instance parameter (for the catalog's lookup by id).
    static var allInstance: [P] {
        var bay = BayData(seed: .zero, number: "1")
        bay.division = BayDivision(direction: .rows, count: 2)
        return [Element(id: ElementID(0), category: .furnitureBays, data: .furnitureBay(bay))].flatMap(instance(for:))
            + FrontKind.allCases.flatMap { instance(for: Element(id: ElementID(0), category: .furnitureFronts, data: .furnitureFront(FrontData(kind: $0)))) }
            + instance(for: Element(id: ElementID(0), category: .furnitureBaySeparators, data: .furnitureBaySeparator(BaySeparatorData(start: .zero, end: Vec2(0, 1)))))
            + [hwKind, hwCount, owner]
    }

    static var allType: [P] { FrontKind.allCases.flatMap { type(for: TypeData(instanceCategory: .furnitureFronts, familyName: $0.rawValue)) } }
}

extension FurnitureFrontParameters {
    static func typeNumber(_ id: ParameterID, _ name: String, tooltip: String) -> BuiltInParameter {
        P(id.key, name, .length, .construction, tooltip: tooltip, get: { e, _ in e.typeData?.params[id] },
          set: { e, v, _ in e.typeData?.params[id] = .double(max(0, try number(v, name))) })
    }
}
