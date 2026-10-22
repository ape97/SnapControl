import SwiftUI

/// Second page: grid list (create, change, sort, delete), snapping (key, permission), autostart and version.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    let back: () -> Void
    let edit: (UUID?) -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    /// Deleting needs a second tap on the (then red) trash can.
    @State private var pendingDelete: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundIconButton(symbol: "chevron.left", size: 24, help: "Back", action: back)
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 2)

            Module(spacing: 4) {
                HStack {
                    SettingLabel(symbol: "square.grid.2x2", title: "Grids", tint: .accentColor)
                    Spacer()
                    RoundIconButton(symbol: "plus", size: 22, help: "Add Grid") { edit(nil) }
                }
                SettingNote("Grids in the menu. Reorder, edit or add them here; turn one on in the menu.")
                    .padding(.bottom, 2)
                ForEach(Array(model.sets.enumerated()), id: \.element.id) { index, grid in
                    row(grid, first: index == 0, last: index == model.sets.count - 1)
                }
            }

            Module(spacing: 10) {
                HStack {
                    SettingLabel(symbol: "keyboard", title: "Snap Key", tint: .accentColor)
                    Spacer()
                    Picker("Snap Key", selection: Binding(get: { model.snapKey }, set: { model.setSnapKey($0) })) {
                        ForEach(SnapKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .help("Hold this key while dragging a window to show the zones")
                }
                SettingNote("Hold this key while dragging a window to show the zones; release it over a zone to snap.")
                HStack {
                    SettingLabel(symbol: "accessibility", title: "Accessibility Access", tint: .blue)
                    Spacer()
                    if model.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow…") { model.requestTrust() }
                            .controlSize(.small)
                            .help("Open System Settings → Privacy & Security → Accessibility and turn on Snap Control")
                    }
                }
                SettingNote("macOS only lets Snap Control move and resize other apps' windows with this access.")
            }

            Module {
                HStack {
                    SettingLabel(symbol: "power", title: "Open at Login", tint: .green)
                    Spacer()
                    Toggle("Open at Login", isOn: Binding(get: { launchAtLogin }, set: { LoginItem.set($0); launchAtLogin = LoginItem.isEnabled }))
                        .labelsHidden()
                        .toggleStyle(.setting)
                        .controlSize(.small)
                        .help("Start Snap Control automatically when you log in")
                }
                SettingNote("Starts Snap Control automatically when you log in.")
            }

            HStack {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
    }

    private func row(_ grid: GridSet, first: Bool, last: Bool) -> some View {
        HStack(spacing: 7) {
            GridGlyph(grid: grid, active: model.active?.id == grid.id)
                .frame(width: 30, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(grid.name).font(.system(size: 12)).lineLimit(1)
                Text(grid.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            Spacer(minLength: 4)
            RoundIconButton(symbol: "chevron.up", size: 22, help: "Move Up") { model.move(grid, by: -1) }
                .opacity(first ? 0.3 : 1).disabled(first)
            RoundIconButton(symbol: "chevron.down", size: 22, help: "Move Down") { model.move(grid, by: 1) }
                .opacity(last ? 0.3 : 1).disabled(last)
            RoundIconButton(symbol: "pencil", size: 22, help: "Edit") { edit(grid.id) }
            RoundIconButton(symbol: "trash", size: 22, active: pendingDelete == grid.id, activeColor: .red,
                            help: pendingDelete == grid.id ? "Click again to delete" : "Delete") {
                if pendingDelete == grid.id {
                    model.delete(grid)
                    pendingDelete = nil
                } else {
                    pendingDelete = grid.id
                }
            }
        }
        .padding(.vertical, 2)
    }
}
