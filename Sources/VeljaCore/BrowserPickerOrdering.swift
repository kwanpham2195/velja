import Foundation

/// Decides which browsers the browser picker lists, and in what order.
public enum BrowserPickerOrdering {
    /// Orders all available entries: those in `savedOrder` first, in that order, then the rest in their
    /// given order. Hidden entries are included, so settings can show and re-enable them.
    public static func orderedBrowserTargets(available: [BrowserTarget], savedOrder: [BrowserTarget]) -> [BrowserTarget] {
        let availableSet = Set(available)
        var seen = Set<BrowserTarget>()
        var ordered: [BrowserTarget] = []
        for target in savedOrder where availableSet.contains(target) && !seen.contains(target) {
            ordered.append(target)
            seen.insert(target)
        }
        for target in available where !seen.contains(target) {
            ordered.append(target)
            seen.insert(target)
        }
        return ordered
    }

    /// The entries the picker shows: the ordered entries minus hidden ones. When everything is hidden,
    /// every entry is shown so the picker is never empty.
    public static func visibleBrowserTargets(
        available: [BrowserTarget],
        savedOrder: [BrowserTarget],
        hidden: Set<BrowserTarget>
    ) -> [BrowserTarget] {
        let ordered = orderedBrowserTargets(available: available, savedOrder: savedOrder)
        let visible = ordered.filter { !hidden.contains($0) }
        return visible.isEmpty ? ordered : visible
    }
}
