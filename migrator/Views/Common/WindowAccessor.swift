//
//  WindowAccessor.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Used to access the NSWindow item.
struct WindowAccessor: NSViewRepresentable {
    
    // MARK: - Environment Objects
    
    @EnvironmentObject private var appDelegate: AppDelegate
    
    // MARK: - Binding Variables
    
    @Binding var window: NSWindow?
    
    // MARK: - NSViewRepresentable methods implementation
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            self.window = view.window
            self.window?.delegate = self.appDelegate
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
