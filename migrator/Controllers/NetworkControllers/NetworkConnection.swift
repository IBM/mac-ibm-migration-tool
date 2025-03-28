//
//  NetworkConnection.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//
//  swiftlint:disable function_body_length type_body_length file_length

import Foundation
import Network
import Combine

/// Represents and manages a network connection, handling both incoming and outgoing data transfer.
final class NetworkConnection {

    // MARK: - Constants
    
    /// The actual network connection being managed.
    let connection: NWConnection
    /// Subject for publishing hostname changes of the connected device.
    let onHostNameChange = PassthroughSubject<String, Never>()
    /// Subject for publishing available space changes on the connected device.
    let onAvailableSpaceChange = PassthroughSubject<Int, Never>()
    /// Subject for publishing availability of the connected device to receive data.
    let onReadyToReceive = PassthroughSubject<Bool, Never>()
    /// Subject for publishing the receive of the migration metadata from the source device.
    let onMigrationMetadataReceived = PassthroughSubject<Int, Never>()
    /// Subject for publishing size of bytes received from file migration.
    let onBytesReceived = PassthroughSubject<Int, Never>()
    /// Subject for publishing size of bytes sent during file migration.
    let onBytesSent = PassthroughSubject<Int, Never>()
    /// Subject for publishing the completion of the migration.
    let onMigrationCompleted = PassthroughSubject<Bool, Never>()
    /// Subject for publishing new connection states.
    let onNewConnectionState = PassthroughSubject<NWConnection.State, Never>()
    /// Subject for publishing when a file have been sent.
    let onFileSent = PassthroughSubject<Int, Never>()
    
    // MARK: - Variables
    
    /// Stores the hostname of the connected device and publishes changes to subscribers.
    var connectedDeviceHostName: String = "" {
        didSet {
            self.onHostNameChange.send(connectedDeviceHostName)
        }
    }
    /// Stores the available space on the connected device and publishes changes to subscribers.
    var connectedDeviceAvailableSpace: Int = 0 {
        didSet {
            self.onAvailableSpaceChange.send(connectedDeviceAvailableSpace)
        }
    }
    /// Stores the size of the migration in bytes.
    var migrationSizeInBytes: Int = 0 {
        didSet {
            self.onMigrationMetadataReceived.send(migrationSizeInBytes)
        }
    }
    var isMigrationCompleted: Bool = false {
        didSet {
            self.onMigrationCompleted.send(isMigrationCompleted)
            if isMigrationCompleted {
                self.connection.cancel()
            }
        }
    }
    /// Stores symbolic link messages that need to be sent to the connected device.
    var symlinks: [SymbolicLinkMessage] = []
    /// Provides the current state of the network connection.
    var state: NWConnection.State {
        return connection.state
    }
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
    // MARK: - Intializers
    
    /// Initializes a new network connection for outgoing connections.
    /// - Parameters:
    ///   - endpoint: The network endpoint to connect to.
    ///   - passcode: A passcode required for establishing the connection.
    init(endpoint: NWEndpoint, withPasscode passcode: String) {
        logger.log("newtorkConnection.initOutgoingConnection: endpoint \"\(endpoint.debugDescription)\"", type: .default)
        let parameters = NWParameters(passcode: passcode)
        parameters.attribution = .developer
        connection = NWConnection(to: endpoint, using: parameters)
        connection.pathUpdateHandler = { path in
            self.logger.log("newtorkConnection.pathUpdateHandler: newPath \"\(path.debugDescription)\"")
        }
        connection.betterPathUpdateHandler = { betterPathAvailable in
            self.logger.log("newtorkConnection.betterPathUpdateHandler: betterPathAvailable \"\(betterPathAvailable.description)\"")
        }
        connection.viabilityUpdateHandler = { available in
            self.logger.log("newtorkConnection.viabilityUpdateHandler: isAvailable \"\(available.description)\"")
        }
        connection.stateUpdateHandler = { newState in
            self.logger.log("newtorkConnection.stateUpdateHandler: newState \"\(String(describing: newState))\"", type: .default)
            self.onNewConnectionState.send(newState)
            if case .ready = newState {
                self.receiveNextMessage()
                Task {
                    try? await self.sendHostName()
                }
            }
        }
    }

    /// Initializes a new network connection for handling incoming connections.
    /// - Parameter connection: The incoming network connection.
    init(connection: NWConnection) {
        logger.log("newtorkConnection.initIncomingConnection: connection \"\(connection.debugDescription)\"", type: .default)
        self.connection = connection
        connection.stateUpdateHandler = { newState in
            self.logger.log("newtorkConnection.stateUpdateHandler: new state \"\(String(describing: newState))\"", type: .default)
            self.onNewConnectionState.send(newState)
            if case .ready = newState {
                self.receiveNextMessage()
                Task {
                    try? await self.sendAvailableFreeSpace()
                }
            }
        }
        connection.start(queue: .main)
    }
    
    // MARK: - Public Methods
    
    /// Asynchronously sends a file to the connected device.
    /// - Parameter file: The file to send.
    func sendFile(_ file: MigratorFile) async throws {
        if file.type == .app {
            try await self.sendFile(file.url.fullURL())
        } else {
            try await _sendFile(file)
            try await sendSymlinks()
        }
    }
    
    /// Asynchronously sends a file to the connected device.
    /// - Parameter fileURL: The URL of the file to send.
    private func sendFile(_ fileURL: URL) async throws {
        try await _sendFile(at: fileURL)
        try await sendSymlinks()
    }
    
    /// Sends the hostname of the current device to the connected device.
    func sendHostName() async throws {
        if let data = (Host.current().localizedName ?? "Connected Device").data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .hostname, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "Hostname",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
        }
    }
    
    /// Sends the available free space of the current device to the connected device.
    func sendAvailableFreeSpace() async throws {
        if let data = Utils.freeSpaceOnDevice.description.data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .availableSpace, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "FreeSpace",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
        }
    }
    
    func sendMigrationSize(_ size: Int) async throws {
        if let data = size.description.data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .metadata, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "MigrationSize",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
            onReadyToReceive.send(true)
        }
    }
    
    func sendMigrationCompleted() async throws {
        if let data = "Completion".data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .result, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "MigrationCompleted",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
            isMigrationCompleted = true
        }
    }
    
    // MARK: - Private Methods
    
    /// A wrapper method to send data asynchronously over the network connection.
    /// - Parameters:
    ///   - content: The data to be sent.
    ///   - contentContext: The context for the data being sent, including any associated metadata.
    private func sendAsyncWrapper(content: Data, contentContext: NWConnection.ContentContext = .defaultMessage) async throws {
        logger.log("newtorkConnection.sendAsync: sending message \"\(contentContext.identifier)\"", type: .debug)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: content, contentContext: contentContext, isComplete: true, completion: .contentProcessed({ error in
                if let error = error {
                    MLogger.main.log("newtorkConnection.sendAsync: error sending message \"\(contentContext.identifier)\", error \"\(error.localizedDescription)\"", type: .error)
                    continuation.resume(throwing: error)
                } else {
                    MLogger.main.log("newtorkConnection.sendAsync: done sending message \"\(contentContext.identifier)\"")
                    continuation.resume()
                }
            }))
        }
    }
    
    private func closeFile(_ fileHandle: FileHandle) throws {
        do {
            try fileHandle.close()
        } catch let error {
            throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
        }
    }
    
    /// Handles the sending of a file, breaking it into chunks if necessary, and collecting symbolic links as needed.
    /// - Parameter file: The file to send.
    private func _sendFile(_ file: MigratorFile) async throws {
        logger.log("networkConnection.sendfile: preparing file \"\(file.url.fullURL().relativePath)\"")
        let chunkSize: UInt64 = 200000000
        
        if file.type == .symlink {
            do {
                let destinationPath = try FileManager.default.destinationOfSymbolicLink(atPath: file.url.fullURL().relativePath)
                guard let destinationURL = URL(string: destinationPath) else {
                    logger.log("networkConnection.sendfile: impossible to create URL from \"\(destinationPath)\"", type: .error)
                    return
                }
                logger.log("networkConnection.sendfile: file \"\(file.url.fullURL().relativePath)\" is alias of \"\(destinationPath)\"")
                let destinationTrackedURL = MigratorFileURL(with: destinationURL)
                let sourceTrackedURL = MigratorFileURL(with: file.url.fullURL())
                if destinationTrackedURL.source == .unknown {
                    let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: file.url.fullURL().deletingLastPathComponent()), relativeDestination: destinationPath)
                    symlinks.append(infoData)
                } else {
                    let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: URL(string: destinationPath)!))
                    symlinks.append(infoData)
                }
                return
            } catch {
                logger.log("networkConnection.sendfile: impossible to create symlink with error -> \(error.localizedDescription)", type: .error)
            }
        }
        
        guard FileManager.default.fileExists(atPath: file.url.fullURL().relativePath) else {
            logger.log("networkConnection.sendfile: file \"\(file.url.fullURL().relativePath)\" doesn't exists", type: .error)
            throw MigratorError.fileError(type: .noData)
        }
            
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.fullURL().relativePath) as [FileAttributeKey: Any] else {
            logger.log("networkConnection.sendfile: failed to get attributes of file \"\(file.url.fullURL().relativePath)\"", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }
        
        if file.type == .directory || file.type == .app {
            let infoData = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            guard var data = "directory".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.internalError(type: .data)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .directory, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "Directory",
                                                      metadata: [message])
            logger.log("networkConnection.sendfile: sending data of directory at \"\(file.url.fullURL().relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onFileSent.send(1)
            self.onBytesSent.send(data.count)

            logger.log("networkConnection.sendfile: start sending content of directory \"\(file.url.fullURL().relativePath)\"")
            if !file.childFiles.isEmpty {
                for child in file.childFiles {
                    try? await sendFile(child)
                    self.onBytesSent.send(data.count)
                }
            } else {
                let unretainedChilds = await file.fetchUnretainedChilds()
                for child in unretainedChilds {
                    try? await sendFile(child)
                    self.onBytesSent.send(data.count)
                }
            }
            return
        }
        
        guard let fileHandle = FileHandle(forReadingAtPath: file.url.fullURL().relativePath) else {
            logger.log("networkConnection.sendfile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }

        var availableBytes = (attributes as NSDictionary).fileSize()
        var parsedBytes: UInt64 = 0
    
        logger.log("networkConnection.sendfile: start sending data of file \"\(file.url.fullURL().relativePath)\"")
        if availableBytes > chunkSize {
            var partNumber: UInt32 = 0
            do {
                try fileHandle.seek(toOffset: parsedBytes)
            } catch let error {
                logger.log("networkConnection.sendfile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
            }
            while availableBytes > 0 {
                let infoData = FileMessage(with: file.url.fullURL(), part: Int(partNumber), attributes: attributes)
                guard var chunk = try? fileHandle.read(upToCount: Int(min(chunkSize, availableBytes))),
                      let infoDataLenght = try? chunk.include(object: infoData)else {
                    try closeFile(fileHandle)
                    logger.log("networkConnection.sendfile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .noData)
                }
                let message = NWProtocolFramer.Message(migratorMessageType: .multipartFile, infoLenght: UInt32(infoDataLenght))
                let context = NWConnection.ContentContext(identifier: "Chunk",
                                                          metadata: [message])
                
                try await sendAsyncWrapper(content: chunk, contentContext: context)
                self.onBytesSent.send(chunk.count)
                            
                parsedBytes += min(chunkSize, availableBytes)
                if availableBytes > chunkSize {
                    availableBytes -= chunkSize
                } else {
                    availableBytes = 0
                }
                partNumber += 1
                
                do {
                    try fileHandle.seek(toOffset: parsedBytes)
                } catch let error {
                    logger.log("networkConnection.sendfile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
                }
            }
        } else if availableBytes == 0 {
            let infoObject = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            let infoData = try JSONEncoder().encode(infoObject)
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoData.count))
            let context = NWConnection.ContentContext(identifier: "EmptyFile",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: infoData, contentContext: context)
            self.onBytesSent.send(infoData.count)
            self.onFileSent.send(1)
        } else {
            let infoData = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            guard var data = try? fileHandle.readToEnd(),
                  let infoDataLenght = try? data.include(object: infoData) else {
                try closeFile(fileHandle)
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "File",
                                                      metadata: [message])
            
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onBytesSent.send(data.count)
            self.onFileSent.send(1)
        }
        try closeFile(fileHandle)
        logger.log("networkConnection.sendfile: done sending file \"\(file.url.fullURL().relativePath)\"")
    }
    
    /// Handles the sending of a file, breaking it into chunks if necessary, and collecting symbolic links as needed.
    /// - Parameter fileURL: The URL of the file to send.
    private func _sendFile(at fileURL: URL) async throws {
        logger.log("networkConnection.sendfile: preparing file \"\(fileURL.relativePath)\"")
        guard !AppContext.excludedFileExtensions.contains(fileURL.lastPathComponent) && fileURL.lastPathComponent.first != "~" else {
            logger.log("networkConnection.sendfile: file \"\(fileURL.relativePath)\" needs to be ignored. This should'n happen.", type: .fault)
            return
        }
        
        let chunkSize: UInt64 = 200000000
        var isDirectory: ObjCBool = false
        
        if let destinationPath = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.relativePath),
            destinationPath != fileURL.relativePath {
            logger.log("networkConnection.sendfile: file \"\(fileURL.relativePath)\" is alias of \"\(destinationPath)\"")
            guard let destinationURL = URL(string: destinationPath) else {
                logger.log("networkConnection.sendfile: impossible to create URL from \"\(destinationPath)\"", type: .error)
                return
            }
            let destinationTrackedURL = MigratorFileURL(with: destinationURL)
            let sourceTrackedURL = MigratorFileURL(with: fileURL)
            if destinationTrackedURL.source == .unknown {
                let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: fileURL.deletingLastPathComponent()), relativeDestination: destinationPath)
                symlinks.append(infoData)
            } else {
                let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: URL(string: destinationPath)!))
                symlinks.append(infoData)
            }
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.relativePath, isDirectory: &isDirectory) else {
            logger.log("networkConnection.sendfile: file \"\(fileURL.relativePath)\" doesn't exists", type: .error)
            throw MigratorError.fileError(type: .noData)
        }
        
        logger.log("networkConnection.sendfile: file \"\(fileURL.relativePath)\" is directory -> \"\(isDirectory.description)\"")
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.relativePath) as [FileAttributeKey: Any] else {
            logger.log("networkConnection.sendfile: failed to get attributes of file \"\(fileURL.relativePath)\"", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }
        
        guard !isDirectory.boolValue else {
            let infoData = FileMessage(with: fileURL, part: 0, attributes: attributes)
            guard var data = "directory".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.internalError(type: .data)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .directory, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "Directory",
                                                      metadata: [message])
            logger.log("networkConnection.sendfile: sending data of directory at \"\(fileURL.relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onBytesSent.send(data.count)

            let childFilePaths = try FileManager.default.contentsOfDirectory(atPath: fileURL.relativePath)
            logger.log("networkConnection.sendfile: start sending content of directory \"\(fileURL.relativePath)\"")
            for childFilePath in childFilePaths {
                guard !childFilePath.isEmpty else { return }
                try await sendFile(fileURL.appendingPathComponent(childFilePath, isDirectory: isDirectory.boolValue))
                self.onBytesSent.send(data.count)
            }
            return
        }
        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.relativePath) else {
            logger.log("networkConnection.sendfile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }

        var availableBytes = (attributes as NSDictionary).fileSize()
        var parsedBytes: UInt64 = 0
    
        logger.log("networkConnection.sendfile: start sending data of file \"\(fileURL.relativePath)\"")
        if availableBytes > chunkSize {
            var partNumber: UInt32 = 0
            do {
                try fileHandle.seek(toOffset: parsedBytes)
            } catch let error {
                logger.log("networkConnection.sendfile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
            }
            while availableBytes > 0 {
                let infoData = FileMessage(with: fileURL, part: Int(partNumber), attributes: attributes)
                guard var chunk = try? fileHandle.read(upToCount: Int(min(chunkSize, availableBytes))),
                      let infoDataLenght = try? chunk.include(object: infoData)else {
                    try closeFile(fileHandle)
                    logger.log("networkConnection.sendfile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .noData)
                }
                let message = NWProtocolFramer.Message(migratorMessageType: .multipartFile, infoLenght: UInt32(infoDataLenght))
                let context = NWConnection.ContentContext(identifier: "Chunk",
                                                          metadata: [message])
                
                try await sendAsyncWrapper(content: chunk, contentContext: context)
                self.onBytesSent.send(chunk.count)
                            
                parsedBytes += min(chunkSize, availableBytes)
                if availableBytes > chunkSize {
                    availableBytes -= chunkSize
                } else {
                    availableBytes = 0
                }
                partNumber += 1
                
                do {
                    try fileHandle.seek(toOffset: parsedBytes)
                } catch let error {
                    logger.log("networkConnection.sendfile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
                }
            }
        } else if availableBytes == 0 {
            let infoObject = FileMessage(with: fileURL, part: 0, attributes: attributes)
            let infoData = try JSONEncoder().encode(infoObject)
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoData.count))
            let context = NWConnection.ContentContext(identifier: "EmptyFile",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: infoData, contentContext: context)
            self.onBytesSent.send(infoData.count)
        } else {
            let infoData = FileMessage(with: fileURL, part: 0, attributes: attributes)
            guard var data = try? fileHandle.readToEnd(),
                  let infoDataLenght = try? data.include(object: infoData) else {
                try closeFile(fileHandle)
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "File",
                                                      metadata: [message])
            
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onBytesSent.send(data.count)
        }
        try closeFile(fileHandle)
        logger.log("networkConnection.sendfile: done sending file \"\(fileURL.relativePath)\"")
    }
    
    /// Sends collected symbolic links to the connected device.
    private func sendSymlinks() async throws {
        logger.log("networkConnection.sendSymlinks: start sending collected symlinks")
        for message in symlinks {
            guard var data = "link".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: message) else {
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .symlink, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "SymbolicLink",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
        }
        symlinks = []
        logger.log("networkConnection.sendSymlinks: done sending collected symlinks")
    }
    
    /// Sends collected symbolic links to the connected device.
    func sendDefaults(_ object: DefaultsMessage) async throws {
        logger.log("networkConnection.sendDefaults: start sending \(object.key) UserDefaults")
        guard var data = "defaults".data(using: .utf8),
              let infoDataLenght = try? data.include(object: object) else {
            throw MigratorError.fileError(type: .noData)
        }
        let message = NWProtocolFramer.Message(migratorMessageType: .defaults, infoLenght: UInt32(infoDataLenght))
        let context = NWConnection.ContentContext(identifier: "UserDefaults",
                                                  metadata: [message])
        try await sendAsyncWrapper(content: data, contentContext: context)
        logger.log("networkConnection.sendDefaults: done sending \(object.key) UserDefaults")
    }
    
    /// Receives and processes the next incoming message from the connected device.
    private func receiveNextMessage() {
        logger.log("networkConnection.receiveNextMessage: waiting for new messages")
        connection.receiveMessage { (content, context, _, error) in
            if let migratorMessage = context?.protocolMetadata(definition: MigratorNetworkProtocol.definition) as? NWProtocolFramer.Message {
                switch migratorMessage.migratorMessageType {
                case .hostname:
                    self.logger.log("networkConnection.receiveNextMessage: hostname message received", type: .default)
                    if let data = content,
                        let hostname = String(data: data, encoding: .utf8) {
                        self.connectedDeviceHostName = hostname
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: impossible to decode hostname", type: .error)
                    }
                case .symlink:
                    self.logger.log("networkConnection.receiveNextMessage: symlink message received!", type: .default)
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: SymbolicLinkMessage.self)
                            self.logger.log("networkConnection.receiveNextMessage: symlink source \"\(messageInfo.source.fullURL().relativePath)\"")
                            self.logger.log("networkConnection.receiveNextMessage: symlink relative destination \"\(messageInfo.relativeDestination ?? "nil")\"")
                            self.logger.log("networkConnection.receiveNextMessage: symlink absolute destination \"\(messageInfo.absoluteDestination.fullURL().relativePath)\"")
                            var destinationPath = ""
                            if let relativeDestination = messageInfo.relativeDestination {
                                destinationPath = relativeDestination
                            } else {
                                destinationPath = messageInfo.absoluteDestination.fullURL().relativePath
                            }
                            try FileManager.default.createSymbolicLink(atPath: messageInfo.source.fullURL().relativePath, withDestinationPath: destinationPath)
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to create symbolik link -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .file:
                    self.logger.log("networkConnection.receiveNextMessage: file message received")
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                            self.onBytesReceived.send(data.count)
                            guard let directory = URL(string: messageInfo.source.fullURL().relativePath)?.deletingLastPathComponent() else {
                                throw MigratorError.fileError(type: .failedToWriteFile)
                            }
                            self.logger.log("networkConnection.receiveNextMessage: file source \"\(messageInfo.source.fullURL().relativePath)\"")
                            if FileManager.default.fileExists(atPath: messageInfo.source.fullURL().relativePath) {
                                switch AppContext.duplicateFilesHandlingPolicy {
                                case .ignore:
                                    break
                                case .move:
                                    if !FileManager.default.fileExists(atPath: "\(AppContext.backupPath)/\(directory.relativePath)") {
                                        try? FileManager.default.createDirectory(atPath: "\(AppContext.backupPath)/\(directory.relativePath)", withIntermediateDirectories: true)
                                    }
                                    try? FileManager.default.moveItem(atPath: messageInfo.source.fullURL().relativePath, toPath: "\(AppContext.backupPath)/\(messageInfo.source.fullURL().relativePath)")
                                    fallthrough
                                case .overwrite:
                                    guard FileManager.default.createFile(atPath: messageInfo.source.fullURL().relativePath, contents: data, attributes: messageInfo.attributes) else {
                                        throw MigratorError.fileError(type: .failedToWriteFile)
                                    }
                                }
                            } else {
                                try FileManager.default.createDirectory(atPath: directory.relativePath, withIntermediateDirectories: true)
                                guard FileManager.default.createFile(atPath: messageInfo.source.fullURL().relativePath, contents: data, attributes: messageInfo.attributes) else {
                                    throw MigratorError.fileError(type: .failedToWriteFile)
                                }
                            }
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to write file -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .directory:
                    self.logger.log("networkConnection.receiveNextMessage: directory message received")
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                            self.logger.log("networkConnection.receiveNextMessage: directory source \"\(messageInfo.source.fullURL().relativePath)\"")
                            try FileManager.default.createDirectory(atPath: messageInfo.source.fullURL().relativePath, withIntermediateDirectories: true, attributes: messageInfo.attributes)
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to create directory -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .result:
                    self.logger.log("networkConnection.receiveNextMessage: result message received", type: .default)
                    self.isMigrationCompleted = true
                    return
                case .invalid:
                    self.logger.log("networkConnection.receiveNextMessage: invalid message received", type: .default)
                case .metadata:
                    self.logger.log("networkConnection.receiveNextMessage: metadata message received", type: .default)
                    if let data = content,
                        let migrationSize = String(data: data, encoding: .utf8) {
                        self.migrationSizeInBytes = Int(migrationSize) ?? 0
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: failed to decode metadata", type: .error)
                    }
                case .availableSpace:
                    self.logger.log("networkConnection.receiveNextMessage: availableSpace message received", type: .default)
                    if let data = content,
                        let freeSpace = String(data: data, encoding: .utf8) {
                        self.connectedDeviceAvailableSpace = Int(freeSpace) ?? 0
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: failed to decode availableSpace", type: .error)
                    }
                case .multipartFile:
                    self.logger.log("networkConnection.receiveNextMessage: multipart file message received")
                    guard var data = content else {
                        self.logger.log("networkConnection.receiveNextMessage: no data in multipart file message", type: .error)
                        self.receiveNextMessage()
                        return
                    }
                    do {
                        let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                        self.onBytesReceived.send(data.count)
                        guard let directory = URL(string: messageInfo.source.fullURL().relativePath)?.deletingLastPathComponent() else {
                            throw MigratorError.fileError(type: .failedToWriteFile)
                        }
                        if !FileManager.default.fileExists(atPath: directory.relativePath) {
                            try FileManager.default.createDirectory(atPath: directory.relativePath, withIntermediateDirectories: true)
                        }
                        if !FileManager.default.fileExists(atPath: messageInfo.source.fullURL().relativePath) || messageInfo.partNumber == 0 {
                            FileManager.default.createFile(atPath: messageInfo.source.fullURL().relativePath, contents: nil, attributes: messageInfo.attributes)
                        }
                        guard let fileHandle = FileHandle(forWritingAtPath: messageInfo.source.fullURL().relativePath) else {
                            throw MigratorError.fileError(type: .failedDuringFileHandling())
                        }
                        try fileHandle.seekToEnd()
                        try fileHandle.write(contentsOf: data)
                        try fileHandle.close()
                        self.receiveNextMessage()
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to write chunk of data -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .defaults:
                    self.logger.log("networkConnection.receiveNextMessage: defaults message received!", type: .default)
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: DefaultsMessage.self)
                            if let boolValue = messageInfo.boolValue {
                                UserDefaults.standard.setValue(boolValue, forKey: messageInfo.key)
                            } else if let stringValue = messageInfo.stringValue {
                                UserDefaults.standard.setValue(stringValue, forKey: messageInfo.key)
                            }
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to save UserDefaults value -> \"\(error.localizedDescription)\"", type: .error)
                    }
                }
            }
            if let error = error {
                self.logger.log("networkConnection.receiveNextMessage: failed to receive message -> \"\(error.localizedDescription)\"", type: .error)
            } else {
                self.receiveNextMessage()
            }
        }
    }
}

//  swiftlint:enable function_body_length type_body_length file_length
