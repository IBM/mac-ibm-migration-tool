//
//  Double-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 09/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension Double {
    /// Generate a pretty formatted string that describe the time left starting from seconds.
    /// - Parameter seconds: seconds left.
    /// - Returns: pretty formatted string describing the time left. e.g. ~ 3 hours and 5 minutes
    func prettyFormattedTimeLeft() -> String {
        guard self.isFinite, !self.isNaN else { return "-" }
        let clamped = max(self, 0)
        let seconds = Int(clamped.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 && minutes == 0 {
            return "Less than a minute"
        }
        if hours == 0 {
            let minuteLabel = minutes == 1 ? "minute" : "minutes"
            return "~ \(minutes) \(minuteLabel)"
        } else {
            let hourLabel = hours == 1 ? "hour" : "hours"
            if minutes > 0 {
                let minuteLabel = minutes == 1 ? "minute" : "minutes"
                return "~ \(hours) \(hourLabel) and \(minutes) \(minuteLabel)"
            } else {
                return "~ \(hours) \(hourLabel)"
            }
        }
    }
}
