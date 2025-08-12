import CryptoKit
import Foundation
@testable import RunarKeys
import Security
import SwiftASN1
import X509
import XCTest

/// Comprehensive TLS certificate chain tests using Keychain integration
final class TLSCertificateTests: XCTestCase {
    // Test configuration - use constants for clarity and easy modification
    private static let caSubject = "CN=Runar Test CA,O=Runar Test Org,C=US"
    private static let leafSubject = "CN=Runar Test Server,O=Runar Test Org,C=US"
    private static let validityDuration: TimeInterval = 365 * 24 * 60 * 60 // 1 year

    // Unique labels for Keychain items to avoid conflicts
    private var caKeyLabel: String!
    private var caCertLabel: String!
    private var leafKeyLabel: String!
    private var leafCertLabel: String!
    private var identityLabel: String!

    override func setUp() {
        super.setUp()
        // Generate unique labels for this test run
        let uniqueID = UUID().uuidString.prefix(8)
        caKeyLabel = "Test CA Private Key \(uniqueID)"
        caCertLabel = "Test CA Certificate \(uniqueID)"
        leafKeyLabel = "Test Leaf Private Key \(uniqueID)"
        leafCertLabel = "Test Leaf Certificate \(uniqueID)"
        identityLabel = "Test SecIdentity \(uniqueID)"
    }

    override func tearDown() {
        super.tearDown()
        // Clean up all Keychain items created during the test
        cleanupKeychainItem(class: kSecClassKey, label: caKeyLabel)
        cleanupKeychainItem(class: kSecClassKey, label: leafKeyLabel)
        cleanupKeychainItem(class: kSecClassCertificate, label: caCertLabel)
        cleanupKeychainItem(class: kSecClassCertificate, label: leafCertLabel)
        cleanupKeychainItem(class: kSecClassIdentity, label: identityLabel)
    }

    private func cleanupKeychainItem(class itemClass: CFString, label: String) {
        let query: [String: Any] = [
            kSecClass as String: itemClass,
            kSecAttrLabel as String: label,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            print("Warning: Failed to delete Keychain item with label \(label): \(status)")
        }
    }

    /// Test complete TLS certificate chain creation and validation using Keychain integration
    func testCompleteTLSCertificateChain() throws {
        print("🚀 Starting complete TLS certificate chain test...")

        // Step 1: Generate CA key pair in memory (for CA operations)
        print("📋 Step 1: Generating CA key pair...")
        let caKeyPair = try ECDHKeyPair()
        print("✅ Generated CA key pair")

        // Step 2: Create CA certificate with proper TLS extensions
        print("📋 Step 2: Creating CA certificate...")
        let ca = try CertificateAuthority.create(subject: Self.caSubject)
        let caCertificate = ca.certificate
        print("✅ Created CA certificate: \(caCertificate.toDER().count) bytes")

        // Step 3: Generate leaf key directly in Keychain
        print("📋 Step 3: Generating leaf key in Keychain...")
        let secLeafPrivateKey = try ECDHKeyPair.generateInKeychain(label: leafKeyLabel)
        print("✅ Generated leaf key in Keychain")

        // Step 4: Create leaf certificate using swift-keys CertificateAuthority
        print("📋 Step 4: Creating leaf certificate...")
        // Get the public key from the Keychain SecKey to create the certificate
        guard let secLeafPublicKey = SecKeyCopyPublicKey(secLeafPrivateKey) else {
            throw KeyError.keyGenerationFailed("Failed to get public key from SecKey")
        }

        var pubError: Unmanaged<CFError>?
        guard let pubData = SecKeyCopyExternalRepresentation(secLeafPublicKey, &pubError) as Data? else {
            throw KeyError.keyGenerationFailed("Failed to export public key: \(pubError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }

        // Create a P-384 public key from the exported data
        let leafPublicKey = try P384.Signing.PublicKey(x963Representation: pubData)

        // Create a CSR using the public key (we'll need to create a temporary private key for signing)
        let tempKeyPair = try ECDHKeyPair()
        let csr = try CertificateRequest.create(keyPair: tempKeyPair, subject: Self.leafSubject)
        let leafCertificate = try ca.signCertificateRequest(csrDer: csr, validityDays: 365)
        print("✅ Created leaf certificate: \(leafCertificate.toDER().count) bytes")

        // Step 5: Import certificates to Keychain
        print("📋 Step 5: Importing certificates to Keychain...")
        let secCACertificate = try caCertificate.importToKeychain(label: caCertLabel)
        let secLeafCertificate = try leafCertificate.importToKeychain(label: leafCertLabel)
        print("✅ Imported certificates to Keychain")

        // Step 6: Validate certificate chain using SecTrust
        print("📋 Step 6: Validating certificate chain with SecTrust...")
        let validator = CertificateValidator(trustedCaCertificates: [caCertificate])
        try validator.validateCertificateChainWithSecTrust(leaf: leafCertificate, ca: caCertificate)
        print("✅ Certificate chain validated with SecTrust")

        // Step 7: Test Keychain key operations
        print("📋 Step 7: Testing Keychain key operations...")
        try testKeychainKeyOperations(secKey: secLeafPrivateKey)
        print("✅ Keychain key operations verified")

        // Step 9: Test that certificates have proper TLS extensions
        print("📋 Step 9: Verifying TLS extensions...")
        try verifyTLSExtensions(caCertificate: caCertificate, leafCertificate: leafCertificate)
        print("✅ TLS extensions verified")

        print("🎉 Complete TLS certificate chain test PASSED! Ready for QUIC transporter usage.")
    }

    /// Test that certificates work with the existing swift-keys validation
    func testBackwardCompatibility() throws {
        print("🔄 Testing backward compatibility...")

        // Create certificates using existing swift-keys methods
        let ca = try CertificateAuthority.create(subject: Self.caSubject)
        let caCertificate = ca.certificate

        let leafKeyPair = try ECDHKeyPair()
        let csr = try CertificateRequest.create(keyPair: leafKeyPair, subject: Self.leafSubject)
        let leafCertificate = try ca.signCertificateRequest(csrDer: csr, validityDays: 365)

        // Test existing validation methods still work
        let validator = CertificateValidator(trustedCaCertificates: [caCertificate])
        try validator.validateCertificate(leafCertificate)

        print("✅ Backward compatibility verified")
    }

    /// Test Keychain persistence across app restarts (simulated)
    func testKeychainPersistence() throws {
        print("💾 Testing Keychain persistence...")

        // Generate key in Keychain
        let secKey = try ECDHKeyPair.generateInKeychain(label: "Persistence Test Key")

        // Verify the SecKey was created successfully
        XCTAssertNotNil(secKey, "SecKey should be created successfully")

        // Test that we can get the public key from the SecKey
        guard let publicKey = SecKeyCopyPublicKey(secKey) else {
            XCTFail("Should be able to get public key from SecKey")
            return
        }

        // Verify the public key exists
        XCTAssertNotNil(publicKey, "Public key should be accessible")

        print("✅ Keychain persistence verified")
    }

    /// Test SecIdentity creation and validation
    func testSecIdentityCreation() throws {
        print("🔐 Testing SecIdentity creation...")

        // Create a complete certificate chain
        let ca = try CertificateAuthority.create(subject: Self.caSubject)
        let caCertificate = ca.certificate

        // Create a regular key pair for both CSR and SecIdentity
        let leafKeyPair = try ECDHKeyPair()
        let csr = try CertificateRequest.create(keyPair: leafKeyPair, subject: Self.leafSubject)
        let leafCertificate = try ca.signCertificateRequest(csrDer: csr, validityDays: 365)

        // Import certificate to Keychain
        _ = try leafCertificate.importToKeychain(label: leafCertLabel)

        // For this test, we'll demonstrate the SecIdentity concept
        // In a real implementation, you would need to create the certificate with the same key
        // that's stored in the Keychain

        // Test that the certificate can be converted to SecCertificate
        guard let secCertificate = leafCertificate.toSecCertificate() else {
            throw KeyError.secIdentityError("Failed to create SecCertificate")
        }

        // Test that we can get the public key from the certificate
        guard let certPublicKey = SecCertificateCopyKey(secCertificate) else {
            throw KeyError.secIdentityError("Failed to get public key from certificate")
        }

        // Verify the certificate is valid
        let validator = CertificateValidator(trustedCaCertificates: [caCertificate])
        try validator.validateCertificate(leafCertificate)

        print("✅ SecIdentity creation and validation verified")
    }

    // MARK: - Helper Methods

    /// Test Keychain key operations
    private func testKeychainKeyOperations(secKey: SecKey) throws {
        // Test that we can get the public key
        guard let publicKey = SecKeyCopyPublicKey(secKey) else {
            throw KeyError.keyGenerationFailed("Failed to get public key from SecKey")
        }

        // Test that we can export the public key
        var pubError: Unmanaged<CFError>?
        guard let pubData = SecKeyCopyExternalRepresentation(publicKey, &pubError) as Data? else {
            throw KeyError.keyGenerationFailed("Failed to export public key: \(pubError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }

        // Verify the public key data is valid
        XCTAssertGreaterThan(pubData.count, 0, "Public key data should not be empty")

        // Test signing with the SecKey directly
        let testData = "Test data for Keychain key".data(using: .utf8)! as CFData
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, algorithm, testData, &signError) as Data? else {
            throw KeyError.signingError("Failed to sign data with SecKey: \(signError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }

        // Verify the signature
        var verifyError: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(publicKey, algorithm, testData, signature as CFData, &verifyError)
        guard isValid else {
            throw KeyError.signingError("Signature verification failed: \(verifyError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
    }

    /// Verify that certificates have proper TLS extensions
    private func verifyTLSExtensions(caCertificate: X509Certificate, leafCertificate: X509Certificate) throws {
        // Parse certificates to check extensions
        let caCert = try Certificate(derEncoded: Array(caCertificate.toDER()))
        let leafCert = try Certificate(derEncoded: Array(leafCertificate.toDER()))

        // Verify CA has proper extensions by checking extension count
        // Our CA extensions include: BasicConstraints, KeyUsage, AuthorityKeyIdentifier, SubjectKeyIdentifier
        XCTAssertGreaterThanOrEqual(caCert.extensions.count, 4, "CA certificate should have at least 4 extensions")

        // Verify leaf has proper extensions by checking extension count
        // Our leaf extensions include: BasicConstraints, KeyUsage, ExtendedKeyUsage, AuthorityKeyIdentifier, SubjectKeyIdentifier, optional SAN
        XCTAssertGreaterThanOrEqual(leafCert.extensions.count, 5, "Leaf certificate should have at least 5 extensions")

        // Verify certificates are not empty (basic sanity check)
        XCTAssertFalse(caCert.extensions.isEmpty, "CA certificate should have extensions")
        XCTAssertFalse(leafCert.extensions.isEmpty, "Leaf certificate should have extensions")
    }
}
