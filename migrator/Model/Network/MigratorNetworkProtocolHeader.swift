//
//  MigratorNetworkProtocolHeader.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents the header for messages sent using the `MigratorNetworkProtocol`.
struct MigratorNetworkProtocolHeader: Codable {
    
    // MARK: - Static Variables
    
    /// The size of the encoded header, calculated based on the size of its `UInt32` properties.
    static var encodedSize: Int {
        return (MemoryLayout<UInt32>.size * 3)
    }
    
    // MARK: - Constants
    
    /// The type of the message, used to identify the kind of operation or data being sent.
    let type: UInt32
    /// The length of the message payload, allowing the receiver to know how much data to expect.
    let length: UInt32
    /// An additional field specifying the length of informational data, if any, included in the message.
    let infoLength: UInt32
    
    // MARK: - Variables
    
    /// Encodes the header into a `Data` object, suitable for transmission.
    var encodedData: Data {
        var tempType = type
        var tempLength = length
        var tempInfoLength = infoLength
        
        var data = Data(bytes: &tempType, count: MemoryLayout<UInt32>.size)
        data.append(Data(bytes: &tempLength, count: MemoryLayout<UInt32>.size))
        data.append(Data(bytes: &tempInfoLength, count: MemoryLayout<UInt32>.size))
        return data
    }

    // MARK: - Initializers
    
    /// Initializes a new header with the specified message type, payload length, and optional info length.
    /// - Parameters:
    ///   - type: The type identifier for the message.
    ///   - length: The length of the message payload.
    ///   - infoLength: The length of any additional informational data included in the message (default is 0).
    init(type: UInt32, length: UInt32, infoLength: UInt32 = 0) {
        self.type = type
        self.length = length
        self.infoLength = infoLength
    }

    /// Initializes a header from a raw buffer, typically used when parsing incoming data.
    /// - Parameter buffer: The buffer containing the raw bytes of the header.
    init(_ buffer: UnsafeMutableRawBufferPointer) {
        var tempType: UInt32 = 0
        var tempLength: UInt32 = 0
        var tempInfoLength: UInt32 = 0
        
        withUnsafeMutableBytes(of: &tempType) { typePtr in
            typePtr.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: 0),
                                                            count: MemoryLayout<UInt32>.size))
        }
        withUnsafeMutableBytes(of: &tempLength) { lengthPtr in
            lengthPtr.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: MemoryLayout<UInt32>.size),
                                                              count: MemoryLayout<UInt32>.size))
        }
        withUnsafeMutableBytes(of: &tempInfoLength) { infoLengthPtr in
            infoLengthPtr.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: MemoryLayout<UInt32>.size * 2),
                                                              count: MemoryLayout<UInt32>.size))
        }
        
        type = tempType
        length = tempLength
        infoLength = tempInfoLength
    }
}
