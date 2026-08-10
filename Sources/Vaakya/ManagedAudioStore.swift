import AVFoundation
import CryptoKit
import Foundation

struct ManagedAudioFile: Sendable {
    let url: URL
    let sourceName: String
    let sha256: String
    let fileSizeBytes: Int64
    let durationSeconds: Double
}

enum ManagedAudioStoreError: LocalizedError {
    case invalidAudio
    case outsideManagedDirectory
    var errorDescription: String? {
        switch self {
        case .invalidAudio: return "The selected file could not be opened as audio."
        case .outsideManagedDirectory: return "The managed audio path is outside Vaakya's storage directory."
        }
    }
}

struct ManagedAudioStore: @unchecked Sendable {
    private let fileManager = FileManager.default

    func importAudio(from sourceURL: URL, jobID: UUID) throws -> ManagedAudioFile {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ManagedAudioStoreError.invalidAudio
        }
        let duration = try Self.durationSeconds(of: sourceURL)
        let jobDirectory = Paths.transcriptionJobsDirectory.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        let destination = jobDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        let attrs = try fileManager.attributesOfItem(atPath: destination.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 44 else { throw ManagedAudioStoreError.invalidAudio }
        return ManagedAudioFile(url: destination, sourceName: sourceURL.lastPathComponent,
                                sha256: try hashFile(destination), fileSizeBytes: size,
                                durationSeconds: duration)
    }

    /// Prefer AVAudioFile; fall back to 16 kHz mono Int16 size estimate so a
    /// quirky WAV header never blocks adopting a capture we already wrote.
    private static func durationSeconds(of url: URL) throws -> Double {
        if let audio = try? AVAudioFile(forReading: url), audio.fileFormat.sampleRate > 0 {
            return Double(audio.length) / audio.fileFormat.sampleRate
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        // 16 kHz mono Int16 = 32_000 bytes/sec, minus a generous header budget.
        let payload = max(0, size - 4096)
        let estimated = Double(payload) / 32_000.0
        guard estimated > 0.05 else { throw ManagedAudioStoreError.invalidAudio }
        return estimated
    }

    func managedURL(relativePath: String) throws -> URL {
        let root = Paths.transcriptionJobsDirectory.standardizedFileURL
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw ManagedAudioStoreError.outsideManagedDirectory
        }
        return url
    }

    private func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
