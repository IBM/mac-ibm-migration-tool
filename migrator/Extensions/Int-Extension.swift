//
//  Int-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/02/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension Int {
    /// Return a string representing a formatted file size using the integers as bytes count.
    var fileSizeToFormattedString: String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(for: self) ?? "Unknown Size"
    }
    
    var timeFormattedString: String {
        let seconds = self % 60
        let minutes = (self / 60) % 60
        let hours = (self / 3600)
        
        if hours == 0 {
            if minutes == 0 {
                return String(format: "%0.2d", seconds)
            }
            return String(format: "%0.2d:%0.2d", minutes, seconds)
        }
        return String(format: "%0.2d:%0.2d:%0.2d", hours, minutes, seconds)
    }
}

extension UInt64 {
    /// Return a string representing a formatted file size using the integers as bytes count.
    var fileSizeToFormattedString: String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(for: self) ?? "Unknown Size"
    }
}
