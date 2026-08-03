import Foundation

/// Where Vaakya keeps its state (plan §2.3: everything under
/// `~/Library/Application Support/Vaakya/`).
enum Paths {
    /// Dev/test override: set VAAKYA_DATA_DIR to relocate all app state
    /// (used by the eval harness and sandboxed CI; unused in normal runs).
    static var appSupport: URL {
        if let override = ProcessInfo.processInfo.environment["VAAKYA_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya", isDirectory: true)
    }

    static var dbURL: URL {
        appSupport.appendingPathComponent("vaakya.db")
    }

    static var configURL: URL {
        appSupport.appendingPathComponent("config.json")
    }

    static func ensureAppSupport() throws {
        try FileManager.default.createDirectory(at: appSupport,
                                                withIntermediateDirectories: true)
    }
}
