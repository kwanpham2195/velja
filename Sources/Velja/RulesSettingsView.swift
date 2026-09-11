import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeljaCore

/// A rule being edited in the rule editor sheet.
struct RuleEditorDraft: Identifiable {
    var rule: LinkRule
    var isNewRule: Bool

    var id: UUID { rule.id }
}

/// The rules list: add, edit, reorder, enable, delete, import, and export rules.
struct RulesSettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedRuleID: UUID?
    @State private var ruleEditorDraft: RuleEditorDraft?
    @State private var importExportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules are checked from top to bottom, and the first match decides where a link opens. App links are checked before rules.")
                .settingsFootnote()

            List(selection: $selectedRuleID) {
                ForEach($model.settings.rules) { $rule in
                    RuleRow(rule: $rule, summary: ruleSummary(rule))
                        .tag(rule.id)
                }
                .onMove { source, destination in
                    model.settings.rules.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UUID.self) { ruleIDs in
                if let ruleID = ruleIDs.first {
                    Button("Edit…") { editRule(id: ruleID) }
                    Button("Duplicate") { duplicateRule(id: ruleID) }
                    Divider()
                    Button("Delete", role: .destructive) { deleteRule(id: ruleID) }
                }
            } primaryAction: { ruleIDs in
                if let ruleID = ruleIDs.first {
                    editRule(id: ruleID)
                }
            }
            .overlay {
                if model.settings.rules.isEmpty {
                    ContentUnavailableView(
                        "No Rules",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add a rule to send links from a site or an app to a specific browser. You can also ⌘-click a browser in the picker.")
                    )
                }
            }

            HStack {
                Button {
                    ruleEditorDraft = RuleEditorDraft(
                        rule: LinkRule(name: "", urlMatchers: [URLMatcher(kind: .domain, pattern: "")], action: .showBrowserPicker),
                        isNewRule: true
                    )
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                Button("Edit…") {
                    if let selectedRuleID { editRule(id: selectedRuleID) }
                }
                .disabled(selectedRuleID == nil)
                Button("Delete") {
                    if let selectedRuleID { deleteRule(id: selectedRuleID) }
                }
                .disabled(selectedRuleID == nil)
                Spacer()
                Menu("Import & Export") {
                    Button("Import Rules…") { importRules() }
                    Button("Export Rules…") { exportRules() }
                        .disabled(model.settings.rules.isEmpty)
                }
                .fixedSize()
            }
            if let importExportMessage {
                Text(importExportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(item: $ruleEditorDraft) { draft in
            RuleEditorView(draft: draft, model: model) { savedRule in
                saveRule(savedRule, isNewRule: draft.isNewRule)
                ruleEditorDraft = nil
            } onCancel: {
                ruleEditorDraft = nil
            }
        }
    }

    // MARK: Editing

    private func editRule(id: UUID) {
        guard let rule = model.settings.rules.first(where: { $0.id == id }) else {
            return
        }
        ruleEditorDraft = RuleEditorDraft(rule: rule, isNewRule: false)
    }

    private func saveRule(_ rule: LinkRule, isNewRule: Bool) {
        if !isNewRule, let index = model.settings.rules.firstIndex(where: { $0.id == rule.id }) {
            model.settings.rules[index] = rule
        } else {
            model.settings.rules.append(rule)
        }
        selectedRuleID = rule.id
    }

    private func duplicateRule(id: UUID) {
        guard let index = model.settings.rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        var copy = model.settings.rules[index]
        copy.id = UUID()
        copy.name = copy.name.isEmpty ? "" : "\(copy.name) Copy"
        copy.urlMatchers = copy.urlMatchers.map { URLMatcher(kind: $0.kind, pattern: $0.pattern) }
        model.settings.rules.insert(copy, at: index + 1)
        selectedRuleID = copy.id
    }

    private func deleteRule(id: UUID) {
        model.settings.rules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
    }

    // MARK: Import and export

    private func exportRules() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "Velja Rules.json"
        guard savePanel.runModal() == .OK, let fileURL = savePanel.url else {
            return
        }
        do {
            try RuleExportFile.encodeRuleExport(model.settings.rules).write(to: fileURL, options: [.atomic])
            importExportMessage = "Exported \(model.settings.rules.count) rules."
        } catch {
            importExportMessage = "Could not export rules: \(error.localizedDescription)"
        }
    }

    private func importRules() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        guard openPanel.runModal() == .OK, let fileURL = openPanel.url else {
            return
        }
        do {
            let importedRules = try RuleExportFile.decodeRuleExport(Data(contentsOf: fileURL))
            model.settings.rules.append(contentsOf: importedRules)
            importExportMessage = "Imported \(importedRules.count) rules. They were added below your existing rules."
        } catch {
            importExportMessage = "Could not import rules: \(error.localizedDescription)"
        }
    }

    // MARK: Summary

    /// One line describing a rule, for example "github.com, gitlab.com · from Slack → Google Chrome".
    private func ruleSummary(_ rule: LinkRule) -> String {
        var conditions: [String] = []
        let patterns = rule.activeURLMatchers.map(\.pattern)
        if !patterns.isEmpty {
            conditions.append(patterns.count > 3 ? patterns.prefix(3).joined(separator: ", ") + ", …" : patterns.joined(separator: ", "))
        }
        if !rule.sourceAppBundleIdentifiers.isEmpty {
            let appNames = rule.sourceAppBundleIdentifiers.map(InstalledAppLookup.appName(forBundleIdentifier:))
            conditions.append("from " + appNames.joined(separator: ", "))
        }
        let destination: String
        switch rule.action {
        case .showBrowserPicker:
            destination = "Browser Picker"
        case .openInBrowser(let target):
            destination = model.browserTitle(for: target)
        }
        let conditionText = conditions.isEmpty ? "No conditions" : conditions.joined(separator: " · ")
        return "\(conditionText) → \(destination)"
    }
}

private struct RuleRow: View {
    @Binding var rule: LinkRule
    let summary: String

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Enable \(rule.name)", isOn: $rule.isEnabled)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? "Untitled Rule" : rule.name)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if !rule.hasConditions {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This rule has no URL pattern or app, so it never matches.")
            }
        }
        .padding(.vertical, 2)
    }
}
