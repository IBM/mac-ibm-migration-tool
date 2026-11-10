//
//  MigrationETAEstimator.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 28/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Estimates the time left for a migration by learning, from the transfer itself, how long a
/// megabyte and a file take.
///
/// Every observation is a window of active transfer time `t` with the bytes and files moved in it.
/// The estimator fits `t = a·megabytes + b·files` with exponentially forgetting least squares, so
/// `a` is the effective seconds per megabyte (network, TLS, disk) and `b` the real per-file overhead.
/// The estimate is then `a·remainingMegabytes + b·remainingFiles`.
struct MigrationETAEstimator: Sendable {

    // MARK: - Configuration

    /// Active seconds needed before the first estimate is returned.
    let warmUpSeconds: TimeInterval
    /// Time constant, in seconds, of the exponential forgetting of old observations.
    let forgettingTimeConstant: TimeInterval
    /// Time constant, in seconds, of the smoothed transfer rate shown to the user.
    let rateTimeConstant: TimeInterval
    /// Minimum duration of an observation. Shorter samples are accumulated until they reach it,
    /// which avoids fitting on windows where a large chunk simply hasn't completed yet.
    let windowSeconds: TimeInterval

    // MARK: - State

    /// Active seconds recorded so far.
    private(set) var activeSeconds: TimeInterval = 0
    /// Time-weighted moving average of the bytes sent per second, `nil` before any observation.
    private(set) var smoothedBytesPerSecond: Double?

    /// Samples accumulated for the observation window being built.
    private var pendingSeconds: TimeInterval = 0
    private var pendingMegabytes: Double = 0
    private var pendingFiles: Double = 0

    /// Weighted normal equations: `sXX` is `Σ w·x·xᵀ` and `sXY` is `Σ w·x·y`, with `x = (megabytes, files)`.
    private var sMM: Double = 0
    private var sMF: Double = 0
    private var sFF: Double = 0
    private var sMY: Double = 0
    private var sFY: Double = 0

    /// Decayed seconds of all windows and of the windows that made progress. A window with no
    /// progress carries no information for the fit above (`x = 0`), so stalls are accounted for
    /// by scaling the estimate with `weightedTotalSeconds / weightedProgressSeconds`.
    private var weightedTotalSeconds: Double = 0
    private var weightedProgressSeconds: Double = 0

    // MARK: - Initializers

    init(warmUpSeconds: TimeInterval = 15,
         forgettingTimeConstant: TimeInterval = 90,
         rateTimeConstant: TimeInterval = 30,
         windowSeconds: TimeInterval = 3) {
        self.warmUpSeconds = warmUpSeconds
        self.forgettingTimeConstant = forgettingTimeConstant
        self.rateTimeConstant = rateTimeConstant
        self.windowSeconds = windowSeconds
    }

    // MARK: - Public Methods

    /// Records progress made during a stretch of *active* transfer time. Paused, reconnecting and
    /// otherwise inactive time must not be reported here.
    /// - Parameters:
    ///   - deltaBytes: Bytes sent during the stretch.
    ///   - deltaFiles: Files completed during the stretch.
    ///   - activeSeconds: Duration of the stretch.
    mutating func record(deltaBytes: Int, deltaFiles: Int, activeSeconds seconds: TimeInterval) {
        guard seconds > 0, seconds.isFinite else { return }
        activeSeconds += seconds
        pendingSeconds += seconds
        pendingMegabytes += Double(max(0, deltaBytes)) / 1_000_000
        pendingFiles += Double(max(0, deltaFiles))
        guard pendingSeconds >= windowSeconds else { return }
        flushWindow()
    }

    /// Estimated seconds left, or `nil` while there isn't enough data (or the result isn't usable).
    func estimate(remainingBytes: Int, remainingFiles: Int) -> TimeInterval? {
        guard activeSeconds >= warmUpSeconds, let costs = fittedCosts() else { return nil }
        guard weightedProgressSeconds > 0 else { return nil }
        // Recent stalls make the remaining work take proportionally longer.
        let stallFactor = max(1, weightedTotalSeconds / weightedProgressSeconds)
        let result = (costs.secondsPerMegabyte * Double(max(0, remainingBytes)) / 1_000_000
            + costs.secondsPerFile * Double(max(0, remainingFiles))) * stallFactor
        guard result.isFinite else { return nil }
        return result
    }

    // MARK: - Private Methods

    private mutating func flushWindow() {
        let seconds = pendingSeconds
        let megabytes = pendingMegabytes
        let files = pendingFiles
        pendingSeconds = 0
        pendingMegabytes = 0
        pendingFiles = 0

        // Decay older observations by the time elapsed, then add the new one.
        let decay = exp(-seconds / forgettingTimeConstant)
        sMM = sMM * decay + megabytes * megabytes
        sMF = sMF * decay + megabytes * files
        sFF = sFF * decay + files * files
        sMY = sMY * decay + megabytes * seconds
        sFY = sFY * decay + files * seconds
        weightedTotalSeconds = weightedTotalSeconds * decay + seconds
        weightedProgressSeconds *= decay
        if megabytes > 0 || files > 0 {
            weightedProgressSeconds += seconds
        }

        let rate = megabytes * 1_000_000 / seconds
        if let current = smoothedBytesPerSecond {
            let alpha = 1 - exp(-seconds / rateTimeConstant)
            smoothedBytesPerSecond = current + alpha * (rate - current)
        } else {
            smoothedBytesPerSecond = rate
        }
    }

    /// Solves the two-term fit, falling back to a single term when the two aren't separable
    /// (for example only huge files so far) or when a coefficient comes out negative.
    private func fittedCosts() -> (secondsPerMegabyte: Double, secondsPerFile: Double)? {
        let determinant = sMM * sFF - sMF * sMF
        // Relative threshold: near-collinear data (files proportional to megabytes) is unreliable.
        if sMM > 0, sFF > 0, determinant > 1e-6 * sMM * sFF {
            let perMegabyte = (sMY * sFF - sFY * sMF) / determinant
            let perFile = (sFY * sMM - sMY * sMF) / determinant
            if perMegabyte >= 0, perFile >= 0 {
                return (perMegabyte, perFile)
            }
        }
        // One-term fallbacks: bytes only if they carry the signal, otherwise files only.
        if sMM > 0, sMY > 0 {
            return (sMY / sMM, 0)
        }
        if sFF > 0, sFY > 0 {
            return (0, sFY / sFF)
        }
        return nil
    }
}
