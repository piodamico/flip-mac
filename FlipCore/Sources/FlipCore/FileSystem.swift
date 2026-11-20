//
//  FileSystem.swift
//  FlipCore
//

import Darwin
import Foundation

/// Operazioni sul file system che non sovrascrivono mai un elemento esistente.
enum FileSystem {
    /// True se al percorso c'è già qualcosa, compresi i link simbolici non validi.
    /// In caso di dubbio (per esempio permesso negato) risponde true, così nessuno ci scrive sopra.
    static func itemExists(at url: URL) -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            return true
        }
        return errno != ENOENT
    }

    enum CommitError: Error {
        case destinationExists
        case failed(errno: Int32)
    }

    /// Sposta `source` in `destination` in modo atomico, e fallisce se `destination` esiste già.
    static func moveWithoutReplacing(_ source: URL, to destination: URL) throws(CommitError) {
        if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
            return
        }
        let renameError = errno
        if renameError == EEXIST {
            throw .destinationExists
        }
        guard renameError == ENOTSUP || renameError == EINVAL else {
            throw .failed(errno: renameError)
        }

        // Il volume non supporta RENAME_EXCL: link(2) fallisce comunque in modo atomico se la destinazione esiste.
        if link(source.path, destination.path) != 0 {
            let linkError = errno
            throw linkError == EEXIST ? .destinationExists : .failed(errno: linkError)
        }
        unlink(source.path)
    }
}
