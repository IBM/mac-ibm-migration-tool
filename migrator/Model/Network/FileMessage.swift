//
//  FileMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 17/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a file and its associated metadata for transfer in the migration process.
struct FileMessage {
    
    // MARK: - Variables
    
    /// Identifies a specific part of a file, used in multipart file transfers.
    var partNumber: Int
    /// File attributes such as modification date, size, etc., stored in a dictionary.
    var attributes: [FileAttributeKey: Any] = [:]
    /// The source file's URL, encapsulated in `MigratorFileURL` to include additional metadata.
    var source: MigratorFileURL

    // MARK: - Initializers
    
    /// Initializes a new `FileMessage` with the specified file URL, part number, and file attributes.
    /// - Parameters:
    ///   - sourceFile: The URL of the source file.
    ///   - part: The part number, defaulting to 0 for single-part files.
    ///   - attributes: A dictionary of file attributes.
    init(with sourceFile: URL, part: Int = 0, attributes: [FileAttributeKey: Any] = [:]) {
        self.partNumber = part
        self.attributes = attributes
        self.source = MigratorFileURL(with: sourceFile)
    }
}

/// Extension to conform `FileMessage` to `Codable` for serialization and deserialization.
extension FileMessage: Codable {
    /// Custom coding keys for encoding and decoding the properties of `FileMessage`.
    private enum CodingKeys: String, CodingKey {
        case partNumber
        case attributes
        case url
    }
    
    /// Decodes an instance of `FileMessage` from a decoder.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partNumber = try container.decode(Int.self, forKey: .partNumber)
        self.source = try container.decode(MigratorFileURL.self, forKey: .url)

        // Decoding attributes requires special handling due to their diverse types.
        let attributesData = try container.decode([String: Data].self, forKey: .attributes)
        var attributes: [FileAttributeKey: Any] = [:]
        for (key, data) in attributesData {
            // Attempts to unarchive each attribute value from its Data representation.
            if let unarchivedObject = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSNumber.self, NSDate.self, NSString.self], from: data) {
                attributes[FileAttributeKey(key)] = unarchivedObject
            }
        }
        self.attributes = attributes
    }
    
    /// Encodes an instance of `FileMessage` to an encoder.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partNumber, forKey: .partNumber)
        try container.encode(source, forKey: .url)
        
        // Attributes are encoded as a dictionary mapping strings to Data.
        var attributesData = [String: Data]()
        for (key, value) in attributes {
            // Attempts to archive each attribute value into Data.
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true) {
                attributesData[key.rawValue] = data
            }
        }
        try container.encode(attributesData, forKey: .attributes)
    }
}
