import SwiftUI

/// Pages in the menu: list, settings, editor of a grid (nil ID = new grid).
enum Page: Equatable {
    case main
    case settings
    case editor(UUID?)

    @MainActor static var initial: Page {
        if Runtime.arguments.contains("--editor") { return .editor(nil) }
        if Runtime.arguments.contains("--settings") { return .settings }
        return .main
    }

    var depth: Int {
        switch self {
        case .main: 0
        case .settings: 1
        case .editor: 2
        }
    }
}

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @State private var page = Page.initial
    @State private var forward = true

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch page {
                case .main:
                    MainPage()
                case .settings:
                    SettingsPage(back: { go(.main) }, edit: { go(.editor($0)) })
                case .editor(let id):
                    GridEditor(original: model.sets.first { $0.id == id }, done: { go(.settings) })
                }
            }
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                    removal: .move(edge: forward ? .leading : .trailing)).combined(with: .opacity))
            FooterBar(settingsActive: page != .main) { go(page == .main ? .settings : .main) }
        }
        .padding(10)
        .frame(width: 380)
    }

    private func go(_ next: Page) {
        forward = next.depth > page.depth
        withAnimation(.snappy(duration: 0.25)) { page = next }
    }
}

/// Main page: on/off with a hint, below it the saved grids (tap = on/off).
/// Create, change and delete via the gear (settings).
struct MainPage: View {
    var body: some View {
        VStack(spacing: 8) {
            StatusModule()
            SetsModule()
        }
    }
}

struct StatusModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Module {
            HStack(spacing: 8) {
                DeviceBadge(symbol: model.active == nil ? AppModel.menuBarSymbol : AppModel.menuBarSymbolActive, size: 28,
                            tint: model.active == nil ? .gray : .accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.active.map { "\($0.name) active" } ?? "Off").font(.system(size: 13, weight: .semibold))
                    Text(model.active.map(\.detail) ?? "Choose a grid to split the screen")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Snapping", isOn: Binding(get: { model.active != nil }, set: { model.setEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.setting)
                    .controlSize(.small)
                    .help(model.active == nil ? "Turn on the last used grid" : "Turn off the grid")
            }
            SettingNote("Drag a window and hold \(model.snapKey.title) to snap it into a zone.")
            if !model.isTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    SettingNote("Needs Accessibility access to move windows.", tint: .primary)
                    Spacer()
                    Button("Allow…") { model.requestTrust() }
                        .controlSize(.small)
                        .help("Open System Settings → Privacy & Security → Accessibility and turn on Snap Control")
                }
            }
        }
    }
}

/// Saved grids. No SwiftUI Button in the row (tap gesture), hover only via opacity.
struct SetsModule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Module(spacing: 2) {
            Text("Saved Grids")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.bottom, 2)
            if model.sets.isEmpty {
                SettingNote("No saved grids yet – add one in Settings.")
                    .padding(.horizontal, 6).padding(.vertical, 6)
            }
            ForEach(model.sets) { grid in
                GridRow(grid: grid)
            }
        }
    }
}

struct GridRow: View {
    @Environment(AppModel.self) private var model
    let grid: GridSet
    @State private var hover = false

    var body: some View {
        let active = model.active?.id == grid.id
        HStack(spacing: 9) {
            GridGlyph(grid: grid, active: active)
                .frame(width: 34, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(grid.name).font(.system(size: 12.5, weight: active ? .semibold : .regular))
                Text(grid.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .opacity(active ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.primary.opacity(hover ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.toggle(grid) }
        .demoTarget(grid.demoID)
        .help(active ? "Turn off this grid" : "Use this grid")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggle(grid) }
    }
}

/// Number with minus/plus (1…8).
struct CountStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12))
            Spacer()
            RoundIconButton(symbol: "minus", size: 22, help: "Fewer \(title.lowercased())") {
                value = max(value - 1, GridSet.range.lowerBound)
            }
            .opacity(value > GridSet.range.lowerBound ? 1 : 0.4)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 18)
            RoundIconButton(symbol: "plus", size: 22, help: "More \(title.lowercased())") {
                value = min(value + 1, GridSet.range.upperBound)
            }
            .opacity(value < GridSet.range.upperBound ? 1 : 0.4)
        }
    }
}

/// Small picture of the grid (aspect ratio like a display). Canvas: changes only redraw, nothing is rebuilt.
/// Draws the same zones as when snapping, including custom layouts.
struct GridGlyph: View {
    let grid: GridSet
    var active = false

    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = size.width > 60 ? 3 : 1.5
            let radius: CGFloat = size.width > 60 ? 4 : 2
            let tint = active ? Color.accentColor : Color.secondary
            // Compute on a large area (rounding doesn't matter), then scale down; flip Cocoa y downward
            let unit = CGRect(x: 0, y: 0, width: 1000, height: 1000)
            let sx = (size.width - gap) / unit.width, sy = (size.height - gap) / unit.height
            for zone in Zones.frames(grid, in: unit) {
                let rect = CGRect(x: gap + zone.minX * sx, y: gap + (unit.height - zone.maxY) * sy,
                                  width: zone.width * sx - gap, height: zone.height * sy - gap)
                ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(tint.opacity(active ? 0.55 : 0.35)))
            }
        }
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("\(grid.sizeLabel) grid")
    }
}

/// Footer as in all apps: name on the left, Settings and Quit on the right.
struct FooterBar: View {
    let settingsActive: Bool
    let toggleSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Snap Control")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            RoundIconButton(symbol: "gearshape.fill", size: 24, active: settingsActive, help: "Settings", action: toggleSettings)
            RoundIconButton(symbol: "power", size: 24, help: "Quit Snap Control") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
    }
}
