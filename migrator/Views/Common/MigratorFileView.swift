//
//  MigratorFileView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/02/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct that define a view representing a migrator file.
struct MigratorFileView: View {
    
    // MARK: - Variables
    
    /// The file that this view will represent.
    @Binding var file: MigratorFile
    /// Flag that enable descriptive File name.
    var needsDescriptiveLabel: Bool = false
    /// Flag that make directories clickable.
    var allowDirectoryOverview: Bool = true
    /// Flag that make file size visible or not.
    var showFileSize: Bool = false
    ///
    var showSelectionToggle: Bool = false
    
    // MARK: - State Variable
    
    /// State variable to show/hide popover to show content of the directory.
    @State private var showContent: Bool = false
    /// State variable used to show/hide hidden files in the directory content popover.
    @State private var showHiddenFiles: Bool = false
    /// State variable used to show/hide file size in order to wait it to be calculated before.
    @State private var fileSizeAvailable: Bool = false
    /// State variable used to track file selection.
    @State private var isSelected: Bool = false
    
    // MARK: - Private Computed Variables
    
    /// Embellished file name.
    private var descriptiveLabel: String {
        guard needsDescriptiveLabel else { return file.name }
        switch file.type {
        case .directory:
            return "\(file.name) Folder"
        default:
            return "\(file.name)"
        }
    }
    
    // MARK: - Views
    
    var body: some View {
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.fullURL().relativePath))
                .resizable()
                .frame(width: 20, height: 20)
            if file.type == .directory && !file.childFiles.isEmpty && allowDirectoryOverview {
                Button(action: {
                    showContent.toggle()
                }, label: {
                    Text(descriptiveLabel)
                        .frame(maxWidth: 300)
                        .lineLimit(1)
                        .fixedSize()
                })
                .buttonStyle(.link)
                .popover(isPresented: $showContent, arrowEdge: .trailing, content: {
                    VStack {
                        HStack {
                            Toggle(isOn: $showHiddenFiles, label: { })
                            .controlSize(.mini)
                            .toggleStyle(.switch)
                            Text(String(format: "migration.setup.directory.content.hidden.label".localized, showHiddenFiles ? "migration.setup.directory.content.hidden.label.hide".localized : "migration.setup.directory.content.hidden.label.show".localized))
                                .lineLimit(1)
                            Spacer(minLength: 32)
                            Button(action: {
                                NSWorkspace.shared.open(file.url.fullURL())
                            }, label: {
                                HStack {
                                    Text("migration.setup.page.directory.popover.top.label")
                                    Image(systemName: "arrow.up.right.square")
                                }
                            })
                            .buttonStyle(.link)
                            .fixedSize()
                        }
                        ScrollView {
                            ForEach($file.childFiles) { child in
                                if child.isHidden.wrappedValue && !showHiddenFiles {
                                    EmptyView()
                                } else {
                                    MigratorFileView(file: child, allowDirectoryOverview: false, showFileSize: true)
                                }
                            }
                            .padding(.trailing, 16)
                        }
                    }
                    .frame(maxWidth: 500, maxHeight: 400)
                    .padding([.leading, .vertical])
                    .padding(.trailing, 8)
                })
            } else {
                Text(descriptiveLabel)
                    .frame(maxWidth: 300)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer()
            if showFileSize {
                if fileSizeAvailable {
                    Text(file.fileSize.fileSizeToFormattedString)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .padding(.horizontal, 8)
                }
            }
            if showSelectionToggle {
                Toggle(isOn: $isSelected.onUpdate {
                    self.$file.isSelected.wrappedValue = self.isSelected
                }, label: {})
            }
        }
        .opacity(file.isHidden ? 0.7 : 1)
        .onReceive(file.$fileSize) { size in
            guard size != -1 && showFileSize else { return }
            Task { @MainActor in
                self.fileSizeAvailable = true
            }
        }
        .onReceive(file.$isSelected) { newValue in
            guard self.isSelected != newValue else { return }
            self.isSelected = newValue
        }
        .onAppear {
            self.isSelected = file.isSelected
        }
    }
}

#Preview {
    MigratorFileView(file: .constant(MigratorFile(with: FileManager.default.homeDirectoryForCurrentUser)))
        .frame(width: 400, height: 50)
}
