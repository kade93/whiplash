import Foundation
import CoreMotion

/// Wrist / phone flick detector. A whip crack is a sharp acceleration spike followed by a stop:
/// user acceleration (gravity removed) above `threshold` g, then quiet within 150 ms.
final class Flick: ObservableObject {
    @Published var armed = false
    @Published var lastStrength: Double = 0
    var onFlick: ((Double) -> Void)?

    static let threshold = 2.0          // g — a deliberate snap; walking is ~0.3, a shake ~1.5 (was 2.6; missed real wrists)
    static let cooldown: TimeInterval = 0.9

    private let motion = CMMotionManager()
    private var peak = 0.0
    private var peakAt: TimeInterval = 0
    private var cooldownUntil: TimeInterval = 0

    var available: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self = self, let m = m else { return }
            let a = m.userAcceleration
            let g = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let now = ProcessInfo.processInfo.systemUptime
            if g > self.peak { self.peak = g; self.peakAt = now }
            // the crack: a peak over threshold, then the hand stops (acceleration back under 1.0 g within 250 ms)
            if self.peak >= Self.threshold, g < 1.0, now - self.peakAt < 0.25, now >= self.cooldownUntil {
                self.cooldownUntil = now + Self.cooldown
                self.lastStrength = self.peak
                self.onFlick?(self.peak)
                self.peak = 0
            }
            if now - self.peakAt > 0.4 { self.peak = 0 }
        }
        armed = true
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        armed = false
    }
}
