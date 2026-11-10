//
//  MigratorFileURLTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 19/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

final class MigratorFileURLTests: XCTestCase {

    private var scratch: URL!

    /// A scratch directory inside the home folder, so it sits under an allowed root.
    override func setUpWithError() throws {
        scratch = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MigratorFileURLTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func userURL(_ relativePath: String) -> MigratorFileURL {
        MigratorFileURL(source: .userFolder, relativePath: relativePath)
    }

    private var scratchRelativePath: String {
        scratch.lastPathComponent
    }

    // MARK: - Path shape

    func testPlainPathInsideHomeIsAccepted() throws {
        let url = try userURL("\(scratchRelativePath)/a/b.txt").validatedReceiveURL()
        XCTAssertTrue(url.path.hasSuffix("\(scratchRelativePath)/a/b.txt"))
    }

    func testUnknownSourceIsRejected() {
        let url = MigratorFileURL(source: .unknown, relativePath: "/etc/passwd")
        XCTAssertThrowsError(try url.validatedReceiveURL())
    }

    func testUnknownSourceWithUnparseablePathDoesNotCrash() {
        let url = MigratorFileURL(source: .unknown, relativePath: "not a url \u{0} %%")
        XCTAssertThrowsError(try url.validatedReceiveURL())
    }

    func testParentTraversalIsRejected() {
        XCTAssertThrowsError(try userURL("../../../etc/passwd").validatedReceiveURL())
        XCTAssertThrowsError(try userURL("\(scratchRelativePath)/../../x").validatedReceiveURL())
    }

    func testAbsoluteRelativePathIsRejected() {
        XCTAssertThrowsError(try userURL("/etc/passwd").validatedReceiveURL())
    }

    // MARK: - Symlinks

    func testWriteThroughSymlinkedDirectoryOutsideRootsIsRejected() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: scratch.appendingPathComponent("link"),
                                                   withDestinationURL: outside)

        XCTAssertThrowsError(try userURL("\(scratchRelativePath)/link/evil.txt").validatedReceiveURL())
    }

    func testDanglingSymlinkLeafPointingOutsideIsRejected() throws {
        try FileManager.default.createSymbolicLink(atPath: scratch.appendingPathComponent("dangling").path,
                                                   withDestinationPath: "/private/tmp/does-not-exist-\(UUID().uuidString)")

        XCTAssertThrowsError(try userURL("\(scratchRelativePath)/dangling").validatedReceiveURL())
    }

    func testReplacingExistingSymlinkIsJudgedByItsLocation() throws {
        try FileManager.default.createSymbolicLink(atPath: scratch.appendingPathComponent("link").path,
                                                   withDestinationPath: "/etc/hosts")
        let url = userURL("\(scratchRelativePath)/link")

        XCTAssertThrowsError(try url.validatedReceiveURL())
        XCTAssertNoThrow(try url.validatedReceiveURL(resolvingFinalComponent: false))
    }

    func testSymlinkTargetOutsideRootsIsRejected() throws {
        let link = scratch.appendingPathComponent("l")
        XCTAssertThrowsError(try MigratorFileURL.validateSymlinkTarget("/etc/passwd", linkURL: link))
        XCTAssertThrowsError(try MigratorFileURL.validateSymlinkTarget("../../../../../../etc/passwd", linkURL: link))
    }

    func testSymlinkTargetInsideRootsIsAccepted() throws {
        let link = scratch.appendingPathComponent("sub/l")
        XCTAssertNoThrow(try MigratorFileURL.validateSymlinkTarget("../sibling", linkURL: link))
        XCTAssertNoThrow(try MigratorFileURL.validateSymlinkTarget("/Applications/SomeNewApp.app", linkURL: link))
    }

    // MARK: - Attributes

    func testSanitizedAttributesDropOwnershipAndSpecialBits() {
        var message = FileMessage(with: scratch)
        message.attributes = [
            .posixPermissions: NSNumber(value: 0o4755),
            .ownerAccountID: NSNumber(value: 0),
            .groupOwnerAccountID: NSNumber(value: 0),
            .modificationDate: Date(timeIntervalSince1970: 1000),
            .immutable: NSNumber(value: true)
        ]
        let sanitized = message.sanitizedAttributes

        XCTAssertEqual((sanitized[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        XCTAssertNil(sanitized[.ownerAccountID])
        XCTAssertNil(sanitized[.groupOwnerAccountID])
        XCTAssertNil(sanitized[.immutable])
        XCTAssertNotNil(sanitized[.modificationDate])
    }

    func testSanitizedDirectoryAttributesKeepOwnerAccess() {
        // Mirrors a source `~/Public` that is `d---r-xr-x`, with owner access coming only from an ACL.
        var message = FileMessage(with: scratch)
        message.attributes = [.posixPermissions: NSNumber(value: 0o055)]

        XCTAssertEqual((message.sanitizedDirectoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        // Files keep their mode untouched.
        XCTAssertEqual((message.sanitizedAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o055)
    }
}
