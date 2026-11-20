//
//  OutputPathAllocatorTests.swift
//  FlipCoreTests
//

import Foundation
import XCTest
@testable import FlipCore

final class OutputPathAllocatorTests: XCTestCase {
    private let allocator = OutputPathAllocator()

    func testUsesConvertedNameNextToSourceWhenFree() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")

        let output = try allocator.outputURL(for: source, fileExtension: "jpg")

        XCTAssertEqual(output.lastPathComponent, "foto-convertito.jpg")
        XCTAssertEqual(output.deletingLastPathComponent().standardizedFileURL, directory.url.standardizedFileURL)
    }

    func testSkipsExistingFiles() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")
        _ = try directory.touch("foto-convertito.jpg")
        _ = try directory.touch("foto-convertito-2.jpg")

        let output = try allocator.outputURL(for: source, fileExtension: "jpg")

        XCTAssertEqual(output.lastPathComponent, "foto-convertito-3.jpg")
    }

    func testOnlyMatchingExtensionCountsAsTaken() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")
        _ = try directory.touch("foto-convertito.tiff")

        let output = try allocator.outputURL(for: source, fileExtension: "jpg")

        XCTAssertEqual(output.lastPathComponent, "foto-convertito.jpg")
    }

    func testBrokenSymlinkCountsAsTaken() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")
        try FileManager.default.createSymbolicLink(
            at: directory.file("foto-convertito.jpg"),
            withDestinationURL: directory.file("non-esiste")
        )

        let output = try allocator.outputURL(for: source, fileExtension: "jpg")

        XCTAssertEqual(output.lastPathComponent, "foto-convertito-2.jpg")
    }

    func testAcceptsLeadingDotAndSourceWithoutExtension() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("scansione")

        let output = try allocator.outputURL(for: source, fileExtension: ".png")

        XCTAssertEqual(output.lastPathComponent, "scansione-convertito.png")
    }

    func testDoesNotCreateFiles() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")

        _ = try allocator.outputURL(for: source, fileExtension: "jpg")

        XCTAssertEqual(try directory.contents(), ["foto.png"])
    }

    func testRejectsInvalidExtension() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")

        for invalid in ["", ".", "a/b"] {
            XCTAssertThrowsError(try allocator.outputURL(for: source, fileExtension: invalid)) { error in
                XCTAssertEqual(error as? OutputPathAllocator.AllocationError, .invalidExtension(invalid))
            }
        }
    }

    func testFailsWhenAllNamesAreTaken() throws {
        let directory = try makeTemporaryDirectory()
        let source = try directory.touch("foto.png")
        _ = try directory.touch("foto-convertito.jpg")
        _ = try directory.touch("foto-convertito-2.jpg")
        let limited = OutputPathAllocator(maxAttempts: 2)

        XCTAssertThrowsError(try limited.outputURL(for: source, fileExtension: "jpg")) { error in
            guard case .noAvailableName = error as? OutputPathAllocator.AllocationError else {
                return XCTFail("errore inatteso: \(error)")
            }
        }
    }
}
