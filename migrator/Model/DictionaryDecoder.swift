//
//  DictionaryDecoder.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 12/11/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This class define a JSONDecoder used to decode objects from Dictionaries.
class DictionaryDecoder {
    
    // MARK: - Private Variables
    
    private let decoder: JSONDecoder

    // MARK: - Initializers
    
    init(dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate,
         dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64,
         nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy = .throw,
         keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys) {
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = dateDecodingStrategy
        self.decoder.dataDecodingStrategy = dataDecodingStrategy
        self.decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        self.decoder.keyDecodingStrategy = keyDecodingStrategy
    }

    // MARK: - Public Methods
    
    func decode<T>(_ type: T.Type, from dictionary: [String: Any]) throws -> T where T: Decodable {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        return try decoder.decode(type, from: data)
    }
}
