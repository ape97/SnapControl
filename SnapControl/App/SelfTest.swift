import AppKit

/// Invisible self-test (scripts/check.sh): checks the core logic and writes the result as JSON.
/// Must not touch any window, focus, system settings or foreign processes – the user should notice nothing.
@MainActor
enum SelfTest {
    static func run(writingTo path: String) {
        var failures: [String] = []
        var report: [String: Any] = [:]
        report["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        if NSImage(systemSymbolName: AppModel.menuBarSymbol, accessibilityDescription: nil) == nil {
            failures.append("menu bar symbol missing: \(AppModel.menuBarSymbol)")
        }
        func expect(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { failures.append(message()) } }

        // Zones: gap-free, equal size (±1 pt rounding), row by row from the top left, area fully covered.
        let area = CGRect(x: 0, y: 25, width: 1512, height: 919)   // MacBook-like without the menu bar
        for (c, r) in [(2, 2), (4, 2), (3, 3), (4, 4), (1, 1), (8, 8), (7, 3)] {
            let g = GridSet(name: "t", columns: c, rows: r)
            let f = Zones.frames(g, in: area)
            expect(f.count == c * r, "\(c)×\(r): \(f.count) zones")
            let sum = f.reduce(0) { $0 + $1.width * $1.height }
            expect(abs(sum - area.width * area.height) < 0.5, "\(c)×\(r): zones cover \(sum) of \(area.width * area.height)")
            expect(f.allSatisfy { area.contains($0) }, "\(c)×\(r): zone outside area")
            let ws = f.map(\.width), hs = f.map(\.height)
            expect((ws.max()! - ws.min()!) <= 1 && (hs.max()! - hs.min()!) <= 1, "\(c)×\(r): unequal zones")
            expect(f.allSatisfy { $0.minX == $0.minX.rounded() && $0.minY == $0.minY.rounded() }, "\(c)×\(r): fractional edges")
            for i in f.indices {
                for j in f.indices where j > i { expect(!f[i].intersects(f[j]), "\(c)×\(r): zones \(i) and \(j) overlap") }
            }
            expect(f.first!.minX == area.minX && f.first!.maxY == area.maxY, "\(c)×\(r): first zone not top left")
            expect(f.last!.maxX == area.maxX && f.last!.minY == area.minY, "\(c)×\(r): last zone not bottom right")
        }
        let four = Zones.frames(GridSet(name: "t", columns: 2, rows: 2), in: area)
        expect(Zones.index(of: CGPoint(x: 10, y: 900), in: four) == 0, "top left point → zone 0")
        expect(Zones.index(of: CGPoint(x: 1500, y: 30), in: four) == 3, "bottom right point → zone 3")
        expect(Zones.index(of: CGPoint(x: 1500, y: 950), in: four) == 1, "point in menu bar → nearest zone 1")
        expect(Zones.index(of: CGPoint(x: 10, y: 0), in: four) == 2, "point in dock area → nearest zone 2")
        // Conversion to accessibility coordinates (top left): menu bar 25 pt → upper zone starts at y = 25.
        let ax = Zones.axRect(four[0], primaryHeight: 944)
        expect(ax.origin == CGPoint(x: 0, y: 0) && ax.size == four[0].size, "ax rect top left: \(ax)")
        let axBottom = Zones.axRect(four[3], primaryHeight: 944)
        expect(axBottom.maxY == 944 - 25, "ax rect bottom zone ends above dock area: \(axBottom)")
        report["zones3x3"] = Zones.frames(GridSet(name: "t", columns: 3, rows: 3), in: area).map { "\(Int($0.width))×\(Int($0.height))" }

        // Custom layouts: gap-free, no overlap, whole points, sizes by share, order as configured.
        func tiles(_ f: [CGRect], _ name: String) {
            let sum = f.reduce(0) { $0 + $1.width * $1.height }
            expect(abs(sum - area.width * area.height) < 0.5, "\(name): zones cover \(sum)")
            expect(f.allSatisfy { area.contains($0) && $0.minX == $0.minX.rounded() && $0.minY == $0.minY.rounded() },
                   "\(name): zone outside area or fractional")
            for i in f.indices {
                for j in f.indices where j > i { expect(!f[i].intersects(f[j]), "\(name): zones \(i) and \(j) overlap") }
            }
        }
        // 3 small windows on top, 3 large ones below (top = 1/3 of the height)
        let topThree = GridSet(name: "t", columns: 1, rows: 1, split: .rows,
                               strips: [Strip(size: 1, count: 3), Strip(size: 2, count: 3)])
        let tf = Zones.frames(topThree, in: area)
        tiles(tf, "rows 3+3")
        expect(tf.count == 6 && topThree.zoneCount == 6, "rows 3+3: \(tf.count) zones")
        expect(tf[0].maxY == area.maxY && tf[0].minX == area.minX && tf[2].maxX == area.maxX, "rows 3+3: first row on top, left to right")
        expect(abs(tf[0].height - area.height / 3) <= 1 && abs(tf[3].height - area.height * 2 / 3) <= 1,
               "rows 3+3: heights \(tf[0].height)/\(tf[3].height)")
        expect(tf[5].minY == area.minY && tf[5].maxX == area.maxX, "rows 3+3: last zone bottom right")
        expect(topThree.sizeLabel == "3 + 3 rows", "rows label: \(topThree.sizeLabel)")
        // Order swapped: large row on top
        var flipped = topThree
        flipped.strips!.swapAt(0, 1)
        let ff = Zones.frames(flipped, in: area)
        expect(ff[0].maxY == area.maxY && abs(ff[0].height - area.height * 2 / 3) <= 1, "swapped rows: large row on top")
        // Two windows side by side, two small ones stacked on the right
        let sideBySide = GridSet(name: "t", columns: 1, rows: 1, split: .columns,
                                 strips: [Strip(count: 1), Strip(count: 1), Strip(count: 2)])
        let sf = Zones.frames(sideBySide, in: area)
        tiles(sf, "columns 1+1+2")
        expect(sf.count == 4, "columns 1+1+2: \(sf.count) zones")
        expect(sf[0].height == area.height && sf[1].height == area.height && sf[0].maxX == sf[1].minX, "columns 1+1+2: two full-height windows")
        expect(sf[2].maxY == area.maxY && sf[3].minY == area.minY && sf[2].minY == sf[3].maxY && sf[2].minX == sf[1].maxX,
               "columns 1+1+2: third column split top/bottom")
        expect(abs(sf[0].width - area.width / 3) <= 1, "columns 1+1+2: equal widths")
        report["zonesCustom"] = tf.map { "\(Int($0.width))×\(Int($0.height))" }
        // An even grid computed as a layout yields the same zones
        let asRows = GridSet(name: "t", columns: 1, rows: 1, split: .rows, strips: Array(repeating: Strip(count: 4), count: 3))
        expect(Zones.frames(asRows, in: area) == Zones.frames(GridSet(name: "t", columns: 4, rows: 3), in: area),
               "equal rows layout matches 4×3 grid")

        // Storage: own test domain, never the user's list.
        let store = GridStore(defaults: AppModel.scratchDefaults())
        expect(store.loadSets() == GridSet.defaults, "empty store → defaults")
        let mine = [GridSet(name: "Wide", columns: 6, rows: 1), GridSet(name: "Broken", columns: 0, rows: 99)]
        store.save(sets: mine)
        let loaded = store.loadSets()
        expect(loaded.count == 2 && loaded[0] == mine[0], "sets round trip")
        expect(loaded[1].columns == 1 && loaded[1].rows == 8, "out-of-range grid clamped: \(loaded[1])")
        // Save a custom layout, clamp corrupted values, keep reading an old list without a layout
        let broken = GridSet(name: "B", columns: 2, rows: 2, split: nil,
                             strips: [Strip(size: 0, count: 0), Strip(size: 9, count: 99)] + Array(repeating: Strip(count: 1), count: 6))
        store.save(sets: [topThree, sideBySide, broken, GridSet(name: "E", columns: 2, rows: 2, split: .columns, strips: [])])
        let customs = store.loadSets()
        expect(customs.count == 4 && customs[0] == topThree && customs[1] == sideBySide, "custom layouts round trip")
        expect(customs[2].split == .rows && customs[2].strips?.count == 6 && customs[2].strips?[0] == Strip(size: 1, count: 1)
               && customs[2].strips?[1] == Strip(size: 4, count: 8), "custom layout clamped: \(customs[2])")
        expect(customs[3].isEqual && customs[3].split == nil, "empty layout → equal grid")
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","columns":3,"rows":2}]"#
        store.defaults.set(Data(old.utf8), forKey: "sets")
        let oldSets = store.loadSets()
        expect(oldSets.count == 1 && oldSets[0].isEqual && oldSets[0].zoneCount == 6, "old saved list still loads: \(oldSets)")
        store.save(active: mine[0])
        expect(store.loadActive() == mine[0], "active round trip")
        store.save(active: nil)
        expect(store.loadActive() == nil, "deactivate clears active")
        store.key = .option
        expect(store.key == .option, "snap key round trip")
        store.defaults.set(Data("x".utf8), forKey: "sets")
        expect(store.loadSets() == GridSet.defaults, "corrupt list → defaults")

        // macOS snapping: only on its own test domain, never com.apple.WindowManager.
        let wmName = "io.github.ape97.snapcontrol.test.wm"
        UserDefaults(suiteName: wmName)!.removePersistentDomain(forName: wmName)
        let wm = UserDefaults(suiteName: wmName)!
        wm.set(true, forKey: "EnableTilingByEdgeDrag")
        wm.set(false, forKey: "EnableTopTilingByEdgeDrag")
        wm.synchronize()
        let tiling = MacTiling(domain: wmName, store: GridStore(defaults: AppModel.scratchDefaults()))
        tiling.disable()
        expect(MacTiling.keys.allSatisfy { tiling.read($0) == false } && tiling.isDisabled, "tiling disabled")
        let written = tiling.store.tilingWrittenAt
        expect(written != nil, "tiling write time")
        tiling.disable()   // a second call must not overwrite the saved values
        expect(tiling.store.tilingWrittenAt == written, "tiling unchanged keeps write time")
        tiling.restore()
        expect(tiling.read("EnableTilingByEdgeDrag") == true && tiling.read("EnableTopTilingByEdgeDrag") == false
               && tiling.read("EnableTilingOptionAccelerator") == nil && !tiling.isDisabled, "tiling restored")
        UserDefaults(suiteName: wmName)!.removePersistentDomain(forName: wmName)

        // Model (storage in the test domain, no monitors in the test run): on/off, switch, save, delete.
        let model = AppModel.shared
        let nine = model.sets.first { $0.isEqual && $0.columns == 3 && $0.rows == 3 }!
        model.toggle(nine)
        expect(model.active == nine, "tap activates")
        model.toggle(nine)
        expect(model.active == nil, "second tap deactivates")
        model.setEnabled(true)
        expect(model.active == nine, "switch restores last grid")
        let custom = GridSet(name: "My 5", columns: 5, rows: 1)
        model.save(custom)
        model.activate(custom)
        expect(model.sets.last == custom && model.active == custom, "save + activate")
        var renamed = custom
        renamed.name = "Five"
        model.save(renamed)
        expect(model.sets.filter { $0.id == custom.id }.count == 1 && model.active?.name == "Five", "edit replaces, active follows")
        model.delete(renamed)
        expect(model.active == nil && !model.sets.contains { $0.id == custom.id }, "delete removes and deactivates")
        model.setEnabled(true)
        expect(model.active == model.sets.first, "switch after deleted last grid → first set")
        model.deactivate()
        let order = model.sets.map(\.id)
        model.move(model.sets[0], by: 1)
        expect(model.sets.map(\.id) == [order[1], order[0]] + order.dropFirst(2), "move down swaps")
        model.move(model.sets[0], by: -1)
        expect(model.sets.map(\.id) == [order[1], order[0]] + order.dropFirst(2), "move above first is ignored")
        model.move(model.sets[1], by: -1)
        expect(model.sets.map(\.id) == order, "move up restores")

        // Draw the overlay (invisible, without a window) – an image to look at next to the result.
        let view = ZoneView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        view.zones = Zones.frames(nine, in: CGRect(x: 0, y: 0, width: 1512, height: 957))
        view.highlighted = 4
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let png = (path as NSString).deletingLastPathComponent + "/overlay.png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: png))
        }

        report["accessibility"] = WindowAX.isTrusted

        report["ok"] = failures.isEmpty
        report["failures"] = failures
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
