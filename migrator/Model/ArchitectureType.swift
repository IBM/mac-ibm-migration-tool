//
//  ArchitectureType.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 03/02/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Enumeration representing different CPU architectures for macOS applications
enum AppArchitecture: String, Codable, Hashable {
    case intel = "x86_64"
    case appleSilicon = "arm64"
    
    /// Human-readable name for the architecture
    var displayName: String {
        switch self {
        case .intel:
            return "Intel"
        case .appleSilicon:
            return "Apple Silicon"
        }
    }
}

/// Enumeration representing the overall architecture type of an application
enum ArchitectureType: String, Codable {
    case intelOnly
    case appleSiliconOnly
    case universal
    case unknown
    
    /// Human-readable name for the architecture type
    var displayName: String {
        switch self {
        case .intelOnly:
            return "app.architecture.badge.intel".localized
        case .appleSiliconOnly:
            return "app.architecture.badge.appleSilicon".localized
        case .universal:
            return "app.architecture.badge.universal".localized
        case .unknown:
            return "app.architecture.badge.unknown".localized
        }
    }
    
    /// Icon name for the architecture type
    var iconName: String {
        switch self {
        case .intelOnly:
            return "cpu"
        case .appleSiliconOnly:
            return "cpu.fill"
        case .universal:
            return "arrow.triangle.2.circlepath"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    var tooltip: String {
        switch self {
        case .intelOnly:
            return "app.architecture.tooltip.intel".localized
        case .appleSiliconOnly:
            return "app.architecture.tooltip.silicon".localized
        case .universal:
            return "app.architecture.tooltip.universal".localized
        case .unknown:
            return "app.architecture.tooltip.unknown".localized
        }
    }
}
