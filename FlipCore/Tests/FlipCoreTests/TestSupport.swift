//
//  TestSupport.swift
//  FlipCoreTests
//

import CoreGraphics
import Foundation
import ImageIO
import XCTest

extension XCTestCase {
    /// Cartella temporanea dedicata al test, rimossa quando il test finisce.
    func makeTemporaryDirectory() throws -> TemporaryDirectory {
        let directory = try TemporaryDirectory()
        let url = directory.url
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return directory
    }
}

struct TemporaryDirectory {
    let url: URL

    fileprivate init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "FlipCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .notDirectory)
    }

    func touch(_ name: String, contents: String = "") throws -> URL {
        let fileURL = file(name)
        try Data(contents.utf8).write(to: fileURL, options: .withoutOverwriting)
        return fileURL
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}

enum TestImages {
    /// Immagine RGBA generata in memoria: metà sinistra rossa opaca, metà destra trasparente se `transparentHalf`.
    static func make(width: Int = 16, height: Int = 8, transparentHalf: Bool = false) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let filledWidth = transparentHalf ? width / 2 : width
        context.fill(CGRect(x: 0, y: 0, width: filledWidth, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// Scrive l'immagine nel formato indicato, per preparare i file sorgente dei test.
    static func write(_ image: CGImage, typeIdentifier: String, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "impossibile scrivere l'immagine di prova")
    }

    /// WebP senza perdita 16×8: metà sinistra rossa opaca, metà destra trasparente.
    /// ImageIO non sa scrivere WebP, quindi il file è stato creato una volta con
    /// `cwebp -lossless -exact` ed è incluso qui in base64 (44 byte).
    static let halfRedWebPBase64 = "UklGRiQAAABXRUJQVlA4TBcAAAAvD8ABEA8Q8x/zHwyxYDJ/6c4UIvofOQA="

    static func writeHalfRedWebP(to url: URL) throws {
        let data = try XCTUnwrap(Data(base64Encoded: halfRedWebPBase64))
        try data.write(to: url, options: .withoutOverwriting)
    }

    struct Info {
        let typeIdentifier: String
        let width: Int
        let height: Int
        let image: CGImage
    }

    static func read(_ url: URL) throws -> Info {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return Info(typeIdentifier: type, width: image.width, height: image.height, image: image)
    }

    /// Componenti RGBA (0–255) del pixel in (x, y), con origine in alto a sinistra.
    static func pixel(of image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var buffer = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return buffer
    }
}
