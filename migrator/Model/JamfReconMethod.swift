//
//  JamfReconStyle.swift
//  migrator
//
//  Created by Simone Martorelli on 29/09/2024.
//  © Copyright IBM Corp. 2023, 2024
//

/// The supported methods to run the jamf Inventory Update.
enum JamfReconMethod: String, Codable {
    case direct /// Implies running `sudo jamf recon` command. The app will ask for the user Mac password.
    case selfServicePolicy /// Run a self service policy using deeplinks. The policy takes care of running the recon. The app track the recon in background.
}
