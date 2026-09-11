import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeljaCore

/// The sheet for creating or editing one rule, with a field to test links against its URL patterns.
struct RuleEditorView: View {
    let isNewRule: Bool
    let model: AppModel
    let onSave: (LinkRule) -> Void
    let onCancel: () -> Void

    @State private var rule: LinkRule
    @State private var sampleLinkText = ""

    init(draft: RuleEditorDraft, model: AppModel, onSave: @escaping (LinkRule) -> Void, onCancel: @escaping () -> Void) {
        self.isNewRule = draft.isNewRule
        self.model = model
        self.onSave = onSave
        self.onCancel = onCancel
        _rule = State(initialValue: draft.rule)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $rule.name, prompt: Text(Self.suggestedRuleName(for: rule)))
                    Toggle("Enabled", isOn: $rule.isEnabled)
                }

                urlPatternSection
                sourceAppSection

                Section {
                    BrowserSelectionPicker(title: "Open in", selection: actionSelection, model: model)
                } header: {
                    Text("Then")
                }

                testSection
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !rule.hasConditions {
                    Text("Add a URL pattern or an app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNewRule ? "Add Rule" : "Save") {
                    onSave(Self.cleanedRule(rule))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rule.hasConditions)
            }
            .padding(16)
        }
        .frame(width: 580, height: 640)
    }

    // MARK: Sections

    private var urlPatternSection: some View {
        Section {
            ForEach($rule.urlMatchers) { $matcher in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Picker("Match type", selection: $matcher.kind) {
                            ForEach(URLMatcherKind.allCases, id: \.self) { kind in
                                Text(Self.title(for: kind)).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField("Pattern", text: $matcher.pattern, prompt: Text(Self.placeholder(for: matcher.kind)))
                            .labelsHidden()
                            .autocorrectionDisabled()
                        Button {
                            rule.urlMatchers.removeAll { $0.id == matcher.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this pattern")
                    }
                    if !matcher.isBlank, let validationError = matcher.patternValidationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Button("Add URL Pattern") {
                rule.urlMatchers.append(URLMatcher(kind: .domain, pattern: ""))
            }
        } header: {
            Text("Links matching any of these patterns")
        } footer: {
            // Verbatim, so SwiftUI does not read "www." or "*" as Markdown.
            Text(verbatim: "Domain matches the site and its subdomains. Prefix matches links that start with the text. Wildcard matches the whole link, with * for any text. Regex searches the full link. Prefix and wildcard patterns without https:// ignore the scheme and a leading www. Leave this empty to match every link from the apps below.")
                .settingsFootnote()
        }
    }

    private var sourceAppSection: some View {
        Section {
            ForEach(rule.sourceAppBundleIdentifiers, id: \.self) { bundleIdentifier in
                HStack(spacing: 8) {
                    if let icon = InstalledAppLookup.appIcon(forBundleIdentifier: bundleIdentifier) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    Text(InstalledAppLookup.appName(forBundleIdentifier: bundleIdentifier))
                    Text(bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        rule.sourceAppBundleIdentifiers.removeAll { $0 == bundleIdentifier }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this app")
                }
            }
            Menu("Add App") {
                ForEach(Self.runningAppChoices(), id: \.bundleIdentifier) { app in
                    Button(app.name) {
                        addSourceApp(app.bundleIdentifier)
                    }
                }
                Divider()
                Button("Choose Another App…") {
                    chooseSourceApp()
                }
            }
            .fixedSize()
        } header: {
            Text("Opened from any of these apps")
        } footer: {
            Text("Leave this empty to match links from any app. Links opened from Terminal or other command-line tools may not report their app.")
                .settingsFootnote()
        }
    }

    private var testSection: some View {
        Section {
            TextField("Test link", text: $sampleLinkText, prompt: Text("Paste a link to test the URL patterns"))
                .autocorrectionDisabled()
            if let sampleLink = LinkTextParser.webLink(fromText: sampleLinkText) {
                Label(testResultText(for: sampleLink), systemImage: testMatches(sampleLink) ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(testMatches(sampleLink) ? .green : .secondary)
            } else if !sampleLinkText.isEmpty {
                Text("Enter a web link, such as https://example.com/page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Test")
        }
    }

    // MARK: Test

    private func testMatches(_ link: URL) -> Bool {
        let matchers = rule.activeURLMatchers
        return matchers.isEmpty || matchers.contains { $0.matchesURL(link) }
    }

    private func testResultText(for link: URL) -> String {
        let appNote = rule.sourceAppBundleIdentifiers.isEmpty ? "" : " The link must also come from one of the apps above."
        if rule.activeURLMatchers.isEmpty {
            return "There are no URL patterns, so every link passes this part." + appNote
        }
        return (testMatches(link) ? "This link matches the URL patterns." : "This link does not match any URL pattern.") + (testMatches(link) ? appNote : "")
    }

    // MARK: Source apps

    private func addSourceApp(_ bundleIdentifier: String) {
        guard !rule.sourceAppBundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) else {
            return
        }
        rule.sourceAppBundleIdentifiers.append(bundleIdentifier)
    }

    private func chooseSourceApp() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = true
        openPanel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        openPanel.prompt = "Add"
        guard openPanel.runModal() == .OK else {
            return
        }
        for appURL in openPanel.urls {
            if let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier {
                addSourceApp(bundleIdentifier)
            }
        }
    }

    private static func runningAppChoices() -> [(bundleIdentifier: String, name: String)] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleIdentifier: String, name: String)? in
                guard let bundleIdentifier = app.bundleIdentifier, bundleIdentifier != ownBundleIdentifier,
                      seen.insert(bundleIdentifier).inserted else {
                    return nil
                }
                return (bundleIdentifier, app.localizedName ?? bundleIdentifier)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Action

    /// The rule's action as a browser selection, so the shared browser picker control can edit it.
    private var actionSelection: Binding<BrowserSelection> {
        Binding(
            get: {
                switch rule.action {
                case .showBrowserPicker: .browserPicker
                case .openInBrowser(let target): .browser(target)
                }
            },
            set: { selection in
                switch selection {
                case .browserPicker: rule.action = .showBrowserPicker
                case .browser(let target): rule.action = .openInBrowser(target)
                }
            }
        )
    }

    // MARK: Helpers

    /// Trims patterns, drops blank ones, and fills in a name when none was typed.
    static func cleanedRule(_ rule: LinkRule) -> LinkRule {
        var cleaned = rule
        cleaned.urlMatchers = rule.urlMatchers
            .map { URLMatcher(id: $0.id, kind: $0.kind, pattern: $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isBlank }
        cleaned.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty {
            cleaned.name = suggestedRuleName(for: cleaned)
        }
        return cleaned
    }

    /// A name built from the first condition, such as "github.com" or "Links from Slack".
    @MainActor
    static func suggestedRuleName(for rule: LinkRule) -> String {
        if let firstPattern = rule.activeURLMatchers.first?.pattern.trimmingCharacters(in: .whitespacesAndNewlines) {
            return firstPattern
        }
        if let firstApp = rule.sourceAppBundleIdentifiers.first {
            return "Links from \(InstalledAppLookup.appName(forBundleIdentifier: firstApp))"
        }
        return "Untitled Rule"
    }

    private static func title(for kind: URLMatcherKind) -> String {
        switch kind {
        case .domain: "Domain"
        case .prefix: "Prefix"
        case .wildcard: "Wildcard"
        case .regex: "Regex"
        }
    }

    private static func placeholder(for kind: URLMatcherKind) -> String {
        switch kind {
        case .domain: "example.com"
        case .prefix: "github.com/my-company"
        case .wildcard: "*.atlassian.net/browse/*"
        case .regex: "^https://(www\\.)?example\\.com/"
        }
    }
}
