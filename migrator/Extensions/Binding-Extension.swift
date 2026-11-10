//
//  Binding-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

extension Binding where Value: Sendable {
    /// When the `Binding`'s `wrappedValue` changes, the given closure is executed.
    /// - Parameter closure: Chunk of code to execute whenever the value changes.
    /// - Returns: New `Binding`.
    func onUpdate(_ closure: @escaping @MainActor @Sendable () -> Void) -> Binding<Value> {
        let base = self
        return Binding(get: {
            base.wrappedValue
        }, set: { newValue in
            base.wrappedValue = newValue
            // SwiftUI always writes bindings from the main thread.
            MainActor.assumeIsolated {
                closure()
            }
        })
    }
}
