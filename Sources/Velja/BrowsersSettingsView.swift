import SwiftUI
import VeljaCore

/// Browser picker settings: which browsers and profiles it lists, and in what order.
struct BrowsersSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("List each browser profile separately", isOn: $model.settings.showsBrowserProfiles)
            Text("Drag to reorder. In the browser picker, the first nine checked entries get the number keys 1–9. Unchecked entries are left out of the picker but can still be used by rules.")
                .settingsFootnote()

            List {
                ForEach(model.orderedBrowserPickerChoices) { choice in
                    HStack(spacing: 10) {
                        Toggle("Show \(choice.title) in the browser picker", isOn: visibilityBinding(for: choice.target))
                            .labelsHidden()
                        Image(nsImage: choice.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(choice.title)
                        Spacer()
                        Text(choice.target.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove(perform: moveChoices)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button("Refresh") {
                    model.refreshInstalledBrowsers()
                }
                Button("Reset Order") {
                    model.settings.browserPickerOrder = []
                }
                .disabled(model.settings.browserPickerOrder.isEmpty)
                Spacer()
            }
        }
        .padding(20)
        .onAppear {
            model.refreshInstalledBrowsers()
        }
    }

    private func visibilityBinding(for target: BrowserTarget) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hiddenBrowserPickerTargets.contains(target) },
            set: { isVisible in
                if isVisible {
                    model.settings.hiddenBrowserPickerTargets.remove(target)
                } else {
                    model.settings.hiddenBrowserPickerTargets.insert(target)
                }
            }
        )
    }

    private func moveChoices(from source: IndexSet, to destination: Int) {
        var targets = model.orderedBrowserPickerChoices.map(\.target)
        targets.move(fromOffsets: source, toOffset: destination)
        // Keep saved positions of entries not listed right now, such as profiles while profiles are merged.
        let listedTargets = Set(targets)
        model.settings.browserPickerOrder = targets + model.settings.browserPickerOrder.filter { !listedTargets.contains($0) }
    }
}
