//
//  ContinuationState.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 10/12/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// `ContinuationState` is an actor that manages the state of a continuation,
/// ensuring that an operation (such as resuming a continuation)
/// is only performed once.
actor ContinuationState {
    
    // MARK: - Private Variables
    
    private var resumed = false
    
    // MARK: - Public Methods
    
    /// Attempts to mark the continuation as resumed.
    ///
    /// - Returns: `true` if this is the first time the continuation is being resumed, and it is successfully marked as resumed; `false` if the continuation had already been resumed previously.
    func tryResume() -> Bool {
        if !resumed {
            resumed = true
            return true
        }
        return false
    }
}
