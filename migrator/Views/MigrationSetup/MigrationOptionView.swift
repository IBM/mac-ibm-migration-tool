//
//  MigrationOptionView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing a migration option.
struct MigrationOptionView: View {
    
    // MARK: - Variables
    
    /// The migration option to be displayed.
    @ObservedObject var option: MigrationOption
    
    // MARK: - Views
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(option.name)
                    .font(.title2)
                Spacer()
                if !option.isFinalSize {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                if option.size > 0 {
                    Text(option.size.fileSizeToFormattedString)
                }
            }
            .padding(.top, 8)
            HStack {
                VStack(alignment: .leading) {
                    ForEach(option.migrationFileList) { file in
                        MigratorFileView(file: .constant(file), needsDescriptiveLabel: true, showFileSize: false)
                    }
                    ForEach(option.migrationAppList) { file in
                        MigratorFileView(file: .constant(file), needsDescriptiveLabel: true, showFileSize: false)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer()
            Divider()
                .padding(.leading, -36)
                .padding(.trailing, -7)
        }
    }
}

private let MOVPreviewOption = MigrationOption(type: .complete)
#Preview {
    MigrationOptionView(option: MOVPreviewOption)
        .frame(width: 400, height: 200)
        .task {
            await MOVPreviewOption.loadFiles()
        }
}
