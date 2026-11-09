import AppKit
import AVFoundation

// MARK: - 입으로 「화츅!」
// 마이크를 열어 두고(켤 때만) 짧고 큰 파열음을 잡는다: 조용하다가 50ms 안에 음량이 확 뛰면 채찍.
// 말소리처럼 서서히 커지는 소리는 안 잡힌다. 녹음·저장은 없고 음량(RMS)만 본다.

final class MouthWhip {
    var onCrack: ((Double) -> Void)?           // 세기 (dB)
    private(set) var running = false
    private(set) var status = ""
    private let engine = AVAudioEngine()
    private var history: [(t: TimeInterval, db: Double)] = []
    private var cooldownUntil: TimeInterval = 0

    static let loud = -14.0                    // dBFS — 이 위면 "크다"
    static let quiet = -34.0                   // dBFS — 직전 0.3초 동안 이 아래였어야 (조용하다가 터지는 소리)
    static let cooldown: TimeInterval = 1.5

    func start() {
        guard !running else { return }
        running = true
        status = t("Checking microphone permission…")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self = self, self.running else { return }
                guard ok else { self.status = t("Microphone access denied — System Settings › Privacy › Microphone"); self.running = false; return }
                self.open()
            }
        }
    }

    private func open() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { status = t("Couldn't open the microphone"); running = false; return }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self = self, let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            let db = Double(20 * log10(max(rms, 1e-6)))
            self.observe(db)
        }
        do {
            try engine.start()
            status = t("Listening — go \"whoosh-crack!\"")
        } catch {
            status = error.localizedDescription; running = false
        }
    }

    private func observe(_ db: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        history.append((now, db))
        history.removeAll { now - $0.t > 0.35 }
        guard db >= Self.loud, now >= cooldownUntil else { return }
        // 직전 0.05~0.35초가 조용했나 (서서히 커진 말소리는 제외)
        let before = history.filter { now - $0.t > 0.05 }
        guard !before.isEmpty, before.allSatisfy({ $0.db < Self.quiet }) else { return }
        cooldownUntil = now + Self.cooldown
        history.removeAll()
        DispatchQueue.main.async { [weak self] in self?.onCrack?(db) }
    }

    func stop() {
        guard running else { return }
        running = false
        status = ""
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
