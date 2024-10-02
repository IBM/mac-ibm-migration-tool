//
//  Double-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 09/09/2024.
//  Copyright © 2024 IBM. All rights reserved.
//

import Foundation

extension Double {
    /// Generate a pretty formatted string that describe the time left starting from seconds.
    /// - Parameter seconds: seconds left.
    /// - Returns: pretty formatted string describing the time left. e.g. ~ 3 hours and 5 minutes
    func prettyFormattedTimeLeft() -> String {
        let seconds = Int(self)
        let components = (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
        if components.0 == 0 {
            if components.1 == 0 {
                return "Less than a minute"
            }
            return "~ \(components.1 > 0 ? "\(components.1) minute\(components.1 == 1 ? "" : "s")" : "")"
        } else {
            return "~ \(components.0) hour\(components.0 == 1 ? "" : "s")" + (components.1 > 0 ? " and \(components.1) minute\(components.1 == 1 ? "" : "s")" : "")
        }
    }
}
