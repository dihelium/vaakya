import Foundation

/// Work-safe Vaakya stores only the user's consent to download the speech model.
struct AppConfig: Codable, Sendable {
    var modelConsentGiven = false

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: WorkSafePaths.configURL) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save() throws {
        try WorkSafePaths.ensureAppSupport()
        let data = try JSONEncoder().encode(self)
        try data.write(to: WorkSafePaths.configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: WorkSafePaths.configURL.path
        )
    }
}

enum WorkSafePaths {
    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya Work Safe", isDirectory: true)
    }

    static var configURL: URL {
        appSupport.appendingPathComponent("config.json")
    }

    static func ensureAppSupport() throws {
        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: appSupport.path
        )
    }
}
