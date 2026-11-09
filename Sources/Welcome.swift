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
                    Text(t("The AI agents running on your Mac roam around as critters. See what they do, crack the whip, send instructions."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                how(kind: .claudeCode, title: t("Whip"), text: t("Hover over an idle critter, then swipe the mouse left-right twice. Whack! It picks its work back up."))
                how(kind: .codex, title: t("Send instruction"), text: t("Click a critter in place for an input box. Type and press ⏎ to deliver it to that session."))
                how(kind: .gemini, title: t("Views"), text: tf("The whip icon in the menu bar, or %@ roam · %@ hide all · %@ carrot field.", "⌃⌥A", "⌃⌥H", "⌃⌥C"))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if Paths.sandboxed {
                    HStack {
                        Text(t("Allow reading your home folder once to see session titles and status.")).font(.system(size: 11))
                        Spacer()
                        Button(Paths.hasHomeAccess ? t("Allowed") : t("Allow home folder…")) { Paths.requestHomeAccess() }
                            .disabled(Paths.hasHomeAccess)
                    }
                } else {
                    option($carrots, t("Show remaining quota — session, weekly, per model; 🥕 carrots are just the picture"),
                           t("Reads the Claude Code login token from the Keychain. macOS will ask once to allow it."))
                }
                option($login, t("Open at login"), t("Starts quietly in the menu bar when you log in. Change it later in Settings."))
            }
            HStack {
                Text(t("No other permissions are needed. Everything stays on this Mac.")).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(t("Get started")) {
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
