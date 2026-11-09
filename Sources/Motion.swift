import AppKit
import CoreMotion

// MARK: - 에어팟 고개 휙
// macOS 14+ 는 에어팟(Pro·3세대·Max·Beats Fit Pro)의 머리 움직임 센서를 앱이 읽을 수 있다.
// 귀에 꽂고 고개를 휙 돌리면(각속도가 문턱을 넘으면) 쉬는 애 전부 채찍. 켤 때만 센서를 읽고, 끄면 바로 멈춘다.

@available(macOS 14.0, *)
final class HeadFlick {
    var onFlick: ((Double) -> Void)?           // 세기 (rad/s)
    private(set) var running = false
    private(set) var status = ""               // 메뉴에 보여 줄 한 줄
    private let manager = CMHeadphoneMotionManager()
    private var cooldownUntil: TimeInterval = 0

    static let threshold = 5.5                 // rad/s — 고개를 "휙" 돌릴 때 보통 6~10, 평소 끄덕임은 2 안팎
    static let cooldown: TimeInterval = 1.5

    var available: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard !running else { return }
        guard manager.isDeviceMotionAvailable else { status = t("No AirPods with motion sensors connected"); return }
        running = true
        status = t("Waiting for AirPods…")
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            if let error = error { self.status = error.localizedDescription; return }
            guard let m = motion else { return }
            let r = m.rotationRate
            let speed = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            if self.status != t("Listening to AirPods") { self.status = t("Listening to AirPods") }
            let now = ProcessInfo.processInfo.systemUptime
            if speed >= Self.threshold, now >= self.cooldownUntil {
                self.cooldownUntil = now + Self.cooldown
                self.onFlick?(speed)
            }
        }
    }

    func stop() {
        guard running else { return }
        manager.stopDeviceMotionUpdates()
        running = false
        status = ""
    }
}
