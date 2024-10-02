//
//  Data-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension Data {
    /// Extracts a `Codable` object from a specified range of the data and then removes that range from the data.
    /// - Parameters:
    ///   - range: The range within the data from which to extract the object.
    ///   - type: The type of the object to extract. Must conform to `Codable`.
    /// - Throws: `MigratorError.fileError` if the specified range is not valid within the data.
    /// - Returns: An instance of the specified `Codable` type.
    mutating func extractObject<T: Codable>(from range: Range<Data.Index>, ofType type: T.Type) throws -> T {
        guard self.count >= range.upperBound else {
            throw MigratorError.fileError(type: .noInfo)
        }
        let infoData = self.subdata(in: range)
        self.removeSubrange(range)
        
        return try JSONDecoder().decode(T.self, from: infoData)
    }
    
    /// Encodes a `Codable` object and prepends it to the data.
    /// - Parameter object: The `Codable` object to include.
    /// - Throws: An error if the object cannot be encoded.
    /// - Returns: The byte count of the encoded object.
    mutating func include<T: Codable>(object: T) throws -> Int {
        let encodedObject = try JSONEncoder().encode(object)
        self.insert(contentsOf: encodedObject, at: 0)
        return encodedObject.count
    }
}
