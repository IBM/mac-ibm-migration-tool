//
//  ScrollingTextView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A view that scrolls text back and forth when it exceeds the available width.
struct ScrollingTextView: View {
    
    // MARK: - Constants
    
    /// The text to display.
    let text: String
    
    // MARK: - Variables
    
    /// The desired text style. Default values is set to `.body`.
    var textStyle: Font.TextStyle = .body
    /// The maximum width for the text container. If nil, uses available space.
    var maxWidth: CGFloat?
    
    // MARK: - State Variables
    
    /// The offset for the scrolling animation.
    @State private var offset: CGFloat = 0
    /// Whether the text needs to scroll (exceeds maxWidth).
    @State private var needsScrolling: Bool = false
    /// The actual width of the text content.
    @State private var textWidth: CGFloat = 0
    /// The actual height of the text content.
    @State private var textheight: CGFloat = 0
    /// Animation direction: true = forward, false = backward.
    @State private var animatingForward: Bool = true
    /// The available width from the parent container.
    @State private var availableWidth: CGFloat = 0
    /// Whether to pause scrolling (e.g., when hovering).
    @State private var isPaused: Bool = true
    /// Task handle for managing animation lifecycle.
    @State private var animationTask: Task<Void, Never>?
    
    // MARK: - Private Constants
    
    /// Delay before starting the scroll animation (in seconds).
    private let initialDelay: Double = 1.0
    /// Delay at each end before reversing direction (in seconds).
    private let endDelay: Double = 1.0
    /// Speed of scrolling (points per second).
    private let scrollSpeed: Double = 30.0

    // MARK: - Views
    
    var body: some View {
        GeometryReader { containerGeometry in
            Text(text)
                .customFont(textStyle)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { textGeometry in
                    Color.clear
                        .onAppear {
                            textWidth = textGeometry.size.width
                            textheight = textGeometry.size.height
                            availableWidth = containerGeometry.size.width
                            needsScrolling = textWidth > availableWidth
                            if needsScrolling && !isPaused {
                                startScrolling()
                            }
                        }
                        .onChange(of: containerGeometry.size.width) { newWidth in
                            if maxWidth == nil {
                                availableWidth = newWidth
                                needsScrolling = textWidth > availableWidth
                                offset = 0
                                animatingForward = true
                                if needsScrolling && !isPaused {
                                    startScrolling()
                                }
                            }
                        }
                })
                .offset(x: needsScrolling ? offset : 0)
                .frame(width: min(availableWidth, textWidth), height: textheight, alignment: .leading)
                .clipped()
                .help(needsScrolling ? text: "")
                .onChange(of: text) { _ in
                    animationTask?.cancel()
                    animationTask = nil
                    offset = 0
                    needsScrolling = false
                    animatingForward = true
                }
                .onChange(of: isPaused) { newValue in
                    if needsScrolling {
                        if newValue {
                            animationTask?.cancel()
                            animationTask = nil
                            withAnimation(.easeInOut(duration: 0.3)) {
                                offset = 0
                            }
                        } else {
                            startScrolling()
                        }
                    }
                }
                .onHover { newValue in
                    isPaused = !newValue
                }
                .onDisappear {
                    animationTask?.cancel()
                    animationTask = nil
                }
        }
        .frame(width: textWidth > 0 ? min(availableWidth, textWidth) : nil,
               height: textheight > 0 ? textheight : nil)
    }
    
    // MARK: - Private Methods
    
    /// Starts the scrolling animation.
    private func startScrolling() {
        guard needsScrolling && !isPaused else { return }
        animationTask?.cancel()
        let scrollDistance = textWidth - availableWidth
        let duration = Double(scrollDistance) / scrollSpeed
        
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            guard !Task.isCancelled && !isPaused else { return }
            await animateScroll(distance: scrollDistance, duration: duration)
        }
    }
    
    /// Animates the scroll in the current direction.
    private func animateScroll(distance: CGFloat, duration: Double) async {
        guard !Task.isCancelled && !isPaused else { return }
        
        if animatingForward {
            withAnimation(.linear(duration: duration)) {
                offset = -distance
            }
            try? await Task.sleep(nanoseconds: UInt64((duration + endDelay) * 1_000_000_000))
            guard !Task.isCancelled && !isPaused else { return }
            animatingForward = false
            await animateScroll(distance: distance, duration: duration)
        } else {
            withAnimation(.linear(duration: duration)) {
                offset = 0
            }
            try? await Task.sleep(nanoseconds: UInt64((duration + endDelay) * 1_000_000_000))
            guard !Task.isCancelled && !isPaused else { return }
            animatingForward = true
            await animateScroll(distance: distance, duration: duration)
        }
    }
}
