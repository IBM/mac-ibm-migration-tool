//
//  ETADisplayStabilizer.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Keeps the displayed time left calm: it refreshes only every few seconds, counts down with the
/// wall clock in between, ignores small upward revisions and rounds to a coarse granularity.
struct ETADisplayStabilizer: Sendable {

    /// Minimum seconds between two accepted revisions of the displayed value.
    let refreshInterval: TimeInterval
    /// Fractional increase over the running countdown needed before a higher estimate is accepted.
    let increaseTolerance: Double

    private var anchorValue: TimeInterval?
    private var anchorDate: Date?
    private var lastRevisionDate: Date?

    init(refreshInterval: TimeInterval = 4, increaseTolerance: Double = 0.2) {
        self.refreshInterval = refreshInterval
        self.increaseTolerance = increaseTolerance
    }

    /// Feeds the latest raw estimate and returns the value to display, already rounded.
    /// - Parameters:
    ///   - estimate: The raw estimate in seconds, or `nil` while it is not available.
    ///   - date: The current date.
    mutating func update(estimate: TimeInterval?, at date: Date) -> TimeInterval? {
        guard let estimate else { return currentValue(at: date).map(Self.rounded) }
        guard let counted = currentValue(at: date), let lastRevision = lastRevisionDate else {
            accept(estimate, at: date)
            return Self.rounded(estimate)
        }
        if date.timeIntervalSince(lastRevision) >= refreshInterval {
            // Lower estimates are always taken; higher ones only when clearly higher.
            if estimate <= counted || estimate > counted * (1 + increaseTolerance) {
                accept(estimate, at: date)
                return Self.rounded(estimate)
            }
            lastRevisionDate = date
        }
        return Self.rounded(counted)
    }

    /// Rounds a duration to what is worth showing: 10 s under 2 min, 1 min under 1 h, 5 min above.
    static func rounded(_ seconds: TimeInterval) -> TimeInterval {
        let step: TimeInterval
        switch seconds {
        case ..<120: step = 10
        case ..<3600: step = 60
        default: step = 300
        }
        return (seconds / step).rounded() * step
    }

    private mutating func accept(_ value: TimeInterval, at date: Date) {
        anchorValue = value
        anchorDate = date
        lastRevisionDate = date
    }

    private func currentValue(at date: Date) -> TimeInterval? {
        guard let anchorValue, let anchorDate else { return nil }
        return max(0, anchorValue - date.timeIntervalSince(anchorDate))
    }
}
