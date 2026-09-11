import SwiftUI
import VeljaCore

/// The settings window's tabs.
struct SettingsView: View {
    @Bindable var model: AppModel
    let linkHandler: IncomingLinkHandler

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            BrowsersSettingsView(model: model)
                .tabItem { Label("Browsers", systemImage: "safari") }
            RulesSettingsView(model: model)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            AppLinksSettingsView(model: model)
                .tabItem { Label("App Links", systemImage: "app.connected.to.app.below.fill") }
            HistorySettingsView(model: model, linkHandler: linkHandler)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .padding(.top, 8)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 460, idealHeight: 560)
    }
}

/// A picker over "Browser Picker" and every installed browser and profile. Keeps a row for a
/// selection whose browser is gone, so the picker never shows an empty value.
struct BrowserSelectionPicker: View {
    let title: String
    @Binding var selection: BrowserSelection
    let model: AppModel

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Browser Picker").tag(BrowserSelection.browserPicker)
            Divider()
            ForEach(model.selectableBrowserChoices) { choice in
                BrowserChoiceLabel(title: choice.title, icon: choice.icon)
                    .tag(BrowserSelection.browser(choice.target))
            }
            if case .browser(let target) = selection, !model.selectableBrowserChoices.contains(where: { $0.target == target }) {
                Text(model.browserTitle(for: target)).tag(selection)
            }
        }
    }
}

/// A browser icon followed by its name, sized for pickers and lists.
struct BrowserChoiceLabel: View {
    let title: String
    let icon: NSImage

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.smallIcon(icon))
            Text(title)
        }
    }

    /// Menus ignore SwiftUI frames, so the icon itself is resized.
    static func smallIcon(_ icon: NSImage) -> NSImage {
        let resizedIcon = icon.copy() as? NSImage ?? icon
        resizedIcon.size = NSSize(width: 16, height: 16)
        return resizedIcon
    }
}
