import Foundation
import ArcusGeometry

// FM9C: the recurring assemblies of the part B pieces, made of the step helpers (inches): a carcass of two sides, a
// top and a bottom; four legs in the corners of a rectangle with rails between them; a top over legs and aprons.

/// The parts of a carcass by role.
struct SBCarcass {
    var left: ElementID
    var right: ElementID
    var top: ElementID?
    var bottom: ElementID
}

extension SBStep {
    /// A part type's thickness (sheets) or width (legs and rails) in inches.
    func thickness(_ cat: Category, _ name: String) throws -> Double {
        let v = FurniturePartTypes.Values(tx.model[try type(cat, name)]?.typeData)
        return (cat == .furnitureLegs || cat == .furnitureRails ? v.width : v.thickness) / Self.inch
    }

    /// The vertical size of a rail type (its depth) in inches.
    func railHeight(_ name: String) throws -> Double {
        FurniturePartTypes.Values(tx.model[try type(.furnitureRails, name)]?.typeData).depth / Self.inch
    }

    /// Two sides from z0 to z1 over the depth, a top between them at z1 (none when `top` is nil) and a bottom between
    /// them with its top face at `bottomAt`.
    @discardableResult
    func carcass(x: (Double, Double)? = nil, y: (Double, Double)? = nil, z: (Double, Double)? = nil, bottomAt: Double,
                 sides: String = "3/4\" Plywood", top: String? = "3/4\" Plywood Top", bottom: String = "3/4\" Plywood Shelf") throws -> SBCarcass {
        let (x0, x1) = x ?? (l, r), (y0, y1) = y ?? (f, b), (z0, z1) = z ?? (0, h)
        let t = try thickness(.furniturePanels, sides)
        let left = try panelX(x0, inward: 1, y: (y0, y1), z: (z0, z1), sides)
        let right = try panelX(x1, inward: -1, y: (y0, y1), z: (z0, z1), sides)
        let topID = try top.map { try board(x: (x0 + t, x1 - t), y: (y0, y1), top: z1, $0, role: .top) }
        let bottomID = try board(x: (x0 + t, x1 - t), y: (y0, y1), top: bottomAt, bottom, role: .bottom)
        return SBCarcass(left: left, right: right, top: topID, bottom: bottomID)
    }

    /// Four legs of `type` in the corners of a plan rectangle, from z0 to z1. Returns them and the leg's width.
    @discardableResult
    func legs(x: (Double, Double), y: (Double, Double), z: (Double, Double), _ type: String) throws -> (ids: [ElementID], width: Double) {
        let lw = try thickness(.furnitureLegs, type)
        let ld = FurniturePartTypes.Values(tx.model[try self.type(.furnitureLegs, type)]?.typeData).depth / Self.inch
        var ids: [ElementID] = []
        for px in [x.0 + lw / 2, x.1 - lw / 2] {
            for py in [y.0 + ld / 2, y.1 - ld / 2] { ids.append(try leg(px, py, z: z, type)) }
        }
        return (ids, lw)
    }

    /// Rails round a plan rectangle between legs `lw` wide in its corners, the rails' tops at `top`, their centres on
    /// the legs' centre lines (or `inset` in from the rectangle's edge).
    @discardableResult
    func railRing(x: (Double, Double), y: (Double, Double), legWidth lw: Double, top: Double, _ type: String, inset: Double? = nil,
                  sides: (front: Bool, back: Bool, left: Bool, right: Bool) = (true, true, true, true)) throws -> [ElementID] {
        let c = inset ?? lw / 2
        var ids: [ElementID] = []
        let x0 = x.0 + lw, x1 = x.1 - lw, y0 = y.0 + lw, y1 = y.1 - lw
        if sides.front { ids.append(try rail((x0, y.0 + c), (x1, y.0 + c), z: top, type)) }
        if sides.back { ids.append(try rail((x1, y.1 - c), (x0, y.1 - c), z: top, type)) }
        if sides.left { ids.append(try rail((x.0 + c, y1), (x.0 + c, y0), z: top, type)) }
        if sides.right { ids.append(try rail((x.1 - c, y0), (x.1 - c, y1), z: top, type)) }
        return ids
    }

    /// A table: a top over the whole plan at Height, four legs `inset` in from its edges and aprons between them under it.
    /// Returns the top and the legs' rectangle (inside their outer faces) and width.
    @discardableResult
    func table(top: String, leg: String, inset: Double = 1, apron: String? = "3/4\" x 3\" Apron", x: (Double, Double)? = nil, y: (Double, Double)? = nil,
               topAt: Double? = nil) throws -> (top: ElementID, legX: (Double, Double), legY: (Double, Double), legWidth: Double, under: Double) {
        let (x0, x1) = x ?? (l, r), (y0, y1) = y ?? (f, b)
        let zt = topAt ?? h
        let tt = try thickness(.furnitureShelves, top)
        let topID = try board(x: (x0, x1), y: (y0, y1), top: zt, top, role: .top)
        let lx = (x0 + inset, x1 - inset), ly = (y0 + inset, y1 - inset)
        let (_, lw) = try legs(x: lx, y: ly, z: (0, zt - tt), leg)
        if let apron { try railRing(x: lx, y: ly, legWidth: lw, top: zt - tt, apron) }
        return (topID, lx, ly, lw, zt - tt)
    }

    /// A chair or stool frame: front legs up to the seat, back legs up to `backTop` (Height by default; the seat when
    /// nil), aprons under the seat, the seat (a board, or slats along x), and `backRails` rails between the back legs
    /// (or vertical slats between a low and a top rail). Returns the leg width.
    @discardableResult
    func chair(seat z: Double, leg: String, seatType: String, apron: String, seatSlats: Int = 0, backTop: Double? = nil, backRails: Int = 2,
               backRail: String? = nil, backSlats: Int = 0, backSlat: String = "3/4\" x 1 1/2\" Maple Rail", backFrom: Double? = nil, stretcherAt: Double? = nil, stretcher: String? = nil,
               x: (Double, Double)? = nil, y: (Double, Double)? = nil) throws -> Double {
        let (x0, x1) = x ?? (l, r), (y0, y1) = y ?? (f, b)
        let lw = try thickness(.furnitureLegs, leg)
        let st = seatSlats > 0 ? try railHeight(seatType) : try thickness(.furnitureShelves, seatType)
        let top = backTop ?? h
        let under = z - st
        for px in [x0 + lw / 2, x1 - lw / 2] {
            try self.leg(px, y0 + lw / 2, z: (0, under), leg)
            try self.leg(px, y1 - lw / 2, z: (0, backRails > 0 || backSlats > 0 ? top : under), leg)
        }
        try railRing(x: (x0, x1), y: (y0, y1), legWidth: lw, top: under, apron)
        if let s = stretcherAt, let t = stretcher {
            try railRing(x: (x0, x1), y: (y0, y1), legWidth: lw, top: s, t, sides: (false, false, true, true))
        }
        if seatSlats > 0 {
            try slats(x: (x0, x1), y: (y0, y1 - lw), alongX: true, count: seatSlats, top: z, seatType)
        } else {
            try board(x: (x0, x1), y: (y0, y1 - lw), top: z, seatType)
        }
        let br = backRail ?? apron
        let rh = try railHeight(br)
        let yb = y1 - lw / 2
        let low = backFrom ?? (z + (top - z) * 0.35)
        if backSlats > 0 {
            try rail((x0 + lw, yb), (x1 - lw, yb), z: low, br)
            try rail((x0 + lw, yb), (x1 - lw, yb), z: top, br)
            for k in 0..<backSlats {
                let px = x0 + lw + (x1 - x0 - 2 * lw) * (Double(k) + 1) / Double(backSlats + 1)
                try railXZ((px, low), (px, top - rh), y: yb, backSlat)
            }
        } else if backRails > 0 {
            for k in 0..<backRails {
                let zt = backRails == 1 ? top : low + (top - low) * Double(k) / Double(backRails - 1)
                try rail((x0 + lw, yb), (x1 - lw, yb), z: max(zt, low), br)
            }
        }
        return lw
    }

    /// A bed: posts in the corners (Height at the head, `foot` at the foot), a headboard and a footboard panel between
    /// them, side rails with their tops at `rail`, slats under the mattress and the mattress (head at the back).
    func bed(post: String, rail railType: String, rail top: Double, foot: Double, panel: String, mattress: String, slat: String = "1\" x 3\" Bed Slat",
             slatCount: Int = 12, headFrom: Double? = nil) throws {
        let pw = try thickness(.furnitureLegs, post)
        let rw = try thickness(.furnitureRails, railType)
        let pt = try thickness(.furniturePanels, panel)
        let mt = try thickness(.furnitureShelves, mattress)
        for (py, ztop) in [(f + pw / 2, foot), (b - pw / 2, h)] {
            try leg(l + pw / 2, py, z: (0, ztop), post)
            try leg(r - pw / 2, py, z: (0, ztop), post)
        }
        let rh = try railHeight(railType)
        let lowPanel = top - rh
        try panelY(b - pw / 2 + pt / 2, inward: -1, x: (l + pw, r - pw), z: (headFrom ?? lowPanel, h - 2), panel)
        try panelY(f + pw / 2 - pt / 2, inward: 1, x: (l + pw, r - pw), z: (lowPanel, foot - 2), panel)
        try rail((l + pw / 2, b - pw), (l + pw / 2, f + pw), z: top, railType)
        try rail((r - pw / 2, f + pw), (r - pw / 2, b - pw), z: top, railType)
        let deck = top - rh + 2.5
        let ix = (l + pw / 2 + rw / 2, r - pw / 2 - rw / 2)
        try slats(x: ix, y: (f + pw, b - pw), alongX: true, count: slatCount, top: deck, slat)
        try board(x: ix, y: (f + pw / 2 + pt / 2, b - pw / 2 - pt / 2), top: deck + mt, mattress)
    }
}
