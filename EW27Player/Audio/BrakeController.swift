import Foundation

@MainActor
final class BrakeController: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable { case off = "Off", short = "Short", long = "Long"; var id: String { rawValue } }
    @Published var mode: Mode = .off
    @Published private(set) var factor: Float = 1
    private var timer: Timer?

    func rampDown(completion: @escaping () -> Void) {
        guard mode != .off else { factor = 1; completion(); return }
        ramp(to: 1.0 / 32.0, duration: mode == .short ? 0.7 : 1.5, completion: completion)
    }

    func rampUp() {
        guard mode != .off else { factor = 1; return }
        ramp(to: 1, duration: 0.5, completion: nil)
    }

    private func ramp(to target: Float, duration: TimeInterval, completion: (() -> Void)?) {
        timer?.invalidate()
        let start = factor
        let started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, Date().timeIntervalSince(started) / duration)
            self.factor = start + (target - start) * Float(progress * progress * (3 - 2 * progress))
            if progress >= 1 { timer.invalidate(); self.timer = nil; completion?() }
        }
    }
}
