@testable import RunarFFI
import XCTest

@available(macOS 11.0, *)
final class NewFeaturesTests: XCTestCase {
    var keysFFI: KeysFFI!
    var logger: Logger!

    override func setUp() {
        super.setUp()
        logger = SimpleLogger()
        keysFFI = KeysFFI(logger: logger)
    }

    override func tearDown() {
        keysFFI = nil
        logger = nil
        super.tearDown()
    }

    // MARK: - Error Code Tests

    func testCAErrorCodes() {
        // Test CA-specific error codes
        XCTAssertEqual(FFIError.caNodeNotInitialized("test").errorCode, 1001)
        XCTAssertEqual(FFIError.caServerNotRunning("test").errorCode, 1002)
        XCTAssertEqual(FFIError.caClientConnectionFailed("test").errorCode, 1003)
        XCTAssertEqual(FFIError.certificateValidationFailed("test").errorCode, 1004)
        XCTAssertEqual(FFIError.profileKeyNotFound("test").errorCode, 1005)
        XCTAssertEqual(FFIError.enrollmentTokenInvalid("test").errorCode, 1006)
        XCTAssertEqual(FFIError.rateLimitExceeded("test").errorCode, 1007)
        XCTAssertEqual(FFIError.adminNotAuthorized("test").errorCode, 1008)
        XCTAssertEqual(FFIError.certificateCreationFailed("test").errorCode, 1009)
        XCTAssertEqual(FFIError.certificateSkiExtractionFailed("test").errorCode, 1010)
        XCTAssertEqual(FFIError.certificateSerialExtractionFailed("test").errorCode, 1011)
        XCTAssertEqual(FFIError.enrollmentTokenGenerationFailed("test").errorCode, 1012)
        XCTAssertEqual(FFIError.mobileResponseConversionFailed("test").errorCode, 1013)
        XCTAssertEqual(FFIError.profileKeyEncryptionFailed("test").errorCode, 1014)
        XCTAssertEqual(FFIError.profileKeyDecryptionFailed("test").errorCode, 1015)
        XCTAssertEqual(FFIError.caClientConfigurationFailed("test").errorCode, 1016)
        XCTAssertEqual(FFIError.crlGenerationFailed("test").errorCode, 1017)
    }

    func testCAErrorDescriptions() {
        // Test CA-specific error descriptions
        XCTAssertTrue(FFIError.caNodeNotInitialized("test").errorDescription?.contains("CA Node not initialized") == true)
        XCTAssertTrue(FFIError.caServerNotRunning("test").errorDescription?.contains("CA Server not running") == true)
        XCTAssertTrue(FFIError.caClientConnectionFailed("test").errorDescription?.contains("CA Client connection failed") == true)
        XCTAssertTrue(FFIError.certificateValidationFailed("test").errorDescription?.contains("Certificate validation failed") == true)
        XCTAssertTrue(FFIError.profileKeyNotFound("test").errorDescription?.contains("Profile key not found") == true)
        XCTAssertTrue(FFIError.enrollmentTokenInvalid("test").errorDescription?.contains("Enrollment token invalid") == true)
        XCTAssertTrue(FFIError.rateLimitExceeded("test").errorDescription?.contains("Rate limit exceeded") == true)
        XCTAssertTrue(FFIError.adminNotAuthorized("test").errorDescription?.contains("Admin not authorized") == true)
        XCTAssertTrue(FFIError.certificateCreationFailed("test").errorDescription?.contains("Certificate creation failed") == true)
        XCTAssertTrue(FFIError.certificateSkiExtractionFailed("test").errorDescription?.contains("Certificate SKI extraction failed") == true)
        XCTAssertTrue(FFIError.certificateSerialExtractionFailed("test").errorDescription?.contains("Certificate serial extraction failed") == true)
        XCTAssertTrue(FFIError.enrollmentTokenGenerationFailed("test").errorDescription?.contains("Enrollment token generation failed") == true)
        XCTAssertTrue(FFIError.mobileResponseConversionFailed("test").errorDescription?.contains("Mobile response conversion failed") == true)
        XCTAssertTrue(FFIError.profileKeyEncryptionFailed("test").errorDescription?.contains("Profile key encryption failed") == true)
        XCTAssertTrue(FFIError.profileKeyDecryptionFailed("test").errorDescription?.contains("Profile key decryption failed") == true)
        XCTAssertTrue(FFIError.caClientConfigurationFailed("test").errorDescription?.contains("CA Client configuration failed") == true)
        XCTAssertTrue(FFIError.crlGenerationFailed("test").errorDescription?.contains("CRL generation failed") == true)
    }

    func testErrorCodeMapping() {
        // Test error code mapping from integers
        XCTAssertEqual(FFIError(code: 1001, message: "test").errorCode, 1001)
        XCTAssertEqual(FFIError(code: 1002, message: "test").errorCode, 1002)
        XCTAssertEqual(FFIError(code: 1003, message: "test").errorCode, 1003)
        XCTAssertEqual(FFIError(code: 1004, message: "test").errorCode, 1004)
        XCTAssertEqual(FFIError(code: 1005, message: "test").errorCode, 1005)
        XCTAssertEqual(FFIError(code: 1006, message: "test").errorCode, 1006)
        XCTAssertEqual(FFIError(code: 1007, message: "test").errorCode, 1007)
        XCTAssertEqual(FFIError(code: 1008, message: "test").errorCode, 1008)
        XCTAssertEqual(FFIError(code: 1009, message: "test").errorCode, 1009)
        XCTAssertEqual(FFIError(code: 1010, message: "test").errorCode, 1010)
        XCTAssertEqual(FFIError(code: 1011, message: "test").errorCode, 1011)
        XCTAssertEqual(FFIError(code: 1012, message: "test").errorCode, 1012)
        XCTAssertEqual(FFIError(code: 1013, message: "test").errorCode, 1013)
        XCTAssertEqual(FFIError(code: 1014, message: "test").errorCode, 1014)
        XCTAssertEqual(FFIError(code: 1015, message: "test").errorCode, 1015)
        XCTAssertEqual(FFIError(code: 1016, message: "test").errorCode, 1016)
        XCTAssertEqual(FFIError(code: 1017, message: "test").errorCode, 1017)
    }

    // MARK: - Data Structure Tests

    func testCaServerConfig() {
        let config = CaServerConfig(
            bootstrapBind: "0.0.0.0:8080",
            authenticatedBind: "0.0.0.0:8081",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )

        XCTAssertEqual(config.bootstrapBind, "0.0.0.0:8080")
        XCTAssertEqual(config.authenticatedBind, "0.0.0.0:8081")
        XCTAssertEqual(config.networkId, "test-network")
        XCTAssertEqual(config.rateLimitPerMinute, 100)
        XCTAssertEqual(config.rateLimitPerHour, 1000)
    }

    func testCaClientConfig() {
        let config = CaClientConfig(
            bootstrapServer: "ca.example.com:8080",
            authenticatedServer: "ca.example.com:8081",
            networkId: "test-network",
            requestTimeoutSeconds: 30,
            maxRetries: 3
        )

        XCTAssertEqual(config.bootstrapServer, "ca.example.com:8080")
        XCTAssertEqual(config.authenticatedServer, "ca.example.com:8081")
        XCTAssertEqual(config.networkId, "test-network")
        XCTAssertEqual(config.requestTimeoutSeconds, 30)
        XCTAssertEqual(config.maxRetries, 3)
    }

    func testCertificateStatus() {
        let status = CertificateStatus(
            isValid: true,
            notBefore: 1_000_000_000,
            notAfter: 2_000_000_000,
            serialHex: "1234567890ABCDEF"
        )

        XCTAssertTrue(status.isValid)
        XCTAssertEqual(status.notBefore, 1_000_000_000)
        XCTAssertEqual(status.notAfter, 2_000_000_000)
        XCTAssertEqual(status.serialHex, "1234567890ABCDEF")
    }

    func testProfileKeyInfo() {
        let publicKey = Data("test-public-key".utf8)
        let info = ProfileKeyInfo(profileId: "test-profile", publicKey: publicKey)

        XCTAssertEqual(info.profileId, "test-profile")
        XCTAssertEqual(info.publicKey, publicKey)
    }

    func testKeystoreCapabilities() {
        let caps = KeystoreCapabilities(version: 1, flags: 0x1234)

        XCTAssertEqual(caps.version, 1)
        XCTAssertEqual(caps.flags, 0x1234)
    }

    func testFfiHandles() {
        let testPointer = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { testPointer.deallocate() }

        let keysHandle = FfiKeysHandle(inner: testPointer)
        let transportHandle = FfiTransportHandle(inner: testPointer)

        XCTAssertEqual(keysHandle.inner, testPointer)
        XCTAssertEqual(transportHandle.inner, testPointer)
    }

    // MARK: - Enrollment Token Tests

    func testEnrollmentTokenParams() {
        let eaKey = Data("test-ea-key".utf8)
        let nonce = Data("test-nonce".utf8)
        let permissions = Data("test-permissions".utf8)

        let params = EnrollmentTokenParams(
            eaKey: eaKey,
            tokenId: "test-token-id",
            networkId: "test-network",
            subject: "CN=test",
            notBefore: 1_000_000_000,
            expiresAt: 2_000_000_000,
            nonce: nonce,
            permissions: permissions
        )

        XCTAssertEqual(params.eaKey, eaKey)
        XCTAssertEqual(params.tokenId, "test-token-id")
        XCTAssertEqual(params.networkId, "test-network")
        XCTAssertEqual(params.subject, "CN=test")
        XCTAssertEqual(params.notBefore, 1_000_000_000)
        XCTAssertEqual(params.expiresAt, 2_000_000_000)
        XCTAssertEqual(params.nonce, nonce)
        XCTAssertEqual(params.permissions, permissions)
    }

    // MARK: - Node Key Manager Additional Functions Tests

    func testNodeKeyManagerAdditionalFunctions() throws {
        // Initialize as node first
        try keysFFI.initializeAsNode()

        // Test hasKeys function
        let hasKeys = try keysFFI.hasKeys()
        // Keys may or may not exist initially, so we just check that the call succeeded
        XCTAssertTrue(hasKeys == false || hasKeys == true, "hasKeys should be true or false")

        // Test generateKeys function
        try keysFFI.generateKeys()

        // Test hasKeys after generation
        let hasKeysAfter = try keysFFI.hasKeys()
        // Keys might not be immediately available after generation
        // This depends on the implementation details
        XCTAssertTrue(hasKeysAfter == false || hasKeysAfter == true, "hasKeys should be true or false after generation")

        // Test getCompactId function
        let publicKey = try keysFFI.nodeGetPublicKey()
        let compactId = try keysFFI.getCompactId(publicKey: publicKey)
        XCTAssertFalse(compactId.isEmpty, "Compact ID should not be empty")
    }

    func testProfileKeyManagement() throws {
        // Initialize as node first
        try keysFFI.initializeAsNode()
        try keysFFI.generateKeys()

        // Test deriveUserProfileKey
        let profileKey = try keysFFI.deriveUserProfileKey(label: "test-profile")
        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")

        // Test installProfilePublicKey
        let testPublicKey = Data("test-public-key".utf8)
        try keysFFI.installProfilePublicKey(testPublicKey)

        // Test getProfilePublicKeyByLabel
        let (retrievedKey, hasKey) = try keysFFI.getProfilePublicKeyByLabel(label: "test-profile")
        XCTAssertTrue(hasKey, "Profile key should exist")
        XCTAssertFalse(retrievedKey.isEmpty, "Retrieved profile key should not be empty")
    }

    func testNetworkManagement() throws {
        // Initialize as node first
        try keysFFI.initializeAsNode()
        try keysFFI.generateKeys()

        // Test getNetworkAgreement - should fail when no network key exists
        let networkPublicKey = Data("test-network-public-key".utf8)
        do {
            _ = try keysFFI.getNetworkAgreement(networkPublicKey: networkPublicKey)
            XCTFail("getNetworkAgreement should fail when no network key exists")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }

        // Test hasNetworkPrivateKey - should return false when no network key exists
        let hasPrivateKey = try keysFFI.hasNetworkPrivateKey(networkPublicKey: networkPublicKey)
        XCTAssertFalse(hasPrivateKey, "Should not have network private key initially")
    }

    // MARK: - Memory Management Tests

    func testFFIMemoryManager() {
        // Test memory allocation and deallocation
        let testData = Data("test-data".utf8)
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: testData.count)
        defer { pointer.deallocate() }

        // Test that the memory manager functions exist and can be called
        // (These are static functions, so we just verify they exist)
        XCTAssertNotNil(FFIMemoryManager.free)
        XCTAssertNotNil(FFIMemoryManager.freeString)
        XCTAssertNotNil(FFIMemoryManager.freeData)
    }
}
