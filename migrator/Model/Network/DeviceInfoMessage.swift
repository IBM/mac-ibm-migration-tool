//
//  DeviceInfoMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a message containing device information including architecture
struct DeviceInfoMessage: Codable {
    
    // MARK: - Variables
    
    /// The CPU architecture of the device (x86_64 or arm64)
    var architecture: String
    /// The macOS version running on the device
    var osVersion: String
    /// Available storage space in bytes
    var availableSpace: Int
    /// Device model identifier (e.g., "MacBookPro18,1")
    var modelIdentifier: String?
    /// Indicates whether Rosetta 2 is installed on the device.
    var isRosetta2Installed: Bool
    
    // MARK: - Initializers
    
    /// Initialize with current device information
    init() {
        self.architecture = ArchitectureDetector.getCurrentDeviceArchitecture().rawValue
        
        // Get macOS version
        let osVersionInfo = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = "\(osVersionInfo.majorVersion).\(osVersionInfo.minorVersion).\(osVersionInfo.patchVersion)"
        
        // Get available space
        if let homeURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            self.availableSpace = capacity
        } else {
            self.availableSpace = 0
        }
        
        // Get model identifier
        self.modelIdentifier = DeviceInfoMessage.getModelIdentifier()
        self.isRosetta2Installed = FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }
    
    /// Initialize with specific values
    /// - Parameters:
    ///   - architecture: CPU architecture
    ///   - osVersion: macOS version
    ///   - availableSpace: Available storage space
    ///   - modelIdentifier: Device model identifier
    init(architecture: String, osVersion: String, availableSpace: Int, modelIdentifier: String? = nil, isRosetta2Installed: Bool) {
        self.architecture = architecture
        self.osVersion = osVersion
        self.availableSpace = availableSpace
        self.modelIdentifier = modelIdentifier
        self.isRosetta2Installed = isRosetta2Installed
    }
    
    // MARK: - Public Methods
    
    /// Returns the AppArchitecture enum value for this device
    var appArchitecture: AppArchitecture? {
        return AppArchitecture(rawValue: architecture)
    }
    
    /// Checks if this device is Apple Silicon
    var isAppleSilicon: Bool {
        return architecture == AppArchitecture.appleSilicon.rawValue
    }
    
    /// Checks if this device is Intel-based
    var isIntel: Bool {
        return architecture == AppArchitecture.intel.rawValue
    }
    
    // MARK: - Private Methods
    
    /// Gets the model identifier using sysctlbyname
    private static func getModelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
