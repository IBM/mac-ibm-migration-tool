//
//  ProfileConfigTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Data_Shift

final class ProfileConfigTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    // MARK: - parseProfileURL Tests
    
    /// Test that plain paths with $HOMEFOLDER are parsed without # delimiters
    func testParseProfileURL_PlainPathWithHomeFolder() throws {
        let input = "$HOMEFOLDER/Desktop/MyFolder"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let expectedPath = homeDir.appendingPathComponent("Desktop/MyFolder").path
        
        XCTAssertEqual(result?.path, expectedPath, "Plain path should not contain # delimiters")
        XCTAssertFalse(result?.path.contains("#") ?? true, "Path should not contain # characters")
    }
    
    /// Test that regex paths with $HOMEFOLDER wrap only the regex component in # delimiters
    func testParseProfileURL_RegexPathWithHomeFolder() throws {
        let input = "$HOMEFOLDER/Library/.+/Cache"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let expectedPath = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("#.+#")
            .appendingPathComponent("Cache")
            .path
        
        XCTAssertEqual(result?.path, expectedPath, "Only the regex component should contain # delimiters")
        XCTAssertTrue(result?.path.contains("#") ?? false, "Path should contain # characters")
    }
    
    /// Test that plain paths with $APPFOLDER are parsed without # delimiters
    func testParseProfileURL_PlainPathWithAppFolder() throws {
        let input = "$APPFOLDER/Utilities/MyApp.app"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let appDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        let expectedPath = appDir?.appendingPathComponent("Utilities/MyApp.app").path
        
        XCTAssertEqual(result?.path, expectedPath, "Plain path should not contain # delimiters")
        XCTAssertFalse(result?.path.contains("#") ?? true, "Path should not contain # characters")
    }
    
    /// Test that regex paths with $APPFOLDER are wrapped in # delimiters
    func testParseProfileURL_RegexPathWithAppFolder() throws {
        let input = "$APPFOLDER/.+ Creator Studio\\.app"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let appDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        let expectedPath = appDir?.appendingPathComponent("#.+ Creator Studio\\.app#").path
        
        XCTAssertEqual(result?.path, expectedPath, "Regex path should contain # delimiters")
        XCTAssertTrue(result?.path.contains("#") ?? false, "Path should contain # characters")
    }
    
    /// Test that plain paths without variables are parsed without # delimiters
    func testParseProfileURL_PlainPathWithoutVariable() throws {
        let input = "Documents/MyFile.txt"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let expectedPath = homeDir.appendingPathComponent("Documents/MyFile.txt").path
        
        XCTAssertEqual(result?.path, expectedPath, "Plain path should not contain # delimiters")
        XCTAssertFalse(result?.path.contains("#") ?? true, "Path should not contain # characters")
    }
    
    /// Test that regex paths without variables wrap only the regex component in # delimiters
    func testParseProfileURL_RegexPathWithoutVariable() throws {
        let input = "Library/Application Support/.*/Preferences"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let expectedPath = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("#.*#")
            .appendingPathComponent("Preferences")
            .path
        
        XCTAssertEqual(result?.path, expectedPath, "Only the regex component should contain # delimiters")
        XCTAssertTrue(result?.path.contains("#") ?? false, "Path should contain # characters")
    }
    
    /// Test that absolute paths stay absolute when parsed from managed configuration.
    func testParseProfileURL_AbsolutePathStaysAbsolute() throws {
        let input = "/Users/test/Library/Application Support"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        XCTAssertEqual(result?.path, input, "Absolute paths should not be rebased to the current home folder")
    }
    
    /// Test that paths with leading slash are handled correctly
    func testParseProfileURL_PathWithLeadingSlash() throws {
        let input = "$HOMEFOLDER/Desktop/Folder"
        let result = Utils.Customization.parseProfileURL(input)
        
        XCTAssertNotNil(result, "Result should not be nil")
        
        // Verify no double slashes in the path
        XCTAssertFalse(result?.path.contains("//") ?? true, "Path should not contain double slashes")
    }
    
    /// Test various regex special characters
    func testParseProfileURL_VariousRegexCharacters() throws {
        let testCases: [(input: String, shouldHaveDelimiters: Bool)] = [
            ("$HOMEFOLDER/test.txt", false),
            ("$HOMEFOLDER/test.*", true),
            ("$HOMEFOLDER/test+file", true),
            ("$HOMEFOLDER/test?file", true),
            ("$HOMEFOLDER/test[abc]", true),
            ("$HOMEFOLDER/test{1,3}", true),
            ("$HOMEFOLDER/test(group)", true),
            ("$HOMEFOLDER/test^start", true),
            ("$HOMEFOLDER/test$end", true),
            ("$HOMEFOLDER/test|or", true),
            ("$HOMEFOLDER/test\\escape", true),
            ("$HOMEFOLDER/normal/path/file", false)
        ]
        
        for testCase in testCases {
            let result = Utils.Customization.parseProfileURL(testCase.input)
            XCTAssertNotNil(result, "Result should not be nil for: \(testCase.input)")
            
            let hasDelimiters = result?.path.contains("#") ?? false
            XCTAssertEqual(hasDelimiters, testCase.shouldHaveDelimiters,
                           "Failed for: \(testCase.input). Expected delimiters: \(testCase.shouldHaveDelimiters), got: \(hasDelimiters)")
        }
    }
    
    /// Test that complex paths are handled correctly
    func testParseProfileURL_ComplexPaths() throws {
        // Test a path with multiple components
        let input1 = "$HOMEFOLDER/Library/Application Support/MyApp/config.json"
        let result1 = Utils.Customization.parseProfileURL(input1)
        XCTAssertNotNil(result1)
        XCTAssertFalse(result1?.path.contains("#") ?? true, "Complex plain path should not have delimiters")
        
        // Test a path with regex in the middle
        let input2 = "$HOMEFOLDER/Library/.+/Cache/data"
        let result2 = Utils.Customization.parseProfileURL(input2)
        XCTAssertNotNil(result2)
        XCTAssertTrue(result2?.path.contains("#") ?? false, "Complex regex path should have delimiters")
    }
    
    // MARK: - URL Matching Tests
    
    func testPatternURLMatching_PlainPathTreatsDotLiterally() throws {
        let pattern = Utils.Customization.parseProfileURL("$APPFOLDER/Safari.app")
        let safariURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?
            .appendingPathComponent("Safari.app")
        let differentURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?
            .appendingPathComponent("Safarixapp")
        
        XCTAssertNotNil(pattern)
        XCTAssertNotNil(safariURL)
        XCTAssertNotNil(differentURL)
        XCTAssertTrue(Utils.FileManagerHelpers.url(safariURL!, matchesPatternURL: pattern!))
        XCTAssertFalse(Utils.FileManagerHelpers.url(differentURL!, matchesPatternURL: pattern!))
    }
    
    func testPatternURLMatching_RegexComponentMatchesExpectedPath() throws {
        let pattern = Utils.Customization.parseProfileURL("$APPFOLDER/.+ Creator Studio\\.app")
        let matchingURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?
            .appendingPathComponent("Foo Creator Studio.app")
        let nonMatchingURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?
            .appendingPathComponent("Foo Studio.app")
        
        XCTAssertNotNil(pattern)
        XCTAssertNotNil(matchingURL)
        XCTAssertNotNil(nonMatchingURL)
        XCTAssertTrue(Utils.FileManagerHelpers.url(matchingURL!, matchesPatternURL: pattern!))
        XCTAssertFalse(Utils.FileManagerHelpers.url(nonMatchingURL!, matchesPatternURL: pattern!))
    }
    
    func testRelationship_DescendantOfExcludedDirectoryIsContained() throws {
        let excludedURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let descendantURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.example.plist")
        
        let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: descendantURL, toItemAt: excludedURL)
        
        XCTAssertEqual(relationship, .contains)
    }
    
    func testRelationship_AncestorOfAllowedDirectoryIsContainedBy() throws {
        let ancestorURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let allowedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        
        let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: ancestorURL, toItemAt: allowedURL)
        
        XCTAssertEqual(relationship, .containedBy)
    }
}
