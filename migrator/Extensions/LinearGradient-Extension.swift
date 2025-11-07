//
//  LinearGradient-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/12/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

extension LinearGradient {
    /// Return BigButtonSelected custom linear gradient for the given color scheme.
    /// - Parameter colorScheme: the color scheme to use to calculate the LinearGradient.
    /// - Returns: custom LinearGradient.
    static func bigButtonSelected(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            return LinearGradient(colors: [Color(red: 0.08627450980392157, green: 0.40784313725490196, blue: 0.8980392156862745), Color(red: 0.08627450980392157, green: 0.36470588235294116, blue: 0.807843137254902)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color(red: 0, green: 0.47843137254901963, blue: 1)], startPoint: .top, endPoint: .bottom)
        }
    }
    
    /// Return ButtonSelected custom linear gradient for the given color scheme.
    /// - Parameter colorScheme: the color scheme to use to calculate the LinearGradient.
    /// - Returns: custom LinearGradient.
    static func buttonSelected(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            return LinearGradient(colors: [Color(red: 0.08627450980392157, green: 0.40784313725490196, blue: 0.8980392156862745), Color(red: 0.08627450980392157, green: 0.36470588235294116, blue: 0.807843137254902)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color(red: 0, green: 0.47843137254901963, blue: 1)], startPoint: .top, endPoint: .bottom)
        }
    }
}
