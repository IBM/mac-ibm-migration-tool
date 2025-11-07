//
//  String-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/02/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension String {
    /// Return the localized instance of the string.
    public var localized: String {
        guard NSLocalizedString(self, comment: "") != self else {
            return self.replacingOccurrences(of: "\\n", with: "\n")
        }
        return NSLocalizedString(self, comment: "")
    }
    
    /// Checks if the string can be converted to an integer.
    public var isNumber: Bool {
        return Int(self) != nil
    }

    /// Checks if the string represents a valid URL with a scheme.
    public var isValidURL: Bool {
        if let url = URL(string: self), url.scheme != nil {
            return true
        }
        return false
    }
    
    /// Extracts a substring between two boundary strings.
    /// - Parameters:
    ///   - upperBound: The starting boundary string.
    ///   - lowerBound: The ending boundary string.
    /// - Returns: The substring between the two boundaries, or nil if either boundary is not found.
    func slice(from upperBound: String, to lowerBound: String) -> String? {
        return (range(of: upperBound)?.upperBound).flatMap { substringFrom in
            (range(of: lowerBound, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}
