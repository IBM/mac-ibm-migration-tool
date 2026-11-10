//
//  EphemeralTLSIdentity.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 25/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//
//  swiftlint:disable file_length

import Foundation
import Network
import Security
import CryptoKit
import CommonCrypto

/// Minimal DER/ASN.1 encoding helpers used to build a self-signed certificate and a PKCS#12 blob
/// without depending on any external crypto library.
enum DER {
    static func length(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        var bytes: [UInt8] = []
        var len = length
        while len > 0 {
            bytes.insert(UInt8(len & 0xFF), at: 0)
            len >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }
    
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + length(content.count) + content
    }
    
    static func sequence(_ content: Data) -> Data { tlv(0x30, content) }
    static func set(_ content: Data) -> Data { tlv(0x31, content) }
    
    /// Encodes a small non-negative integer (used for version numbers).
    static func integer(_ value: Int) -> Data {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining != 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        return tlv(0x02, Data(bytes))
    }
    
    /// Encodes an INTEGER from raw unsigned bytes with the top bit of the first byte already cleared.
    static func positiveInteger(_ bytes: Data) -> Data { tlv(0x02, bytes) }
    
    static func bitString(_ content: Data, unusedBits: UInt8 = 0) -> Data {
        tlv(0x03, Data([unusedBits]) + content)
    }
    static func octetString(_ content: Data) -> Data { tlv(0x04, content) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func utf8String(_ string: String) -> Data { tlv(0x0C, Data(string.utf8)) }
    
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return tlv(0x17, Data(formatter.string(from: date).utf8))
    }
    
    /// Constructed, explicitly-tagged context value: `[tagNumber] EXPLICIT content`.
    static func contextExplicit(_ tagNumber: UInt8, _ content: Data) -> Data {
        tlv(0xA0 | tagNumber, content)
    }
    
    /// Primitive, implicitly-tagged context value: `[tagNumber] IMPLICIT content` (replaces the
    /// universal tag rather than wrapping it, e.g. for `encryptedContent [0] IMPLICIT OCTET STRING`).
    static func contextImplicit(_ tagNumber: UInt8, _ content: Data) -> Data {
        tlv(0x80 | tagNumber, content)
    }
}

/// Well-known OIDs used while building the self-signed certificate and PKCS#12 container.
enum ASN1OID {
    static let rsaEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    static let sha256WithRSAEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    static let commonName: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    
    static let pkcs12Data: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
    static let pkcs7EncryptedData: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x06]
    static let pkcs12CertBag: [UInt8] = [0x06, 0x0B, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x0C, 0x0A, 0x01, 0x03]
    static let pkcs12X509Certificate: [UInt8] = [0x06, 0x0A, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x16, 0x01]
    static let pkcs8ShroudedKeyBag: [UInt8] = [0x06, 0x0B, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x0C, 0x0A, 0x01, 0x02]
    static let pbeWithSHA1And3KeyTripleDESCBC: [UInt8] = [0x06, 0x0A, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x0C, 0x01, 0x03]
    
    static let sha256: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    static let localKeyID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x15]
}

/// Builds an ephemeral, in-memory-only TLS server identity for pairing over TLS 1.3.
///
/// TLS 1.3 has no external-PSK mode in Network.framework, so the destination Mac serves a
/// throwaway self-signed certificate purely to get an encrypted, forward-secret channel.
/// Peer authentication is done at the application layer with a PAKE bound to this channel,
/// so the client deliberately accepts any certificate (see `NWParameters-Extension.swift`).
/// The private key never touches the keychain: it lives only as long as the process does.
///
/// The key is RSA, not EC: Apple's `SecPKCS12Import` (used below to assemble a `sec_identity_t`
/// without persisting anything) only links a certificate to its private key for EC keys when the
/// key is stored in a keychain first. For an in-memory-only import it silently returns just the
/// certificate chain and no identity, even though the PKCS#12 blob is fully spec-valid (verified
/// against OpenSSL). RSA does not have this limitation.
enum EphemeralTLSIdentity {
    
    enum IdentityError: Error {
        case keyGenerationFailed(String)
        case certificateEncodingFailed
        case encryptionFailed(CCCryptorStatus)
        case pkcs12ImportFailed(OSStatus)
        case noIdentityInImportResult
    }
    
    /// Creates a fresh self-signed RSA-2048 identity and returns a `sec_identity_t` usable as a
    /// TLS server identity. Nothing is written to any keychain.
    static func makeIdentity() throws -> sec_identity_t {
        let (privateKey, publicKey) = try makeRSAKeyPair()
        let privateKeyDER = try pkcs8PrivateKeyInfo(for: privateKey)
        let certificateDER = try makeSelfSignedCertificate(privateKey: privateKey, publicKey: publicKey)
        let passphrase = UUID().uuidString
        
        let pkcs12Data = try makePKCS12(privateKeyDER: privateKeyDER,
                                        certificateDER: certificateDER,
                                        passphrase: passphrase)
        
        let options: [CFString: Any] = [
            kSecImportExportPassphrase: passphrase,
            kSecImportToMemoryOnly: true
        ]
        
        var rawItems: CFArray?
        let status = SecPKCS12Import(pkcs12Data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess else {
            throw IdentityError.pkcs12ImportFailed(status)
        }
        guard let items = rawItems as? [[CFString: Any]],
              let firstItem = items.first,
              let identityRef = firstItem[kSecImportItemIdentity] else {
            throw IdentityError.noIdentityInImportResult
        }
        // swiftlint:disable:next force_cast
        let secIdentity = identityRef as! SecIdentity
        return sec_identity_create(secIdentity)!
    }
    
    // MARK: - RSA key pair
    
    /// Generates a fresh in-memory-only RSA-2048 key pair (no keychain persistence).
    private static func makeRSAKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw IdentityError.keyGenerationFailed((error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown")
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw IdentityError.keyGenerationFailed("no public key")
        }
        return (privateKey, publicKey)
    }
    
    /// Wraps an RSA `SecKey`'s PKCS#1 external representation into a PKCS#8 `PrivateKeyInfo`.
    private static func pkcs8PrivateKeyInfo(for privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let pkcs1DER = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw IdentityError.keyGenerationFailed((error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown")
        }
        let algorithmIdentifier = DER.sequence(Data(ASN1OID.rsaEncryption) + DER.null())
        return DER.sequence(DER.integer(0) + algorithmIdentifier + DER.octetString(pkcs1DER))
    }
    
    /// Wraps an RSA `SecKey`'s PKCS#1 public-key external representation into a full
    /// `SubjectPublicKeyInfo`.
    private static func subjectPublicKeyInfo(for publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let pkcs1DER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IdentityError.keyGenerationFailed((error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown")
        }
        let algorithmIdentifier = DER.sequence(Data(ASN1OID.rsaEncryption) + DER.null())
        return DER.sequence(algorithmIdentifier + DER.bitString(pkcs1DER))
    }
    
    // MARK: - Certificate
    
    private static func makeSelfSignedCertificate(privateKey: SecKey, publicKey: SecKey) throws -> Data {
        var serialBytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F // keep the INTEGER positive without extra padding
        
        let signatureAlgorithm = DER.sequence(Data(ASN1OID.sha256WithRSAEncryption) + DER.null())
        let name = DER.sequence(
            DER.set(
                DER.sequence(Data(ASN1OID.commonName) + DER.utf8String("Data Shift Pairing"))
            )
        )
        
        let now = Date()
        let validity = DER.sequence(
            DER.utcTime(now.addingTimeInterval(-300)) + DER.utcTime(now.addingTimeInterval(86_400))
        )
        
        let subjectPublicKeyInfoDER = try subjectPublicKeyInfo(for: publicKey)
        
        let tbsCertificate = DER.sequence(
            DER.positiveInteger(Data(serialBytes)) +
            signatureAlgorithm +
            name +
            validity +
            name +
            subjectPublicKeyInfoDER
        )
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    tbsCertificate as CFData, &error) as Data? else {
            throw IdentityError.keyGenerationFailed((error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown")
        }
        
        let certificate = DER.sequence(
            tbsCertificate +
            signatureAlgorithm +
            DER.bitString(signature)
        )
        
        guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
            throw IdentityError.certificateEncodingFailed
        }
        return certificate
    }
    
    // MARK: - PKCS#12
    
    /// Builds a minimal PKCS#12 (PFX) blob following the classic dual-`ContentInfo` layout:
    /// the certificate bag lives inside an encrypted (`pkcs7-encryptedData`) `ContentInfo`, and
    /// the shrouded key bag lives inside a plain `data` `ContentInfo`, both using
    /// `pbeWithSHA1And3-KeyTripleDES-CBC`. This is what Apple's `SecPKCS12Import` actually expects
    /// in order to link the certificate to its private key into a single identity: putting both
    /// bags together in one unencrypted `data` `ContentInfo` (a layout modern OpenSSL also
    /// produces, and RFC 7292-valid) decodes fine and verifies its MAC, but Apple's legacy
    /// importer then only returns the certificate chain and no identity. The whole thing is
    /// wrapped with a password-derived HMAC-SHA256 MacData for integrity, and only ever consumed
    /// locally in-process via `kSecImportToMemoryOnly`, so the random passphrase never needs to
    /// be remembered.
    private static func makePKCS12(privateKeyDER: Data, certificateDER: Data, passphrase: String) throws -> Data {
        // A shared localKeyID attribute is how a PKCS#12 parser correlates a certificate's
        // SafeBag with its matching private key's SafeBag inside the same file.
        let keyID = Data((0..<20).map { _ in UInt8.random(in: .min ... .max) })
        let bagAttributes = DER.set(
            DER.sequence(Data(ASN1OID.localKeyID) + DER.set(DER.octetString(keyID)))
        )
        
        let certSafeBag = DER.sequence(
            Data(ASN1OID.pkcs12CertBag) + DER.contextExplicit(0, certBagValue(certificateDER)) + bagAttributes
        )
        let firstContentInfo = try encryptedCertContentInfo(certSafeBag: certSafeBag, passphrase: passphrase)
        
        let encryptedKey = try encryptPrivateKey(privateKeyDER, passphrase: passphrase)
        let keySafeBag = DER.sequence(
            Data(ASN1OID.pkcs8ShroudedKeyBag) + DER.contextExplicit(0, encryptedKey) + bagAttributes
        )
        let keySafeContents = DER.sequence(keySafeBag)
        let secondContentInfo = DER.sequence(
            Data(ASN1OID.pkcs12Data) +
            DER.contextExplicit(0, DER.octetString(keySafeContents))
        )
        
        let authenticatedSafe = DER.sequence(firstContentInfo + secondContentInfo)
        
        let authSafeContentInfo = DER.sequence(
            Data(ASN1OID.pkcs12Data) +
            DER.contextExplicit(0, DER.octetString(authenticatedSafe))
        )
        
        let macData = try makeMacData(authenticatedSafeDER: authenticatedSafe, passphrase: passphrase)
        
        let pfx = DER.sequence(
            DER.integer(3) +
            authSafeContentInfo +
            macData
        )
        return pfx
    }
    
    private static func certBagValue(_ certificateDER: Data) -> Data {
        DER.sequence(Data(ASN1OID.pkcs12X509Certificate) + DER.contextExplicit(0, DER.octetString(certificateDER)))
    }
    
    /// Wraps a certificate `SafeBag` in an encrypted `pkcs7-encryptedData` `ContentInfo`.
    private static func encryptedCertContentInfo(certSafeBag: Data, passphrase: String) throws -> Data {
        let certSafeContents = DER.sequence(certSafeBag)
        let (algorithmIdentifier, ciphertext) = try pbeEncrypt(certSafeContents, passphrase: passphrase)
        
        let encryptedContentInfo = DER.sequence(
            Data(ASN1OID.pkcs12Data) +
            algorithmIdentifier +
            DER.contextImplicit(0, ciphertext)
        )
        let encryptedData = DER.sequence(DER.integer(0) + encryptedContentInfo)
        return DER.sequence(Data(ASN1OID.pkcs7EncryptedData) + DER.contextExplicit(0, encryptedData))
    }
    
    /// Encrypts a PKCS#8 `PrivateKeyInfo` into an `EncryptedPrivateKeyInfo`.
    private static func encryptPrivateKey(_ privateKeyDER: Data, passphrase: String) throws -> Data {
        let (algorithmIdentifier, ciphertext) = try pbeEncrypt(privateKeyDER, passphrase: passphrase)
        return DER.sequence(algorithmIdentifier + DER.octetString(ciphertext))
    }
    
    /// Encrypts arbitrary DER using the classic PKCS#12 `pbeWithSHA1And3-KeyTripleDES-CBC` scheme,
    /// which is what Apple's `SecPKCS12Import` actually supports (the newer PBES2/AES-256
    /// combination decodes fine, verified against OpenSSL, but Apple's importer silently ignores
    /// it). Returns the DER `AlgorithmIdentifier` alongside the ciphertext.
    private static func pbeEncrypt(_ plaintext: Data, passphrase: String) throws -> (algorithmIdentifier: Data, ciphertext: Data) {
        let salt = Data((0..<8).map { _ in UInt8.random(in: .min ... .max) })
        let iterations = 2_048
        
        let key = pkcs12KDF(passphrase: passphrase, salt: salt, iterations: iterations,
                            diversifierID: 1, keyLengthBytes: 24, blockSize: 64,
                            hash: { Data(Insecure.SHA1.hash(data: $0)) })
        let initializationVector = pkcs12KDF(passphrase: passphrase, salt: salt, iterations: iterations,
                                              diversifierID: 2, keyLengthBytes: 8, blockSize: 64,
                                              hash: { Data(Insecure.SHA1.hash(data: $0)) })
        let ciphertext = try tripleDESCBCEncrypt(key: key, initializationVector: initializationVector, plaintext: plaintext)
        
        let pbeParameter = DER.sequence(DER.octetString(salt) + DER.integer(iterations))
        let algorithmIdentifier = DER.sequence(Data(ASN1OID.pbeWithSHA1And3KeyTripleDESCBC) + pbeParameter)
        return (algorithmIdentifier, ciphertext)
    }
    
    /// Triple-DES-CBC encryption with PKCS#7 padding via CommonCrypto.
    private static func tripleDESCBCEncrypt(key: Data, initializationVector: Data, plaintext: Data) throws -> Data {
        let outputLength = plaintext.count + kCCBlockSize3DES
        var ciphertext = [UInt8](repeating: 0, count: outputLength)
        var moved = 0
        let status = key.withUnsafeBytes { keyPtr in
            initializationVector.withUnsafeBytes { ivPtr in
                plaintext.withUnsafeBytes { plaintextPtr in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithm3DES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            plaintextPtr.baseAddress, plaintext.count,
                            &ciphertext, outputLength, &moved)
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw IdentityError.encryptionFailed(status)
        }
        return Data(ciphertext.prefix(moved))
    }
    
    /// RFC 7292 Appendix B password-based MAC, using SHA-256 in place of the legacy SHA-1.
    private static func makeMacData(authenticatedSafeDER: Data, passphrase: String) throws -> Data {
        let salt = Data((0..<8).map { _ in UInt8.random(in: .min ... .max) })
        let iterations = 2_048
        let macKey = pkcs12KDF(passphrase: passphrase, salt: salt, iterations: iterations,
                               diversifierID: 3, keyLengthBytes: 32, blockSize: 64,
                               hash: { Data(SHA256.hash(data: $0)) })
        let mac = HMAC<SHA256>.authenticationCode(for: authenticatedSafeDER, using: SymmetricKey(data: macKey))
        
        let digestAlgorithm = DER.sequence(Data(ASN1OID.sha256))
        let macSequence = DER.sequence(digestAlgorithm + DER.octetString(Data(mac)))
        return DER.sequence(macSequence + DER.octetString(salt) + DER.integer(iterations))
    }
    
    /// RFC 7292 Appendix B.2 key-derivation function (id: 1 = key material, 2 = IV, 3 = MAC key),
    /// parameterized over the underlying hash so it can serve both the SHA-1-based classic PBE
    /// scheme and the SHA-256 MacData above.
    private static func pkcs12KDF(passphrase: String, salt: Data, iterations: Int, diversifierID: UInt8, // swiftlint:disable:this function_parameter_count
                                  keyLengthBytes: Int, blockSize: Int,
                                  hash: (Data) -> Data) -> Data {
        // BMPString (UTF-16BE, NUL-terminated) representation of the passphrase.
        var passwordBytes = Data()
        for scalar in passphrase.unicodeScalars {
            let value = scalar.value
            passwordBytes.append(UInt8((value >> 8) & 0xFF))
            passwordBytes.append(UInt8(value & 0xFF))
        }
        passwordBytes.append(0x00)
        passwordBytes.append(0x00)
        
        func fill(_ source: Data, to length: Int) -> Data {
            guard !source.isEmpty else { return Data(repeating: 0, count: length) }
            var result = Data()
            while result.count < length {
                result.append(source)
            }
            return result.prefix(length)
        }
        
        let diversifier = Data(repeating: diversifierID, count: blockSize)
        let saltBlock = fill(salt, to: blockSize * ((salt.count + blockSize - 1) / max(blockSize, 1)))
        let passwordBlock = fill(passwordBytes, to: blockSize * ((passwordBytes.count + blockSize - 1) / max(blockSize, 1)))
        
        var iBlock = saltBlock + passwordBlock
        var result = Data()
        while result.count < keyLengthBytes {
            var aBlock = hash(diversifier + iBlock)
            for _ in 1..<iterations {
                aBlock = hash(aBlock)
            }
            result.append(aBlock)
            
            // B = A repeated to fill one block-sized block, then I_j = (I_j + B + 1) mod 2^(blockSize*8)
            let bBlock = fill(aBlock, to: blockSize)
            var newIBlock = Data(capacity: iBlock.count)
            var blockCount = iBlock.count / blockSize
            if blockCount == 0 { blockCount = 1 }
            for blockIndex in 0..<blockCount {
                let start = blockIndex * blockSize
                let end = min(start + blockSize, iBlock.count)
                var block = [UInt8](iBlock[start..<end])
                let bBytes = [UInt8](bBlock)
                var carry: UInt16 = 1
                for byteIndex in stride(from: block.count - 1, through: 0, by: -1) {
                    let sum = UInt16(block[byteIndex]) + UInt16(bBytes[byteIndex % bBytes.count]) + carry
                    block[byteIndex] = UInt8(sum & 0xFF)
                    carry = sum >> 8
                }
                newIBlock.append(Data(block))
            }
            iBlock = newIBlock
        }
        return result.prefix(keyLengthBytes)
    }
}
//  swiftlint:enable file_length
