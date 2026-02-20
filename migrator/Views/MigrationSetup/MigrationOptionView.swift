//
//  MigrationOptionView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing a migration option.
struct MigrationOptionView: View {
    
    // MARK: - Variables
    
    /// The migration option to be displayed.
    @ObservedObject var option: MigrationOption
    
    /// Configurable threshold for switching to compact display mode.
    /// When the total number of items (files + apps) exceeds this value,
    /// the view will display a compact summary instead of the full list.
    var displayThreshold: Int = 4
    
    // MARK: - State Variables
    
    /// Controls the presentation of the detail sheet
    @State private var showDetailSheet: Bool = false
    
    // MARK: - Private Computed Properties
    
    /// Total count of items (files + apps)
    private var totalItemCount: Int {
        option.migrationFileList.count + option.migrationAppList.count
    }
    
    /// Determines whether to use compact display mode
    private var shouldUseCompactMode: Bool {
        totalItemCount > displayThreshold
    }
    
    // MARK: - Views
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(option.name)
                    .customFont(.title2)
                Spacer()
                if !option.isFinalSize {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                if option.size > 0 {
                    Text(option.size.fileSizeToFormattedString)
                        .customFont(.body)
                }
            }
            .padding(.top, 8)
            HStack {
                VStack(alignment: .leading) {
                    if shouldUseCompactMode {
                        CompactItemsSummaryView(fileCount: option.migrationFileList.count,
                                                appCount: option.migrationAppList.count)
                        .onTapGesture {
                            showDetailSheet = true
                        }
                    } else {
                        TwoByTwoGridView(first: option.migrationFileList, second: option.migrationAppList.map { $0.migratorFile }) { item in
                            MigratorFileView(file: .constant(item), needsDescriptiveLabel: true, showFileSize: false)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
        }
        .sheet(isPresented: $showDetailSheet) {
            MigrationItemsDetailSheet(option: option)
        }
    }
}
