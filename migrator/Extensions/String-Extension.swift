//
//  String-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/02/2024.
//  © Copyright IBM Corp. 2023, 2024
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
    
    public var isNumber: Bool {
        return Int(self) != nil
    }
    
    func slice(from upperBound: String, to lowerBound: String) -> String? {
        return (range(of: upperBound)?.upperBound).flatMap { substringFrom in
            (range(of: lowerBound, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}
