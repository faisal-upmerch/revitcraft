import Foundation
import ArcusGeometry
import ArcusCalc

// FM3: regeneration of Furniture documents (one call from `Regenerator.regenerate`). Planes follow the Family Types
// values: formulas and labelled dimensions place them, as in a family. A plane the user dragged or moved changes the
// parameter its labelled dimension shows (the Family Editor's behaviour), then everything is solved again.

public enum FurnitureRegeneration {
    /// Regenerates a Furniture document's planes; does nothing in projects. Later milestones (parts) hook in after the
    /// planes are placed: `FurnitureRegeneration.afterPlanes` (FM4).
    public static func regenerate(_ tx: TransactionContext) {
        guard tx.model.isFurniture, tx.model.projectInfo.furniture != nil else { return }
        let touched = tx.touchedIDs
        guard !touched.isEmpty else { return }
        adoptNewPlanes(tx, touched)
        let relevant = touched.contains { id in
            guard let e = tx.model[id] ?? tx.originalElement(id) else { return false }
            return e.category == .projectInfo || e.category == .referencePlanes || e.category == .dimensions
        }
        if relevant {
            backSolveMovedPlanes(tx, touched)
            placePlanes(tx)
        }
        FurniturePartRegeneration.regenerate(tx, touched) // FM4: parts follow their planes (after the planes)
    }

    /// Gives axis-aligned reference planes drawn in a Furniture document their axis, so dimensions can drive them.
    static func adoptNewPlanes(_ tx: TransactionContext, _ touched: [ElementID]) {
        for id in touched {
            guard let e = tx.model[id], e.ownerViewID == nil, let rp = e.referencePlane, rp.furniture == nil, let axis = FurniturePlanes.axis(of: rp) else { continue }
            tx.propagate(id) { $0.referencePlane?.furniture = FurniturePlaneData(axis: axis) }
        }
    }

    /// Planes the user moved in this transaction change the parameter of a labelled dimension that measures them.
    /// The new value is the one that solves the dragged plane to where it was put (the solve is linear in the value).
    static func backSolveMovedPlanes(_ tx: TransactionContext, _ touched: [ElementID]) {
        guard let info = tx.model.projectInfoElement else { return }
        // A Family Types edit in the same transaction wins: the planes follow the values.
        if touched.contains(info.id), tx.originalElement(info.id)?.projectInfo?.furniture != info.projectInfo?.furniture { return }
        let names = FurniturePlanes.names(tx.model)
        for id in touched {
            guard tx.driven.contains(id), let before = tx.originalElement(id)?.referencePlane, let now = tx.model[id]?.referencePlane,
                  let a = FurniturePlanes.position(before), let target = FurniturePlanes.position(now), abs(a - target) > Tolerance.length,
                  let name = names[id], var setup = tx.model.furnitureSetup else { continue }
            let labels = tx.model.elements(.dimensions).compactMap { d -> String? in
                guard let dd = d.dimension, let l = dd.labelParameter, dd.references.contains(where: { $0.elementID == id }) else { return nil }
                return l
            }
            for label in labels {
                guard let p = setup.family.parameter(named: label), p.type == .length, p.formula == nil,
                      let ti = setup.family.types.firstIndex(where: { $0.name == setup.currentType }) else { continue }
                let v0 = FurnitureParameters.value(label, tx.model).flatMap { if case .quantity(let v, _) = $0 { v } else { nil } } ?? 0
                let step = max(abs(v0) * 0.1, 0.01)
                func solved(_ v: Double) -> Double? {
                    var s = setup
                    s.family.types[ti].values[label] = .double(v)
                    guard let (fam, ids) = FurnitureParameters.frame(tx.model, setup: s), ids[name] == id else { return nil }
                    return FamilyEvaluator.evaluate(fam, typeName: s.currentType, units: tx.model.units).planes[name]
                }
                guard let p0 = solved(v0), let p1 = solved(v0 + step) else { continue }
                let slope = (p1 - p0) / step
                guard abs(slope) > 1e-6 else { continue }
                let v = v0 + (target - p0) / slope
                guard v > Tolerance.length else {
                    tx.warn(ModelWarning(.warning, code: "furniture.value", "“\(label)” can't be zero or less.", elements: [id]))
                    continue
                }
                setup.family.types[ti].values[label] = .double(v)
                tx.propagate(info.id) { $0.projectInfo?.furniture = setup }
                break
            }
        }
    }

    /// Moves every furniture plane to its solved position and fits the planes' extents around the piece.
    static func placePlanes(_ tx: TransactionContext) {
        guard let solution = FurnitureParameters.solve(tx.model) else { return }
        for e in solution.errors.prefix(3) {
            tx.warn(ModelWarning(.warning, code: "furniture.solve", e, elements: []))
        }
        let extents = FurniturePlanes.extents(tx.model, positions: solution.planes)
        for p in FurniturePlanes.all(tx.model) {
            guard let rp = p.referencePlane, let v = solution.planes[p.id] ?? FurniturePlanes.position(rp) else { continue }
            let placed = FurniturePlanes.placed(rp, at: v, extents: extents)
            if placed != rp { tx.propagate(p.id) { $0.referencePlane = placed } }
        }
        fitCrops(tx, extents)
    }

    /// Views whose crop follows the piece (the template's views, `FurnitureViews.autoCrop`): plans crop to the planes'
    /// plan extents, elevations and sections to their extents seen from the view.
    static func fitCrops(_ tx: TransactionContext, _ e: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>)) {
        let pad = 0.05
        for v in tx.model.views where v.params[FurnitureViews.autoCrop]?.boolValue == true {
            guard let d = v.view else { continue }
            let crop: Rect2
            if d.kind.isPlan {
                crop = Rect2(min: Vec2(e.x.lowerBound - pad, e.y.lowerBound - pad), max: Vec2(e.x.upperBound + pad, e.y.upperBound + pad))
            } else if d.kind.isVerticalCut, let o = d.planeOrigin, let r = d.rightVector {
                let us = [Vec2(e.x.lowerBound, e.y.lowerBound), Vec2(e.x.upperBound, e.y.lowerBound), Vec2(e.x.lowerBound, e.y.upperBound),
                          Vec2(e.x.upperBound, e.y.upperBound)].map { ($0 - o.xy).dot(r) }
                crop = Rect2(min: Vec2((us.min() ?? 0) - pad, e.z.lowerBound - pad), max: Vec2((us.max() ?? 0) + pad, e.z.upperBound + pad))
            } else { continue }
            if d.cropRegion != crop || !d.cropActive || !d.annotationCropActive {
                tx.propagate(v.id) { $0.view?.cropRegion = crop; $0.view?.cropActive = true; $0.view?.annotationCropActive = true }
            }
        }
    }
}

/// FM3: view settings of Furniture documents.
public enum FurnitureViews {
    /// A view parameter: the crop region follows the piece as its size changes (set on the template's views).
    public static let autoCrop = ParameterID("furniture.autoCrop")
}
