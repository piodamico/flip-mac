//
//  FileLogger.swift
//  FlipMac
//

import Foundation

/// Scrive righe di log in ~/Library/Logs/FlipMac/flipmac.log, sempre in coda.
final class FileLogger {
    static let shared = FileLogger()

    let fileURL: URL
    private let formatter: ISO8601DateFormatter

    private init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/FlipMac", directoryHint: .isDirectory)
        fileURL = logsDirectory.appending(path: "flipmac.log", directoryHint: .notDirectory)

        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current

        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    /// Scrive un evento; ogni riga di `details` va su una riga indentata sotto l'evento.
    func log(_ event: String, _ details: [String] = []) {
        var text = "\(formatter.string(from: Date())) \(event)\n"
        for detail in details {
            text += "    \(detail)\n"
        }
        append(Data(text.utf8))
    }

    private func append(_ data: Data) {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
