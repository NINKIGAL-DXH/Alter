import Foundation

public struct LensBubble: Identifiable, Sendable {
    public let id: String, name: String
    public let bytes: Int64
    public let directory: Bool, remainder: Bool
    public let x: Double, y: Double, radius: Double
}

/// Tangent circle packing. A single scale is applied to sqrt(bytes), so areas
/// remain proportional; tiny entries are grouped rather than artificially enlarged.
public enum LensLayout {
    public static func pack(_ input: [DiskEntry]) -> [LensBubble] {
        let sorted = input.filter { $0.size > 0 }.sorted { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }
        guard let largest = sorted.first else { return [] }
        let visible = Array(sorted.prefix(22).prefix { Double($0.size) / Double(largest.size) >= 0.003 })
        var items = visible.map { ($0.path, $0.name, $0.size, $0.isDir, false) }
        let rest = sorted.dropFirst(visible.count).reduce(Int64(0)) { value, entry in
            let sum = value.addingReportingOverflow(entry.size); return sum.overflow ? Int64.max : sum.partialValue
        }
        if rest > 0 { items.append(("alter:remainder", "其他项目", rest, false, true)) }
        items.sort { $0.2 > $1.2 }
        struct Circle { var x: Double, y: Double, r: Double }
        var placed: [Circle] = []
        for item in items {
            let radius = sqrt(Double(item.2) / Double(items[0].2))
            if placed.isEmpty { placed.append(Circle(x: 0, y: 0, r: radius)); continue }
            var best: Circle?
            var score = Double.infinity
            func consider(_ x: Double, _ y: Double) {
                let candidate = Circle(x: x, y: y, r: radius)
                guard placed.allSatisfy({ hypot(x - $0.x, y - $0.y) + 0.0000001 >= radius + $0.r + 0.015 }) else { return }
                let cost = hypot(x, y) + radius
                if cost < score { score = cost; best = candidate }
            }
            // Angular candidates ensure a solution even for one existing circle.
            for anchor in placed {
                for step in 0..<72 {
                    let angle = Double(step) * .pi / 36
                    let d = radius + anchor.r + 0.016
                    consider(anchor.x + cos(angle) * d, anchor.y + sin(angle) * d)
                }
            }
            if let best { placed.append(best) }
            else {
                let right = placed.map { $0.x + $0.r }.max() ?? 0
                placed.append(Circle(x: right + radius + 0.016, y: 0, r: radius))
            }
        }
        let minX = placed.map { $0.x - $0.r }.min()!, maxX = placed.map { $0.x + $0.r }.max()!
        let minY = placed.map { $0.y - $0.r }.min()!, maxY = placed.map { $0.y + $0.r }.max()!
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        let extent = placed.map { hypot($0.x - centerX, $0.y - centerY) + $0.r }.max()!
        return zip(items, placed).map { item, c in
            LensBubble(id: item.0, name: item.1, bytes: item.2, directory: item.3, remainder: item.4,
                       x: (c.x - centerX) / extent, y: (c.y - centerY) / extent, radius: c.r / extent)
        }
    }
}
