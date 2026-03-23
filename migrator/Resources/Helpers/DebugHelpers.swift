//
//  DebugHelpers.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 18/03/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

struct DebugHelpers {
    struct AppContext {
        /// Test list of paths excluded during local debug runs.
        static let debugExcludedPathsList: [String] = {
            return ["$HOMEFOLDER/DebugMigration/Excluded",
                    "$APPFOLDER/DebugExcluded.app",
                    "$HOMEFOLDER/Library/Application Support/.*/Preferences"]
        }()
        
        /// Test list of explicitly allowed paths used during local debug runs.
        static let debugAllowedPathsList: [String] = {
            return ["$HOMEFOLDER/DebugMigration/Allowed",
                    "$APPFOLDER/DebugAllowed.app",
                    "$HOMEFOLDER/Library/Application Support/.*/Preferences/Keep"]
        }()
    }
}
