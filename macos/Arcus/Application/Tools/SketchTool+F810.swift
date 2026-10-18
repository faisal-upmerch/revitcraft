import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F810: sketch-mode finishes of View ▸ Cut Profile and View ▸ Callout ▸ Sketch, as RevitCraft's finish_sketch does them
// (`SketchKind::CutProfile`, `SketchKind::Callout`).

/// What an F810 sketch creates.
public enum F810SketchTarget: Sendable, Equatable {
    /// A cut profile of the wall in the sketch's plan view.
    case cutProfile(wall: ElementID)

    public var title: String {
        switch self {
        case .cutProfile: "Cut Profile"
        }
    }
}

extension SketchTool {
    /// Commits a validated F810 sketch.
    func f810Commit(_ t: F810SketchTarget, _ sketch: Sketch, view: ElementID) {
        switch t {
        case .cutProfile(let wall):
            guard case .success(let polys) = sketch.polygons(), let outer = polys.first else { message("Sketch a closed profile."); return }
            ctx.session.perform("Cut Profile") { tx in try CutProfiles.create(region: outer.points, wall: wall, view: view, tx) }
            if let err = ctx.session.lastError { message(err.message) }
        }
    }

    /// Callout ▸ Sketch: a callout of the plan cropped to the sketched closed boundary. False when the sketch is not
    /// one closed loop (the sketch stays open to fix it).
    func f810CreateSketchedCallout() -> Bool {
        let loops = splitLoops(curves)
        if let issue = SketchValidation.validate(curves, loops: loops) { presentSketchIssue(issue); return false }
        guard loops.count == 1, case .success(let polys) = Sketch(loops: loops).polygons(), let shape = polys.first else {
            message("Sketch one closed callout boundary.")
            return false
        }
        guard let parent = ctx.view?.id else { return false }
        ctx.session.perform("Create Callout") { tx in try SketchedCallouts.create(parent: parent, shape: shape.points, tx) }
        if let err = ctx.session.lastError { message(err.message); return false }
        return true
    }
}
