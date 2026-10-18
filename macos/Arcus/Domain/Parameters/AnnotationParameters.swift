import Foundation
import ArcusGeometry

// W2-ANNOT: parameters of line styles on lines, text notes and text types, dimension types, special tags and detail
// components. Wired into `BuiltInCatalog.instance(for:)` / `type(for:)` with one-line hooks.
extension BuiltInCatalog {
    private static func annotErr(_ s: String) -> ParameterError { ParameterError(s) }
    private static func annotText(_ v: ParamValue) -> String { v.textValue ?? v.description }
    private static func annotBool(_ v: ParamValue) throws(ParameterError) -> Bool {
        guard let b = v.boolValue else { throw annotErr("Type Yes or No.") }
        return b
    }
    private static func annotPaper(_ v: ParamValue, _ name: String, max: Double = 0.05) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw annotErr("“\(name)” needs a number.") }
        guard d >= 0, d <= max else { throw annotErr("“\(name)” is a size on paper and must be between 0 and \(Int(max * 1000)) mm.") }
        return d
    }

    // MARK: Lines

    static let lineStyleParam = P("line.style", "Line Style", .elementRef(.lineStyles), .graphics,
                                  tooltip: "Weight, colour and pattern of the line (Manage ▸ Line Styles).",
                                  get: { e, _ in e.modelLine.map { .ref($0.styleID) } },
                                  set: { e, v, ctx in
                                      guard let id = v.refValue else { throw annotErr("Choose a line style.") }
                                      guard ctx.model[id]?.lineStyle != nil else { throw annotErr("The chosen element is not a line style.") }
                                      e.modelLine?.styleID = id
                                  })

    // MARK: Text notes

    private enum TextFace: Sendable { case bold, italic, underline }
    private static func textOverride(_ key: String, _ name: String, _ face: TextFace, _ typeID: ParameterID) -> P {
        P(key, name, .bool, .text, tooltip: "Overrides the text type for this note.",
          get: { e, ctx in
              guard let n = e.textNote else { return nil }
              let own: Bool? = switch face { case .bold: n.bold; case .italic: n.italic; case .underline: n.underline }
              return .bool(own ?? ctx.model.typeData(of: e)?.params[typeID]?.boolValue ?? false)
          },
          set: { e, v, _ in
              let b = try annotBool(v)
              switch face {
              case .bold: e.textNote?.bold = b
              case .italic: e.textNote?.italic = b
              case .underline: e.textNote?.underline = b
              }
          })
    }
    static let textBoldParam = textOverride("text.instance.bold", "Bold", .bold, AnnotationParams.textBold)
    static let textItalicParam = textOverride("text.instance.italic", "Italic", .italic, AnnotationParams.textItalic)
    static let textUnderlineParam = textOverride("text.instance.underline", "Underline", .underline, AnnotationParams.textUnderline)
    static let textAlignmentParam = P("text.alignment", "Horizontal Align", .choice(TextAlignment.allCases.map(\.rawValue)), .text,
                                      get: { e, _ in e.textNote.map { .text($0.alignment.rawValue) } },
                                      set: { e, v, _ in
                                          guard let a = TextAlignment(rawValue: annotText(v)) else { throw annotErr("Choose Left, Center or Right.") }
                                          e.textNote?.alignment = a
                                      })
    static let textLeaderShapeParam = P("text.leaderShape", "Leader", .choice(LeaderShape.allCases.map(\.rawValue)), .graphics,
                                        get: { e, _ in e.textNote.map { .text(($0.leaderShape ?? .straight).rawValue) } },
                                        set: { e, v, _ in
                                            guard let s = LeaderShape(rawValue: annotText(v)) else { throw annotErr("Choose Straight or Arc.") }
                                            e.textNote?.leaderShape = s == .straight ? nil : s
                                        })
    static let textRotationParam = P("text.rotation", "Rotation", .angle, .graphics,
                                     get: { e, _ in e.textNote.map { .double($0.rotation) } },
                                     set: { e, v, _ in
                                         guard let a = v.doubleValue, a.isFinite else { throw annotErr("“Rotation” needs an angle.") }
                                         e.textNote?.rotation = Angle.normalizeSigned(a)
                                     })

    static func annotTextInstanceParams() -> [P] {
        [textAlignmentParam, textBoldParam, textItalicParam, textUnderlineParam, textLeaderShapeParam, textRotationParam]
    }

    // MARK: Text types

    private static func typeBoolParam(_ id: ParameterID, _ name: String) -> P {
        P(id.key, name, .bool, .text, get: { e, _ in .bool(e.typeData?.params[id]?.boolValue ?? false) },
          set: { e, v, _ in e.typeData?.params[id] = .bool(try annotBool(v)) })
    }
    private static func typeChoiceParam(_ id: ParameterID, _ name: String, _ options: [String], _ fallback: String, _ group: ParameterGroup = .graphics) -> P {
        P(id.key, name, .choice(options), group, get: { e, _ in .text(e.typeData?.params[id]?.textValue ?? fallback) },
          set: { e, v, _ in
              let s = annotText(v)
              guard options.contains(s) else { throw annotErr("Choose one of: \(options.joined(separator: ", ")).") }
              e.typeData?.params[id] = .text(s)
          })
    }
    private static func typePaperParam(_ id: ParameterID, _ name: String, _ fallback: Double, _ group: ParameterGroup = .graphics,
                                       tooltip: String = "", min: Double = 0) -> P {
        P(id.key, name, .length, group, tooltip: tooltip, get: { e, _ in .double(e.typeData?.params[id]?.doubleValue ?? fallback) },
          set: { e, v, _ in
              let d = try annotPaper(v, name)
              guard d >= min else { throw annotErr("“\(name)” must be greater than zero.") }
              e.typeData?.params[id] = .double(d)
          })
    }

    static let textSizeParam = typePaperParam(AnnotationParams.textSize, "Text Size", 0.0025, .text,
                                              tooltip: "Height of capital letters on paper, at any view scale.", min: 0.0005)
    static let textTypeBold = typeBoolParam(AnnotationParams.textBold, "Bold")
    static let textTypeItalic = typeBoolParam(AnnotationParams.textItalic, "Italic")
    static let textTypeUnderline = typeBoolParam(AnnotationParams.textUnderline, "Underline")
    static let textBackgroundParam = typeChoiceParam(AnnotationParams.textBackground, "Background", TextBackground.allCases.map(\.rawValue),
                                                     TextBackground.transparent.rawValue)
    static let textArrowheadParam = typeChoiceParam(AnnotationParams.textArrowhead, "Leader Arrowhead", LeaderArrowhead.allCases.map(\.rawValue),
                                                    LeaderArrowhead.arrow.rawValue)

    static var annotTextTypeParams: [P] {
        [textSizeParam, textTypeBold, textTypeItalic, textTypeUnderline, textBackgroundParam, textArrowheadParam, typeComments]
    }

    // MARK: Dimension types

    static let dimensionTextSizeParam = typePaperParam(AnnotationParams.dimensionTextSize, "Text Size", 0.0025, .text, min: 0.0005)
    static let dimensionTickParam = typeChoiceParam(AnnotationParams.dimensionTick, "Tick Mark", DimensionTickMark.allCases.map(\.rawValue),
                                                    DimensionTickMark.diagonal.rawValue)
    static let dimensionGapParam = typePaperParam(AnnotationParams.dimensionWitnessGap, "Witness Line Gap to Element", 0.0015,
                                                  tooltip: "Space between the measured element and the start of each witness line.")
    static let dimensionWitnessExtParam = typePaperParam(AnnotationParams.dimensionWitnessExtension, "Witness Line Extension", 0.002)
    static let dimensionLineExtParam = P(AnnotationParams.dimensionLineExtension.key, "Dimension Line Extension", .length, .graphics,
                                         get: { e, _ in .double(DimensionStyle.of(type: e.typeData).lineExtension) },
                                         set: { e, v, _ in e.typeData?.params[AnnotationParams.dimensionLineExtension] = .double(try annotPaper(v, "Dimension Line Extension")) })
    static let dimensionTextOffsetParam = typePaperParam(AnnotationParams.dimensionTextOffset, "Text Offset", 0.0012, .text)

    static var annotDimensionTypeParams: [P] {
        [dimensionTickParam, dimensionLineExtParam, dimensionGapParam, dimensionWitnessExtParam, dimensionTextSizeParam, dimensionTextOffsetParam, typeComments]
    }

    // MARK: Dimensions, tags and detail components

    static let dimensionEqualityDisplayParam = P("dimension.equalityDisplay", "Equality Display", .choice(EqualityDisplay.allCases.map(\.rawValue)), .graphics,
                                                 tooltip: "How an equality-constrained string labels its segments.",
                                                 get: { e, _ in e.dimension.map { .text(($0.equalityDisplay ?? .text).rawValue) } },
                                                 set: { e, v, _ in
                                                     guard let d = EqualityDisplay(rawValue: annotText(v)) else { throw annotErr("Unknown equality display.") }
                                                     e.dimension?.equalityDisplay = d == .text ? nil : d
                                                 })

    static let keynoteDisplayParam = P("tag.keynoteDisplay", "Keynote Display", .choice(KeynoteDisplay.allCases.map(\.rawValue)), .text,
                                       get: { e, _ in e.tag.map { .text(($0.keynoteDisplay ?? .key).rawValue) } },
                                       set: { e, v, _ in
                                           guard let d = KeynoteDisplay(rawValue: annotText(v)) else { throw annotErr("Unknown keynote display.") }
                                           e.tag?.keynoteDisplay = d
                                       })
    static let userKeynoteParam = P("tag.keynote", "Key Value", .text, .text,
                                    get: { e, _ in e.tag.map { .text($0.keynote ?? "") } },
                                    set: { e, v, _ in let s = annotText(v).trimmingCharacters(in: .whitespaces); e.tag?.keynote = s.isEmpty ? nil : s })
    static let tagMaterialParam = P("tag.material", "Material", .elementRef(.materials), .materials,
                                    get: { e, _ in e.tag.map { .ref($0.materialID) } },
                                    set: { e, v, ctx in
                                        if let id = v.refValue, ctx.model[id]?.material == nil { throw annotErr("Choose a material.") }
                                        e.tag?.materialID = v.refValue
                                    })
    static let tagAngleParam = P("tag.angle", "Direction", .angle, .graphics,
                                 get: { e, _ in e.tag.map { .double($0.angle ?? 0) } },
                                 set: { e, v, _ in
                                     guard let a = v.doubleValue, a.isFinite else { throw annotErr("“Direction” needs an angle.") }
                                     e.tag?.angle = Angle.normalizeSigned(a)
                                 })

    static func annotTagParams(_ e: Element) -> [P] {
        guard let k = e.tag?.kind else { return [] }
        switch k {
        case .keynoteUser: return [keynoteDisplayParam, userKeynoteParam]
        case .keynoteElement: return [keynoteDisplayParam]
        case .keynoteMaterial: return [keynoteDisplayParam, tagMaterialParam]
        case .material: return [tagMaterialParam]
        case .spanDirection: return [tagAngleParam]
        default: return []
        }
    }

    static let repeatSpacingParam = P("detail.repeatSpacing", "Spacing", .length, .dimensions,
                                      tooltip: "Distance between repeated components; 0 uses the component's own length.",
                                      get: { e, _ in e.detailComponent?.repeatEnd == nil ? nil : .double(e.detailComponent?.repeatSpacing ?? 0) },
                                      set: { e, v, _ in
                                          guard let d = v.doubleValue, d.isFinite, d >= 0 else { throw annotErr("“Spacing” must be zero or more.") }
                                          e.detailComponent?.repeatSpacing = d > Tolerance.length ? d : nil
                                      })
    static let legendLengthParam = P("detail.legendLength", "Host Length", .length, .dimensions,
                                     get: { e, _ in e.detailComponent?.legendTypeID == nil ? nil : .double(e.detailComponent?.legendLength ?? 1) },
                                     set: { e, v, _ in
                                         guard let d = v.doubleValue, d.isFinite, d > Tolerance.length else { throw annotErr("“Host Length” must be greater than zero.") }
                                         e.detailComponent?.legendLength = d
                                     })

    static func annotDetailParams(_ e: Element) -> [P] {
        guard let d = e.detailComponent else { return [] }
        if d.repeatEnd != nil { return [repeatSpacingParam] }
        if d.legendTypeID != nil { return [legendLengthParam] }
        return []
    }

    static func annotDimensionParams(_ e: Element) -> [P] {
        guard let k = e.dimension?.kind, k == .linear || k == .aligned else { return [] }
        return [dimensionEqualityDisplayParam]
    }

    /// Probe elements so `byID` and the display order know the parameters that only some elements show.
    static var annotProbeElements: [Element] {
        let data: [ElementData] = annotProbes + [.textNote(TextNoteData(position: .zero, text: "")),
                                                 .dimension(DimensionData(kind: .aligned, references: [], linePoint: .zero))]
        return data.map { Element(id: ElementID(0), category: .genericModels, data: $0) }
            + [Element(id: ElementID(0), category: .detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(.zero, .unitX)))))]
    }

    static var annotProbes: [ElementData] {
        var keynote = TagData(taggedID: ElementID(0), head: .zero); keynote.kind = .keynoteMaterial
        var user = TagData(taggedID: ElementID(0), head: .zero); user.kind = .keynoteUser
        var span = TagData(taggedID: ElementID(0), head: .zero); span.kind = .spanDirection
        var rep = DetailComponentData(location: .zero); rep.repeatEnd = .unitX
        var legend = DetailComponentData(location: .zero); legend.legendTypeID = ElementID(0)
        return [.tag(keynote), .tag(user), .tag(span), .detailComponent(rep), .detailComponent(legend)]
    }
}
