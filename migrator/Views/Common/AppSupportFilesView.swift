//
//  AppSupportFilesView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/05/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Displays discovered application support files grouped by category.
struct AppSupportFilesView: View {
    
    // MARK: - Variables
    
    /// The discovered support-file metadata to display.
    let appInfo: AppInfo
    
    // MARK: - Views
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appInfo.applicationSupportFiles.isEmpty {
                supportFileCategoryView(title: "selectionView.appSupportFile.applicationSupport.label".localized,
                                        files: Array(appInfo.applicationSupportFiles),
                                        color: .blue)
            }
            
            if !appInfo.containerFiles.isEmpty {
                supportFileCategoryView(title: "selectionView.appSupportFile.containers.label".localized,
                                        files: Array(appInfo.containerFiles),
                                        color: .green)
            }
            
            if !appInfo.groupContainerFiles.isEmpty {
                supportFileCategoryView(title: "selectionView.appSupportFile.groupContainers.label".localized,
                                        files: Array(appInfo.groupContainerFiles),
                                        color: .orange)
            }
            
            if !appInfo.preferenceFiles.isEmpty {
                supportFileCategoryView(title: "selectionView.appSupportFile.preferences.label".localized,
                                        files: Array(appInfo.preferenceFiles),
                                        color: .purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .padding(.vertical, 4)
    }
    
    // MARK: - Private Views
    
    /// Creates a view for a category of support files.
    private func supportFileCategoryView(title: String, files: [URL], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .customFont(.callout, weight: .regular)
                    .foregroundColor(color)
                Text(String(format: "selectionView.appSupportFiles.count.label".localized, files.count))
                    .customFont(.callout)
                    .foregroundColor(.secondary)
            }
            
            ForEach(files.prefix(3), id: \.self) { fileURL in
                Text(String(format: "selectionView.appSupportFiles.supportFile.bullet".localized, fileURL.lastPathComponent))
                    .customFont(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            if files.count > 3 {
                Text(String(format: "selectionView.appSupportFiles.more.label".localized, files.count - 3))
                    .customFont(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
