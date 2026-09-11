import OSLog

/// Loggers for Velja. Read them with `log stream --predicate 'subsystem == "com.kwanpham.Velja"'`.
/// Links are logged as private, so they show as `<private>` unless private data logging is enabled.
enum VeljaLog {
    static let subsystem = "com.kwanpham.Velja"
    /// Incoming links, routing decisions, and failures to open links.
    static let routing = Logger(subsystem: subsystem, category: "routing")
    /// Settings and history files.
    static let storage = Logger(subsystem: subsystem, category: "storage")
    /// Default browser, launch at login, and other system integration.
    static let system = Logger(subsystem: subsystem, category: "system")
}
