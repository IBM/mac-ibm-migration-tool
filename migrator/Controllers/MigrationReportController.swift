//
//  MigrationReportController.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2025.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import PDFKit

struct MigrationReportData {
    let migrationStart: Date?
    let migrationEnd: Date?
    let migrationSizeInBytes: Int64?
    let sourceDeviceName: String?
    let targetDeviceName: String?
    let transferMethod: String?
    let chosenMigrationOption: String?
    let migratedFiles: [String]
    let migratedApps: [String]
    let errors: [String]
}

final class MigrationReportController {
    
    // MARK: - Static Constants
    
    static let shared = MigrationReportController()
    
    // MARK: - Private Properties
    
    // Custom serial queue for PDF generation and saving
    private let customQueue = DispatchQueue(label: "com.ibm.migrator.reportCustomQueue", qos: .utility)
    private var migrationStart: Date?
    private var migrationEnd: Date?
    private var migrationSizeInBytes: Int64 = 0
    private var sourceDeviceName: String?
    private var targetDeviceName: String?
    private var transferMethod: String?
    private var chosenMigrationOption: String?
    private var migratedFiles: [String] = []
    private var migratedApps: [String] = []
    private var errors: [String] = []
    private let logger = MLogger.main
    
    // MARK: - Public Properties
    
    var reportURL: URL
    
    // MARK: - Initializer
    
    init() {
        let baseURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "MigrationReport_\(formatter.string(from: .now)).pdf"
        reportURL = baseURL.appendingPathComponent(fileName)
        self.sourceDeviceName = Host.current().localizedName ?? "server.page.default.device.name"
    }
    
    // MARK: - Public Methods
    
    func setMigrationStart(_ date: Date = .now) {
        self.migrationStart = date
        self.saveToUserDefaults(key: .lastMigrationStartDate, value: date as NSDate)
        self.generateAndSavePDF()
    }
    
    func setMigrationEnd(_ date: Date = .now) {
        self.migrationEnd = date
        self.saveToUserDefaults(key: .lastMigrationEndDate, value: date as NSDate)
        self.generateAndSavePDF()
    }
    
    func setTargetDevice(_ target: String) {
        self.targetDeviceName = target
        self.saveToUserDefaults(key: .lastMigrationTargetDevice, value: target as NSString)
        self.generateAndSavePDF()
    }
    
    func addMigratedFile(_ file: String) {
        logger.log("migrationReportcontroller.addMigratedFile: Adding migrated file to report: \(file)", type: .debug)
        self.migratedFiles.append(file)
        self.generateAndSavePDF()
    }
    
    func addMigratedApp(_ app: String) {
        logger.log("migrationReportcontroller.addMigratedApp: Adding migrated app to report: \(app)", type: .debug)
        self.migratedApps.append(app)
        self.generateAndSavePDF()
    }
    
    func addError(_ errorMessage: String) {
        self.errors.append(errorMessage)
        self.saveToUserDefaults(key: .lastMigrationErrors, value: errors as NSArray)
        self.generateAndSavePDF()
    }
    
    func setMigrationSize(_ bytes: Int64) {
        self.migrationSizeInBytes = bytes
        self.saveToUserDefaults(key: .lastMigrationSize, value: bytes as NSNumber)
        self.generateAndSavePDF()
    }
    
    func setMigrationTransferMethod(_ method: String) {
        self.transferMethod = method
        self.saveToUserDefaults(key: .lastMigrationTransferMethod, value: method as NSString)
        self.generateAndSavePDF()
    }
    
    func setMigrationChosenOption(_ option: String) {
        self.chosenMigrationOption = option
        self.saveToUserDefaults(key: .lastMigrationChosenOption, value: option as NSString)
        self.generateAndSavePDF()
    }
    
    /// Resets the stored data (in case you want to reuse the instance for another migration)
    func reset() {
        migrationStart = nil
        migrationEnd = nil
        sourceDeviceName = nil
        targetDeviceName = nil
        migrationSizeInBytes = 0
        migratedFiles.removeAll()
        migratedApps.removeAll()
        errors.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func buildPDF(from data: MigrationReportData) -> Data? {
        let pdfDocument = PDFDocument()
        let content = buildPrintableContent(from: data)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        
        let image = NSImage(size: pageRect.size)
        image.lockFocus()
        content.draw(in: CGRect(x: 20, y: 20, width: pageRect.width - 40, height: pageRect.height - 40))
        image.unlockFocus()
        
        if let page = PDFPage(image: image) {
            pdfDocument.insert(page, at: 0)
        }
        
        return pdfDocument.dataRepresentation()
    }
    
    // swiftlint:disable function_body_length
    private func buildPrintableContent(from data: MigrationReportData) -> NSAttributedString {
        let attrString = NSMutableAttributedString()
        func addHeading(_ str: String) {
            attrString.append(NSAttributedString(string: "\(str)\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]))
        }
        func addLine(_ str: String) {
            attrString.append(NSAttributedString(string: "\(str)\n", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .full
        
        addHeading("Migration Report")
        addLine("Last update on: \(dateFormatter.string(from: .now))")
        addLine("")
        
        addHeading("Migration Summary")
        let startTimeString = data.migrationStart != nil ? dateFormatter.string(from: data.migrationStart!) : "N/P"
        addLine("Start Time: \(startTimeString)")
        let endTimeString = data.migrationEnd != nil ? dateFormatter.string(from: data.migrationEnd!) : "N/P"
        addLine("End Time: \(endTimeString)")
        
        if let size = data.migrationSizeInBytes {
            let sizeMB = Double(size) / 1_048_576.0
            addLine(String(format: "Total Size: %.2f MB", sizeMB))
        }
        
        addLine("Source Device: \(data.sourceDeviceName ?? "N/P")")
        addLine("Target Device: \(data.targetDeviceName ?? "N/P")")
        addLine("")
        
        if let option = data.chosenMigrationOption, !option.isEmpty {
            addLine("Selected Migration Option: \(option)")
            addLine("")
        }
        
        if let method = data.transferMethod, !method.isEmpty {
            addLine("Transfer Method: \(method)")
            addLine("")
        }
        
        addHeading("Migrated Files/Directories")
        if data.migratedFiles.isEmpty {
            addLine("None")
        } else {
            data.migratedFiles.forEach {
                addLine("• \($0)")
            }
        }
        addLine("")
        
        addHeading("Migrated Apps")
        if data.migratedApps.isEmpty {
            addLine("None")
        } else {
            data.migratedApps.forEach {
                addLine("• \($0)")
            }
        }
        addLine("")
        
        addHeading("Errors")
        if data.errors.isEmpty {
            addLine("No errors reported.")
        } else {
            data.errors.forEach {
                addLine("• \($0)")
            }
        }
        
        return attrString
    }
    // swiftlint:enable function_body_length
    
    /// Generate and save the PDF report.
    private func generateAndSavePDF() {
        guard MigrationController.shared.operatingMode == .browser && AppContext.shouldGenerateReport else { return }
        logger.log("migrationReportcontroller.generateAndSavePDF: Generating PDF report...", type: .debug)
        customQueue.async {
            let reportData = MigrationReportData(
                migrationStart: self.migrationStart,
                migrationEnd: self.migrationEnd,
                migrationSizeInBytes: self.migrationSizeInBytes,
                sourceDeviceName: self.sourceDeviceName,
                targetDeviceName: self.targetDeviceName,
                transferMethod: self.transferMethod,
                chosenMigrationOption: self.chosenMigrationOption,
                migratedFiles: self.migratedFiles,
                migratedApps: self.migratedApps,
                errors: self.errors
            )
            
            if let pdfData = self.buildPDF(from: reportData) {
                self.savePDF(pdfData: pdfData)
            }
        }
    }
    
    private func savePDF(pdfData: Data) {
        logger.log("migrationReportcontroller.savePDF: Saving PDF report to \(reportURL.relativePath)", type: .debug)
        
        // If the file exists, remove it first to avoid createFile failure
        if FileManager.default.fileExists(atPath: reportURL.relativePath) {
            logger.log("migrationReportcontroller.savePDF: Existing report file found, removing it", type: .debug)
            do {
                try FileManager.default.removeItem(atPath: reportURL.relativePath)
            } catch {
                logger.log("migrationReportcontroller.savePDF: Error removing existing report file: \(error.localizedDescription)", type: .error)
                return
            }
        }
        
        // Create the new file with the updated content
        guard FileManager.default.createFile(atPath: reportURL.relativePath, contents: pdfData) else {
            logger.log("migrationReportcontroller.savePDF: Error creating report file", type: .error)
            return
        }
        logger.log("migrationReportcontroller.savePDF: PDF report saved successfully!", type: .debug)
    }
    
    private func saveToUserDefaults(key: Utils.UserDefaultsHelpers.ReportKeys, value: Any) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
