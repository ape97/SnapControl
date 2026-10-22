import AppKit

/// Direction of a custom layout: rows (top → bottom) or columns (left → right).
enum Split: String, Codable, CaseIterable {
    case rows, columns
}

/// One strip of a custom layout: share of the height or width (1×…4×) and the number of windows in it.
struct Strip: Codable, Hashable {
    var size = 1
    var count: Int

    static let sizeRange = 1...4
}

/// A grid: name, columns × rows. Saved sets and the currently active grid have this shape.
/// With `strips` it is a custom layout (e.g. 3 small windows on top, 3 large ones below); `columns`/`rows` then only
/// remain as the starting value for an even grid. Old saved lists without `strips` load unchanged.
struct GridSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var columns: Int
    var rows: Int
    var split: Split?
    var strips: [Strip]?

    static let range = 1...8
    /// Maximum number of strips in a custom layout.
    static let stripRange = 1...6
    /// Name of a custom, unsaved grid.
    static let customName = "Custom"

    /// Defaults: 4, 8, 9 and 16 equally sized zones.
    static let defaults: [GridSet] = [
        GridSet(name: "2 × 2", columns: 2, rows: 2),
        GridSet(name: "4 × 2", columns: 4, rows: 2),
        GridSet(name: "3 × 3", columns: 3, rows: 3),
        GridSet(name: "4 × 4", columns: 4, rows: 4),
    ]

    var isEqual: Bool { strips == nil }

    /// Layout in order; an even grid is `rows` equally tall rows with `columns` windows each.
    var layout: (split: Split, strips: [Strip]) {
        if let strips { return (split ?? .rows, strips) }
        return (.rows, Array(repeating: Strip(count: columns), count: rows))
    }

    var zoneCount: Int { layout.strips.reduce(0) { $0 + $1.count } }
    var sizeLabel: String {
        guard let strips else { return "\(columns) × \(rows)" }
        return strips.map { "\($0.count)" }.joined(separator: " + ") + " " + (split ?? .rows).rawValue
    }
    var detail: String { "\(sizeLabel) · \(zoneCount) \(zoneCount == 1 ? "zone" : "zones")" }

    /// Clamp out-of-range values (e.g. from a corrupted list) to what is allowed.
    var clamped: GridSet {
        var g = self
        g.columns = min(max(columns, Self.range.lowerBound), Self.range.upperBound)
        g.rows = min(max(rows, Self.range.lowerBound), Self.range.upperBound)
        if let strips, !strips.isEmpty {
            g.split = split ?? .rows
            g.strips = strips.prefix(Self.stripRange.upperBound).map {
                Strip(size: min(max($0.size, Strip.sizeRange.lowerBound), Strip.sizeRange.upperBound),
                      count: min(max($0.count, Self.range.lowerBound), Self.range.upperBound))
            }
        } else {
            g.split = nil
            g.strips = nil
        }
        return g
    }
}

/// Zones of a grid on an area (Cocoa coordinates, origin bottom left).
/// Order is row by row from the top left, for column layouts column by column from the top left. Edges are rounded to whole points so neighbouring zones join without gaps.
enum Zones {
    static func frames(_ grid: GridSet, in area: CGRect) -> [CGRect] {
        let (split, strips) = grid.layout
        var out: [CGRect] = []
        out.reserveCapacity(grid.zoneCount)
        switch split {
        case .rows:
            // Row 0 = top: edges run upward from minY, so weights go from bottom to top
            let ys = edges(from: area.minY, length: area.height, weights: strips.reversed().map(\.size))
            for (row, strip) in strips.enumerated() {
                let top = ys[strips.count - row], bottom = ys[strips.count - row - 1]
                let xs = edges(from: area.minX, length: area.width, weights: Array(repeating: 1, count: strip.count))
                for col in 0..<strip.count {
                    out.append(CGRect(x: xs[col], y: bottom, width: xs[col + 1] - xs[col], height: top - bottom))
                }
            }
        case .columns:
            // Column by column from the left, top to bottom within each
            let xs = edges(from: area.minX, length: area.width, weights: strips.map(\.size))
            for (col, strip) in strips.enumerated() {
                let ys = edges(from: area.minY, length: area.height, weights: Array(repeating: 1, count: strip.count))
                for row in 0..<strip.count {
                    let top = ys[strip.count - row], bottom = ys[strip.count - row - 1]
                    out.append(CGRect(x: xs[col], y: bottom, width: xs[col + 1] - xs[col], height: top - bottom))
                }
            }
        }
        return out
    }

    /// Index of the zone under the point; if it lies outside (menu bar, Dock), the nearest zone counts.
    static func index(of point: CGPoint, in frames: [CGRect]) -> Int? {
        if let i = frames.firstIndex(where: { $0.contains(point) }) { return i }
        return frames.indices.min { distance(point, frames[$0]) < distance(point, frames[$1]) }
    }

    /// Cocoa rect (bottom left, global) → accessibility screen coordinates (top left of the main display).
    static func axRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Edges by share; rounded to whole points, the last one exactly at the edge.
    private static func edges(from start: CGFloat, length: CGFloat, weights: [Int]) -> [CGFloat] {
        let total = CGFloat(max(weights.reduce(0, +), 1))
        var sum = 0, out = [start]
        for (i, w) in weights.enumerated() {
            sum += w
            out.append(i == weights.count - 1 ? start + length : (start + length * CGFloat(sum) / total).rounded())
        }
        return out
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}

/// Key that shows the zones while a window is being dragged.
enum SnapKey: String, Codable, CaseIterable {
    case control, option, command, shift

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .command: .command
        case .shift: .shift
        }
    }

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }

    var title: String { "\(symbol) \(rawValue.capitalized)" }
}

/// Sets, active grid and key in UserDefaults (JSON). If the list is missing or unreadable, the defaults apply.
struct GridStore {
    var defaults: UserDefaults

    func loadSets() -> [GridSet] {
        guard let data = defaults.data(forKey: "sets"), let list = try? JSONDecoder().decode([GridSet].self, from: data)
        else { return GridSet.defaults }
        return list.map(\.clamped)
    }

    func save(sets: [GridSet]) {
        if let data = try? JSONEncoder().encode(sets) { defaults.set(data, forKey: "sets") }
    }

    func loadActive() -> GridSet? {
        defaults.data(forKey: "active").flatMap { try? JSONDecoder().decode(GridSet.self, from: $0) }?.clamped
    }

    func save(active: GridSet?) {
        if let active, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: "active")
        } else {
            defaults.removeObject(forKey: "active")
        }
    }

    /// Last used grid: the switch at the top turns it back on.
    func loadLast() -> GridSet? {
        defaults.data(forKey: "last").flatMap { try? JSONDecoder().decode(GridSet.self, from: $0) }?.clamped
    }

    func save(last: GridSet) {
        if let data = try? JSONEncoder().encode(last) { defaults.set(data, forKey: "last") }
    }

    var key: SnapKey {
        get { defaults.string(forKey: "snapKey").flatMap(SnapKey.init) ?? .control }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "snapKey") }
    }

    /// Saved macOS values for the built-in snapping (nil = nothing switched off). See `MacTiling`.
    var savedTiling: [String: Bool]? {
        get { defaults.dictionary(forKey: "savedTiling") as? [String: Bool] }
        nonmutating set { defaults.set(newValue, forKey: "savedTiling") }
    }

    /// When the macOS values were last changed – WindowManager must have started after that to know them.
    var tilingWrittenAt: Date? {
        get { defaults.object(forKey: "tilingWrittenAt") as? Date }
        nonmutating set { defaults.set(newValue, forKey: "tilingWrittenAt") }
    }
}
