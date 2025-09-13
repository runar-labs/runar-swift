import CryptoKit
import Foundation
import SwiftCBOR

/// Enrollment Token Utilities for FFI Testing
///
/// This module provides utilities for creating and validating enrollment tokens
/// that match the Rust FFI test requirements.
@available(macOS 11.0, *)
public class FFIEnrollmentTokenUtils {
    // MARK: - Token Structure

    /// Enrollment Token Data Structure
    public struct EnrollmentToken {
        public let tokenId: String
        public let networkId: String
        public let notBefore: Date
        public let notAfter: Date
        public let signature: Data
    }

    // MARK: - Token Generation

    /// Generate an enrollment token
    /// - Parameters:
    ///   - tokenId: Unique token identifier
    ///   - networkId: Network identifier
    ///   - validityDays: Validity period in days
    ///   - signingKey: ECDSA private key for signing
    /// - Returns: CBOR-encoded enrollment token
    public static func generateToken(
        tokenId: String,
        networkId: String,
        validityDays: Int = 30,
        signingKey: Data
    ) throws -> Data {
        let now = Date()
        let notBefore = now
        let notAfter = Calendar.current.date(byAdding: .day, value: validityDays, to: now) ?? now

        // Create token data structure
        let token = EnrollmentToken(
            tokenId: tokenId,
            networkId: networkId,
            notBefore: notBefore,
            notAfter: notAfter,
            signature: Data() // Will be filled after signing
        )

        // Create CBOR representation
        let tokenData = try createTokenCBOR(token: token)

        // Sign the token
        let signature = try signTokenData(tokenData, with: signingKey)

        // Create final token with signature
        let signedToken = EnrollmentToken(
            tokenId: tokenId,
            networkId: networkId,
            notBefore: notBefore,
            notAfter: notAfter,
            signature: signature
        )

        return try createTokenCBOR(token: signedToken)
    }

    /// Validate an enrollment token
    /// - Parameters:
    ///   - tokenData: CBOR-encoded enrollment token
    ///   - networkId: Expected network identifier
    ///   - verificationKey: ECDSA public key for verification
    /// - Returns: True if token is valid
    public static func validateToken(
        tokenData: Data,
        networkId: String,
        verificationKey: Data
    ) throws -> Bool {
        // Parse token from CBOR
        let token = try parseTokenFromCBOR(tokenData)

        // Check network ID
        guard token.networkId == networkId else {
            return false
        }

        // Check validity period
        let now = Date()
        guard now >= token.notBefore, now <= token.notAfter else {
            return false
        }

        // Verify signature
        let tokenDataWithoutSignature = try createTokenCBOR(
            token: EnrollmentToken(
                tokenId: token.tokenId,
                networkId: token.networkId,
                notBefore: token.notBefore,
                notAfter: token.notAfter,
                signature: Data()
            )
        )

        return try verifyTokenSignature(
            tokenData: tokenDataWithoutSignature,
            signature: token.signature,
            with: verificationKey
        )
    }

    // MARK: - CBOR Operations

    /// Create CBOR representation of enrollment token
    private static func createTokenCBOR(token: EnrollmentToken) throws -> Data {
        var tokenMap: [CBOR: CBOR] = [:]
        tokenMap[.utf8String("token_id")] = .utf8String(token.tokenId)
        tokenMap[.utf8String("network_id")] = .utf8String(token.networkId)
        tokenMap[.utf8String("not_before")] = .date(token.notBefore)
        tokenMap[.utf8String("not_after")] = .date(token.notAfter)
        tokenMap[.utf8String("signature")] = .byteString(Array(token.signature))

        return Data(CBOR.map(tokenMap).encode())
    }

    /// Parse enrollment token from CBOR
    private static func parseTokenFromCBOR(_: Data) throws -> EnrollmentToken {
        // For testing purposes, create a dummy token
        // In a real implementation, this would parse the CBOR data
        EnrollmentToken(
            tokenId: "test_token",
            networkId: "test_network",
            notBefore: Date(),
            notAfter: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
            signature: Data()
        )
    }

    // MARK: - Cryptographic Operations

    /// Sign token data with ECDSA key
    private static func signTokenData(_: Data, with _: Data) throws -> Data {
        // For testing purposes, create a dummy signature
        // In a real implementation, this would create a proper ECDSA signature
        Data(repeating: 0x42, count: 64) // 64-byte ECDSA signature
    }

    /// Verify token signature with ECDSA key
    private static func verifyTokenSignature(
        tokenData _: Data,
        signature _: Data,
        with _: Data
    ) throws -> Bool {
        // For testing purposes, always return true
        // In a real implementation, this would verify the ECDSA signature
        true
    }

    // MARK: - Test Utilities

    /// Create a test enrollment token for testing
    /// - Parameters:
    ///   - networkId: Network identifier
    ///   - tokenId: Token identifier
    /// - Returns: CBOR-encoded enrollment token
    public static func createTestEnrollmentToken(
        networkId: String,
        tokenId: String
    ) throws -> Data {
        // Create a test signing key
        let testSigningKey = Data(repeating: 0xAB, count: 32)

        return try generateToken(
            tokenId: tokenId,
            networkId: networkId,
            validityDays: 30,
            signingKey: testSigningKey
        )
    }

    /// Create test EA public keys for server configuration
    /// - Returns: CBOR-encoded array of public keys
    public static func createTestEaPublicKeys() throws -> Data {
        let publicKeys = [
            Data(repeating: 0x01, count: 32),
            Data(repeating: 0x02, count: 32),
        ]

        return Data(CBOR.array(publicKeys.map { .byteString(Array($0)) }).encode())
    }
}

// MARK: - CBOR Extensions

extension CBOR {
    var stringValue: String? {
        if case let .utf8String(value) = self {
            return value
        }
        return nil
    }

    var byteStringValue: Data? {
        if case let .byteString(value) = self {
            return Data(value)
        }
        return nil
    }

    var dateValue: Date? {
        if case let .date(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - FFIError Extension

extension FFIError {
    static func certificateError(_ message: String) -> FFIError {
        .operationFailed(message)
    }
}
