import ServiceManagement

/// Turns "launch Velja at login" on and off through the system login items list.
/// The system list is the source of truth, so this is not stored in Velja's settings.
@MainActor
enum LaunchAtLogin {
    /// True when Velja is registered as a login item, including while it waits for the user's approval.
    static var isLaunchAtLoginEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// True when the user must approve Velja in System Settings > General > Login Items.
    static var needsLoginItemApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings > General > Login Items, where the user approves Velja.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
