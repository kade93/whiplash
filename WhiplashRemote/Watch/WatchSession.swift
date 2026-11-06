import Foundation
import WatchConnectivity

/// Sends wrist snaps to the phone, which relays them to the Mac.
final class WatchSession: NSObject, WCSessionDelegate, ObservableObject {
    @Published var phoneReachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.phoneReachable = session.isReachable }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.phoneReachable = session.isReachable }
    }

    func sendFlick(_ g: Double) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["flick": g], replyHandler: nil, errorHandler: nil)
    }
}
