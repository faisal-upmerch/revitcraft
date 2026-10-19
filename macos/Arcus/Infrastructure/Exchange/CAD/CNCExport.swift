import Foundation
import ArcusGeometry
import ArcusDomain

// FM7: Fabricate ▸ CNC Export (Docs/FurnitureMode.md §3 "CNC Export"): writes the CNC programs of FurnitureCNC as
// DXF (inches, R2000) or DWG (through the bundled DWG engine), one file per part (face B in its own file or on B_
// layers) or one per nested sheet, plus a CSV part list. Layer conventions are documented in FurnitureCNC.swift.

public enum CNCExport {
    /// One file per part, or one per nested sheet.
    public enum Layout: String, CaseIterable, Sendable { case perPart = "Per Part", perSheet = "Per Nested Sheet" }
    /// Where face B operations go.
    public enum FaceB: String, CaseIterable, Sendable { case separateFile = "Separate File (_B)", flipLayers = "Flip Layers (B_)" }
    public enum Format: String, CaseIterable, Sendable { case dxf = "DXF", dwg = "DWG" }

    public struct Options: Sendable {
        public var layout: Layout
        public var format: Format
        public var faceB: FaceB
        public var includeCSV: Bool
        /// Parts by key to export (nil = every part).
        public var partKeys: Set<String>?
        public init(layout: Layout = .perPart, format: Format = .dxf, faceB: FaceB = .separateFile, includeCSV: Bool = true, partKeys: Set<String>? = nil) {
            self.layout = layout; self.format = format; self.faceB = faceB; self.includeCSV = includeCSV; self.partKeys = partKeys
        }
    }

    /// The files an export writes: name and drawing (CSV handled separately).
    public static func files(_ m: BIMModel, _ o: Options) -> [(name: String, drawing: CNCDrawing)] {
        switch o.layout {
        case .perPart:
            var out: [(String, CNCDrawing)] = []
            for p in FurnitureCNC.programs(m) where o.partKeys?.contains(p.part.key) ?? true {
                var a = p.faceA
                if let b = p.faceB, o.faceB == .flipLayers { a.append(b, layerPrefix: "B_") }
                out.append((p.name, a))
                if let b = p.faceB, o.faceB == .separateFile { out.append((p.name + "_B", b)) }
            }
            return out
        case .perSheet:
            return FurnitureCNC.sheetPrograms(m).map { ($0.name, $0.drawing) }
        }
    }

    /// A CNC drawing as DXF (inches): closed outlines and lines as LWPOLYLINE, holes as CIRCLE, labels as TEXT.
    public static func dxf(_ d: CNCDrawing) -> Data {
        let layers = d.layers
        let index = Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($1, $0) })
        var prims: [[GPrimitive]] = Array(repeating: [], count: layers.count)
        for p in d.paths { prims[index[p.layer]!].append(.polyline(p.points, closed: p.closed, GStroke(weight: 1))) }
        for c in d.circles { prims[index[c.layer]!].append(.arc(Arc2(center: c.center, radius: c.radius, startAngle: 0, sweep: 2 * .pi), GStroke(weight: 1))) }
        for t in d.labels {
            prims[index[t.layer]!].append(.text(GText(position: t.position, height: t.height, string: t.text, alignment: .center, verticalAnchor: 0.5)))
        }
        // The item's element id carries its layer's index.
        let items = prims.enumerated().map { i, ps in GItem(elementID: ElementID(UInt64(i + 1)), category: category(layers[i]), layer: .model, primitives: ps) }
        var ext = Rect2.empty
        for i in items { ext.include(i.bounds) }
        let g = ViewGraphics(viewID: ElementID(0), scale: 1, items: items, extents: ext, crop: nil, modelRevision: 0)
        return DXFWriter.write(g, units: .inches, itemLayer: { item in layers[Int((item.elementID?.raw ?? 1) - 1)] })
    }

    /// Object Styles colour family per layer kind (outlines dark, machining coloured), as CAM layer colours.
    static func category(_ layer: String) -> ArcusDomain.Category {
        let l = layer.hasPrefix("B_") ? String(layer.dropFirst(2)) : layer
        if l == "OUTLINE" || l == "SHEET" { return .detailLines }
        if l == "INNER" { return .wallOpenings }
        if l == "LABEL" || l == "GRAIN" { return .textNotes }
        return .dimensions
    }

    /// Writes the export into `folder`. DWG needs the bundled DWG helper (`dwgHelper`). Returns the files written.
    public static func write(_ m: BIMModel, to folder: URL, options o: Options, dwgHelper: URL? = nil,
                             isCancelled: @Sendable () -> Bool = { false }) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var out: [URL] = []
        for (name, d) in files(m, o) {
            if isCancelled() { break }
            let data = dxf(d)
            switch o.format {
            case .dxf:
                let url = folder.appendingPathComponent(name + ".dxf")
                try data.write(to: url)
                out.append(url)
            case .dwg:
                let url = folder.appendingPathComponent(name + ".dwg")
                try DWGExporter.write(dxf: data, to: url, helper: dwgHelper, isCancelled: isCancelled)
                out.append(url)
            }
        }
        if o.includeCSV {
            let url = folder.appendingPathComponent("Part List.csv")
            try Data(FurnitureCNC.csv(m).utf8).write(to: url)
            out.append(url)
        }
        return out
    }
}
