import AppKit
import SwiftUI

// MARK: - 「알리고 물어보기」 창
// 과부하가 이어지거나(설정 ▸ When an agent is overloaded) 유출 감시에 걸리면(Guard.swift) 화면 오른쪽 위에 뜬다.
// 한 줄에 한 건: 누가 · 무슨 일 · [멈추기 (Ctrl-C)] [창 앞으로] [그냥 두기]. 다 답하면 창은 사라진다.

struct AlertsView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.alerts) { a in
                if let g = model.snapshot.groups.first(where: { $0.id == a.groupID }) { row(a, g) }
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ a: Model.AgentAlert, _ g: AgentGroup) -> some View {
        let stoppable = model.canStop(g)
        HStack(alignment: .top, spacing: 10) {
            SpriteTile(kind: g.kind, awake: true, cell: 2)
            VStack(alignment: .leading, spacing: 5) {
                switch a.kind {
                case .overload:
                    Text(tf("🥵 %@ is overloaded", model.alertName(g))).font(.system(size: 13, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let mins = max(1, Int(ctx.date.timeIntervalSince(a.since) / 60 + 0.5))
                        Text(tf("CPU %@ · Memory %@ · for %d min", fmtPct(g.cpu / Double(max(model.snapshot.ncpu, 1))), fmtBytes(g.memory), mins))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if model.overloadMode == .auto, stoppable {
                            let left = max(0, Int(Model.overloadCountdown - ctx.date.timeIntervalSince(a.raisedAt) + 0.5))
                            Text(tf("Stopping it in %d s unless you say otherwise", left))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0xE0443E))
                        }
                    }
                case .risk(let title, let detail):
                    Text(tf("⚠️ %@: %@", model.alertName(g), t(title))).font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if model.leakGuard == "whip", g.session?.socketPath != nil, !Paths.sandboxed {
                        Text(t("I told it to stop and undo this.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    if stoppable {
                        Button(t("Stop it (Ctrl-C)")) { model.answer(a, stop: true) }
                    } else if a.kind == .overload {
                        Text(t("Can't be stopped from here")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button(t("Bring window to front")) { model.bringToFront(g) }
                    Button(t("Leave it")) { model.answer(a, stop: false) }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 버튼만 있는 창이라 키 창이 될 필요가 없다 (하던 일의 포커스를 뺏지 않는다)
final class AlertsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
