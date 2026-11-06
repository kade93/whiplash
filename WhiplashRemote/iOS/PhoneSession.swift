import Foundation
import WatchConnectivity

/// Receives flicks from the Watch and hands them to the sender.
final class PhoneSession: NSObject, WCSessionDelegate, ObservableObject {
    @Published var watchReachable = false
    var onWatchFlick: ((Double) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.watchReachable = session.isReachable }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.watchReachable = session.isReachable }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let g = message["flick"] as? Double { DispatchQueue.main.async { self.onWatchFlick?(g) } }
    }
}
