import AppKit
import Network

// MARK: - 리모트 수신부 (아이폰·애플워치)
// 같은 Wi‑Fi 의 아이폰 앱(WhiplashRemote)이 Bonjour 로 이 맥을 찾아 UDP 로 한 줄을 보낸다:
//   "whipall"            쉬는 애 전부 채찍                       → "ok whipped 3" / "ok nobody to whip"
//   "whip"               쉬는 애 아무나                          → "ok whipped <이름>"
//   "whip <id>"          그 애만                                 → "ok whipped <이름>"
//   "treatall"           일하는 애 전부 간식                     → "ok treated 2"
//   "treat <id>"         그 애만 간식                            → "ok treated <이름>"
//   "list"               세션 목록 → "list" 줄 뒤에 한 줄씩  <id>\t<이름>\t<상태>\t<종류>  (상태: working/resting/waiting/strike)
//   "flick <세기>"        손목 스냅 (세기 = g 단위, 기록용)        → 답 없음
//   "ping"               연결 확인 → "pong"
// 포트 47777, 서비스 _whiplash._udp. 켤 때만 듣는다. 같은 네트워크 안에서만 닿는다.

final class RemoteReceiver {
    var onCommand: ((String, String) -> String?)?   // (명령, 인자) → 답 한 줄 (nil 이면 답 없음). 메인 스레드에서 불린다
    private(set) var running = false
    private(set) var status = ""
    private(set) var lastSender = ""
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]     // queue 에서만 만진다
    private let queue = DispatchQueue(label: "com.kade.whiplash.remote")
    static let port: UInt16 = 47777
    static let service = "_whiplash._udp"

    func start() {
        guard !running else { return }
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.service = NWListener.Service(name: Host.current().localizedName ?? "Whiplash", type: Self.service)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.status = tf("Listening for remotes (port %d)", Int(Self.port))
                    case .failed(let e): self?.status = e.localizedDescription; self?.running = false
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.start(queue: queue)
            listener = l
            running = true
            status = t("Starting remote…")
        } catch {
            status = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        running = false; status = ""
        queue.async { [weak self] in                     // 이미 붙어 있던 리모트도 끊는다 (끄면 정말 꺼지게)
            guard let self = self else { return }
            for c in self.connections.values { c.cancel() }
            self.connections = [:]
        }
    }

    private func accept(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        connections[key] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections[key] = nil
            default: break
            }
        }
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let d = data, let line = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                let cmd = line.split(separator: " ", maxSplits: 1).first.map { String($0).lowercased() } ?? ""
                let arg = line.split(separator: " ", maxSplits: 1).count > 1 ? String(line.split(separator: " ", maxSplits: 1)[1]) : ""
                if case .hostPort(let host, _) = conn.endpoint { self.lastSender = "\(host)" }
                if cmd == "ping" {      // (receive 는 queue 에서 돈다)
                    conn.send(content: "pong\n".data(using: .utf8), completion: .contentProcessed { _ in })
                } else {
                    DispatchQueue.main.async {
                        guard self.running, let reply = self.onCommand?(cmd, arg) else { return }   // 꺼진 뒤에 도착한 명령은 버린다
                        conn.send(content: (reply + "\n").data(using: .utf8), completion: .contentProcessed { _ in })
                    }
                }
            }
            if error == nil { self.receive(conn) } else { conn.cancel() }
        }
    }
}
