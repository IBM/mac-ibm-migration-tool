//
//  ManagedEnvironment.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This struct represents a MDM environment.
struct ManagedEnvironment {
    
    // MARK: - Variables
    
    var name: String
    var serverURL: String
    var reconPolicyID: String

    // MARK: - Initializers

    init(name: String, serverURL: String, reconPolicyID: String) {
        self.name = name
        self.reconPolicyID = reconPolicyID

        /// Allow for serverURL to be input without the "/mdm/ServerURL" suffix.
        if !serverURL.hasSuffix("/mdm/ServerURL") {
            if serverURL.hasSuffix("/") {
                self.serverURL = serverURL + "mdm/ServerURL"
            } else {
                self.serverURL = serverURL + "/mdm/ServerURL"
            }
        } else {
            /// The serverURL is already formatted correctly.
            self.serverURL = serverURL
        }
    }
}
