//
//  NoBackgroundScroller.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Cocoa

/// Custom NSScroller subclass to remove the background and change alpha on mouse events
class NoBackgroundScroller: NSScroller {
    
    /// Override draw method to only draw the knob
    override func draw(_ dirtyRect: NSRect) {
        self.drawKnob()
    }
    
    /// Override mouseEntered method to animate alpha value on mouse enter
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { (context) in
            context.duration = 0.1
            self.animator().alphaValue = 0.85
        }
    }
    
    /// Override mouseExited method to animate alpha value on mouse exit
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { (context) in
            context.duration = 0.15
            self.animator().alphaValue = 0.35
        }
    }
}
