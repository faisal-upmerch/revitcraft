import SwiftUI
import ArcusDomain
import ArcusApplication

// FM6: Manage ▸ Joint Rules (also Fabricate ▸ Joint Rules), a settings table like Object Styles: one row per kind of
// part pair with its joint, the part that runs through when they're drawn overlapping, and the joint's sizes. Edits
// stay in the dialog until OK (one undoable change); Defaults restores the category's defaults.

/// Sheets of the joints batch.
enum FM6Dialog: Equatable {
    case jointRules
}

struct FM6DialogHost: View {
    let state: DocumentState
    let dialog: FM6Dialog
    var body: some View {
        switch dialog {
        case .jointRules: FurnitureJointRulesDialog(state: state)
        }
    }
}

struct FurnitureJointRulesDialog: View {
    let state: DocumentState
    @State private var rules: FurnitureJointRules?

    var category: FamilyTemplate { state.model.furnitureSetup?.category ?? .casework }

    var body: some View {
        ArcusDialog(icon: "square.split.diagonal", tint: .brown, title: "Joint Rules", subtitle: (category == .casework ? "Casework" : "Furniture") + " · joints you set with the Joint tool keep their settings.",
                    size: .wide, onCancel: { state.presented = nil }, onOK: commit) {
            if rules != nil {
                JointRulesEditor(rules: Binding(get: { rules ?? .defaults(category) }, set: { rules = $0 }), model: state.model, category: category)
            }
        } leading: {
            Button("Defaults") { rules = .defaults(category) }
                .help("The \(category == .casework ? "Casework" : "Furniture") defaults")
        }
        .onAppear { if rules == nil { rules = state.model.furnitureJointRules } }
    }

    func commit() {
        if let r = rules, r != state.model.furnitureJointRules {
            state.session.perform("Joint Rules") { tx in try FurnitureJointOperations.setRules(r, in: tx) }
            if let e = state.session.lastError { state.show(e.message, error: true) }
        }
        state.presented = nil
    }
}

/// The rules table (also rendered on its own by QA).
struct JointRulesEditor: View {
    @Binding var rules: FurnitureJointRules
    let model: BIMModel
    let category: FamilyTemplate

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(JointPairKind.allCases, id: \.self) { pair in
                        row(pair)
                        DialogColors.rowDivider.frame(height: 1)
                    }
                }
            }
            .frame(height: 420)
        }
        .background(RoundedRectangle(cornerRadius: Tokens.radiusSection).fill(DialogColors.sectionFill))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
    }

    var header: some View {
        HStack(spacing: 10) {
            Text("Pair").frame(width: 170, alignment: .leading)
            Text("Joint").frame(width: 150, alignment: .leading)
            Text("Runs Through").frame(width: 120, alignment: .leading)
            Text("Sizes").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DialogStyle.sectionTitle).foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    func rule(_ pair: JointPairKind) -> JointRule { rules.rule(pair, category: category) }

    func update(_ pair: JointPairKind, _ change: (inout JointRule) -> Void) {
        var r = rule(pair)
        change(&r)
        if let i = rules.rules.firstIndex(where: { $0.pair == pair }) { rules.rules[i] = r } else { rules.rules.append(r) }
    }

    func throughLabel(_ t: JointThrough, _ pair: JointPairKind) -> String {
        let (a, b) = pair.roles
        switch t {
        case .first: return a == b ? "First Drawn" : a
        case .second: return a == b ? "Last Drawn" : b
        case .longer: return "Longer"
        }
    }

    func row(_ pair: JointPairKind) -> some View {
        let r = rule(pair)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pair.rawValue).font(.system(size: 12))
                Text(pair.help).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)
            Picker("", selection: Binding(get: { r.type }, set: { t in update(pair) { $0.type = t; $0.parameters = JointParameters() } })) {
                ForEach(JointType.allCases.filter { $0 != .miter || [.sideTop, .sideBottom, .sideSide, .other].contains(pair) }, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 150)
            Picker("", selection: Binding(get: { r.through }, set: { t in update(pair) { $0.through = t } })) {
                ForEach(JointThrough.allCases, id: \.self) { Text(throughLabel($0, pair)).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 120)
            HStack(spacing: 8) {
                ForEach(r.type.parameterKeys.filter { !$0.isAngle && !$0.isCount }, id: \.self) { k in sizeField(pair, r, k) }
                if r.type.parameterKeys.isEmpty { Text("—").foregroundStyle(.tertiary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    /// Column-friendly names (the Options Bar and Properties use the full ones).
    func shortLabel(_ k: JointParameterKey, _ t: JointType) -> String {
        switch k {
        case .edgeDistance: "Edge"
        case .diameter: "Dia."
        case .tenonThickness: "Thickness"
        case .depth where t == .mortiseTenon: "Tenon"
        default: k.rawValue
        }
    }

    func sizeField(_ pair: JointPairKind, _ r: JointRule, _ k: JointParameterKey) -> some View {
        let value = r.parameters.over(.defaults(r.type)).value(k)
        let text = k.isCount ? ((value ?? 0) > 0 ? String(Int(value ?? 0)) : "Auto") : value.map { Parameters.format(.double($0), type: .length, model: model) } ?? "Auto"
        return HStack(spacing: 3) {
            Text(shortLabel(k, r.type)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
            FurnitureField(value: text) { s in
                update(pair) { rule in
                    if k.isCount {
                        rule.parameters.count = Int(s.trimmingCharacters(in: .whitespaces)).map { max(0, $0) }
                    } else if case .double(let d)? = try? Parameters.parse(s, type: .length, model: model), d >= 0 {
                        rule.parameters.set(k, d)
                    }
                }
            }
            .frame(width: k.isCount ? 44 : 76)
            .controlSize(.small)
        }
    }
}
