import AppKit
import SwiftUI

// MARK: - 첫 실행 환영 창
// 처음 한 번만. 권한은 따로 안 받는다 — 켤 때 묻는 기능(당근밭 보기·로그인 시 열기)만 여기서 고른다.

final class WelcomePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct WelcomeView: View {
    @ObservedObject var model: Model
    let close: () -> Void
    @State private var carrots: Bool
    @State private var login: Bool

    init(model: Model, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _carrots = State(initialValue: model.quotaEnabled)
        _login = State(initialValue: model.loginItemEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whiplash").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text(t("맥에서 돌아가는 AI 에이전트들이 캐릭터로 돌아다녀요. 뭘 하는지 보고, 채찍질하고, 지시를 보내세요."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                how(kind: .claudeCode, title: t("채찍질"), text: t("쉬는 캐릭터 위에 잠깐 머문 뒤 마우스를 좌우로 휙휙 두 번. 「찰싹!」 하고 하던 일을 이어가요."))
                how(kind: .codex, title: t("지시 보내기"), text: t("캐릭터를 제자리 클릭하면 입력창. 쓰고 ⏎ 누르면 그 세션에 바로 들어가요."))
                how(kind: .gemini, title: t("보기 전환"), text: tf("메뉴 막대의 채찍 아이콘, 또는 %@ 풀어놓기 · %@ 모두 숨기기 · %@ 당근밭.", "⌃⌥A", "⌃⌥H", "⌃⌥C"))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if Paths.sandboxed {
                    HStack {
                        Text(t("세션 제목과 상태를 보려면 홈 폴더 읽기를 한 번 허용해야 해요.")).font(.system(size: 11))
                        Spacer()
                        Button(Paths.hasHomeAccess ? t("허용됨") : t("홈 폴더 허용…")) { Paths.requestHomeAccess() }
                            .disabled(Paths.hasHomeAccess)
                    }
                } else {
                    option($carrots, t("남은 쿼터 보기 — 세션·주간·모델별, 🥕 당근은 그림"),
                           t("Claude Code 로그인 토큰을 키체인에서 읽어요. 켜면 macOS가 키체인 허용을 한 번 물어요."))
                }
                option($login, t("로그인할 때 열기"), t("맥을 켜면 메뉴 막대에 조용히 올라와요. 나중에 설정에서 바꿀 수 있어요."))
            }
            HStack {
                Text(t("그 밖의 권한은 필요 없어요. 모든 정보는 이 맥 안에만 있어요.")).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(t("시작하기")) {
                    if !Paths.sandboxed, carrots != model.quotaEnabled { model.quotaEnabled = carrots }
                    if login != model.loginItemEnabled { model.loginItemEnabled = login }
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func option(_ on: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch)
        }
    }

    private func how(kind: AgentKind, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SpriteTile(kind: kind, awake: true, cell: 1.5).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AppDelegate {
    /// 처음 한 번 (WHIPLASH_WELCOME=1 이면 늘)
    func showWelcomeIfNeeded() {
        let forced = ProcessInfo.processInfo.environment["WHIPLASH_WELCOME"] != nil
        guard forced || !UserDefaults.standard.bool(forKey: "welcomed") else { return }
        UserDefaults.standard.set(true, forKey: "welcomed")
        let p = WelcomePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.backgroundColor = .windowBackgroundColor
        p.isOpaque = true
        p.appearance = NSAppearance(named: Theme.current.dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: WelcomeView(model: model) { [weak p] in p?.orderOut(nil) })
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.center()
        welcome = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }
}
