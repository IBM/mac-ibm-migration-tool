//
//  View-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

extension View {
    /// Conditionally hides the view based on a Boolean flag.
    /// - Parameter isHidden: A Boolean value that determines whether the view should be hidden.
    /// - Returns: A view that is either hidden or visible based on the `isHidden` parameter.
    func hiddenConditionally(isHidden: Bool) -> some View {
        if isHidden {
            return AnyView(self.hidden())
        } else {
            return AnyView(self)
        }
    }
}
