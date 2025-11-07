//
//  MigratorNetworkProtocol.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 11/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network

/// Custom network protocol for the migrator, implementing framing for network messages.
class MigratorNetworkProtocol: NWProtocolFramerImplementation {

    // MARK: - Static Variables
    
    /// Definition for the custom network protocol, used to create protocol instances.
    static let definition = NWProtocolFramer.Definition(implementation: MigratorNetworkProtocol.self)
    
    // MARK: - Static Constants
    
    /// Label for the protocol, useful for debugging and logging.
    static var label: String { return "MigratorNetworkProtocol" }

    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
    // MARK: - Initializers
    
    /// Required initializer for the protocol framer instance.
    required init(framer: NWProtocolFramer.Instance) { }

    // MARK: - Public Methods
    
    /// Called to start the protocol. Indicates the framer is ready to process data.
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { return .ready }

    /// Called when the framer needs to be woken up, but typically not used for stateless protocols.
    func wakeup(framer: NWProtocolFramer.Instance) { }

    /// Called to stop the protocol. Returns true to indicate the stop was handled.
    func stop(framer: NWProtocolFramer.Instance) -> Bool { return true }

    /// Cleans up any state or resources when the protocol is no longer needed.
    func cleanup(framer: NWProtocolFramer.Instance) { }

    /// Handles outgoing data, adding protocol-specific framing before sending.
    /// - Parameters:
    ///   - framer: The protocol framer instance.
    ///   - message: The message being sent.
    ///   - messageLength: The length of the message payload.
    ///   - isComplete: Whether this is the complete message.
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        // Prepares the custom protocol header with message type and length.
        let type = message.migratorMessageType
        let infoLength = message.migratorMessageInfoLenght
        let header = MigratorNetworkProtocolHeader(type: type.rawValue, length: UInt32(messageLength), infoLength: infoLength)
        
        // Writes the header to the output data stream.
        framer.writeOutput(data: header.encodedData)

        // Writes the message payload to the output data stream without copying, for efficiency.
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch let error {
            logger.log("migratorNetworkProtocol.handleOutput: failed to write output with error \(error.localizedDescription)", type: .error)
        }
    }

    /// Handles incoming data, removing protocol-specific framing and delivering payloads.
    /// - Parameter framer: The protocol framer instance.
    /// - Returns: The number of bytes consumed from the input stream.
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var tempHeader: MigratorNetworkProtocolHeader?
            let headerSize = MigratorNetworkProtocolHeader.encodedSize
            
            // Attempts to parse the header from the incoming data stream.
            let parsed = framer.parseInput(minimumIncompleteLength: headerSize,
                                           maximumLength: headerSize) { (buffer, _) -> Int in
                guard let buffer = buffer else {
                    return 0
                }
                if buffer.count < headerSize {
                    return 0  // Incomplete header, needs more data.
                }
                tempHeader = MigratorNetworkProtocolHeader(buffer)
                return headerSize
            }

            // Proceeds only if a complete header was successfully parsed.
            guard parsed, let header = tempHeader else {
                return headerSize  // Returns the expected size of the header to wait for more data.
            }

            // Determines the message type from the header.
            var messageType = MigratorMessageType.invalid
            if let parsedMessageType = MigratorMessageType(rawValue: header.type) {
                messageType = parsedMessageType
            }

            // Creates a message with the parsed type and delivers it along with the payload.
            let message = NWProtocolFramer.Message(migratorMessageType: messageType, infoLenght: header.infoLength)
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0  // If delivery fails, indicates no bytes were consumed.
            }
        }
    }
}
