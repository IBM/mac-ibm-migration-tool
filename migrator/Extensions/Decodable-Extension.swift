//
//  Decodable-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension Decodable {
    /// Initializing object decoding JSON format string.
    /// - Parameter json: the JSON format string.
    /// - Throws: deconding or data errors.
    init(from json: String) throws {
        guard let jsonData = json.data(using: .utf8) else {
            throw MigratorError.internalError(type: .data)
        }
        do {
            self = try JSONDecoder().decode(Self.self, from: jsonData)
        } catch {
            throw MigratorError.internalError(type: .data)
        }
    }
    /// Intializing obeject from decoding JSON file.
    /// - Parameter url: JSON file url.
    /// - Throws: deconding or url errors.
    init(from url: URL) throws {
        guard let jsonData = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw MigratorError.internalError(type: .data)
        }
        do {
            self = try JSONDecoder().decode(Self.self, from: jsonData)
        } catch {
            throw MigratorError.internalError(type: .data)
        }
    }
}
