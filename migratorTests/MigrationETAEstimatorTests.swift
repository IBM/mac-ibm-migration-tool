//
//  MigrationETAEstimatorTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 28/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Testing
@testable import Mac_IBM_Data_Shift

struct MigrationETAEstimatorTests {

    /// Feeds `seconds` of a constant `megabytesPerSecond` / `filesPerSecond` transfer in 1 s steps.
    private func feedSteady(_ estimator: inout MigrationETAEstimator,
                            seconds: Int,
                            megabytesPerSecond: Double,
                            filesPerSecond: Int = 0) {
        for _ in 0..<seconds {
            estimator.record(deltaBytes: Int(megabytesPerSecond * 1_000_000),
                             deltaFiles: filesPerSecond,
                             activeSeconds: 1)
        }
    }

    // MARK: - Estimator

    @Test func returnsNilDuringWarmUp() {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 10, megabytesPerSecond: 10)
        #expect(estimator.estimate(remainingBytes: 500_000_000, remainingFiles: 0) == nil)
    }

    @Test func returnsNilWhenNothingWasTransferred() {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 60, megabytesPerSecond: 0)
        #expect(estimator.estimate(remainingBytes: 500_000_000, remainingFiles: 10) == nil)
    }

    @Test func steadyRateGivesBytesOverRate() throws {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 60, megabytesPerSecond: 10)
        let estimate = try #require(estimator.estimate(remainingBytes: 600_000_000, remainingFiles: 0))
        #expect(abs(estimate - 60) < 3)
        let rate = try #require(estimator.smoothedBytesPerSecond)
        #expect(abs(rate - 10_000_000) < 100_000)
    }

    @Test func learnsPerFileCostFromMixedWorkload() throws {
        // Ground truth: 0.1 s per MB and 0.05 s per file, with a varying mix of both.
        let secondsPerMegabyte = 0.1
        let secondsPerFile = 0.05
        let mixes: [(megabytes: Double, files: Int)] = [(5, 0), (1, 20), (3, 10), (8, 2)]
        // One step per observation window, otherwise the 3 s accumulation would merge every
        // 4-step cycle into the same (collinear) mix.
        var estimator = MigrationETAEstimator(windowSeconds: 0.1)
        for index in 0..<40 {
            let mix = mixes[index % mixes.count]
            let seconds = secondsPerMegabyte * mix.megabytes + secondsPerFile * Double(mix.files)
            estimator.record(deltaBytes: Int(mix.megabytes * 1_000_000), deltaFiles: mix.files, activeSeconds: seconds)
        }
        // 100 MB (10 s) and 1000 files (50 s).
        let estimate = try #require(estimator.estimate(remainingBytes: 100_000_000, remainingFiles: 1000))
        #expect(abs(estimate - 60) < 1)
    }

    @Test func fallsBackToBytesOnlyWhenNoFilesCompleted() throws {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 60, megabytesPerSecond: 20)
        // Files never completed (one huge file): the file term must not blow the estimate up.
        let estimate = try #require(estimator.estimate(remainingBytes: 200_000_000, remainingFiles: 500))
        #expect(abs(estimate - 10) < 1)
    }

    @Test func stallRaisesTheEstimate() throws {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 60, megabytesPerSecond: 10)
        let before = try #require(estimator.estimate(remainingBytes: 600_000_000, remainingFiles: 0))
        feedSteady(&estimator, seconds: 15, megabytesPerSecond: 0)
        let after = try #require(estimator.estimate(remainingBytes: 600_000_000, remainingFiles: 0))
        #expect(after > before)
        #expect(after.isFinite)
    }

    @Test func adaptsWhenTheRateChanges() throws {
        var estimator = MigrationETAEstimator()
        feedSteady(&estimator, seconds: 120, megabytesPerSecond: 20)
        feedSteady(&estimator, seconds: 400, megabytesPerSecond: 5)
        let estimate = try #require(estimator.estimate(remainingBytes: 500_000_000, remainingFiles: 0))
        // Converged on the slow rate (100 s), not the old fast one (25 s).
        #expect(abs(estimate - 100) < 10)
    }

    @Test func ignoresInvalidSamples() {
        var estimator = MigrationETAEstimator()
        estimator.record(deltaBytes: 1_000_000, deltaFiles: 1, activeSeconds: 0)
        estimator.record(deltaBytes: 1_000_000, deltaFiles: 1, activeSeconds: -5)
        estimator.record(deltaBytes: 1_000_000, deltaFiles: 1, activeSeconds: .infinity)
        #expect(estimator.activeSeconds == 0)
        #expect(estimator.smoothedBytesPerSecond == nil)
    }

    // MARK: - Stabilizer

    @Test func roundsToCoarseGranularity() {
        #expect(ETADisplayStabilizer.rounded(34) == 30)
        #expect(ETADisplayStabilizer.rounded(119) == 120)
        #expect(ETADisplayStabilizer.rounded(400) == 420)
        #expect(ETADisplayStabilizer.rounded(3_700) == 3_600)
        #expect(ETADisplayStabilizer.rounded(7_000) == 6_900)
    }

    @Test func stabilizerShowsNothingUntilFirstEstimate() {
        var stabilizer = ETADisplayStabilizer()
        #expect(stabilizer.update(estimate: nil, at: Date()) == nil)
    }

    @Test func stabilizerCountsDownBetweenRefreshes() {
        var stabilizer = ETADisplayStabilizer()
        let start = Date()
        #expect(stabilizer.update(estimate: 600, at: start) == 600)
        // Two seconds later, before the refresh interval: keeps counting down, ignores the raw value.
        #expect(stabilizer.update(estimate: 900, at: start.addingTimeInterval(2)) == 600)
        #expect(stabilizer.update(estimate: 900, at: start.addingTimeInterval(3)) == 600)
        // 100 s later the countdown has advanced; a raw estimate within tolerance doesn't reset it.
        #expect(stabilizer.update(estimate: 520, at: start.addingTimeInterval(100)) == 480)
    }

    @Test func stabilizerIgnoresSmallIncreasesButAcceptsLargeOnes() {
        var stabilizer = ETADisplayStabilizer()
        let start = Date()
        _ = stabilizer.update(estimate: 600, at: start)
        // +10% over the countdown: ignored.
        #expect(stabilizer.update(estimate: 660, at: start.addingTimeInterval(5)) == 600)
        // Clearly higher (+50%): accepted.
        #expect(stabilizer.update(estimate: 900, at: start.addingTimeInterval(10)) == 900)
    }

    @Test func stabilizerAcceptsLowerEstimates() {
        var stabilizer = ETADisplayStabilizer()
        let start = Date()
        _ = stabilizer.update(estimate: 600, at: start)
        #expect(stabilizer.update(estimate: 300, at: start.addingTimeInterval(5)) == 300)
    }
}
