//
//  CompactItemsSummaryView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 23/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A compact view that displays a summary of migration items (files and apps) with counts.
/// Used when the number of items exceeds the display threshold.
struct CompactItemsSummaryView: View {
    
    // MARK: - Constants
    
    /// Number of files/folders to display
    let fileCount: Int
    /// Number of applications to display
    let appCount: Int
    
    // MARK: - State Variables
    
    /// Tracks hover state for visual feedback
    @State private var isHovered: Bool = false
    
    // MARK: - Private Computed Properties
    
    /// Localized string for file count
    private var fileCountText: String {
        if fileCount == 1 {
            return "migration.option.compact.folder.singular".localized
        } else {
            return String(format: "migration.option.compact.folders.count".localized, fileCount)
        }
    }
    
    /// Localized string for app count
    private var appCountText: String {
        if appCount == 1 {
            return "migration.option.compact.app.singular".localized
        } else {
            return String(format: "migration.option.compact.apps.count".localized, appCount)
        }
    }
    
    /// Combined accessibility label
    private var accessibilityLabel: String {
        var components: [String] = []
        if fileCount > 0 {
            components.append(fileCountText)
        }
        if appCount > 0 {
            components.append(appCountText)
        }
        return components.joined(separator: ", ")
    }
    
    // MARK: - Views
    
    var body: some View {
        HStack(spacing: 8) {
            if fileCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundColor(.accentColor)
                    Text(fileCountText)
                        .customFont(.body)
                        .lineLimit(1)
                }
            }
            if appCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "app.fill")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .foregroundColor(.accentColor)
                    Text(appCountText)
                        .customFont(.body)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1.0 : 0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: isHovered ? .controlBackgroundColor : .controlColor))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: isHovered ? .controlBackgroundColor : .controlColor))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("migration.option.view.details.hint")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("With Files and Apps") {
    CompactItemsSummaryView(fileCount: 3, appCount: 15)
        .frame(width: 400)
        .padding()
}

#Preview("Files Only") {
    CompactItemsSummaryView(fileCount: 5, appCount: 0)
        .frame(width: 400)
        .padding()
}

#Preview("Apps Only") {
    CompactItemsSummaryView(fileCount: 0, appCount: 12)
        .frame(width: 400)
        .padding()
}
