import Foundation
func stable(_ x: Double, _ y: Double, _ z: Double, _ expected: Int32) {
    var policy = RotationPolicy()
    assert(policy.update(x: x, y: y, z: z, now: 0) == nil)
    assert(policy.update(x: x, y: y, z: z, now: 0.5) == nil)
    assert(policy.update(x: x, y: y, z: z, now: 0.7) == expected)
}
// Confirmed sensor captures and inferred opposite edge signs.
stable(-0.065, -0.962, -0.327, 0)
stable(0.888, -0.042, -0.342, 90)
stable(0, 1, 0, 180)
stable(-1, 0, 0, 270)
var policy = RotationPolicy()
assert(policy.update(x: 0, y: -1, z: 0, now: 0) == nil)
assert(policy.update(x: -0.054, y: -0.011, z: -1.027, now: 1) == nil) // Flat breaks stability.
assert(policy.update(x: 0, y: -1, z: 0, now: 2) == nil)
assert(policy.update(x: 0.7, y: 0.7, z: 0, now: 3) == nil) // Diagonal.
assert(policy.update(x: 2, y: 0, z: 0, now: 4) == nil) // Shaking.
assert(policy.update(x: Double.nan, y: 0, z: 0, now: 5) == nil)
assert(policy.update(x: 0, y: -1, z: 0, now: 6) == nil)
assert(policy.update(x: 0, y: -1, z: 0, now: 6.7) == 0)
print("Rotation policy: calibrated poses, stability, flat/diagonal/shaking rejection passed")

let modes = [
    HiDPIModeDescription(width: 1824, height: 2736, pixelWidth: 1824, pixelHeight: 2736, refreshRate: 60),
    HiDPIModeDescription(width: 912, height: 1368, pixelWidth: 1824, pixelHeight: 2736, refreshRate: 40),
    HiDPIModeDescription(width: 912, height: 1368, pixelWidth: 1824, pixelHeight: 2736, refreshRate: 60),
    HiDPIModeDescription(width: 1368, height: 912, pixelWidth: 2736, pixelHeight: 1824, refreshRate: 60)]
assert(HiDPIModePolicy.choose(modes, longEdge: 1368, shortEdge: 912, portrait: true, refreshRate: 60) == 2)
assert(HiDPIModePolicy.choose(modes, longEdge: 1368, shortEdge: 912, portrait: false, refreshRate: 60) == 3)
assert(HiDPIModePolicy.choose(modes, longEdge: 1368, shortEdge: 912, portrait: true, refreshRate: 40) == 1)
assert(HiDPIModePolicy.choose([modes[0]], longEdge: 2736, shortEdge: 1824, portrait: true, refreshRate: 60) == nil)
assert(HiDPIModePolicy.choose(modes, longEdge: 0, shortEdge: 0, portrait: true, refreshRate: 60) == nil)
print("HiDPI selection: orientation, refresh matching, native1x rejection and absent-size cases passed")
