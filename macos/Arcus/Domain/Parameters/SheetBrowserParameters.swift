import Foundation
import ArcusGeometry

// BL-BROWSER: sheet parameters (Title Block, Guide Grid, Revisions on Sheet) and the Referencing Sheet / Referencing
// Detail of sections, elevations and callouts.

extension BuiltInCatalog {
    static func guideGridLabel(_ spacing: Double?) -> String {
        guard let s = spacing else { return "<None>" }
        return SheetTitleBlocks.guideGridChoices.first { $0.1.map { abs($0 - s) < 1e-9 } ?? false }?.0 ?? String(format: "%.0f mm", s * 1000)
    }

    static let sheetTitleBlock = P("sheet.titleBlock", "Title Block", .text, .graphics,
                                   tooltip: "Change it in the Type Selector; the title block sets the sheet size.",
                                   get: { e, ctx in .text(ctx.model[e.sheet?.titleBlockTypeID].map { "\($0.typeData?.familyName ?? ""): \($0.name)" } ?? "None") })
    static let sheetGuideGrid = P("sheet.guideGrid", "Guide Grid", .choice(SheetTitleBlocks.guideGridChoices.map(\.0)), .graphics,
                                  tooltip: "A grid on the sheet (not printed) for lining up viewports.",
                                  get: { e, _ in e.sheet.map { .text(guideGridLabel($0.guideGridSpacing)) } },
                                  set: { e, v, _ in
                                      let label = v.textValue ?? v.description
                                      guard let choice = SheetTitleBlocks.guideGridChoices.first(where: { $0.0 == label }) else { throw ParameterError("Choose a guide grid spacing.") }
                                      e.sheet?.guideGridSpacing = choice.1
                                  })
    static let sheetRevisions = P("sheet.revisionsOnSheet", "Revisions on Sheet", .text, .identity,
                                  tooltip: "Revisions with clouds on this sheet or its views, plus those added in Manage ▸ Revisions.",
                                  get: { e, ctx in
                                      let revs = RevisionQueries.revisions(onSheet: e, ctx.model)
                                      return .text(revs.isEmpty ? "None" : revs.map { "\(RevisionQueries.label($0, ctx.model)) \($0.revisionData?.description ?? "")" }.joined(separator: ", "))
                                  })
    static var sheetBrowserParameters: [P] { [sheetTitleBlock, sheetGuideGrid, sheetRevisions] }

    static let viewReferencingSheet = P("view.referencingSheet", "Referencing Sheet", .text, .identity,
                                        tooltip: "The sheet of the view that shows this view's marker.",
                                        get: { e, ctx in .text(ViewReferences.referencingSheetAndDetail(of: e.id, ctx.model)?.sheet ?? "") })
    static let viewReferencingDetail = P("view.referencingDetail", "Referencing Detail", .text, .identity,
                                         tooltip: "The detail number, on its sheet, of the view that shows this view's marker.",
                                         get: { e, ctx in .text(ViewReferences.referencingSheetAndDetail(of: e.id, ctx.model)?.detail ?? "") })

    /// Referencing Sheet/Detail for sections, elevations and detail views.
    static func viewReferenceParameters(_ e: Element) -> [P] {
        guard let k = e.view?.kind, k == .section || k == .elevation || k == .detail else { return [] }
        return [viewReferencingSheet, viewReferencingDetail]
    }
}

extension BuiltInCatalog {
    /// For ranges measured from other levels (Level Above, Unlimited, a named level): Top ≥ Cut ≥ Bottom ≥ View Depth
    /// in absolute elevations. Ranges measured from the associated level only are checked by the offset rules.
    static func checkViewRange(_ e: Element, _ ctx: ParameterContext) throws(ParameterError) {
        guard let r = e.view?.viewRange, !r.isAssociatedLevelOnly, let p = r.problem(viewLevel: e.levelID, in: ctx.model) else { return }
        throw ParameterError(p)
    }
}
