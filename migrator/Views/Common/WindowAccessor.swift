//
//  WindowAccessor.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2024.
//  © Copyright IBM Corp. 2023, 2026
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
        let view = WindowObservingView()
        view.onWindowAttached = { newWindow in
            newWindow.delegate = self.appDelegate
            self.window = newWindow
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A view that reports the window it is attached to as soon as it is available,
/// since `window` is still nil when the representable creates the view.
private final class WindowObservingView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onWindowAttached?(window)
    }
}
