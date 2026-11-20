//
//  ImageConverterTests.swift
//  FlipCoreTests
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FlipCore

final class ImageConverterTests: XCTestCase {
    private let converter = ImageConverter()

    func testPNGToJPEG() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)
        let sourceBytes = try Data(contentsOf: source)

        let output = try converter.convert(source, to: .jpeg)

        XCTAssertEqual(output.lastPathComponent, "foto-convertito.jpg")
        let info = try TestImages.read(output)
        XCTAssertEqual(info.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(info.width, 16)
        XCTAssertEqual(info.height, 8)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes, "la sorgente non deve cambiare")
        XCTAssertEqual(try directory.contents(), ["foto-convertito.jpg", "foto.png"], "nessun file temporaneo deve restare")
    }

    func testJPEGToPNG() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.jpg")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.jpeg.identifier, to: source)
        let sourceBytes = try Data(contentsOf: source)

        let output = try converter.convert(source, to: .png)

        XCTAssertEqual(output.lastPathComponent, "foto-convertito.png")
        let info = try TestImages.read(output)
        XCTAssertEqual(info.typeIdentifier, UTType.png.identifier)
        XCTAssertEqual(info.width, 16)
        XCTAssertEqual(info.height, 8)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes, "la sorgente non deve cambiare")
        XCTAssertEqual(try directory.contents(), ["foto-convertito.png", "foto.jpg"])
    }

    func testTransparentPNGToJPEGIsFlattenedOnWhite() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("logo.png")
        try TestImages.write(try TestImages.make(transparentHalf: true), typeIdentifier: UTType.png.identifier, to: source)

        let output = try converter.convert(source, to: .jpeg)

        let image = try TestImages.read(output).image
        let opaque = try TestImages.pixel(of: image, x: 2, y: 4)
        let transparent = try TestImages.pixel(of: image, x: 13, y: 4)
        XCTAssertGreaterThan(opaque[0], 200, "la metà rossa resta rossa: \(opaque)")
        XCTAssertLessThan(opaque[1], 60, "la metà rossa resta rossa: \(opaque)")
        XCTAssertTrue(transparent[0...2].allSatisfy { $0 > 240 }, "la metà trasparente diventa bianca: \(transparent)")
    }

    func testSecondConversionGetsNumberedName() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)

        let first = try converter.convert(source, to: .jpeg)
        let firstBytes = try Data(contentsOf: first)
        let second = try converter.convert(source, to: .jpeg)

        XCTAssertEqual(first.lastPathComponent, "foto-convertito.jpg")
        XCTAssertEqual(second.lastPathComponent, "foto-convertito-2.jpg")
        XCTAssertEqual(try Data(contentsOf: first), firstBytes, "la prima conversione non deve cambiare")
    }

    func testRefusesToOverwriteExistingDestination() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)
        let existing = try directory.touch("occupato.jpg", contents: "non toccare")

        XCTAssertThrowsError(try converter.convert(source, to: .jpeg, destination: existing)) { error in
            XCTAssertEqual(error as? ImageConversionError, .destinationExists(existing))
        }
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "non toccare")
        XCTAssertEqual(try directory.contents(), ["foto.png", "occupato.jpg"], "nessun file temporaneo deve restare")
    }

    func testRefusesToOverwriteFileCreatedDuringConversion() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)
        let temporary = try directory.touch("temporaneo.jpg", contents: "temporaneo")
        let destination = try directory.touch("arrivato-prima.jpg", contents: "arrivato prima")

        // Simula la fase finale quando un altro processo ha creato la destinazione dopo il controllo iniziale.
        XCTAssertThrowsError(try FileSystem.moveWithoutReplacing(temporary, to: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "arrivato prima")
    }

    func testUnsupportedTargetFormatFails() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)
        let unknown = ImageFormat(typeIdentifier: "com.flipmac.test.formato-inesistente", fileExtension: "xyz")

        XCTAssertThrowsError(try converter.convert(source, to: unknown)) { error in
            XCTAssertEqual(error as? ImageConversionError, .unsupportedTargetFormat("com.flipmac.test.formato-inesistente"))
        }
        XCTAssertEqual(try directory.contents(), ["foto.png"])
    }

    func testUnreadableSourceFails() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("non-immagine.png", contents: "solo testo")

        XCTAssertThrowsError(try converter.convert(source, to: .jpeg)) { error in
            XCTAssertEqual(error as? ImageConversionError, .unreadableSource(source))
        }
        XCTAssertEqual(try directory.contents(), ["non-immagine.png"])
    }

    func testWebPToPNG() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("sticker.webp")
        try TestImages.writeHalfRedWebP(to: source)
        let sourceBytes = try Data(contentsOf: source)

        let output = try converter.convert(source, to: .png)

        XCTAssertEqual(output.lastPathComponent, "sticker-convertito.png")
        let info = try TestImages.read(output)
        XCTAssertEqual(info.typeIdentifier, UTType.png.identifier)
        XCTAssertEqual(info.width, 16)
        XCTAssertEqual(info.height, 8)
        let opaque = try TestImages.pixel(of: info.image, x: 2, y: 4)
        let transparent = try TestImages.pixel(of: info.image, x: 13, y: 4)
        XCTAssertEqual(opaque, [255, 0, 0, 255], "la metà rossa resta rossa e opaca")
        XCTAssertEqual(transparent[3], 0, "la trasparenza resta: \(transparent)")
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes, "la sorgente non deve cambiare")
        XCTAssertEqual(try directory.contents(), ["sticker-convertito.png", "sticker.webp"])
    }

    func testWebPToJPEG() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("sticker.webp")
        try TestImages.writeHalfRedWebP(to: source)
        let sourceBytes = try Data(contentsOf: source)

        let output = try converter.convert(source, to: .jpeg)

        XCTAssertEqual(output.lastPathComponent, "sticker-convertito.jpg")
        let info = try TestImages.read(output)
        XCTAssertEqual(info.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(info.width, 16)
        XCTAssertEqual(info.height, 8)
        let opaque = try TestImages.pixel(of: info.image, x: 2, y: 4)
        let transparent = try TestImages.pixel(of: info.image, x: 13, y: 4)
        XCTAssertGreaterThan(opaque[0], 200, "la metà rossa resta rossa: \(opaque)")
        XCTAssertLessThan(opaque[1], 60, "la metà rossa resta rossa: \(opaque)")
        XCTAssertTrue(transparent[0...2].allSatisfy { $0 > 240 }, "la metà trasparente diventa bianca: \(transparent)")
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes, "la sorgente non deve cambiare")
        XCTAssertEqual(try directory.contents(), ["sticker-convertito.jpg", "sticker.webp"])
    }

    func testWebPAsTargetIsUnsupported() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)

        XCTAssertThrowsError(try converter.convert(source, to: .webp)) { error in
            XCTAssertEqual(error as? ImageConversionError, .unsupportedTargetFormat(UTType.webP.identifier))
        }
        XCTAssertEqual(try directory.contents(), ["foto.png"], "nessun file deve essere creato")
    }

    func testTIFFAndHEICWhenWritable() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.file("foto.png")
        try TestImages.write(try TestImages.make(), typeIdentifier: UTType.png.identifier, to: source)

        for format in [ImageFormat.tiff, .heic] {
            guard ImageConverter.canWrite(format) else {
                print("ImageIO non sa scrivere \(format.typeIdentifier) su questo sistema: verifica saltata")
                continue
            }
            let output = try converter.convert(source, to: format)
            let info = try TestImages.read(output)
            XCTAssertEqual(info.typeIdentifier, format.typeIdentifier)
            XCTAssertEqual(info.width, 16)
        }
    }
}
