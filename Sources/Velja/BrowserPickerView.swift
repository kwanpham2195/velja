import SwiftUI
import VeljaCore

/// The browser picker's content: the link, one row per browser, and keyboard hints.
struct BrowserPickerView: View {
    @Bindable var model: BrowserPickerModel
    /// Height of the browser list when there are too many entries to fit on screen; the list then
    /// scrolls. `nil` shows every entry without scrolling.
    var maximumListHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let maximumListHeight {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        browserRows
                    }
                    .frame(height: maximumListHeight)
                    .onChange(of: model.selectedIndex) { _, selectedIndex in
                        scrollProxy.scrollTo(selectedIndex)
                    }
                }
            } else {
                browserRows
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var browserRows: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.choices.enumerated()), id: \.element.id) { index, choice in
                BrowserPickerRow(
                    choice: choice,
                    shortcutNumber: index < 9 ? index + 1 : nil,
                    isSelected: index == model.selectedIndex
                )
                .id(index)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        model.selectedIndex = index
                    }
                }
                .onTapGesture {
                    model.chooseEntry(at: index, modifierFlags: NSEvent.modifierFlags)
                }
                .contextMenu {
                    Button("Open") {
                        model.finish(.openInBrowser(choice.target, inBackground: false))
                    }
                    Button("Open in Background") {
                        model.finish(.openInBrowser(choice.target, inBackground: true))
                    }
                    if model.request.url.host(percentEncoded: false) != nil {
                        Button("Always Open \(model.linkTitle) in \(choice.title)") {
                            model.finish(.alwaysOpenInBrowser(choice.target))
                        }
                    }
                    Divider()
                    Button("Copy Link") {
                        model.finish(.copyLink)
                    }
                }
            }
        }
        .padding(6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.linkTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(model.request.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(model.request.url.absoluteString)
            if let sourceApp = model.request.sourceApp {
                HStack(spacing: 4) {
                    if let icon = sourceApp.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text("From \(sourceApp.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("↩ Open   ⌃↩ Background   ⌘↩ Always   ⌘C Copy   ⎋ Cancel")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct BrowserPickerRow: View {
    let choice: BrowserChoice
    let shortcutNumber: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: choice.icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(choice.browserName)
                    .lineLimit(1)
                if let profileName = choice.profileName {
                    Text(profileName)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcutNumber {
                Text("\(shortcutNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
