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

    static var transcriptionJobsDirectory: URL {
        appSupport.appendingPathComponent("transcription-jobs", isDirectory: true)
    }

    static func jobDirectory(jobID: String) -> URL {
        transcriptionJobsDirectory.appendingPathComponent(jobID, isDirectory: true)
    }

    static func jobLensesDirectory(jobID: String) -> URL {
        jobDirectory(jobID: jobID).appendingPathComponent("lenses", isDirectory: true)
    }

    static var customLensesDirectory: URL {
        appSupport.appendingPathComponent("custom-lenses", isDirectory: true)
    }

    static func ensureAppSupport() throws {
        try FileManager.default.createDirectory(at: appSupport,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptionJobsDirectory,
                                                withIntermediateDirectories: true)
    }

    static func ensureCustomLensesDirectory() throws {
        try ensureAppSupport()
        try FileManager.default.createDirectory(at: customLensesDirectory,
                                                withIntermediateDirectories: true)
    }

    static func ensureJobDirectories(jobID: String) throws {
        try ensureAppSupport()
        try FileManager.default.createDirectory(at: jobDirectory(jobID: jobID),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: jobLensesDirectory(jobID: jobID),
                                                withIntermediateDirectories: true)
    }
}
