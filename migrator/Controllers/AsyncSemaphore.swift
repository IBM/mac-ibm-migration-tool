//
//  AsyncSemaphore.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 10/12/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// An actor-based semaphore providing safe concurrent access and operation limiting in a Swift
/// Concurrency context, without blocking any thread while waiting for a permit.
///
/// `DispatchSemaphore.wait()` blocks the calling OS thread rather than suspending the calling
/// task. Swift Concurrency tasks run on a size-limited cooperative thread pool, so a thread
/// blocked that way can't be reclaimed to run other tasks - including the task that would call
/// `release()` and unblock it. With enough concurrent waiters, every thread in the pool can end
/// up parked in `wait()`, which deadlocks the pool. This implementation instead suspends waiting
/// tasks with `withCheckedContinuation`, which frees the underlying thread while a task waits.
actor AsyncSemaphore {

    // MARK: - Private Variables

    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializer

    init(value: Int) {
        self.availablePermits = value
    }

    // MARK: - Public Methods

    /// Requests a permit from the semaphore, suspending the calling task until a permit is available.
    ///
    /// Use this method to limit concurrent access to a shared resource by acquiring a token.
    /// The task will be suspended (without blocking its thread) until the semaphore signals availability.
    func request() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a permit back to the semaphore, signaling that a previously acquired resource is now available.
    ///
    /// Call this after completing a task that previously called `request()` to ensure
    /// that other waiting tasks can proceed. Failing to call this method after acquiring
    /// a permit may result in deadlocks or resource starvation.
    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }
}
