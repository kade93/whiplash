import SwiftUI
import AppKit

// MARK: - 공통

func fmtBytes(_ b: UInt64) -> String {
    let gb = Double(b) / 1_073_741_824
    if gb >= 100 { return String(format: "%.0fGB", gb) }
    if gb >= 1 { return String(format: "%.1fGB", gb) }
    let mb = Double(b) / 1_048_576
    return String(format: "%.0fMB", mb)
}

func fmtPct(_ f: Double) -> String {
    if f <= 0 { return "0%" }
    if f < 0.01 { return "<1%" }
    return String(format: "%.0f%%", min(f, 9.99) * 100)
}

struct BarPart: Equatable {
    var color: Color
    var value: Double   // 0...1
}

/// 칸으로 끊긴 픽셀 막대. 여러 색을 이어 붙일 수 있다.
struct PixelBar: View {
    var parts: [BarPart]
    var segments: Int
    var gap: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))
                HStack(spacing: 0) {
                    ForEach(Array(clamped.enumerated()), id: \.offset) { _, p in
                        Rectangle()
                            .fill(p.color)
                            .frame(width: p.value > 0.002 ? max(w * p.value, 1.5) : 0)
                    }
                }
            }
            .mask(
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { _ in Rectangle() }
                }
            )
        }
        .animation(.easeOut(duration: 0.3), value: parts)
    }

    private var clamped: [BarPart] {
        var left = 1.0
        return parts.map { p in
            let v = min(max(p.value, 0), left)
            left -= v
            return BarPart(color: p.color, value: v)
        }
    }
}

private let monoSmall = Font.system(size: 9.5, weight: .medium, design: .monospaced)
private let otherColor = Color.primary.opacity(0.38)
let waitColor = Color(hex: 0xE0A030)     // 「내 차례」 색
let hotColor = Color(hex: 0xE04F3A)      // 「과부하」 색

func fmtCores(_ c: Double) -> String { tf("%.1f코어", c) }

// MARK: - 루트

/// 채찍질 설정 메뉴. 줄 메뉴 안에도 하위 메뉴로 들어간다.
struct SettingsMenu: View {
    @ObservedObject var model: Model
    @AppStorage("useAppIcons") private var useAppIcons = false   // 기본은 캐릭터

    var body: some View {
        Toggle(t("풀어놓기 — 화면 돌아다니기"), isOn: $model.roaming)
        Toggle(t("작게 풀어놓기 (이름표 없이)"), isOn: $model.critterSmall)
        Toggle(t("당근밭에 박아두기"), isOn: $model.caged)
        Toggle(t("풀어놓을 때 채찍질 창도 보기"), isOn: $model.panelWithCritters)
        Toggle(t("Dock 에 아이콘 보이기"), isOn: $model.dockIcon)
        Toggle(t("당근밭 보기 — 남은 쿼터 (Claude 로그인 키체인 읽기)"), isOn: $model.quotaEnabled)
        Toggle(t("⌥ 누른 채로만 채찍 (오작동 방지)"), isOn: $model.whipNeedsOption)
        Toggle(t("캐릭터 뒤 물빛 칸"), isOn: $model.critterBox)
        Toggle(t("모두 숨기기 (메뉴 막대 채찍으로 되돌림)"), isOn: $model.hidden)
        Divider()
        Toggle(t("작게 보기"), isOn: $model.compact)
        Toggle(t("앱 아이콘으로 보기"), isOn: $useAppIcons)
        Toggle(t("항상 맨 위에"), isOn: $model.alwaysOnTop)
        Toggle(t("로그인할 때 열기"), isOn: $model.loginItemEnabled)
        Button(t("저장공간 다시 재기")) { model.rescanStorage() }
        Divider()
        if Paths.sandboxed { Button(t("전체 기능판 받기… (채찍 메시지·지시 보내기·오토 채찍)")) { Paths.openFullEdition() } }
        if !Paths.sandboxed { Menu(t("오토 채찍질")) {
            Button(t("1시간 동안")) { model.setAutoWhip(until: Date().addingTimeInterval(3600)) }
            Button(t("3시간 동안")) { model.setAutoWhip(until: Date().addingTimeInterval(3 * 3600)) }
            Button(t("자정까지")) { model.setAutoWhip(until: Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)) }
            Button(t("아침 9시까지")) { model.setAutoWhip(until: Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime)) }
            if model.autoWhipOn { Button(t("끄기")) { model.setAutoWhip(until: nil) } }
            Divider()
            Button(t("채찍 문구 편집…")) { model.editWhipWords() }
        } }
        Button(t("채찍 일감 편집…")) { model.editTasks() }
        Button(t("채찍 일감 다시 읽기")) { model.reloadTasks() }
        Button(t("채찍 결과 폴더 열기")) { model.openResults() }
        Button(t("단축키 편집…")) { _ = HotKeys.loadCombos(); NSWorkspace.shared.open(HotKeys.file) }
        Menu(t("언어")) {
            ForEach(Lang.allCases, id: \.self) { l in
                Button(action: { Lang.current = l; model.objectWillChange.send() }) {
                    if Lang.current == l { Label(l.title, systemImage: "checkmark") } else { Text(l.title) }
                }
            }
        }
        Divider()
        Button(t("Whiplash 닫기")) { NSApp.terminate(nil) }
    }
}

/// 맥 창의 빨강·노랑·초록. 테두리 없는 창이라 직접 그린다.
/// 빨강 = 닫기(메뉴 막대 채찍에서 다시 열기) · 노랑 = 작게 보기 · 초록 = 풀어놓기
struct TrafficLights: View {
    @ObservedObject var model: Model
    var size: CGFloat = 11
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            light(Color(hex: 0xFF5F57), Color(hex: 0xE0443E), "×",
                  model.roaming ? t("이 창만 닫기 — 캐릭터는 계속 돌아다녀요 (메뉴 막대 채찍 → 풀어놓을 때 채찍질 창도 보기)")
                                : t("닫기 — 메뉴 막대 채찍에서 다시 열어요")) {
                if model.roaming { model.panelWithCritters = false } else { model.hidden = true }
            }
            light(Color(hex: 0xFEBC2E), Color(hex: 0xDEA123), "−", model.compact ? t("크게 보기") : t("작게 보기")) { model.compact.toggle() }
            light(Color(hex: 0x28C840), Color(hex: 0x1AAB29), "+", model.roaming ? t("채찍질 창으로 모으기") : t("풀어놓기 — 화면 돌아다니기")) { model.roaming.toggle(); if model.roaming { model.hidden = false } }
        }
        .onHover { hovering = $0 }
        .noDrag()
    }

    private func light(_ fill: Color, _ ring: Color, _ glyph: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(ring, lineWidth: 0.6)
                Text(glyph)
                    .font(.system(size: size * 0.85, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct WidgetView: View {
    @ObservedObject var model: Model
    var onNoDrag: ([CGRect]) -> Void = { _ in }
    var onWhipTargets: ([String: CGRect]) -> Void = { _ in }
    var onClickTargets: ([String: CGRect]) -> Void = { _ in }

    var body: some View {
        Group {
            if model.compact {
                CompactView(model: model)
            } else {
                FullView(model: model)
            }
        }
        .padding(12)
        .coordinateSpace(name: "root")
        .onPreferenceChange(NoDragKey.self) { rects in onNoDrag(rects) }
        .onPreferenceChange(WhipTargetKey.self) { rects in onWhipTargets(rects) }
        .onPreferenceChange(ClickTargetKey.self) { rects in onClickTargets(rects) }
        .fixedSize()
        .contentShape(Rectangle())
    }
}

// MARK: - 크게 보기

struct FullView: View {
    @ObservedObject var model: Model

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 10) {
            header(s)
            summary(s)
            if model.quotaEnabled { CarrotField(model: model) }
            if s.groups.isEmpty {
                EmptyField()
            } else {
                VStack(spacing: 6) {
                    ForEach(s.groups) { g in
                        AgentRow(model: model, group: g)
                    }
                }
            }
            if !model.results.isEmpty {
                WhipResults(model: model)
            }
            footer(s)
        }
        .frame(width: 286, alignment: .leading)
    }

    private func header(_ s: Snapshot) -> some View {
        let working = s.groups.filter { $0.awake }.count
        let waiting = s.groups.filter { $0.session?.needsYou == true }.count
        let hot = s.groups.filter { $0.overloaded(memTotal: s.memTotal) }.count
        let striking = s.groups.filter { model.onStrike($0) }.count
        return HStack(alignment: .center, spacing: 6) {
            TrafficLights(model: model)
                .padding(.trailing, 2)
            Text("Whiplash")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Spacer()
            if s.groups.isEmpty {
                Text("모두 쉬는 중").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(tf("%d마리 · %d 일하는 중", s.groups.count, working))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if waiting > 0 {
                    Text(tf("· %d 내 차례", waiting))
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(waitColor)
                }
                if hot > 0 {
                    Text(tf("· %d 과부하", hot))
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(hotColor)
                }
                if striking > 0 {
                    Text(tf("· %d 파업", striking))
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(hotColor)
                }
            }
            if model.autoWhipOn, let until = model.autoWhipUntil {
                Text("⚡\(until, style: .time)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE07A5F))
                    .help(tf("오토 채찍질 켜짐 · %d분마다 쉬는 세션에 「계속해」 · 지금까지 %d번", Int(model.autoWhipInterval / 60), model.autoWhipCount))
            }
        }
    }

    private func summary(_ s: Snapshot) -> some View {
        let n = Double(max(s.ncpu, 1))
        let agentCPU = s.agentCPU / n
        let cpuParts: [BarPart] = s.byKind.map { BarPart(color: $0.kind.barColor, value: $0.cpu / n) }
            + [BarPart(color: otherColor, value: max(0, s.machineBusy - agentCPU))]

        let total = Double(max(s.memTotal, 1))
        let agentMem = s.agentMemory
        let restMem = s.memUsed > agentMem ? s.memUsed - agentMem : 0
        let memParts: [BarPart] = s.byKind.map { BarPart(color: $0.kind.barColor, value: Double($0.memory) / total) }
            + [BarPart(color: otherColor, value: Double(restMem) / total)]

        return VStack(spacing: 5) {
            UsageLine(title: "CPU", parts: cpuParts,
                      value: tf("%@ / 전체 %@", fmtPct(agentCPU), fmtPct(s.machineBusy)))
            UsageLine(title: t("메모리"), parts: memParts,
                      value: "\(fmtBytes(agentMem)) / \(fmtBytes(s.memUsed))")
        }
        .help(t("색 = 에이전트, 회색 = 다른 앱, 빈 칸 = 남은 자원"))
    }

    @ViewBuilder
    private func footer(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            if !model.storage.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 4) {
                    ForEach(model.storage) { item in
                        HStack(spacing: 4) {
                            SpriteTile(kind: item.kind, awake: true, cell: 1.5)
                            Text(fmtBytes(item.bytes)).font(monoSmall)
                        }
                        .help(tf("%@ 데이터 폴더\n", item.kind.title) + item.paths.joined(separator: "\n"))
                    }
                }
            }

            let d = model.disk
            if d.total > 0 {
                let total = Double(d.total)
                let agentBytes = model.storage.reduce(UInt64(0)) { $0 + $1.bytes }
                let used = d.total > d.free ? d.total - d.free : 0
                let rest = used > agentBytes ? used - agentBytes : 0
                let parts: [BarPart] = model.storage.map { BarPart(color: $0.kind.barColor, value: Double($0.bytes) / total) }
                    + [BarPart(color: otherColor, value: Double(rest) / total)]
                UsageLine(title: t("디스크"), parts: parts, value: tf("여유 %@", fmtBytes(d.free)))
                    .help(tf("에이전트 데이터 폴더 합계 %@ · 30분마다 다시 잼", fmtBytes(agentBytes)))
            }

            Text(tf("채찍질 자체 CPU %@ · %@", fmtPct(s.selfCPU / Double(max(s.ncpu, 1))), fmtBytes(s.selfMemory)))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

/// 당근밭: 남은 쿼터만큼 당근이 남아 있다. 쿼터를 쓸수록 오른쪽부터 뽑혀 나간다.
struct CarrotField: View {
    @ObservedObject var model: Model
    private let count = 12

    var body: some View {
        let q = model.quota
        let five = q?.fiveHour
        let seven = q?.sevenDay
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(t("당근밭"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { i in
                        let alive = five.map { Double(i) < Double(count) * $0.remaining / 100 - 0.001 } ?? true
                        PixelArt(rows: alive ? ToolArt.carrot : ToolArt.carrotEaten, cell: 1.5)
                            .opacity(q == nil ? 0.35 : 1)
                    }
                }
                Spacer(minLength: 0)
                Text(fieldText(five))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(five.map { $0.utilization >= 100 ? AnyShapeStyle(hotColor) : ($0.utilization >= 80 ? AnyShapeStyle(waitColor) : AnyShapeStyle(.primary)) } ?? AnyShapeStyle(.tertiary))
                    .lineLimit(1)
            }
            if let seven = seven {
                UsageLine(title: t("7일"), parts: [BarPart(color: seven.utilization >= 90 ? hotColor : Color(hex: 0xF28C28), value: seven.utilization / 100)],
                          value: tf("%d%% 씀 · %@", Int(seven.utilization), seven.resetsAt.map { fmtAgoFuture($0) } ?? ""))
            }
            if let e = q?.error {
                Text(e).font(.system(size: 9)).foregroundStyle(hotColor).lineLimit(2)
            }
        }
        .help(t("5시간 창 남은 쿼터 = 남은 당근. 다 뽑히면 애들이 파업해요. 5분마다 Claude 사용량을 조회해요 (키체인의 Claude Code 로그인으로)."))
        .padding(.vertical, 2)
    }

    private func fieldText(_ w: Quota.Window?) -> String {
        guard let w = w else { return t("조회 중…") }
        if w.utilization >= 100 { return t("다 뽑힘 · 파업!") }
        let reset = w.resetsAt.map { fmtAgoFuture($0) } ?? ""
        return tf("%d%% 남음 · %@", Int(w.remaining), reset)
    }
}

/// "2시간 뒤" 처럼 앞으로 남은 시간
func fmtAgoFuture(_ d: Date) -> String {
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return t("지금") }
    if s < 3600 { return tf("%d분 뒤", s / 60) }
    if s < 86400 { return tf("%d시간 %d분 뒤", s / 3600, s % 3600 / 60) }
    return tf("%d일 뒤", s / 86400)
}

struct UsageLine: View {
    let title: String
    let parts: [BarPart]
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            PixelBar(parts: parts, segments: 24)
                .frame(height: 7)
            Text(value)
                .font(monoSmall)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
    }
}

// MARK: - 줄 하나

/// 한 줄에 보여 줄 상태 글과 색
struct RowStatus {
    let text: String
    let color: Color?    // nil 이면 흐리게
    let tone: AgentSession.Waiting
    var hot = false

    static func of(_ g: AgentGroup, job: WhipJob?, memTotal: UInt64 = 0, immune: Bool = false, angry: String? = nil, strike: Date? = nil) -> RowStatus {
        if g.id == Model.ghostID { return RowStatus(text: t("자는 중 · 휘두르면 깨워요"), color: nil, tone: .none) }
        if let line = angry { return RowStatus(text: "😠 " + line, color: hotColor, tone: .none) }
        if let until = strike {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return RowStatus(text: tf("✊ 파업 중 · %@ 까지", f.string(from: until)), color: hotColor, tone: .none)
        }
        if immune {
            var r = of(g, job: job, memTotal: memTotal, immune: false)
            r = RowStatus(text: "🛡 " + r.text, color: r.color, tone: r.tone, hot: r.hot)
            return r
        }
        if memTotal > 0, g.overloaded(memTotal: memTotal) {
            return RowStatus(text: tf("과부하 · CPU %@ · %@", fmtCores(g.cpu), fmtBytes(g.memory)), color: hotColor, tone: .none, hot: true)
        }
        if let job = job { return RowStatus(text: tf("채찍 맞고 %@", job.task.title), color: g.kind.barColor, tone: .none) }
        guard let s = g.session, s.status != .unknown else {
            let state = g.awake ? t("일하는 중") : t("쉬는 중")
            return RowStatus(text: g.processCount > 1 ? tf("%@ · %d개", state, g.processCount) : state,
                             color: g.awake ? g.kind.barColor : nil, tone: .none)
        }
        if s.status == .busy {
            let act = s.activity.isEmpty ? t("일하는 중") : s.activity
            return RowStatus(text: act, color: g.kind.barColor, tone: .none)
        }
        let ago = fmtAgo(s.statusSince)
        switch s.waiting {
        case .reply:      return RowStatus(text: tf("답 기다리는 중 · %@", ago), color: waitColor, tone: .reply)
        case .question:   return RowStatus(text: tf("물어보고 기다림 · %@", ago), color: waitColor, tone: .question)
        case .permission: return RowStatus(text: tf("허락 기다리는 중 · %@", ago), color: waitColor, tone: .permission)
        case .none:       return RowStatus(text: ago.isEmpty ? t("쉬는 중") : tf("쉬는 중 · %@", ago), color: nil, tone: .none)
        }
    }
}

/// 일하는 캐릭터가 들 연장: 세션이 알려 주면 그 일, 모르면 망치. 파업이면 피켓.
func chore(_ g: AgentGroup, strike: Bool = false) -> Chore {
    if strike { return .strike }
    guard g.awake else { return .none }
    if g.whipJob != nil { return .run }
    if let c = g.session?.chore, c != .none { return c }
    return .run
}

/// 지시를 보내면 초록으로 한 번 반짝
struct SentFlash: ViewModifier {
    let at: Date?
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x4E9A57), lineWidth: on ? 2 : 0).opacity(on ? 1 : 0))
            .onChange(of: at) { _ in
                withAnimation(.easeOut(duration: 0.15)) { on = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.easeOut(duration: 0.4)) { on = false } }
            }
    }
}

extension View {
    func sentFlash(_ at: Date?) -> some View { modifier(SentFlash(at: at)) }

    /// 채찍 맞을 캐릭터에 커서가 올라가면: 살짝 커지고 노랗게 반짝
    func whipHover(_ on: Bool) -> some View {
        scaleEffect(on ? 1.12 : 1)
            .shadow(color: waitColor.opacity(on ? 0.9 : 0), radius: on ? 6 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: on)
    }
}

/// 기다리는 캐릭터 머리 위 말풍선
struct WaitBadge: View {
    let tone: AgentSession.Waiting
    var small = false

    var body: some View {
        if tone != .none {
            Text(tone == .question ? "?" : (tone == .permission ? "✋" : "!"))
                .font(.system(size: small ? 7 : 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, small ? 2.5 : 3.5)
                .padding(.vertical, small ? 0.5 : 1)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(waitColor))
        }
    }
}

struct AgentRow: View {
    @ObservedObject var model: Model
    let group: AgentGroup

    var body: some View {
        let g = group
        let snap = model.snapshot
        let n = Double(max(snap.ncpu, 1))
        let strike = model.onStrike(g)
        let st = RowStatus.of(g, job: g.whipJob, memTotal: snap.memTotal, immune: model.isImmune(g),
                              angry: model.isAngry(g.id) ? model.angry[g.id]?.line : nil,
                              strike: strike ? (g.session?.strikeUntil ?? model.quota?.fiveHour?.resetsAt ?? Date().addingTimeInterval(3600)) : nil)
        let canWhip = model.canWhip(g)
        let barColor = st.hot ? hotColor : g.kind.barColor

        HStack(spacing: 8) {
            StrikeTile(strike: model.lastStrike[g.id], angryLine: model.isAngry(g.id) ? model.angry[g.id]?.line : nil) {
                SpriteTile(kind: g.kind, awake: g.awake,
                           bob: g.awake && model.tick % 2 == 1,
                           sweat: g.awake && g.cpu >= 1.0, cell: 3, chore: chore(g, strike: strike), hot: st.hot, angry: model.isAngry(g.id))
            }
            .whipHover(model.hoverWhipID == g.id)
            .sentFlash(model.lastSent[g.id])
            .overlay(alignment: .topLeading) { WaitBadge(tone: st.tone).offset(x: -6, y: -6) }
            .whipTarget(g.id, on: canWhip)
            .clickTarget(g.id)

            VStack(alignment: .leading, spacing: 1) {
                Text(title(g))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle(g))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(st.text)
                        .font(.system(size: 9, weight: st.tone == .none ? .regular : .semibold))
                        .foregroundStyle(st.color.map { AnyShapeStyle($0) }
                                         ?? AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if canWhip { WhipHint() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if g.id == Model.ghostID {
                Text("휙휙 → 앱 켜기\n오른쪽 클릭 → 폴더 골라 터미널")
                    .font(.system(size: 8)).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
            } else {
                VStack(alignment: .trailing, spacing: 5) {
                    MeterLine(title: "CPU", value: g.cpu / n, text: fmtPct(g.cpu / n), color: barColor)
                    MeterLine(title: "MEM", value: Double(g.memory) / Double(max(snap.memTotal, 1)),
                              text: fmtBytes(g.memory), color: barColor)
                }
            }
        }
        .opacity(g.id == Model.ghostID ? 0.6 : 1)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(st.hot ? hotColor.opacity(0.14) : (st.tone == .none ? Color.primary.opacity(0.05) : waitColor.opacity(0.13))))
        .help(rowTooltip(model, g))
    }

    private func title(_ g: AgentGroup) -> String {
        if g.id == Model.ghostID { return t("Claude (꺼짐)") }
        if let s = g.session, !s.name.isEmpty { return s.name }
        return g.kind.title
    }

    private func subtitle(_ g: AgentGroup) -> String {
        guard let s = g.session, !s.name.isEmpty else { return g.label }
        var parts = [g.label]
        if s.costUSD > 0 { parts.append(fmtUSD(s.costUSD)) }
        if s.linesAdded + s.linesRemoved > 0 { parts.append("+\(s.linesAdded) −\(s.linesRemoved)") }
        return parts.joined(separator: " · ")
    }

}

/// 줄·크리터 공용 설명 풍선
func rowTooltip(_ model: Model, _ g: AgentGroup) -> String {
    var lines: [String] = []
    if let s = g.session {
        if !s.lastPrompt.isEmpty {
            let p = s.lastPrompt.replacingOccurrences(of: "\n", with: " ")
            lines.append(t("마지막 지시: ") + (p.count > 160 ? String(p.prefix(160)) + "…" : p))
        }
        if let st = s.startedAt { lines.append(tf("세션 시작 %@ 전 · %@", fmtAgo(st), s.isDesktop ? t("Claude 앱") : t("터미널"))) }
        var money: [String] = []
        if s.costUSD > 0 { money.append(tf("먹이값 %@", fmtUSD(s.costUSD))) }
        if s.linesAdded + s.linesRemoved > 0 { money.append(tf("고친 줄 +%d −%d", s.linesAdded, s.linesRemoved)) }
        if !money.isEmpty { lines.append(money.joined(separator: " · ")) }
    }
    if let d = g.dir { lines.append(d) }
    lines.append(tf("%@ · PID %d · 프로세스 %d개 · CPU는 맥 전체 대비", t(g.kind.sprite.friend), Int(g.rootPID), g.processCount))
    if model.canWhip(g) {
        lines.append(g.id.hasPrefix("app:") ? t("캐릭터 위에서 마우스를 휙휙 흔들면 앱을 앞으로 불러와요")
                                            : t("캐릭터 위에서 마우스를 휙휙 흔들면 채찍질 (읽기만 하는 일감 하나) · 오른쪽 클릭으로 골라서"))
    }
    return lines.joined(separator: "\n")
}

/// 줄·크리터 공용 오른쪽 클릭 메뉴
struct RowMenu: View {
    @ObservedObject var model: Model
    let group: AgentGroup

    var body: some View {
        let g = group
        if g.id == Model.ghostID {
            Button(t("Claude 앱 열기")) { model.wakeClaude(dir: nil) }
            Menu(t("터미널에서 claude 열기")) {
                ForEach(model.recentProjects(), id: \.self) { d in
                    Button((d as NSString).lastPathComponent) { model.wakeClaude(dir: d) }
                }
                Divider()
                Button(t("홈 폴더에서")) { model.wakeClaude(dir: Paths.home) }
            }
            Divider()
        }
        if model.canWhip(g), !g.id.hasPrefix("app:"), g.id != Model.ghostID, !Paths.sandboxed {
            Menu(t("채찍 — 일감 골라 시키기")) {
                ForEach(model.tasks) { t in Button(t.title) { model.whip(g, task: t) } }
            }
            Divider()
        }
        if let s = g.session {
            Text(s.name.isEmpty ? g.label : s.name)
            Button(model.isImmune(g) ? t("채찍 면역 풀기") : t("채찍 면역 (손·오토 채찍 다 안 맞음)")) { model.toggleImmune(g) }
            if Paths.sandboxed { Button(t("전체 기능판 받기… (채찍 메시지·지시 보내기·오토 채찍)")) { Paths.openFullEdition() } }
            else { Text(t("제자리 클릭 → 지시 보내기")) }
            Button(t("창 앞으로")) { model.bringToFront(g) }
            Button(t("폴더 열기")) { model.openFolder(g) }
            if !s.lastPrompt.isEmpty { Button(t("마지막 지시 복사")) { model.copyPrompt(g) } }
            if s.transcript != nil { Button(t("대화 기록 파일 열기")) { model.openTranscript(g) } }
            if s.status == .busy && !s.isDesktop && !Paths.sandboxed {
                Divider()
                Button(t("하던 일 멈추기 (Ctrl-C)")) { model.interrupt(g) }
            }
        } else {
            Button(t("창 앞으로")) { model.bringToFront(g) }
            if g.dir != nil { Button(t("폴더 열기")) { model.openFolder(g) } }
        }
        Divider()
        // 자주 쓰는 것은 바로
        if model.roaming {
            Button(model.caged ? t("당근밭에서 뽑기") : t("당근밭에 박아두기")) { model.caged.toggle() }
            Button(t("채찍질 창으로 모으기")) { model.roaming = false }
            Button(model.critterSmall ? t("크게 풀어놓기") : t("작게 풀어놓기")) { model.critterSmall.toggle() }
        } else {
            Button(t("풀어놓기 — 화면 돌아다니기")) { model.roaming = true; model.hidden = false }
        }
        Button(t("모두 숨기기")) { model.hidden = true }
        Divider()
        Menu(t("채찍질 설정")) { SettingsMenu(model: model) }
    }
}

struct MeterLine: View {
    let title: String
    let value: Double
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .leading)
            PixelBar(parts: [BarPart(color: color, value: value)], segments: 10)
                .frame(width: 60, height: 6)
            Text(text)
                .font(monoSmall)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct EmptyField: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(AgentKind.allCases) { k in
                    SpriteTile(kind: k, awake: false, cell: 2)
                }
            }
            Text("지금 돌아가는 에이전트가 없어요")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - 작게 보기 (캐릭터 + 막대 두 줄)

struct CompactView: View {
    @ObservedObject var model: Model

    var body: some View {
        let s = model.snapshot
        let n = Double(max(s.ncpu, 1))
        HStack(spacing: 6) {
            TrafficLights(model: model, size: 8)
                .padding(.trailing, 2)
            if s.groups.isEmpty {
                SpriteTile(kind: .other, awake: false, cell: 2)
                    .help(t("지금 돌아가는 에이전트가 없어요"))
            }
            ForEach(s.groups) { g in
                let strike = model.onStrike(g)
                let st = RowStatus.of(g, job: g.whipJob, memTotal: s.memTotal, immune: model.isImmune(g),
                                      angry: model.isAngry(g.id) ? model.angry[g.id]?.line : nil,
                                      strike: strike ? (g.session?.strikeUntil ?? Date().addingTimeInterval(3600)) : nil)
                VStack(spacing: 3) {
                    let tile = StrikeTile(strike: model.lastStrike[g.id], angryLine: model.isAngry(g.id) ? model.angry[g.id]?.line : nil) {
                        SpriteTile(kind: g.kind, awake: g.awake,
                                   bob: g.awake && model.tick % 2 == 1,
                                   sweat: g.awake && g.cpu >= 1.0, cell: 2, chore: chore(g, strike: strike), hot: st.hot, angry: model.isAngry(g.id))
                    }
                    .whipHover(model.hoverWhipID == g.id)
                    .sentFlash(model.lastSent[g.id])
                    .overlay(alignment: .topLeading) { WaitBadge(tone: st.tone, small: true).offset(x: -4, y: -5) }
                    .whipTarget(g.id, on: model.canWhip(g))
                    .clickTarget(g.id)
                    if model.canWhip(g) {
                        Button { model.whip(g) } label: { tile }
                            .buttonStyle(.plain)
                            .noDrag()
                    } else {
                        tile
                    }
                    PixelBar(parts: [BarPart(color: st.hot ? hotColor : g.kind.barColor, value: g.cpu / n)], segments: 6)
                        .frame(width: 30, height: 3)
                    PixelBar(parts: [BarPart(color: st.hot ? hotColor : g.kind.barColor,
                                             value: Double(g.memory) / Double(max(s.memTotal, 1)))],
                             segments: 6)
                        .frame(width: 30, height: 3)
                }
                .help(compactHelp(g, st))
            }
        }
    }

    private func compactHelp(_ g: AgentGroup, _ st: RowStatus) -> String {
        let name = (g.session?.name).flatMap { $0.isEmpty ? nil : $0 } ?? g.kind.title
        var text = tf("%@ · %@\n%@\nCPU %@ · 메모리 %@", name, g.label, st.text, fmtPct(g.cpu / Double(max(model.snapshot.ncpu, 1))), fmtBytes(g.memory))
        if model.canWhip(g) { text += t("\n마우스를 휙휙 흔들거나 눌러서 채찍질") }
        return text
    }
}

// MARK: - 채찍 UI

/// 쉬는 캐릭터 옆의 작은 채찍 표시: 「마우스로 후려칠 수 있어요」
struct WhipHint: View {
    var body: some View {
        WhipCanvas(cell: 1.5)
            .opacity(0.55)
    }
}

/// 채찍을 맞으면: 채찍이 휘둘러지고 → 「짝!」 터지며 펄쩍 → 좌우로 부들부들 → 「아야」 풍선
struct StrikeTile<Content: View>: View {
    let strike: Date?
    var angryLine: String? = nil     // 화났으면 「아야」 대신 이 말
    @ViewBuilder let content: () -> Content
    @State private var phase = 0     // 0 평소 · 1 치켜듦 · 2 내려침 · 3~5 떨기 · 6 아야
    @State private var shake: CGFloat = 0

    var body: some View {
        content()
            .offset(x: shake, y: phase == 2 ? -7 : 0)
            .scaleEffect(phase == 2 ? 1.12 : 1, anchor: .bottom)
            .overlay(alignment: .topTrailing) {
                WhipCanvas(cell: 2)
                    .rotationEffect(.degrees(phase == 1 ? -60 : (phase >= 2 ? 35 : 0)), anchor: .bottomLeading)
                    .offset(x: 10, y: -8)
                    .opacity(phase == 0 || phase >= 4 ? 0 : 1)
            }
            .overlay(alignment: .top) {
                Text("짝!")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xE04F3A))
                    .shadow(color: .white.opacity(0.8), radius: 0, x: 1, y: 1)
                    .rotationEffect(.degrees(-12))
                    .scaleEffect(phase == 2 ? 1.4 : (phase == 3 ? 1 : 0.3))
                    .offset(x: 6, y: -14)
                    .opacity(phase == 2 || phase == 3 ? 1 : 0)
            }
            .overlay(alignment: .topLeading) {
                Text(angryLine ?? t("아야"))
                    .font(.system(size: angryLine == nil ? 8 : 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color(hex: 0xE04F3A)))
                    .offset(x: angryLine == nil ? -8 : -14, y: angryLine == nil ? -6 : -10)
                    .opacity(phase >= 4 || (angryLine != nil && phase != 0) ? 1 : 0)
            }
            .onChange(of: strike) { _ in play() }
    }

    private func play() {
        func at(_ s: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: body) }
        if angryLine != nil {            // 화남: 채찍 없이 바로 쿵쿵 발 구르며 세게 떨기
            withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) { phase = 4; shake = 6 }
            for i in 1...8 { at(0.08 * Double(i)) { withAnimation(.easeOut(duration: 0.06)) { shake = i % 2 == 0 ? 6 : -6 } } }
            at(0.75) { withAnimation(.easeOut(duration: 0.1)) { shake = 0; phase = 6 } }
            at(2.4) { withAnimation(.easeOut(duration: 0.25)) { phase = 0 } }
            return
        }
        withAnimation(.easeIn(duration: 0.10)) { phase = 1 }
        at(0.12) { withAnimation(.spring(response: 0.14, dampingFraction: 0.35)) { phase = 2; shake = 4 } }
        at(0.26) { withAnimation(.easeOut(duration: 0.07)) { phase = 3; shake = -4 } }
        at(0.33) { withAnimation(.easeOut(duration: 0.06)) { phase = 4; shake = 3 } }
        at(0.39) { withAnimation(.easeOut(duration: 0.06)) { phase = 5; shake = -2 } }
        at(0.45) { withAnimation(.easeOut(duration: 0.08)) { phase = 6; shake = 0 } }
        at(1.15) { withAnimation(.easeOut(duration: 0.25)) { phase = 0 } }
    }
}

struct WhipResults: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.results) { r in
                HStack(spacing: 6) {
                    Button { model.open(r) } label: {
                        HStack(spacing: 4) {
                            Text(r.ok ? t("결과") : t("실패"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(r.ok ? Color(hex: 0x4E9A57) : Color(hex: 0xE04F3A))
                            Text("\(r.project) · \(r.title)")
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(r.finished, style: .time)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .noDrag()
                    .help(r.ok ? t("눌러서 결과 열기") : r.note)

                    Button { model.dismiss(r) } label: {
                        Text("×").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .noDrag()
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: 0xE07A5F).opacity(0.08)))
    }
}
