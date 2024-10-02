//
//  Array-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 06/05/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

// swiftlint:disable force_cast
extension Array {
    mutating func checkAndAppendFile(_ file: MigratorFile) {
        guard file.type != .socket else { return }
        self.append(file as! Element)
    }
}
// swiftlint:enable force_cast
