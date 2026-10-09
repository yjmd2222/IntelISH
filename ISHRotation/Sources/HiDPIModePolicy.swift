// SPDX-License-Identifier: GPL-2.0-only
import Foundation

struct HiDPIModeDescription {
    let width: Int, height: Int, pixelWidth: Int, pixelHeight: Int
    let refreshRate: Double
    var isHiDPI: Bool { width > 0 && height > 0 && pixelWidth >= width * 2 && pixelHeight >= height * 2 }
}
struct HiDPIModePolicy {
    static func choose(_ modes: [HiDPIModeDescription], longEdge: Int, shortEdge: Int,
                       portrait: Bool, refreshRate: Double) -> Int? {
        let width = portrait ? shortEdge : longEdge
        let height = portrait ? longEdge : shortEdge
        guard width > 0, height > 0 else { return nil }
        let candidates = modes.indices.filter { modes[$0].isHiDPI && modes[$0].width == width && modes[$0].height == height }
        return candidates.min { abs(modes[$0].refreshRate - refreshRate) < abs(modes[$1].refreshRate - refreshRate) }
    }
}
