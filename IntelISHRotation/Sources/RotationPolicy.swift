// SPDX-License-Identifier: GPL-2.0-only
// HP Elite x2 mounting verified with IntelISH 0.7.0, 2026-10-08.
import Foundation

struct RotationPolicy {
    private var candidate: Int32?
    private var since: TimeInterval = 0

    mutating func reset() { candidate = nil }

    // Acceleration is in g. Ignore flat, shaking, and diagonal poses.
    // Confirm a stable edge for 0.6 s; caller retains orientation otherwise.
    mutating func update(x: Double, y: Double, z: Double, now: TimeInterval) -> Int32? {
        let magnitude = sqrt(x*x + y*y + z*z)
        let dominant = max(abs(x), abs(y))
        guard x.isFinite, y.isFinite, z.isFinite, (0.75...1.3).contains(magnitude),
              dominant > 0.65, dominant > abs(z) * 1.25,
              abs(abs(x) - abs(y)) > 0.2 else {
            reset(); return nil
        }
        let angle: Int32 = abs(y) > abs(x) ? (y < 0 ? 0 : 180) : (x > 0 ? 90 : 270)
        if candidate != angle { candidate = angle; since = now; return nil }
        return now - since >= 0.6 ? angle : nil
    }
}
