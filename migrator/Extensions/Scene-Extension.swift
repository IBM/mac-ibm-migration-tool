//
//  Scene-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

extension Scene {
    /// Adjusts the window resizability based on the content size for macOS 13.0 and above.
    /// - Returns: A modified `Scene` with updated window resizability settings or the original `Scene` for older macOS versions.
    func windowResizabilityContentSize() -> some Scene {
        if #available(macOS 13.0, *) {
            return windowResizability(.contentSize)
        } else {
            return self
        }
    }
}
