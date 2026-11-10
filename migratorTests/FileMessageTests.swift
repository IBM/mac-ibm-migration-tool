//
//  FileMessageTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 16/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

final class FileMessageTests: XCTestCase {

    private let sourceURL = URL(fileURLWithPath: "/tmp/large-file.bin")

    /// The byte offset used to place a multipart chunk must survive a round trip.
    func testByteOffset_RoundTrips() throws {
        let message = FileMessage(with: sourceURL, part: 3, byteOffset: 100_663_296)
        let decoded = try JSONDecoder().decode(FileMessage.self, from: JSONEncoder().encode(message))

        XCTAssertEqual(decoded.partNumber, 3)
        XCTAssertEqual(decoded.byteOffset, 100_663_296)
    }

    /// A message without an offset (single-part files, or a peer that predates the field)
    /// must still decode, with the offset left unset.
    func testByteOffset_AbsentDecodesAsNil() throws {
        let message = FileMessage(with: sourceURL, part: 0)
        let decoded = try JSONDecoder().decode(FileMessage.self, from: JSONEncoder().encode(message))

        XCTAssertNil(decoded.byteOffset)
        XCTAssertEqual(decoded.partNumber, 0)
    }
}
