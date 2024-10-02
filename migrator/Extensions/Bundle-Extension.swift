//
//  Bundle-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/08/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension Bundle {
    var name: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "app.name.backup".localized
    }
}
