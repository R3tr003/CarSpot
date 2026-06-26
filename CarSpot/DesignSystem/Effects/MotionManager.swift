import SwiftUI
import CoreMotion

/// Streams a normalized device tilt (-1...1 on each axis) used to drive the
/// holographic foil and parallax. Gracefully no-ops where motion is unavailable
/// (e.g. previews / simulator without sensors) so the UI still renders.
@MainActor
@Observable
final class MotionManager {
    private(set) var roll: Double = 0   // left/right tilt, -1...1
    private(set) var pitch: Double = 0  // forward/back tilt, -1...1

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = max(-1, min(1, motion.attitude.roll / 0.9))
            let p = max(-1, min(1, motion.attitude.pitch / 0.9))
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                self.roll = r
                self.pitch = p
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
