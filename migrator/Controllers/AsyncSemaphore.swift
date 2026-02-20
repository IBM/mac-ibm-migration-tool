//
//  AsyncSemaphore.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 10/12/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// An actor wrapper around `DispatchSemaphore`, providing safe concurrent access and operation
/// limiting in a Swift Concurrency context.
actor AsyncSemaphore {
    
    // MARK: - Private Variables
    
    private var semaphore: DispatchSemaphore
    
    // MARK: - Initializer
    
    init(value: Int) {
        self.semaphore = DispatchSemaphore(value: value)
    }
    
    // MARK: - Public Methods
    
    /// Requests a permit from the semaphore, blocking the calling task until a permit is available.
    ///
    /// Use this method to limit concurrent access to a shared resource by acquiring a token.
    /// The task will be suspended until the semaphore signals availability.
    func request() {
        semaphore.wait()
    }
    
    /// Releases a permit back to the semaphore, signaling that a previously acquired resource is now available.
    ///
    /// Call this after completing a task that previously called `request()` to ensure
    /// that other waiting tasks can proceed. Failing to call this method after acquiring
    /// a permit may result in deadlocks or resource starvation.
    func release() {
        semaphore.signal()
    }
}
