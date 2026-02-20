//
//  TwoByTwoGridView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 03/02/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A reusable SwiftUI view that arranges up to four items from two input collections into a 2x2 grid.
struct TwoByTwoGridView<Item: Identifiable, Content: View>: View {
    
    // MARK: - Constants
    
    let first: [Item]
    let second: [Item]
    let content: (Item) -> Content
    
    // MARK: - Private Variables
    
    private var merged: [Item] {
        Array((first + second).prefix(4))
    }
    
    // MARK: - Private Constants

    private let rows = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    
    // MARK: - Views
    
    var body: some View {
        GeometryReader { geometry in
            LazyHGrid(rows: rows, spacing: 8) {
                ForEach(merged) { item in
                    content(item)
                        .frame(width: (geometry.size.width - 8) / 2, height: (geometry.size.height - 8) / 2)
                }
            }
        }
    }
}
