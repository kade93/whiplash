import AppKit
import AVFoundation
import Vision

// MARK: - 카메라 손 휘두르기
// 맥 카메라 영상에서 Vision 으로 손 관절을 잡아, 손목이 0.35초 안에 화면 폭의 30% 이상 가로로 지나가면 채찍.
// 켤 때만 카메라를 열고(권한 한 번), 15fps 로 돌린다. 영상은 저장하지 않고 손 위치만 본다.

final class HandSwing: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onSwing: ((Double) -> Void)?          // 세기 (화면 폭 대비 이동량)
    private(set) var running = false
    private(set) var status = ""
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kr.urbanism.whiplash.handcam", qos: .userInitiated)
    private var trail: [(t: TimeInterval, x: Double)] = []
    private var cooldownUntil: TimeInterval = 0
    private var frames = 0

    static let window: TimeInterval = 0.35
    static let distance = 0.30                 // 화면 폭 대비
    static let cooldown: TimeInterval = 2.0

    func start() {
        guard !running else { return }
        running = true
        status = t("Checking camera permission…")
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.running else { return }                    // 그새 껐으면
                guard ok else { self.status = t("Camera access denied — System Settings › Privacy › Camera"); self.running = false; return }
                self.open()
            }
        }
    }

    private func open() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            status = t("Couldn't open the camera"); running = false; return
        }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        // 15fps 면 충분하고 배터리도 덜 먹는다
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()
        }
        status = t("Watching the camera — swing your hand sideways")
        queue.async { [weak self] in self?.session.startRunning() }
    }

    func stop() {
        guard running else { return }
        running = false
        status = ""
        queue.async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            for i in self.session.inputs { self.session.removeInput(i) }
            for o in self.session.outputs { self.session.removeOutput(o) }
        }
    }

    private lazy var request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard running else { return }
        frames += 1
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let hand = request.results?.first,
              let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.3 else {
            if frames % 15 == 0 { trail.removeAll() }                     // 손이 사라지면 잊는다
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        trail.append((now, Double(wrist.location.x)))
        trail.removeAll { now - $0.t > Self.window }
        guard now >= cooldownUntil, let first = trail.first else { return }
        let dx = abs(trail.last!.x - first.x)
        if dx >= Self.distance {
            cooldownUntil = now + Self.cooldown
            trail.removeAll()
            DispatchQueue.main.async { [weak self] in self?.onSwing?(dx) }
        }
    }
}
