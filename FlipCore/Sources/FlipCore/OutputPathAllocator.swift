//
//  OutputPathAllocator.swift
//  FlipCore
//

import Foundation

/// Sceglie dove salvare un file convertito: accanto all'originale, con un nome che non esiste ancora.
///
/// Per `foto.png` verso `jpg` prova `foto-convertito.jpg`, poi `foto-convertito-2.jpg`,
/// `foto-convertito-3.jpg` e così via. Non crea né modifica file.
public struct OutputPathAllocator: Sendable {
    public static let defaultSuffix = "convertito"

    public enum AllocationError: Error, Equatable {
        /// L'estensione è vuota o contiene caratteri non validi in un nome di file.
        case invalidExtension(String)
        /// Tutti i nomi fino a `maxAttempts` sono già occupati.
        case noAvailableName(lastTried: URL)
    }

    public let suffix: String
    public let maxAttempts: Int

    public init(suffix: String = OutputPathAllocator.defaultSuffix, maxAttempts: Int = 10_000) {
        self.suffix = suffix
        self.maxAttempts = maxAttempts
    }

    /// Restituisce un percorso libero accanto a `source`, con estensione `fileExtension` (il punto iniziale è facoltativo).
    ///
    /// Il percorso è libero nel momento della chiamata: chi scrive deve comunque rifiutare di sovrascrivere,
    /// come fa `ImageConverter`.
    public func outputURL(for source: URL, fileExtension: String) throws(AllocationError) -> URL {
        let cleanExtension = fileExtension.hasPrefix(".") ? String(fileExtension.dropFirst()) : fileExtension
        guard !cleanExtension.isEmpty, !cleanExtension.contains("/"), !cleanExtension.contains(":") else {
            throw .invalidExtension(fileExtension)
        }

        let directory = source.deletingLastPathComponent()
        let baseName = source.deletingPathExtension().lastPathComponent

        var candidate = directory
        for attempt in 1...max(maxAttempts, 1) {
            let name = attempt == 1 ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix)-\(attempt)"
            candidate = directory.appending(path: "\(name).\(cleanExtension)", directoryHint: .notDirectory)
            if !FileSystem.itemExists(at: candidate) {
                return candidate
            }
        }
        throw .noAvailableName(lastTried: candidate)
    }
}
