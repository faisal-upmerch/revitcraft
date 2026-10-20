import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

// AITOOLS: Family Editor tools, run on a FamilyEditingHost (the Family Editor window in the app, file mode's family):
// parameters, types and formulas, reference planes, forms, dimensions with labels, nested families, visibility, flex
// and Load into Project. Each call is one step on the family's own undo stack and is flexed afterwards.

extension ArcusToolCatalog {
    static let familyNote = "Lengths: numbers in feet (Imperial) or mm (Metric), or text like 2'-6\" or 750 mm. A bound may also be a reference plane name (the form locks to it) or a formula like 'Width / 2'."

    static let familyTools: [ToolSpec] = [
        ToolSpec("family_info", "Family Info", "Read the family: template, types with values, parameters (type/instance, formulas), reference planes with positions, forms (kind, bounds, visibility), dimensions and labels, nested families.",
                 risk: .read, group: .family, modes: .family, properties: ["type": S.str("Evaluate this type (default the current type)")]),
        ToolSpec("add_family_parameter", "Add Family Parameter",
                 "Add (or change) family parameters, like Family Types ▸ New Parameter: name, type (length, area, angle, number, integer, text, yes_no, material), instance or type, group, formula, and the value for the current type (or every type). " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["parameters": S.array(S.object(["name": S.str(), "type": S.oneOf(["length", "area", "volume", "angle", "number", "integer", "text", "yes_no", "material"], "Default length"),
                                                              "instance": S.bool("Default false (type parameter)"), "group": S.str("Dimensions, Constraints, Materials and Finishes, Graphics, Identity Data…"),
                                                              "formula": S.str("e.g. 'Width / 2' or 'if(Height > 3\\', 2, 1)'"), "value": S.anyValue, "all_types": S.bool("Set value in every type")],
                                                             required: ["name"]))],
                 required: ["parameters"]),
        ToolSpec("set_family_type", "Set Family Type",
                 "Family Types: make a new type (copying the current one), rename or delete one, switch the current type, and set parameter values in a type, e.g. {new:'36\" x 80\"', values:{Width:'36\"', Height:'80\"'}}. " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["type": S.str("Type to change (default current)"), "new": S.str("Create this type (copies `type`)"), "rename": S.str("New name for `type`"),
                              "delete": S.str("Delete this type"), "make_current": S.bool("Default true for new"), "values": S.object([:], "{parameter: value}")]),
        ToolSpec("add_reference_plane", "Add Reference Plane",
                 "Add reference planes on an axis: x (left/right planes, vertical in plan), y (front/back), z (levels of height). offset is from the origin, or a formula. Optionally dimension it to another plane and label the dimension with a parameter (created if missing). " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["planes": S.array(S.object(["name": S.str(), "axis": S.oneOf(["x", "y", "z"]), "offset": S.len(), "strength": S.oneOf(["weak", "strong", "not_a_reference", "left", "right", "front", "back", "bottom", "top"]),
                                                          "dimension_to": S.str("Another plane to dimension to"), "label": S.str("Parameter for that dimension")], required: ["name", "axis", "offset"]))],
                 required: ["planes"]),
        ToolSpec("add_form", "Add Form",
                 "Create a solid or void form: extrusion (rect bounds, or polygon points, or circle), blend (bottom and top polygons), revolve (profile + axis point, degrees) or sweep (path + profile). Bounds can be plane names so the form flexes. Polygon points [[x,y],…] are in the sketch plane. " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["kind": S.oneOf(["extrusion", "blend", "revolve", "sweep"], "Default extrusion"), "name": S.str(), "void": S.bool(),
                              "x_min": S.ref(), "x_max": S.ref(), "y_min": S.ref(), "y_max": S.ref(), "z_min": S.ref("Default 0 / Ref. Level"), "z_max": S.ref("Default 1' / 300 mm"),
                              "points": S.points("Polygon (extrusion) or revolve profile"), "top_points": S.points("Blend top"), "center": S.point(), "radius": S.len(),
                              "axis": S.point("Revolve axis point"), "start_degrees": S.num(), "end_degrees": S.num(), "path": S.points("Sweep path"), "profile": S.points("Sweep profile"),
                              "work_plane": S.oneOf(["xy", "xz", "yz"], "Sketch plane (default xy = plan)"), "material_parameter": S.str(), "subcategory": S.str()]),
        ToolSpec("edit_form", "Edit Form",
                 "Change forms by name: bounds (lock to planes), material parameter, visibility (detail levels, plan/3D/front-back/left-right, a Yes/No visibility parameter), solid/void, rename. " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["forms": S.array(S.str(), "Form names (default all)"), "rename": S.str(), "void": S.bool(), "x_min": S.ref(), "x_max": S.ref(), "y_min": S.ref(), "y_max": S.ref(),
                              "z_min": S.ref(), "z_max": S.ref(), "material_parameter": S.str(), "visibility_parameter": S.str("Yes/No parameter (created if missing); '' clears"),
                              "visible_at": S.array(S.oneOf(["coarse", "medium", "fine"])), "visible_in_plan": S.bool(), "visible_in_3d": S.bool(),
                              "visible_front_back": S.bool(), "visible_left_right": S.bool()]),
        ToolSpec("add_family_dimension", "Add Family Dimension",
                 "Dimension two parallel reference planes and label it with a parameter (created as a length parameter with today's distance when missing), or EQ three planes (equality), or lock it. Labelled dimensions drive the planes when the type's value changes.",
                 risk: .edit, group: .family, modes: .family,
                 properties: ["plane_a": S.str(), "plane_b": S.str(), "plane_c": S.str("Third plane for EQ"), "label": S.str("Parameter name"), "equality": S.bool(), "lock": S.bool()],
                 required: ["plane_a", "plane_b"]),
        ToolSpec("add_nested_family", "Add Nested Family",
                 "Nest a family from the built-in component library (search words) at a point, with its type, rotation and optional parameter bindings {nested parameter: host parameter or formula}. " + familyNote,
                 risk: .edit, group: .family, modes: .family,
                 properties: ["family": S.str("Library family name or search words, e.g. 'Knob'"), "type": S.str(), "point": S.array(S.ref(), "[x, y] or [x, y, z]; each a length, plane name or formula"),
                              "rotation": S.num("Degrees"), "bindings": S.object([:]), "visibility_parameter": S.str()],
                 required: ["family"]),
        ToolSpec("delete_family_item", "Delete Family Item", "Delete family items by name: forms, reference planes (with their dimensions; locked bounds keep their position), parameters, nested instances or labels.",
                 risk: .destructive, group: .family, modes: .family,
                 properties: ["forms": S.array(S.str()), "planes": S.array(S.str()), "parameters": S.array(S.str()), "nested": S.array(S.str(), "Nested family names")]),
        ToolSpec("flex_family", "Flex Family", "Flex test: evaluate every type (and lengths at 50% / 150%) and report problems: formula errors, planes that cross, forms that collapse. Optionally set a value temporarily to try it.",
                 risk: .read, group: .family, modes: .family, properties: ["values": S.object([:], "Try these values on the current type (not saved)")]),
        ToolSpec("load_family_into_project", "Load into Project", "Load (or reload, keeping project type values) the family into its project, after a flex test. Fails with the flex problems if any.",
                 risk: .projectWide, group: .family, modes: .family, properties: ["force": S.bool("Load even with flex problems")]),
    ]
}

extension ArcusToolbox {
    static let familyHandlers: [String: ToolHandler] = [
        "family_info": { b, c in try b.familyInfo(c) },
        "add_family_parameter": { b, c in try b.addFamilyParameters(c) },
        "set_family_type": { b, c in try b.setFamilyType(c) },
        "add_reference_plane": { b, c in try b.addReferencePlanes(c) },
        "add_form": { b, c in try b.addForm(c) },
        "edit_form": { b, c in try b.editForms(c) },
        "add_family_dimension": { b, c in try b.addFamilyDimension(c) },
        "add_nested_family": { b, c in try b.addNestedFamily(c) },
        "delete_family_item": { b, c in try b.deleteFamilyItems(c) },
        "flex_family": { b, c in try b.flexFamily(c) },
        "load_family_into_project": { b, c in try b.loadFamilyIntoProject(c) },
    ]

    func requireFamily() throws(ToolError) -> any FamilyEditingHost {
        guard let f = familyHost else { throw ToolError("No family is open. Open the Family Editor (Edit Family, or Home ▸ Family), or create_family in file mode.") }
        return f
    }

    // MARK: Values

    /// Meters per family unit and the length parser.
    nonisolated static func familyLength(_ v: JSONValue, _ what: String, _ units: UnitsSettings) throws(ToolError) -> Double {
        let scale = units.system == .imperial ? 0.3048 : 0.001
        if let d = v.doubleValue { return d * scale }
        guard let s = v.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { throw ToolError("“\(what)” must be a length.") }
        if let d = Double(s) { return d * scale }
        do { return try QuantityParser.parse(s, kind: .length, units: units) } catch {
            throw ToolError("“\(what)”: can't read “\(s)” as a length. Use a number in \(units.system == .imperial ? "feet" : "mm") or text like 2'-6\".")
        }
    }

    /// A form bound: a plane name (locks), a length, or a formula.
    nonisolated static func familyBound(_ v: JSONValue, _ what: String, _ f: FamilyDefinition, _ units: UnitsSettings) throws(ToolError) -> FamilyBound {
        if let s = v.stringValue {
            if let p = f.referencePlanes.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return .plane(p.name) }
            if let d = try? familyLength(v, what, units) { return .expr(FamilyEditing.numberText(d)) }
            let known = f.parameters.map(\.name) + f.referencePlanes.map(\.name)
            guard known.contains(where: { s.contains($0) }) else {
                throw ToolError("“\(what)”: “\(s)” is not a plane, a length or a formula of parameters. Planes: \(f.referencePlanes.map(\.name).joined(separator: ", ")); parameters: \(f.parameters.prefix(20).map(\.name).joined(separator: ", ")).")
            }
            return .expr(s)
        }
        return .expr(FamilyEditing.numberText(try familyLength(v, what, units)))
    }

    nonisolated static func familyPoints(_ v: JSONValue, _ what: String, _ f: FamilyDefinition, _ units: UnitsSettings, min: Int = 3) throws(ToolError) -> [FamilyPoint] {
        guard let a = v.arrayValue, a.count >= min else { throw ToolError("“\(what)” must be at least \(min) points [[x, y], …].") }
        var out: [FamilyPoint] = []
        for (k, p) in a.enumerated() {
            guard let xy = p.arrayValue, xy.count >= 2 else { throw ToolError("\(what)[\(k)] must be [x, y].") }
            out.append(FamilyPoint(try familyBound(xy[0], "\(what)[\(k)].x", f, units), try familyBound(xy[1], "\(what)[\(k)].y", f, units)))
        }
        return out
    }

    nonisolated static func familyParamType(_ s: String?) throws(ToolError) -> ParamType {
        switch s?.lowercased() ?? "length" {
        case "length": return .length
        case "area": return .area
        case "volume": return .volume
        case "angle": return .angle
        case "number": return .number
        case "integer": return .integer
        case "text": return .text
        case "yes_no", "yesno", "bool", "boolean": return .bool
        case "material": return .elementRef(.materials)
        default: throw ToolError("type “\(s ?? "")”: use length, area, volume, angle, number, integer, text, yes_no or material.")
        }
    }

    /// A type value from JSON for a parameter type.
    nonisolated static func familyValue(_ v: JSONValue, _ type: ParamType, _ name: String, _ units: UnitsSettings) throws(ToolError) -> ParamValue {
        switch type {
        case .length: return .double(try familyLength(v, name, units))
        case .bool: guard let b = v.boolValue else { throw ToolError("\(name) is Yes/No: give true or false.") }; return .bool(b)
        case .integer: guard let i = v.intValue else { throw ToolError("\(name) is an integer.") }; return .int(i)
        case .text, .multilineText, .url: return .text(v.stringValue ?? v.jsonText)
        case .elementRef: return .text(v.stringValue ?? "")
        case .angle:
            if let d = v.doubleValue { return .double(d * .pi / 180) }
            fallthrough
        default:
            if let d = v.doubleValue { return .double(d) }
            if let s = v.stringValue, let k = type.unitKind, let d = try? QuantityParser.parse(s, kind: k, units: units) { return .double(d) }
            throw ToolError("\(name): can't read \(v.jsonText) as \(type.displayName.lowercased()).")
        }
    }

    // MARK: Results

    /// A family edit's result with the flex check as its verification.
    func familyResult(_ fam: any FamilyEditingHost, _ fields: [String: JSONValue]) -> ToolOutput {
        var o = fields
        let problems = fam.flexTest()
        o["verification"] = ["ok": .bool(problems.isEmpty), "problems": .array(problems.prefix(10).map { .string($0) })]
        let ev = FamilyEvaluator.evaluate(fam.family, typeName: fam.currentType, units: fam.units, quality: .coarse)
        o["current_type"] = .string(fam.currentType)
        o["planes"] = .object(ev.planes.reduce(into: [:]) { $0[$1.key] = .string(QuantityFormatter.format($1.value, kind: .length, units: fam.units, locale: Locale(identifier: "en_US_POSIX"))) })
        return ToolOutput(.object(o))
    }

    func familyInfo(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let f = fam.family
        let typeName = c.args.string("type") ?? fam.currentType
        guard f.type(named: typeName) != nil else { throw ToolError("No type “\(typeName)”. Types: \(f.types.map(\.name).joined(separator: ", ")).") }
        let ev = FamilyEvaluator.evaluate(f, typeName: typeName, units: fam.units, quality: .coarse)
        let fmt = { (d: Double) in QuantityFormatter.format(d, kind: .length, units: fam.units, locale: Locale(identifier: "en_US_POSIX")) }
        func bound(_ b: FamilyBound) -> JSONValue { switch b { case .plane(let p): .string("plane " + p); case .expr(let e): .string(e) } }
        let o: [String: JSONValue] = [
            "name": .string(f.name), "template": .string(f.template.rawValue), "current_type": .string(fam.currentType),
            "types": .array(f.types.map { t in ["name": .string(t.name), "values": .object(t.values.reduce(into: [:]) { o, kv in
                let p = f.parameter(named: kv.key)
                o[kv.key] = .string(p?.type == .length ? (kv.value.doubleValue.map(fmt) ?? kv.value.description) : kv.value.description)
            })] }),
            "parameters": .array(f.parameters.map { p in
                var o: [String: JSONValue] = ["name": .string(p.name), "type": .string(p.type.displayName), "instance": .bool(p.isInstance), "group": .string(p.group.rawValue)]
                if let fm = p.formula { o["formula"] = .string(fm) }
                if p.isBuiltIn { o["built_in"] = true }
                if let v = ev.values[p.name] { o["value"] = .string("\(v)") }
                return .object(o)
            }),
            "planes": .array(f.referencePlanes.map { p in ["name": .string(p.name), "axis": .string(p.axis.rawValue.lowercased()), "offset": .string(p.offset),
                                                         "position": .string(ev.planes[p.name].map(fmt) ?? "?"), "strength": .string(p.strength.rawValue), "origin": .bool(p.definesOrigin)] }),
            "forms": .array(f.solids.map { s in
                var o: [String: JSONValue] = ["name": .string(s.name), "kind": .string(s.profile.formName), "void": .bool(s.isVoid), "z_min": bound(s.zMin), "z_max": bound(s.zMax),
                                              "visible_at": .array(s.visibleAt.map { .string($0.rawValue) }.sorted { $0.stringValue! < $1.stringValue! }),
                                              "plan": .bool(s.visibleInPlan), "3d": .bool(s.visibleIn3D)]
                if case .rectangle(let x0, let x1, let y0, let y1) = s.profile { o["x"] = [bound(x0), bound(x1)]; o["y"] = [bound(y0), bound(y1)] }
                if let v = s.visibilityParameter { o["visibility_parameter"] = .string(v) }
                if let mp = s.materialParameter { o["material_parameter"] = .string(mp) }
                return .object(o)
            }),
            "dimensions": .array(f.dimensions.map { d in
                var o: [String: JSONValue] = ["planes": .array([d.planeA, d.planeB] .map { .string($0) } + (d.planeC.map { [.string($0)] } ?? []))]
                if let l = d.labelParameter { o["label"] = .string(l) }
                if d.isEquality { o["equality"] = true }
                if d.isLocked { o["locked"] = true }
                return .object(o)
            }),
            "nested": .array(f.nestedInstances.map { ["family": .string($0.familyName), "type": .string($0.typeName ?? "")] }),
            "labels": .int(f.labels.count), "unit": .string(fam.units.system == .imperial ? "ft" : "mm"),
        ]
        return ToolOutput(.object(o))
    }

    func addFamilyParameters(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let specs = try c.args.requireArray("parameters")
        var added: [String] = [], changed: [String] = []
        try fam.apply(name: "Family Parameters") { f in
            for (k, s) in specs.enumerated() {
                let what = "parameters[\(k)]"
                guard let name = s["name"]?.stringValue?.trimmingCharacters(in: .whitespaces), FamilyEditing.isValidName(name) else {
                    throw ToolError("\(what): name must start with a letter and use letters, numbers, spaces or _.")
                }
                let type = try Self.familyParamType(s["type"]?.stringValue)
                if f.referencePlanes.contains(where: { $0.name == name }) { throw ToolError("\(what): “\(name)” is a reference plane name; pick another parameter name.") }
                if let i = f.parameters.firstIndex(where: { $0.name == name }) {
                    if f.parameters[i].isBuiltIn, s["formula"] != nil { throw ToolError("“\(name)” is built in; it can't take a formula.") }
                    if let fm = s["formula"] { f.parameters[i].formula = fm.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
                    if let inst = s["instance"]?.boolValue { f.parameters[i].isInstance = inst }
                    changed.append(name)
                } else {
                    var group = ParameterGroup.dimensions
                    if let g = s["group"]?.stringValue {
                        guard let pg = ParameterGroup.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(g.lowercased()) }) else {
                            throw ToolError("\(what).group: use one of \(ParameterGroup.allCases.map(\.rawValue).joined(separator: ", ")).")
                        }
                        group = pg
                    } else if type == .bool { group = .graphics } else if type == .elementRef(.materials) { group = .materials }
                    f.parameters.append(FamilyParameter(name: name, type: type, isInstance: s["instance"]?.boolValue ?? false, group: group,
                                                        formula: s["formula"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }))
                    added.append(name)
                }
                if let v = s["value"] {
                    let value = try Self.familyValue(v, type, name, fam.units)
                    for t in f.types.indices where s["all_types"]?.boolValue == true || f.types[t].name == fam.currentType { f.types[t].values[name] = value }
                }
            }
        }
        return familyResult(fam, ["added": .array(added.map { .string($0) }), "changed": .array(changed.map { .string($0) })])
    }

    func setFamilyType(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let f0 = fam.family
        var target = c.args.string("type") ?? fam.currentType
        guard f0.type(named: target) != nil else { throw ToolError("No type “\(target)”. Types: \(f0.types.map(\.name).joined(separator: ", ")).") }
        var notes: [String] = []
        let values = c.args["values"]?.objectValue ?? [:]
        let newName = c.args.string("new"), rename = c.args.string("rename"), del = c.args.string("delete")
        guard newName != nil || rename != nil || del != nil || !values.isEmpty || c.args["make_current"] != nil else {
            throw ToolError("Give new, rename, delete, values or make_current.")
        }
        try fam.apply(name: "Family Types") { f in
            if let n = newName {
                guard FamilyEditing.addType(&f, named: n, copying: target) else { throw ToolError("A type named “\(n)” exists (or the name is blank).") }
                target = n
                notes.append("created \(n)")
            }
            if let r = rename {
                guard FamilyEditing.renameType(&f, target, to: r) else { throw ToolError("Can't rename “\(target)” to “\(r)”: the name is blank or taken.") }
                target = r
            }
            if let d = del {
                guard FamilyEditing.deleteType(&f, d) else { throw ToolError("Can't delete “\(d)”: it doesn't exist or it's the last type.") }
                notes.append("deleted \(d)")
                if target == d { target = f.types.first?.name ?? "" }
            }
            guard let ti = f.types.firstIndex(where: { $0.name == target }) else { return }
            for (name, v) in values.sorted(by: { $0.key < $1.key }) {
                guard let p = f.parameter(named: name) else {
                    throw ToolError("No parameter “\(name)”. Parameters: \(f.parameters.map(\.name).joined(separator: ", ")). add_family_parameter makes one.")
                }
                if p.formula != nil { throw ToolError("“\(name)” has a formula (\(p.formula!)); change the formula with add_family_parameter instead.") }
                f.types[ti].values[name] = try Self.familyValue(v, p.type, name, fam.units)
            }
        }
        if c.args.bool("make_current", default: newName != nil || rename != nil) || fam.family.type(named: fam.currentType) == nil, fam.family.type(named: target) != nil {
            fam.currentType = target
        }
        return familyResult(fam, ["type": .string(target), "types": .array(fam.family.types.map { .string($0.name) }), "notes": .array(notes.map { .string($0) })])
    }

    nonisolated static func strength(_ s: String?) -> ReferenceStrength {
        switch s?.lowercased().replacingOccurrences(of: "_", with: " ") {
        case "strong": .strong
        case "not a reference": .notAReference
        case let k?: ReferenceStrength.allCases.first { $0.rawValue.lowercased() == k } ?? .weak
        default: .weak
        }
    }

    func addReferencePlanes(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let specs = try c.args.requireArray("planes")
        var names: [String] = []
        try fam.apply(name: "Reference Plane") { f in
            for (k, s) in specs.enumerated() {
                let what = "planes[\(k)]"
                guard let name = s["name"]?.stringValue, FamilyEditing.isValidName(name) else { throw ToolError("\(what): a valid name is required.") }
                guard !f.referencePlanes.contains(where: { $0.name == name }) else { throw ToolError("\(what): a plane named “\(name)” exists.") }
                guard let ax = s["axis"]?.stringValue?.lowercased(), let axis = FamilyAxis(rawValue: ax.uppercased()) else { throw ToolError("\(what).axis must be x, y or z.") }
                guard let ov = s["offset"] else { throw ToolError("\(what) needs offset.") }
                let offset: String
                switch try Self.familyBound(ov, what + ".offset", f, fam.units) {
                case .expr(let e): offset = e
                case .plane(let p): throw ToolError("\(what).offset can't be the plane “\(p)”; give a length or a formula.")
                }
                f.referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: offset, strength: Self.strength(s["strength"]?.stringValue)))
                names.append(name)
                if let other = s["dimension_to"]?.stringValue {
                    guard let o = f.referencePlanes.first(where: { $0.name.caseInsensitiveCompare(other) == .orderedSame }), o.axis == axis else {
                        throw ToolError("\(what).dimension_to: no \(ax)-axis plane “\(other)”.")
                    }
                    var d = FamilyDimension(planeA: o.name, planeB: name)
                    if let label = s["label"]?.stringValue {
                        try Self.ensureLengthParameter(label, between: o.name, and: name, in: &f, fam)
                        d.labelParameter = label
                    }
                    f.dimensions.append(d)
                }
            }
        }
        return familyResult(fam, ["planes_added": .array(names.map { .string($0) })])
    }

    /// Makes `label` a length parameter whose value in every type is today's distance between two planes.
    static func ensureLengthParameter(_ label: String, between a: String, and b: String, in f: inout FamilyDefinition, _ fam: any FamilyEditingHost) throws(ToolError) {
        if let p = f.parameter(named: label) {
            guard p.type == .length else { throw ToolError("“\(label)” is a \(p.type.displayName.lowercased()) parameter; a dimension label must be a length.") }
            return
        }
        guard FamilyEditing.isValidName(label) else { throw ToolError("“\(label)” isn't a valid parameter name.") }
        f.parameters.append(FamilyParameter(name: label, type: .length))
        for t in f.types.indices {
            let ev = FamilyEvaluator.evaluate(f, typeName: f.types[t].name, units: fam.units, quality: .coarse)
            if let pa = ev.planes[a], let pb = ev.planes[b] { f.types[t].values[label] = .double(abs(pb - pa)) }
        }
    }

    func addForm(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let a = c.args
        let kind = a.string("kind")?.lowercased() ?? "extrusion"
        var made = ""
        try fam.apply(name: "Create Form") { f in
            let u = fam.units
            let step = u.system == .imperial ? 0.3048 : 0.3
            func b(_ k: String, _ d: Double) throws -> FamilyBound { try a[k].map { try Self.familyBound($0, k, f, u) } ?? .expr(FamilyEditing.numberText(d)) }
            let profile: FamilySolid.Profile
            switch kind {
            case "extrusion", "void", "extrude":
                if let pv = a["points"] { profile = .polygon(try Self.familyPoints(pv, "points", f, u)) } else if let cv = a["center"], let r = a["radius"] {
                    let pts = try Self.familyPoints([cv, cv, cv], "center", f, u, min: 1)
                    profile = .circle(center: pts[0], radius: FamilyEditing.numberText(try Self.familyLength(r, "radius", u)))
                } else {
                    let planes = f.referencePlanes
                    let def = { (axis: FamilyAxis, hi: Bool) -> FamilyBound in
                        // Default: the outermost planes on the axis (the template's Left/Right, Front/Back), else ±6".
                        let named = planes.filter { $0.axis == axis }.map(\.name)
                        let pref = axis == .x ? (hi ? "Right" : "Left") : (hi ? "Back" : "Front")
                        if let n = named.first(where: { $0 == pref }) { return .plane(n) }
                        return .expr(FamilyEditing.numberText(hi ? step / 2 : -step / 2))
                    }
                    profile = .rectangle(xMin: try a["x_min"].map { try Self.familyBound($0, "x_min", f, u) } ?? def(.x, false),
                                         xMax: try a["x_max"].map { try Self.familyBound($0, "x_max", f, u) } ?? def(.x, true),
                                         yMin: try a["y_min"].map { try Self.familyBound($0, "y_min", f, u) } ?? def(.y, false),
                                         yMax: try a["y_max"].map { try Self.familyBound($0, "y_max", f, u) } ?? def(.y, true))
                }
            case "blend":
                guard let bp = a["points"], let tp = a["top_points"] else { throw ToolError("A blend needs points (bottom) and top_points.") }
                profile = .blend(FamilyBlend(bottom: try Self.familyPoints(bp, "points", f, u), top: try Self.familyPoints(tp, "top_points", f, u)))
            case "revolve":
                guard let pv = a["points"] else { throw ToolError("A revolve needs points (its profile) and axis.") }
                let axis = try a["axis"].map { try Self.familyPoints([$0], "axis", f, u, min: 1)[0] } ?? FamilyPoint("0", "0")
                profile = .revolve(FamilyRevolve(profile: try Self.familyPoints(pv, "points", f, u), axis: axis,
                                                 startDegrees: FamilyEditing.numberText(a.double("start_degrees") ?? 0), endDegrees: FamilyEditing.numberText(a.double("end_degrees") ?? 360)))
            case "sweep":
                guard let path = a["path"], let pr = a["profile"] else { throw ToolError("A sweep needs path (2+ points) and profile (3+ points).") }
                profile = .sweep(FamilySweep(path: try Self.familyPoints(path, "path", f, u, min: 2), profile: try Self.familyPoints(pr, "profile", f, u)))
            default: throw ToolError("kind must be extrusion, blend, revolve or sweep.")
            }
            let isVoid = a.bool("void", default: kind == "void")
            let n = a.string("name") ?? FamilyEditing.numberedName(isVoid ? "Void" : profile.formName, count: f.solids.count) { name in f.solids.contains { $0.name == name } }
            guard !f.solids.contains(where: { $0.name == n }) else { throw ToolError("A form named “\(n)” exists.") }
            var s = FamilySolid(name: n, profile: profile, zMin: try b("z_min", 0), zMax: try b("z_max", step), materialParameter: a.string("material_parameter"), isVoid: isVoid)
            if let wp = a.string("work_plane"), let p = FamilySketchPlane(rawValue: wp.uppercased()) { s.workPlane = p }
            if let sc = a.string("subcategory"), let k = FamilySubcategory.allCases.first(where: { $0.rawValue.lowercased() == sc.lowercased() }) { s.subcategory = k }
            f.solids.append(s)
            made = n
        }
        let ev = FamilyEvaluator.evaluate(fam.family, typeName: fam.currentType, units: fam.units, quality: .coarse)
        let solid = ev.solids.first { $0.name == made }
        var o: [String: JSONValue] = ["form": .string(made), "kind": .string(kind)]
        if let s = solid { o["height"] = .string(QuantityFormatter.format(s.zMax - s.zMin, kind: .length, units: fam.units, locale: Locale(identifier: "en_US_POSIX"))) }
        var out = familyResult(fam, o)
        if solid == nil || (solid.map { $0.zMax - $0.zMin <= 0 } ?? true), var v = out.json["verification"]?.objectValue {
            v["ok"] = false
            v["problems"] = .array((v["problems"]?.arrayValue ?? []) + [.string("Form “\(made)” has no volume for type “\(fam.currentType)”: check its bounds.")])
            var j = out.json.objectValue ?? [:]
            j["verification"] = .object(v)
            out.json = .object(j)
        }
        return out
    }

    func editForms(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let a = c.args
        let wanted = a.array("forms")?.compactMap(\.stringValue)
        var touched: [String] = []
        try fam.apply(name: "Edit Form") { f in
            let u = fam.units
            if let w = wanted {
                for n in w where !f.solids.contains(where: { $0.name == n }) { throw ToolError("No form “\(n)”. Forms: \(f.solids.map(\.name).joined(separator: ", ")).") }
            }
            if let vp = a.string("visibility_parameter"), !vp.isEmpty, f.parameter(named: vp) == nil {
                f.parameters.append(FamilyParameter(name: vp, type: .bool, group: .graphics))
                for t in f.types.indices { f.types[t].values[vp] = .bool(true) }
            }
            let snapshot = f
            for i in f.solids.indices where wanted?.contains(f.solids[i].name) ?? true {
                var s = f.solids[i]
                if let r = a.string("rename") { s.name = r }
                if let v = a["void"]?.boolValue { s.isVoid = v }
                if case .rectangle(var x0, var x1, var y0, var y1) = s.profile {
                    if let v = a["x_min"] { x0 = try Self.familyBound(v, "x_min", snapshot, u) }
                    if let v = a["x_max"] { x1 = try Self.familyBound(v, "x_max", snapshot, u) }
                    if let v = a["y_min"] { y0 = try Self.familyBound(v, "y_min", snapshot, u) }
                    if let v = a["y_max"] { y1 = try Self.familyBound(v, "y_max", snapshot, u) }
                    s.profile = .rectangle(xMin: x0, xMax: x1, yMin: y0, yMax: y1)
                } else if ["x_min", "x_max", "y_min", "y_max"].contains(where: { a[$0] != nil }) {
                    throw ToolError("“\(s.name)” is a \(s.profile.formName.lowercased()) with a sketched profile; only rectangular extrusions take x/y bounds.")
                }
                if let v = a["z_min"] { s.zMin = try Self.familyBound(v, "z_min", snapshot, u) }
                if let v = a["z_max"] { s.zMax = try Self.familyBound(v, "z_max", snapshot, u) }
                if let mp = a.string("material_parameter") { s.materialParameter = mp.isEmpty ? nil : mp }
                if let vp = a.string("visibility_parameter") { s.visibilityParameter = vp.isEmpty ? nil : vp }
                if let levels = a.array("visible_at") {
                    s.visibleAt = Set(try levels.map { v throws(ToolError) -> DetailLevel in
                        guard let d = DetailLevel.allCases.first(where: { $0.rawValue.lowercased() == v.stringValue?.lowercased() }) else { throw ToolError("visible_at: use coarse, medium, fine.") }
                        return d
                    })
                }
                if let v = a["visible_in_plan"]?.boolValue { s.visibleInPlan = v }
                if let v = a["visible_in_3d"]?.boolValue { s.visibleIn3D = v }
                if let v = a["visible_front_back"]?.boolValue { s.visibleInFrontBack = v }
                if let v = a["visible_left_right"]?.boolValue { s.visibleInLeftRight = v }
                f.solids[i] = s
                touched.append(s.name)
            }
            if touched.isEmpty { throw ToolError("The family has no forms yet. add_form makes one.") }
        }
        return familyResult(fam, ["forms": .array(touched.map { .string($0) })])
    }

    func addFamilyDimension(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let a = try c.args.requireString("plane_a"), b = try c.args.requireString("plane_b")
        try fam.apply(name: "Dimension") { f in
            func plane(_ n: String) throws -> FamilyReferencePlane {
                guard let p = f.referencePlanes.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else {
                    throw ToolError("No reference plane “\(n)”. Planes: \(f.referencePlanes.map { "\($0.name) (\($0.axis.rawValue.lowercased()))" }.joined(separator: ", ")).")
                }
                return p
            }
            let pa = try plane(a), pb = try plane(b)
            guard pa.axis == pb.axis, pa.name != pb.name else { throw ToolError("“\(pa.name)” and “\(pb.name)” aren't two parallel planes (axes \(pa.axis.rawValue) and \(pb.axis.rawValue)).") }
            if c.args.bool("equality", default: false) {
                guard let cn = c.args.string("plane_c") else { throw ToolError("EQ needs plane_c: plane_b is held midway between plane_a and plane_c.") }
                let pc = try plane(cn)
                guard pc.axis == pa.axis else { throw ToolError("plane_c must be on the same axis.") }
                f.dimensions.append(.equality(pa.name, pb.name, pc.name))
                return
            }
            var d = FamilyDimension(planeA: pa.name, planeB: pb.name)
            if let label = c.args.string("label") {
                try Self.ensureLengthParameter(label, between: pa.name, and: pb.name, in: &f, fam)
                if f.dimensions.contains(where: { $0.labelParameter == label && Set([$0.planeA, $0.planeB]) == Set([pa.name, pb.name]) }) { return }
                d.labelParameter = label
            }
            d.isLocked = c.args.bool("lock", default: false)
            f.dimensions.append(d)
        }
        return familyResult(fam, ["dimensions": .int(fam.family.dimensions.count)])
    }

    func addNestedFamily(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let q = try c.args.requireString("family")
        let item = ComponentLibrary.item(named: q) ?? Self.uniqueSearch(q)
        let existing = fam.family.nestedFamilies.first { $0.name.caseInsensitiveCompare(q) == .orderedSame }
        guard let source = existing ?? item?.family else {
            let near = ComponentLibrary.search(q).prefix(8).map(\.name)
            throw ToolError("No library family “\(q)”.\(near.isEmpty ? "" : " Similar: \(near.joined(separator: "; ")).")")
        }
        let typeName = c.args.string("type") ?? source.types.first?.name
        if let t = typeName, source.type(named: t) == nil { throw ToolError("“\(source.name)” has no type “\(t)”. Types: \(source.types.map(\.name).joined(separator: ", ")).") }
        try fam.apply(name: "Nested Family") { f in
            if !f.nestedFamilies.contains(where: { $0.name == source.name }) { f.nestedFamilies.append(source) }
            let pt = c.args.array("point") ?? []
            let snapshot = f, u = fam.units
            func coord(_ k: Int) throws -> FamilyBound { k < pt.count ? try Self.familyBound(pt[k], "point[\(k)]", snapshot, u) : .expr("0") }
            var inst = NestedFamilyInstance(familyName: source.name, typeName: typeName, x: try coord(0), y: try coord(1), z: try coord(2))
            inst.rotation = FamilyEditing.numberText(c.args.double("rotation") ?? 0)
            for (k, v) in c.args["bindings"]?.objectValue ?? [:] {
                guard source.parameter(named: k) != nil else { throw ToolError("bindings: “\(source.name)” has no parameter “\(k)”. Its parameters: \(source.parameters.map(\.name).joined(separator: ", ")).") }
                inst.bindings[k] = v.stringValue ?? v.jsonText
            }
            if let vp = c.args.string("visibility_parameter") { inst.visibilityParameter = vp }
            f.nestedInstances.append(inst)
        }
        return familyResult(fam, ["nested": .string(source.name), "type": .string(typeName ?? ""), "instances": .int(fam.family.nestedInstances.count)])
    }

    func deleteFamilyItems(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        var removed: [String] = []
        let positions = FamilyEvaluator.evaluate(fam.family, typeName: fam.currentType, units: fam.units, quality: .coarse).planes
        try fam.apply(name: "Delete") { f in
            for n in c.args.array("forms")?.compactMap(\.stringValue) ?? [] {
                guard f.solids.contains(where: { $0.name == n }) else { throw ToolError("No form “\(n)”.") }
                f.solids.removeAll { $0.name == n }; removed.append("form " + n)
            }
            for n in c.args.array("planes")?.compactMap(\.stringValue) ?? [] {
                guard let p = f.referencePlanes.first(where: { $0.name == n }) else { throw ToolError("No plane “\(n)”.") }
                if p.definesOrigin { throw ToolError("“\(n)” defines the origin and can't be deleted.") }
                FamilyEditing.deletePlane(&f, n, positions: positions); removed.append("plane " + n)
            }
            for n in c.args.array("parameters")?.compactMap(\.stringValue) ?? [] {
                guard let p = f.parameter(named: n) else { throw ToolError("No parameter “\(n)”.") }
                if p.isBuiltIn { throw ToolError("“\(n)” is built in.") }
                FamilyEditing.deleteParameter(&f, n); removed.append("parameter " + n)
            }
            for n in c.args.array("nested")?.compactMap(\.stringValue) ?? [] {
                let before = f.nestedInstances.count
                f.nestedInstances.removeAll { $0.familyName.caseInsensitiveCompare(n) == .orderedSame }
                if before == f.nestedInstances.count { throw ToolError("No nested “\(n)”.") }
                removed.append("nested " + n)
            }
        }
        guard !removed.isEmpty else { throw ToolError("Give forms, planes, parameters or nested names to delete.") }
        return familyResult(fam, ["deleted": .array(removed.map { .string($0) })])
    }

    func flexFamily(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        var f = fam.family
        if let values = c.args["values"]?.objectValue, let ti = f.types.firstIndex(where: { $0.name == fam.currentType }) {
            for (name, v) in values {
                guard let p = f.parameter(named: name) else { throw ToolError("No parameter “\(name)”.") }
                f.types[ti].values[name] = try Self.familyValue(v, p.type, name, fam.units)
            }
        }
        let problems = FamilyEvaluator.flexTest(f, units: fam.units)
        let ev = FamilyEvaluator.evaluate(f, typeName: fam.currentType, units: fam.units, quality: .coarse)
        let collapsed = ev.solids.filter { $0.zMax - $0.zMin <= 0 || $0.profile.outer.area <= 0 }.map(\.name)
        let all = problems + collapsed.map { "Form “\($0)” has no volume." }
        return ToolOutput(["ok": .bool(all.isEmpty), "problems": .array(all.map { .string($0) }), "types": .int(f.types.count),
                           "planes": .object(ev.planes.reduce(into: [:]) { $0[$1.key] = .string(QuantityFormatter.format($1.value, kind: .length, units: fam.units, locale: Locale(identifier: "en_US_POSIX"))) })])
    }

    func loadFamilyIntoProject(_ c: ToolContext) throws -> ToolOutput {
        let fam = try requireFamily()
        let problems = fam.flexTest()
        if !problems.isEmpty && !c.args.bool("force", default: false) {
            throw ToolError("The family has \(problems.count) flex problem(s): \(problems.prefix(3).joined(separator: "; ")). Fix them, or pass force: true.")
        }
        let what = try fam.loadIntoProject()
        return ToolOutput(["loaded": .string(what), "verification": ["ok": .bool(problems.isEmpty), "problems": .array(problems.prefix(10).map { .string($0) })]])
    }
}
