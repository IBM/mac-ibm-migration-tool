//
//  ConfigProfilePayload.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This struct describes the payload of a configuration profile.
struct ConfigProfilePayload: Decodable {
    
    // MARK: - Constants
    
    let name: String
    let organization: String?
    let identifier: String
    let uuid: String
    let serverURL: String?
    
    // MARK: - Private Enums
    
    private enum CodingKeys: String, CodingKey {
        case name = "_name"
        case organization = "spconfigprofile_organization"
        case identifier = "spconfigprofile_payload_identifier"
        case uuid = "spconfigprofile_payload_uuid"
        case serverURL = "spconfigprofile_payload_data"
    }
    
    // MARK: - Initializers
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.uuid = try container.decode(String.self, forKey: .uuid)
        self.serverURL = (try container.decodeIfPresent(String.self, forKey: .serverURL))?.slice(from: "ServerURL = \"", to: "\"")
    }
}
