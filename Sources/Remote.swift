import AppKit
import Network

// MARK: - 리모트 수신부 (아이폰·애플워치)
// 같은 Wi‑Fi 의 아이폰 앱(WhiplashRemote)이 Bonjour 로 이 맥을 찾아 UDP 로 한 줄을 보낸다:
//   "whipall"            쉬는 애 전부 채찍
//   "whip"               쉬는 애 아무나
//   "flick <세기>"        손목 스냅 (세기 = g 단위, 기록용)
//   "ping"               연결 확인 → "pong" 으로 답한다
// 포트 47777, 서비스 _whiplash._udp. 켤 때만 듣는다. 같은 네트워크 안에서만 닿는다.

final class RemoteReceiver {
    var onCommand: ((String, Double) -> Void)?   // 명령, 세기
    private(set) var running = false
    private(set) var status = ""
    private(set) var lastSender = ""
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "kr.urbanism.whiplash.remote")
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
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let d = data, let line = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                let parts = line.split(separator: " ")
                let cmd = String(parts[0]).lowercased()
                let strength = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
                if case .hostPort(let host, _) = conn.endpoint { self.lastSender = "\(host)" }
                if cmd == "ping" {
                    conn.send(content: "pong\n".data(using: .utf8), completion: .contentProcessed { _ in })
                } else {
                    DispatchQueue.main.async { self.onCommand?(cmd, strength) }
                }
            }
            if error == nil { self.receive(conn) } else { conn.cancel() }
        }
    }
}
