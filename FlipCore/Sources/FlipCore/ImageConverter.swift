//
//  ImageConverter.swift
//  FlipCore
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Formato immagine identificato dal suo Uniform Type Identifier.
public struct ImageFormat: Hashable, Sendable {
    public let typeIdentifier: String
    public let fileExtension: String

    public init(typeIdentifier: String, fileExtension: String) {
        self.typeIdentifier = typeIdentifier
        self.fileExtension = fileExtension
    }

    public static let png = ImageFormat(typeIdentifier: UTType.png.identifier, fileExtension: "png")
    public static let jpeg = ImageFormat(typeIdentifier: UTType.jpeg.identifier, fileExtension: "jpg")
    public static let heic = ImageFormat(typeIdentifier: UTType.heic.identifier, fileExtension: "heic")
    public static let tiff = ImageFormat(typeIdentifier: UTType.tiff.identifier, fileExtension: "tiff")
    /// Solo in lettura: ImageIO legge WebP ma non sa scriverlo.
    public static let webp = ImageFormat(typeIdentifier: UTType.webP.identifier, fileExtension: "webp")

    /// JPEG non ha canale alfa: le immagini trasparenti vanno appiattite prima di scriverle.
    var supportsAlpha: Bool {
        self != .jpeg
    }

    var isLossy: Bool {
        self == .jpeg || self == .heic
    }
}

public enum ImageConversionError: Error, Equatable {
    /// ImageIO non riesce a leggere il file sorgente come immagine.
    case unreadableSource(URL)
    /// La sorgente è un'immagine, ma di un formato che il convertitore non gestisce.
    case unsupportedSourceFormat(String)
    /// ImageIO su questo sistema non sa scrivere il formato richiesto.
    case unsupportedTargetFormat(String)
    /// La destinazione esiste già: non viene mai sovrascritta.
    case destinationExists(URL)
    /// ImageIO non è riuscito a codificare l'immagine.
    case encodingFailed(String)
    /// Il file temporaneo non è stato spostato nella destinazione.
    case commitFailed(URL, errno: Int32)
}

/// Converte immagini con ImageIO: legge PNG, JPEG, HEIC, TIFF e WebP, scrive PNG, JPEG, HEIC e TIFF.
///
/// Scrive in un file temporaneo nella cartella di destinazione e poi lo rinomina con un'operazione
/// che fallisce se la destinazione esiste: il file sorgente e i file esistenti non vengono mai toccati.
public struct ImageConverter: Sendable {
    public static let supportedTargetFormats: [ImageFormat] = [.png, .jpeg, .heic, .tiff]
    public static let supportedSourceFormats: [ImageFormat] = supportedTargetFormats + [.webp]

    public let allocator: OutputPathAllocator
    /// Qualità per i formati con perdita (JPEG, HEIC), da 0 a 1.
    public let lossyQuality: Double

    public init(allocator: OutputPathAllocator = OutputPathAllocator(), lossyQuality: Double = 0.9) {
        self.allocator = allocator
        self.lossyQuality = lossyQuality
    }

    /// I tipi che ImageIO sa scrivere su questo sistema.
    public static var writableTypeIdentifiers: [String] {
        CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    }

    public static func canWrite(_ format: ImageFormat) -> Bool {
        writableTypeIdentifiers.contains(format.typeIdentifier)
    }

    /// Converte `source` nel formato richiesto e lo salva accanto all'originale con un nome libero.
    @discardableResult
    public func convert(_ source: URL, to format: ImageFormat) throws -> URL {
        let destination = try allocator.outputURL(for: source, fileExtension: format.fileExtension)
        try convert(source, to: format, destination: destination)
        return destination
    }

    /// Converte `source` nel formato richiesto e lo salva in `destination`, che non deve esistere.
    public func convert(_ source: URL, to format: ImageFormat, destination: URL) throws(ImageConversionError) {
        guard Self.supportedTargetFormats.contains(format), Self.canWrite(format) else {
            throw .unsupportedTargetFormat(format.typeIdentifier)
        }
        guard !FileSystem.itemExists(at: destination) else {
            throw .destinationExists(destination)
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let imageSource = CGImageSourceCreateWithURL(source as CFURL, sourceOptions),
            CGImageSourceGetStatus(imageSource) == .statusComplete,
            CGImageSourceGetCount(imageSource) > 0,
            let sourceType = CGImageSourceGetType(imageSource) as String?
        else {
            throw .unreadableSource(source)
        }
        guard Self.supportedSourceFormats.contains(where: { $0.typeIdentifier == sourceType }) else {
            throw .unsupportedSourceFormat(sourceType)
        }

        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).flip-\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        try encode(imageSource, as: format, to: temporary)

        do throws(FileSystem.CommitError) {
            try FileSystem.moveWithoutReplacing(temporary, to: destination)
        } catch {
            switch error {
            case .destinationExists:
                throw .destinationExists(destination)
            case .failed(let code):
                throw .commitFailed(destination, errno: code)
            }
        }
        committed = true
    }

    private func encode(_ imageSource: CGImageSource, as format: ImageFormat, to url: URL) throws(ImageConversionError) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw .unsupportedTargetFormat(format.typeIdentifier)
        }

        var options: [CFString: Any] = [:]
        if format.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = lossyQuality
        }

        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] ?? [:]
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false

        if !format.supportsAlpha && hasAlpha {
            guard
                let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil),
                let flattened = Self.flattenedOnWhite(image)
            else {
                throw .encodingFailed("impossibile appiattire la trasparenza")
            }
            var imageProperties = properties
            imageProperties[kCGImagePropertyHasAlpha] = false
            imageProperties.merge(options) { _, new in new }
            CGImageDestinationAddImage(destination, flattened, imageProperties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, imageSource, index, options as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw .encodingFailed(format.typeIdentifier)
        }
    }

    /// Disegna l'immagine su fondo bianco, senza canale alfa.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let colorSpace: CGColorSpace
        if let imageColorSpace = image.colorSpace, imageColorSpace.model == .rgb {
            colorSpace = imageColorSpace
        } else if let sRGB = CGColorSpace(name: CGColorSpace.sRGB) {
            colorSpace = sRGB
        } else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
