import AppKit

#if DEBUG
if let snapshotDirectory = UISnapshotHarness.requestedSnapshotDirectory() {
    let snapshotHarness = UISnapshotHarness(outputDirectory: snapshotDirectory)
    NSApplication.shared.delegate = snapshotHarness
    withExtendedLifetime(snapshotHarness) {
        NSApplication.shared.run()
    }
    exit(0)
}
#endif

// NSApplication keeps only a weak reference to its delegate, so this global keeps it alive.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
