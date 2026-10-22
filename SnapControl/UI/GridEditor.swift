import SwiftUI

/// Third page: create or change a grid – name and layout. Saving puts it into the list.
/// "Equal" = equally sized zones (columns × rows); "Rows"/"Columns" = custom strips with size and window count,
/// order via arrows (rows top → bottom, columns left → right).
struct GridEditor: View {
    @Environment(AppModel.self) private var model
    let original: GridSet?
    let done: () -> Void
    @State private var draft: GridSet

    private enum Mode: String, CaseIterable {
        case equal = "Equal", rows = "Rows", columns = "Columns"
    }

    init(original: GridSet?, done: @escaping () -> Void) {
        self.original = original
        self.done = done
        var start = original ?? GridSet(name: "", columns: 3, rows: 3)
        // Snapshot of the custom layout: 3 small windows on top, 3 large ones below
        if original == nil, Runtime.arguments.contains("--editor-custom") {
            start.split = .rows
            start.strips = [Strip(size: 1, count: 3), Strip(size: 2, count: 3)]
        }
        _draft = State(initialValue: start)
    }

    private var mode: Binding<Mode> {
        Binding {
            guard draft.strips != nil else { return .equal }
            return draft.split == .columns ? .columns : .rows
        } set: { new in
            switch new {
            case .equal:
                draft.split = nil
                draft.strips = nil
            case .rows, .columns:
                let split: Split = new == .rows ? .rows : .columns
                // Start from the even grid with its layout; custom strips keep only the direction
                if draft.strips == nil {
                    draft.strips = split == .rows
                        ? Array(repeating: Strip(count: draft.columns), count: draft.rows)
                        : Array(repeating: Strip(count: draft.rows), count: draft.columns)
                }
                draft.split = split
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundIconButton(symbol: "chevron.left", size: 24, help: "Back", action: done)
                Text(original == nil ? "New Grid" : "Edit Grid").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 2)

            Module(spacing: 10) {
                HStack {
                    SettingLabel(symbol: "character.cursor.ibeam", title: "Name", tint: .gray)
                    Spacer(minLength: 12)
                    TextField("Name", text: $draft.name, prompt: Text(draft.sizeLabel))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 180)
                        .help("Name in the list; empty uses the size")
                }
                HStack(alignment: .top, spacing: 14) {
                    GridGlyph(grid: draft, active: true)
                        .frame(width: 112, height: 70)
                    VStack(spacing: 8) {
                        Picker("Layout", selection: mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .help("Equal zones, or your own rows or columns")
                        if draft.strips == nil {
                            CountStepper(title: "Columns", value: $draft.columns)
                            CountStepper(title: "Rows", value: $draft.rows)
                        }
                        Text("\(draft.zoneCount) \(draft.strips == nil ? "equal " : "")\(draft.zoneCount == 1 ? "zone" : "zones")")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let strips = draft.strips {
                    StripList(strips: strips, split: draft.split ?? .rows) { draft.strips = $0 }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: done).controlSize(.small)
                    .help("Close without saving")
                Button("Save") {
                    var grid = draft
                    grid.name = grid.name.trimmingCharacters(in: .whitespaces)
                    if grid.name.isEmpty { grid.name = grid.sizeLabel }
                    model.save(grid)
                    done()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Save this grid to the list")
            }
            .padding(.horizontal, 2)
        }
    }
}

/// Strips of a custom layout: per row size (1×…4×), window count, order, delete; add below.
private struct StripList: View {
    let strips: [Strip]
    let split: Split
    let change: ([Strip]) -> Void

    private var noun: String { split == .rows ? "Row" : "Column" }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(split == .rows ? "Rows, top to bottom" : "Columns, left to right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 72)
                Text("Windows").frame(width: 72)
                Color.clear.frame(width: 3 * 20 + 2 * 4)
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)

            ForEach(Array(strips.indices), id: \.self) { i in
                HStack(spacing: 4) {
                    Text("\(noun) \(i + 1)").font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SmallStepper(value: strips[i].size, range: Strip.sizeRange, suffix: "×",
                                 help: "\(noun) \(i + 1) size") { v in update(i) { $0.size = v } }
                    SmallStepper(value: strips[i].count, range: GridSet.range, suffix: "",
                                 help: "Windows in \(noun.lowercased()) \(i + 1)") { v in update(i) { $0.count = v } }
                    RoundIconButton(symbol: "chevron.up", size: 20, help: "Move \(noun) Up") { swap(i, i - 1) }
                        .opacity(i == 0 ? 0.3 : 1).disabled(i == 0)
                    RoundIconButton(symbol: "chevron.down", size: 20, help: "Move \(noun) Down") { swap(i, i + 1) }
                        .opacity(i == strips.count - 1 ? 0.3 : 1).disabled(i == strips.count - 1)
                    RoundIconButton(symbol: "trash", size: 20, help: "Remove \(noun)") {
                        var s = strips
                        s.remove(at: i)
                        change(s)
                    }
                    .opacity(strips.count > 1 ? 1 : 0.3).disabled(strips.count <= 1)
                }
            }

            HStack {
                Button("Add \(noun)") { change(strips + [Strip(count: strips.last?.count ?? 2)]) }
                    .controlSize(.small)
                    .disabled(strips.count >= GridSet.stripRange.upperBound)
                    .help("Add a \(noun.lowercased()) at the \(split == .rows ? "bottom" : "right")")
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func update(_ i: Int, _ apply: (inout Strip) -> Void) {
        var s = strips
        apply(&s[i])
        change(s)
    }

    private func swap(_ a: Int, _ b: Int) {
        guard strips.indices.contains(b) else { return }
        var s = strips
        s.swapAt(a, b)
        change(s)
    }
}

/// Small number with minus/plus for the strip list.
private struct SmallStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
    let help: String
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            RoundIconButton(symbol: "minus", size: 20, help: "Less: \(help)") { change(max(value - 1, range.lowerBound)) }
                .opacity(value > range.lowerBound ? 1 : 0.4)
            Text("\(value)\(suffix)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 26)
            RoundIconButton(symbol: "plus", size: 20, help: "More: \(help)") { change(min(value + 1, range.upperBound)) }
                .opacity(value < range.upperBound ? 1 : 0.4)
        }
        .frame(width: 72)
    }
}
