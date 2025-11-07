//
//  NSTableView-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import AppKit

/// Custom subclass of NSTableView
extension NSTableView {
    /// Override the viewDidMoveToWindow method to customize the table view when it's added to a window
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        backgroundColor = NSColor.clear
        enclosingScrollView?.drawsBackground = false
        enclosingScrollView?.verticalScroller = NoBackgroundScroller()
    }
}
