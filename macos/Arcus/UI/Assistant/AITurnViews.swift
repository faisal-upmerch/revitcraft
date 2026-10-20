import AppKit
import SwiftUI
import ArcusAssistant

// AICORE: the transcript: each prompt (right, with its selection and attachments), then the reply: the plan with live
// progress and time, streamed text, tool steps (collapsible), confirmation cards, notices, the change summary with
// Undo, and the cost line. Under the last reply, the chat's running total and this month's spending.

struct AITranscript: View {
    @Bindable var panel: AIAssistantPanel

    var body: some View {
        let store = panel.agent.store
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.current.turns) { t in
                        AITurnView(panel: panel, turn: t).id(t.id)
                    }
                    AIChatTotals(panel: panel).id("totals")
                }
                .padding(.horizontal, AIStyle.side).padding(.vertical, 12)
            }
            .onChange(of: scrollKey) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("totals", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("totals", anchor: .bottom) }
        }
    }

    /// Changes whenever the last reply grows.
    private var scrollKey: Int {
        guard let t = panel.agent.store.current.turns.last else { return 0 }
        return t.items.count * 1000 + t.finalText.count / 40 + panel.agent.store.current.turns.count * 1_000_000
    }
}

struct AITurnView: View {
    @Bindable var panel: AIAssistantPanel
    let turn: AITurn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIPromptBubble(turn: turn)
            if !turn.plan.isEmpty { AIPlanView(turn: turn) }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                switch g {
                case .text(let s): AIMarkdownText(text: s)
                case .steps(let steps): AIStepGroup(steps: steps, running: turn.status == .running)
                case .confirmation(let c): AIConfirmationCard(item: c) { allow in panel.agent.answer(c.id, allow: allow) }
                case .notice(let n): AINoticeRow(notice: n, retry: retryAction(n))
                }
            }
            if turn.status == .running { AIWorkingRow(turn: turn, model: panel.agent.activeModel) }
            if !turn.changes.isEmpty, turn.status != .running { AIChangeSummary(panel: panel, turn: turn) }
            if turn.status != .running, !turn.costLine.isEmpty {
                Text(turn.costLine).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary)
                    .accessibilityLabel("Cost: \(turn.costLine)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retryAction(_ n: AINotice) -> (() -> Void)? {
        guard n.kind == .error, turn.id == panel.agent.store.current.turns.last?.id, !panel.agent.isRunning,
              let k = turn.errorKind, ["offline", "timeout", "rateLimited", "overloaded", "server", "badResponse"].contains(k) else { return nil }
        return { panel.send(turn.prompt) }
    }

    enum Group {
        case text(String)
        case steps([AIToolStep])
        case confirmation(AIConfirmationItem)
        case notice(AINotice)
    }

    /// Consecutive steps fold into one group.
    var groups: [Group] {
        var out: [Group] = []
        for item in turn.items {
            switch item {
            case .text(let s):
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.text(s)) }
            case .step(let s):
                if case .steps(var list)? = out.last { list.append(s); out[out.count - 1] = .steps(list) } else { out.append(.steps([s])) }
            case .confirmation(let c): out.append(.confirmation(c))
            case .notice(let n): out.append(.notice(n))
            }
        }
        return out
    }
}

struct AIPromptBubble: View {
    let turn: AITurn
    var body: some View {
        HStack {
            Spacer(minLength: 36)
            VStack(alignment: .trailing, spacing: 5) {
                if !turn.prompt.isEmpty {
                    Text(turn.prompt).font(.system(size: 12.5)).textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AIStyle.tint.opacity(0.16)))
                }
                if !turn.selection.isEmpty || !turn.attachmentNames.isEmpty {
                    HStack(spacing: 6) {
                        if !turn.selection.isEmpty {
                            Label(turn.selection.count == 1 ? turn.selection[0].title : "\(turn.selection.count) selected", systemImage: "cursorarrow.rays")
                        }
                        ForEach(turn.attachmentNames, id: \.self) { Label($0, systemImage: "photo") }
                    }
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// Markdown (inline styles, line breaks kept) in the system font.
struct AIMarkdownText: View {
    let text: String
    var body: some View {
        Text(Self.attributed(text)).font(.system(size: 12.5)).lineSpacing(2).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    static func attributed(_ s: String) -> AttributedString {
        // Bullets as "•" so lists read as lists with inline-only parsing.
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            let t = l.drop { $0 == " " }
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return String(repeating: " ", count: l.count - t.count) + "• " + t.dropFirst(2) }
            if t.hasPrefix("#") { return "**" + t.drop { $0 == "#" || $0 == " " } + "**" }
            return String(l)
        }
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(joined)
    }
}

// MARK: - Plan and progress

struct AIPlanView: View {
    let turn: AITurn
    var body: some View {
        let done = turn.plan.filter(\.done).count
        let current = turn.plan.first { !$0.done }?.id
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Plan").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(done) of \(turn.plan.count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(1, turn.plan.count))).progressViewStyle(.linear).tint(AIStyle.tint)
            ForEach(turn.plan) { s in
                HStack(spacing: 8) {
                    Group {
                        if s.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if s.id == current && turn.status == .running { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "circle").foregroundStyle(.tertiary) }
                    }
                    .font(.system(size: 11)).frame(width: 14)
                    Text(s.title).font(.system(size: 11.5)).foregroundStyle(s.done ? .secondary : .primary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).fill(AIStyle.card))
        .overlay(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).strokeBorder(AIStyle.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan, \(done) of \(turn.plan.count) steps done")
    }
}

/// While a reply runs: the elapsed time, the step count and the model.
struct AIWorkingRow: View {
    let turn: AITurn
    let model: AIModel?
    var body: some View {
        TimelineView(.periodic(from: turn.started, by: 1)) { ctx in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label(ctx.date)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private func label(_ now: Date) -> String {
        let s = Int(now.timeIntervalSince(turn.started))
        let time = String(format: "%d:%02d", s / 60, s % 60)
        let waiting = turn.items.contains { if case .confirmation(let c) = $0 { c.decision == .pending } else { false } }
        if waiting { return "Waiting for you · \(time)" }
        let steps = turn.steps.count
        var parts = ["Working", time]
        if steps > 0 { parts.append("\(steps) step\(steps == 1 ? "" : "s")") }
        if let model { parts.append(model.displayName) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Steps

struct AIStepGroup: View {
    let steps: [AIToolStep]
    let running: Bool
    @State private var expanded = false

    var body: some View {
        let failed = steps.filter { $0.status == .failed }.count
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Image(systemName: "wrench.and.screwdriver").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if failed > 0 { Text("\(failed) failed").font(.system(size: 10.5)).foregroundStyle(.orange) }
                    Text(AIStepRow.duration(steps.reduce(0) { $0 + $1.duration })).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")
            if expanded || steps.count == 1 || steps.contains(where: { $0.status == .running || $0.status == .waiting }) {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { s in AIStepRow(step: s, showsDetail: expanded) }
                }
                .padding(.vertical, 3)
            }
        }
        .background(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).fill(AIStyle.card))
        .overlay(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).strokeBorder(AIStyle.stroke))
    }

    private var title: String {
        if steps.count == 1 { return steps[0].status == .running ? "Running \(steps[0].title)…" : "1 step" }
        return "\(steps.count) steps"
    }
}

struct AIStepRow: View {
    let step: AIToolStep
    let showsDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon.frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(step.title).font(.system(size: 11.5))
                        if step.model == .sonnet {
                            Text(step.model.displayName).font(.system(size: 9.5, weight: .medium)).foregroundStyle(AIStyle.tint)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(AIStyle.tint.opacity(0.14)))
                        }
                    }
                    if !step.summary.isEmpty { Text(step.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if step.duration > 0 { Text(Self.duration(step.duration)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary) }
            }
            ForEach(step.findings.prefix(showsDetail ? 6 : 2), id: \.self) { f in
                Text(f).font(.system(size: 10.5)).foregroundStyle(step.status == .failed ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 22)
            }
            if showsDetail, !step.detail.isEmpty, step.findings.isEmpty {
                Text(step.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(6)
                    .textSelection(.enabled).padding(.leading, 22)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch step.status {
        case .running: ProgressView().controlSize(.mini)
        case .waiting: Image(systemName: "hand.raised.fill").font(.system(size: 10)).foregroundStyle(.orange)
        case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
        case .declined: Image(systemName: "minus.circle").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    static func duration(_ s: Double) -> String { s < 1 ? String(format: "%.1fs", s) : String(format: "%.0fs", s) }
}

// MARK: - Cards

/// The inline question: Arcus asks before saving files, big deletes and project-wide changes.
struct AIConfirmationCard: View {
    let item: AIConfirmationItem
    let answer: (Bool) -> Void

    var body: some View {
        let c = item.confirmation
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: c.destructive ? "trash" : (c.action == "Continue" ? "gauge.with.dots.needle.100percent" : "questionmark.circle.fill"))
                    .foregroundStyle(c.destructive ? .red : .orange)
                Text(c.title).font(.system(size: 12.5, weight: .semibold))
            }
            Text(c.message).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch item.decision {
            case .pending:
                HStack(spacing: 8) {
                    Spacer()
                    Button(c.action == "Continue" ? "Stop" : "Don't Allow") { answer(false) }.controlSize(.regular)
                    Button(c.action) { answer(true) }.controlSize(.regular)
                        .buttonStyle(.borderedProminent).tint(c.destructive ? .red : .accentColor)
                }
            case .allowed:
                Label(c.action == "Continue" ? "Continued" : "Allowed", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(.secondary)
            case .declined:
                Label(c.action == "Continue" ? "Stopped" : "Not allowed", systemImage: "xmark").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).fill(Color.orange.opacity(item.decision == .pending ? 0.10 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).strokeBorder(Color.orange.opacity(item.decision == .pending ? 0.45 : 0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(c.title)
    }
}

struct AINoticeRow: View {
    let notice: AINotice
    var retry: (() -> Void)?
    var body: some View {
        let (symbol, color): (String, Color) = switch notice.kind {
        case .info: ("sparkles", AIStyle.tint)
        case .success: ("checkmark.circle.fill", .green)
        case .warning: ("exclamationmark.triangle.fill", .orange)
        case .error: ("xmark.octagon.fill", .red)
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.system(size: 11.5, weight: notice.message.isEmpty ? .regular : .semibold))
                if !notice.message.isEmpty { Text(notice.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            if let retry { Button("Try Again", action: retry).controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(notice.kind == .info ? 0.08 : 0.10)))
    }
}

/// What the prompt changed, with Undo (the prompt is one undo step).
struct AIChangeSummary: View {
    @Bindable var panel: AIAssistantPanel
    let turn: AITurn
    var body: some View {
        let _ = panel.agent.store.revision
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(turn.undone ? "Changes undone" : "Changes", systemImage: turn.undone ? "arrow.uturn.backward" : "checkmark.seal")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(turn.undone ? .secondary : .primary)
                Spacer()
                if !turn.undone, turn.undoName != nil {
                    Button { panel.agent.undo(turn.id) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .controlSize(.small)
                        .disabled(!panel.agent.canUndo(turn))
                        .help(panel.agent.canUndo(turn) ? "Undo everything this prompt changed (one step)" : "Undo the later changes first")
                }
            }
            ForEach(turn.changes, id: \.self) { c in
                Text("• " + c).font(.system(size: 11)).foregroundStyle(.secondary).strikethrough(turn.undone).lineLimit(2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).fill(Color.green.opacity(turn.undone ? 0.03 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).strokeBorder(Color.green.opacity(turn.undone ? 0.1 : 0.25)))
    }
}

/// The chat's total and the month's spending (with the budget).
struct AIChatTotals: View {
    @Bindable var panel: AIAssistantPanel
    var body: some View {
        let chat = panel.agent.store.current.cost
        let s = panel.settings
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle").font(.system(size: 10))
            Text("This chat \(AIFormat.dollars(chat)) · \(Date().formatted(.dateTime.month(.wide))) \(AIFormat.dollars(s.spent()))" + (s.monthlyBudget > 0 ? " of \(AIFormat.dollars(s.monthlyBudget))" : ""))
                .font(.system(size: 10.5).monospacedDigit())
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .opacity(panel.agent.store.current.turns.isEmpty ? 0 : 1)
    }
}
