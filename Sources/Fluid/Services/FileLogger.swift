import Foundation

/// A lightweight file-backed logger that mirrors in-app debug logs to disk for diagnostics.
final class FileLogger {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "file.logger.queue", qos: .utility)
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let logFileURL: URL
    private let backupLogURL: URL
    private let maxLogFileSize: UInt64 = 1 * 1024 * 1024 // 1 MB limit per log file
    private let maxLogFileAge: TimeInterval = 72 * 60 * 60 // Rotate every 72 hours

    private init() {
        let baseDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        logDirectory = baseDirectory.appendingPathComponent("Logs/Fluid", isDirectory: true)
        logFileURL = logDirectory.appendingPathComponent("fluid.log", isDirectory: false)
        backupLogURL = logDirectory.appendingPathComponent("fluid.log.1", isDirectory: false)

        queue.sync {
            self.createLogDirectoryIfNeeded()
            self.rotateIfNeeded(force: false)
        }
    }

    func append(line: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.createLogDirectoryIfNeeded()
            self.rotateIfNeeded(force: false)
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if !self.fileManager.fileExists(atPath: self.logFileURL.path) {
                self.fileManager.createFile(atPath: self.logFileURL.path, contents: data)
            } else if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            }
        }
    }

    func currentLogFileURL() -> URL {
        return logFileURL
    }

    // MARK: - Private helpers

    private func createLogDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: logDirectory.path) else { return }
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            // If the directory cannot be created, fall back to /tmp
        }
    }

    private func rotateIfNeeded(force: Bool) {
        guard fileManager.fileExists(atPath: logFileURL.path) else { return }

        let shouldRotate: Bool
        if force {
            shouldRotate = true
        } else {
            let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path)
            let size = attributes?[.size] as? UInt64 ?? 0
            let modifiedDate = attributes?[.modificationDate] as? Date ?? Date()
            let ageExceedsLimit = Date().timeIntervalSince(modifiedDate) >= maxLogFileAge
            shouldRotate = size >= maxLogFileSize || ageExceedsLimit
        }

        guard shouldRotate else { return }

        // Remove existing backup if present
        if fileManager.fileExists(atPath: backupLogURL.path) {
            try? fileManager.removeItem(at: backupLogURL)
        }

        // Move current log to backup and create a fresh file
        try? fileManager.moveItem(at: logFileURL, to: backupLogURL)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }
}
