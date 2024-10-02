//
//  ConfigProfile.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// this struct describes a configuration profile.
struct ConfigProfile: Decodable {
    
    // MARK: - Constants
    
    let name: String
    let organization: String?
    let installDate: Date?
    let identifier: String?
    let uuid: String?
    let removalDisallowed: Bool?
    let payloads: [ConfigProfilePayload]?
    
    // MARK: - Private Enums
    
    private enum CodingKeys: String, CodingKey {
        case name = "_name"
        case organization = "spconfigprofile_organization"
        case installDate = "spconfigprofile_install_date"
        case identifier = "spconfigprofile_profile_identifier"
        case uuid = "spconfigprofile_profile_uuid"
        case removalDisallowed = "spconfigprofile_RemovalDisallowed"
        case payloads = "_items"
    }
    
    // MARK: - Initializers
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        self.installDate = dateFormatter.date(from: try container.decodeIfPresent(String.self, forKey: .installDate)?.slice(from: "(", to: ")") ?? "")
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        self.uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        self.removalDisallowed = try container.decodeIfPresent(String.self, forKey: .removalDisallowed) ?? "no" == "yes"
        self.payloads = try container.decodeIfPresent([ConfigProfilePayload].self, forKey: .payloads)
    }
}
