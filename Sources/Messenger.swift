import AppKit
import SwiftUI

// MARK: - 떠 있는 Claude Code 세션에 지시 넣기
// Claude Code 는 세션마다 /tmp/cc-socks/<pid>.sock 유닉스 소켓을 열어 두고,
// 「auth 한 줄 + user 한 줄」을 받으면 그 세션에 사용자 메시지로 넣는다. (Claude Code 자체 로그 문구에 적힌 형식)
//   {"type":"auth","token":"<peerToken>"}
//   {"type":"user","message":{"role":"user","content":"..."}}
// peerToken 은 ~/.claude/sessions/<pid>.<hash>.key 에 있다. 읽기만 하고 어디에도 남기지 않는다.

enum SessionMessenger {
    enum Failure: Error, LocalizedError {
        case noSocket, noToken, connect(Int32), write(Int32), rejected(String), sandboxed
        var errorDescription: String? {
            switch self {
            case .noSocket:        return t("이 세션은 메시지 소켓이 없어요")
            case .noToken:         return t("세션 키 파일을 못 읽었어요")
            case .connect(let e):  return tf("세션에 연결 못 함 (errno %d)", Int(e))
            case .write(let e):    return tf("보내다 끊김 (errno %d)", Int(e))
            case .rejected(let s): return tf("세션이 거절함: %@", s)
            case .sandboxed:       return t("앱스토어판에서는 보낼 수 없어요 — 전체 기능판에서 돼요")
            }
        }
    }

    private static let queue = DispatchQueue(label: "kr.urbanism.whiplash.messenger", qos: .userInitiated)

    static func send(_ text: String, to session: AgentSession, completion: @escaping (Result<String, Failure>) -> Void) {
        queue.async {
            let r = sendNow(text, to: session)
            DispatchQueue.main.async { completion(r) }
        }
    }

    private static func sendNow(_ text: String, to session: AgentSession) -> Result<String, Failure> {
        let env = ProcessInfo.processInfo.environment
        var path = session.socketPath
        var token: String? = nil
        if let fake = env["WHIPLASH_FAKE_SOCK"] { path = fake; token = env["WHIPLASH_FAKE_TOKEN"] ?? "test" }   // 개발용 가짜 서버
        guard let sock = path, !sock.isEmpty else { return .failure(.noSocket) }
        if Paths.sandboxed && env["WHIPLASH_FAKE_SOCK"] == nil { return .failure(.sandboxed) }
        if token == nil {
            guard let k = session.keyFile, let data = try? Data(contentsOf: k),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let t = j["peerToken"] as? String else { return .failure(.noToken) }
            token = t
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(.connect(errno)) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = withUnsafeMutablePointer(to: &addr.sun_path) { ptr -> Bool in
            let cap = MemoryLayout.size(ofValue: ptr.pointee)
            return sock.utf8CString.withUnsafeBufferPointer { src in
                guard src.count <= cap else { return false }
                ptr.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
                    for (i, c) in src.enumerated() { dst[i] = c }
                }
                return true
            }
        }
        guard ok else { return .failure(.noSocket) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .failure(.connect(errno)) }

        func line(_ obj: [String: Any]) -> String {
            let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data()
            return String(decoding: d, as: UTF8.self) + "\n"
        }
        let payload = line(["type": "auth", "token": token!])
                    + line(["type": "user", "message": ["role": "user", "content": text]])
        var bytes = Array(payload.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeMutableBufferPointer { write(fd, $0.baseAddress! + sent, $0.count - sent) }
            if n <= 0 { return .failure(.write(errno)) }
            sent += n
        }
        shutdown(fd, SHUT_WR)
        // 답이 있으면 읽는다 (없어도 보낸 건 보낸 것)
        var buf = [UInt8](repeating: 0, count: 4096)
        var reply = Data()
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(buf, count: n)
            if reply.count > 64 * 1024 { break }
        }
        let text = String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().contains("unauthorized") || text.lowercased().contains("\"error\"") {
            return .failure(.rejected(String(text.prefix(120))))
        }
        return .success(text)
    }
}

// MARK: - 지시 입력창 (캐릭터 왼쪽 클릭)

final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }     // 글자를 받아야 하니 키 창이 된다 (앱은 활성화 안 함)
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct PromptView: View {
    @ObservedObject var model: Model
    let groupID: String
    let close: () -> Void
    @State private var text = ""
    @State private var state: State = .idle
    @FocusState private var focused: Bool

    enum State: Equatable { case idle, sending, sent, failed(String) }

    var body: some View {
        let g = model.snapshot.groups.first { $0.id == groupID }
        let name = g.flatMap { $0.session?.name }.flatMap { $0.isEmpty ? nil : $0 } ?? g?.kind.title ?? ""
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let g = g { SpriteTile(kind: g.kind, awake: true, cell: 1.5) }
                Text(name).font(.system(size: 11, weight: .bold)).lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(g?.session?.isDesktop == true ? t("Claude 앱 세션") : t("터미널 세션"))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                TextField(t("지시를 쳐서 바로 보내요 (⏎ 보내기 · esc 닫기)"), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { send() }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty || state == .sending
                                         ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color(hex: 0xE07A5F)))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || state == .sending)
            }
            HStack(spacing: 6) {
                switch state {
                case .idle:
                    Text(g?.session?.status == .busy ? t("일하는 중이라 지금 턴이 끝난 뒤에 읽어요") : t("쉬는 중 · 바로 읽어요"))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                case .sending:
                    ProgressView().controlSize(.mini)
                    Text("보내는 중…").font(.system(size: 9)).foregroundStyle(.secondary)
                case .sent:
                    Text("보냈어요 ✓").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x4E9A57))
                case .failed(let why):
                    Text(why).font(.system(size: 9)).foregroundStyle(Color(hex: 0xE04F3A)).lineLimit(2)
                    if Paths.sandboxed {
                        Button(t("전체 기능판 받기…")) { Paths.openFullEdition(); close() }
                            .buttonStyle(.plain).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0xE07A5F))
                    }
                }
                Spacer()
                if g != nil {
                    Button(t("창 앞으로")) { if let g = g { model.bringToFront(g) }; close() }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 320)
        .onAppear {
            focused = true
            if Paths.sandboxed { state = .failed(SessionMessenger.Failure.sandboxed.localizedDescription) }
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let g = model.snapshot.groups.first(where: { $0.id == groupID }) else { return }
        state = .sending
        model.send(t, to: g) { result in
            switch result {
            case .success:
                state = .sent
                text = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { close() }
            case .failure(let e):
                state = .failed(e.localizedDescription)
            }
        }
    }
}
