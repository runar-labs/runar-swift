import CryptoKit
import Foundation
import Security
import SwiftASN1
import X509
import XCTest

/// Errors specific to certificate chain creation and management
enum CertificateChainError: Error {
    case keyGenerationFailed(String)
    case certificateCreationFailed(String)
    case signingFailed(String)
    case keychainOperationFailed(String)
    case verificationFailed(String)
}

/// POC test class for creating and verifying a proper TLS certificate chain for QUIC transporter
final class SecIdentityPOCTests: XCTestCase {
    // Test configuration - use constants for clarity and easy modification
    private static let caSubject = "CN=Runar Test CA,O=Runar Test Org,C=US"
    private static let leafSubject = "CN=Runar Test Server,O=Runar Test Org,C=US"
    private static let keyCurve = P384.Signing.self // Use P-384 for stronger security (TLS 1.3 compatible)
    private static let validityDuration: TimeInterval = 365 * 24 * 60 * 60 // 1 year
    private static let caKeyUsage = KeyUsage(keyCertSign: true, cRLSign: true) // CA-specific usage
    private static let leafKeyUsage = KeyUsage(digitalSignature: true, keyEncipherment: true) // Server TLS usage
    private static let leafExtendedKeyUsage: ExtendedKeyUsage = // Only serverAuth for TLS servers; can easily add clientAuth if needed
        // Using the high-level Usage API from swift-certificates 1.7.0
        try! ExtendedKeyUsage([.serverAuth])

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

    func testCreateAndVerifyTLSChainForQUIC() throws {
        print("🚀 Starting TLS certificate chain POC test...")

        // Step 1: Generate CA private key (P-384 ECDSA)
        print("📋 Step 1: Generating CA private key...")
        let caPrivateKey = try generatePrivateKey()
        let caPublicKey = caPrivateKey.publicKey
        print("✅ Generated CA private key (P-384 ECDSA)")

        // Step 2: Create self-signed CA certificate with proper extensions
        print("📋 Step 2: Creating self-signed CA certificate...")
        let caDN = try parseDistinguishedName(Self.caSubject)
        let caCertificate = try createCACertificate(
            privateKey: caPrivateKey,
            publicKey: caPublicKey,
            subject: caDN
        )
        let caCertDER = try serializeCertificate(caCertificate)
        print("✅ Created CA certificate: \(caCertDER.count) bytes")

        // Step 3: Generating leaf key directly in Keychain and deriving public key
        print("📋 Step 3: Generating leaf key in Keychain...")
        let secLeafPrivateKey = try generatePrivateKeyInKeychain(label: leafKeyLabel)
        guard let secLeafPublicKey = SecKeyCopyPublicKey(secLeafPrivateKey) else {
            throw CertificateChainError.keychainOperationFailed("Failed to get public key from SecKey")
        }
        var pubError: Unmanaged<CFError>?
        guard let pubData = SecKeyCopyExternalRepresentation(secLeafPublicKey, &pubError) as Data? else {
            throw CertificateChainError.keychainOperationFailed("Failed to export public key: \(pubError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        let leafPublicKey = try P384.Signing.PublicKey(x963Representation: pubData)
        print("✅ Generated leaf key in Keychain and derived public key")

        // Step 4: Creating leaf certificate...
        print("📋 Step 4: Creating leaf certificate...")
        let leafDN = try parseDistinguishedName(Self.leafSubject)
        let leafCertificate = try createLeafCertificate(
            caCertificate: caCertificate,
            caPrivateKey: caPrivateKey,
            publicKey: leafPublicKey,
            subject: leafDN
        )
        let leafCertDER = try serializeCertificate(leafCertificate)
        print("✅ Created leaf certificate: \(leafCertDER.count) bytes")

        // Step 5: Import CA certificate to Keychain (as trust anchor)
        print("📋 Step 5: Importing CA certificate to Keychain...")
        let secCACertificate = try importCertificateToKeychain(der: caCertDER, label: caCertLabel)
        print("✅ Imported CA certificate to Keychain")

        // Step 6: Importing leaf certificate to Keychain...
        print("📋 Step 6: Importing leaf certificate to Keychain...")
        let secLeafCertificate = try importCertificateToKeychain(der: leafCertDER, label: leafCertLabel)
        print("✅ Imported leaf certificate to Keychain")

        // Step 7: Creating SecIdentity (virtual – not stored separately)
        print("📋 Step 7: Creating SecIdentity (virtual)...")
        var maybeIdentity: SecIdentity?
        let idStatus = SecIdentityCreateWithCertificate(nil, secLeafCertificate, &maybeIdentity)
        guard idStatus == errSecSuccess, let secIdentity = maybeIdentity else {
            throw CertificateChainError.keychainOperationFailed("Failed to create SecIdentity: \(idStatus)")
        }
        print("✅ SecIdentity created (Keychain provides virtual identity)")

        // Step 8: Verifying certificate chain...
        print("📋 Step 8: Verifying certificate chain...")
        try verifyCertificateChain(leaf: secLeafCertificate, ca: secCACertificate)
        print("✅ Certificate chain verified successfully")

        // Step 9: Validating SecIdentity with sign/verify...
        print("📋 Step 9: Validating SecIdentity with sign/verify...")
        try validateSecIdentity(secIdentity)
        print("✅ SecIdentity validated: signature verification succeeded")

        print("🎉 TLS certificate chain POC test PASSED! Ready for QUIC transporter usage.")
    }

    // MARK: - Helper Functions

    /// Generate secure random bytes for serial numbers
    private func generateSecureRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw CertificateChainError.keyGenerationFailed("Failed to generate secure random bytes: \(status)")
        }
        return bytes
    }

    /// Generate a new P-384 ECDSA private key
    private func generatePrivateKey() throws -> P384.Signing.PrivateKey {
        return P384.Signing.PrivateKey()
    }

    /// Parse string DN to X509 DistinguishedName
    private func parseDistinguishedName(_ dn: String) throws -> DistinguishedName {
        var components: [RelativeDistinguishedName] = []
        let parts = dn.components(separatedBy: ",")

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let keyValue = trimmed.components(separatedBy: "=")
            guard keyValue.count == 2 else {
                throw CertificateChainError.certificateCreationFailed("Invalid DN component: \(trimmed)")
            }

            let key = keyValue[0].trimmingCharacters(in: .whitespaces).uppercased()
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)

            let attribute: RelativeDistinguishedName.Attribute
            switch key {
            case "CN":
                attribute = .init(type: .RDNAttributeType.commonName, utf8String: value)
            case "C":
                attribute = try .init(type: .RDNAttributeType.countryName, printableString: value)
            case "O":
                attribute = .init(type: .RDNAttributeType.organizationName, utf8String: value)
            default:
                throw CertificateChainError.certificateCreationFailed("Unsupported DN attribute: \(key)")
            }

            components.append(RelativeDistinguishedName([attribute]))
        }

        return DistinguishedName(components)
    }

    /// Create self-signed CA certificate with proper extensions
    private func createCACertificate(
        privateKey: P384.Signing.PrivateKey,
        publicKey: P384.Signing.PublicKey,
        subject: DistinguishedName
    ) throws -> Certificate {
        let serialBytes = try generateSecureRandomBytes(count: 16)
        let serial = Certificate.SerialNumber(bytes: serialBytes)

        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            )
            Critical(Self.caKeyUsage)
            AuthorityKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.x963Representation))))
            SubjectKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.x963Representation))))
        }

        return try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: .init(publicKey),
            notValidBefore: Date().addingTimeInterval(-60), // Start 1 minute ago to ensure validity
            notValidAfter: Date().addingTimeInterval(Self.validityDuration * 10),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: extensions,
            issuerPrivateKey: .init(privateKey)
        )
    }

    /// Create leaf certificate signed by CA with proper extensions
    private func createLeafCertificate(
        caCertificate: Certificate,
        caPrivateKey: P384.Signing.PrivateKey,
        publicKey: P384.Signing.PublicKey,
        subject: DistinguishedName
    ) throws -> Certificate {
        let serialBytes = try generateSecureRandomBytes(count: 16)
        let serial = Certificate.SerialNumber(bytes: serialBytes)

        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.notCertificateAuthority
            )
            Critical(Self.leafKeyUsage)
            Critical(
                Self.leafExtendedKeyUsage
            )
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(Data(SHA256.hash(data: Data(caCertificate.publicKey.subjectPublicKeyInfoBytes))))
            )
            SubjectKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.x963Representation))))
            SubjectAlternativeNames([.dnsName("localhost"), .dnsName("runar.test")])
        }

        return try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: .init(publicKey),
            notValidBefore: Date().addingTimeInterval(-60), // Start 1 minute ago to ensure validity
            notValidAfter: Date().addingTimeInterval(Self.validityDuration),
            issuer: caCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: extensions,
            issuerPrivateKey: .init(caPrivateKey)
        )
    }

    /// Serialize certificate to DER format
    private func serializeCertificate(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    /// Import DER-encoded certificate to Keychain and return SecCertificate
    private func importCertificateToKeychain(der: Data, label: String) throws -> SecCertificate {
        guard let secCertificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw CertificateChainError.keychainOperationFailed("Failed to create SecCertificate from DER data")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: secCertificate,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CertificateChainError.keychainOperationFailed("Failed to import certificate to Keychain: \(status)")
        }

        return secCertificate
    }

    /// Generate a new P-384 private key **directly in the Keychain** and return the `SecKey` reference.
    ///
    /// This avoids `paramErr` (-50) that can occur when importing raw key bytes.
    /// **TODO**: add an alternative PKCS#8-import path if we need to import externally-generated keys.
    private func generatePrivateKeyInKeychain(label: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 384,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: label,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CertificateChainError.keychainOperationFailed("Failed to generate private key in Keychain: \(error?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        return secKey
    }

    // MARK: Key export helpers

    /// Extract raw representation from a `SecKey` (if allowed) to bridge back to CryptoKit
    private func rawPrivateKeyData(from secKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(secKey, &error) as Data? else {
            throw CertificateChainError.keychainOperationFailed("Failed to export SecKey: \(error?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        return data
    }

    // Removed explicit SecIdentity storage – Keychain synthesises it from key + certificate

    /// Verify the certificate chain using SecTrust
    private func verifyCertificateChain(leaf: SecCertificate, ca: SecCertificate) throws {
        let policy = SecPolicyCreateSSL(true, nil) // SSL policy for TLS validation

        let certificates = [leaf, ca] as CFArray
        var trust: SecTrust?
        let createStatus = SecTrustCreateWithCertificates(certificates, policy, &trust)
        guard createStatus == errSecSuccess, let secTrust = trust else {
            throw CertificateChainError.verificationFailed("Failed to create SecTrust: \(createStatus)")
        }

        // Set CA as anchor
        let anchors = [ca] as CFArray
        let anchorStatus = SecTrustSetAnchorCertificates(secTrust, anchors)
        guard anchorStatus == errSecSuccess else {
            throw CertificateChainError.verificationFailed("Failed to set anchor certificates: \(anchorStatus)")
        }

        // Evaluate trust
        var error: CFError?
        guard SecTrustEvaluateWithError(secTrust, &error) else {
            throw CertificateChainError.verificationFailed("Chain validation failed: \(error?.localizedDescription ?? "Unknown error")")
        }
    }

    /// Validate SecIdentity by signing data and verifying the signature
    private func validateSecIdentity(_ identity: SecIdentity) throws {
        var privateKey: SecKey?
        let keyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard keyStatus == errSecSuccess, let secPrivateKey = privateKey else {
            throw CertificateChainError.verificationFailed("Failed to get private key from identity: \(keyStatus)")
        }

        var certificate: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certStatus == errSecSuccess, let secCertificate = certificate else {
            throw CertificateChainError.verificationFailed("Failed to get certificate from identity: \(certStatus)")
        }

        let dataToSign = "Test validation data".data(using: .utf8)! as CFData
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA384

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secPrivateKey, algorithm, dataToSign, &signError) as Data? else {
            throw CertificateChainError.signingFailed("Failed to sign data: \(signError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }

        guard let publicKey = SecCertificateCopyKey(secCertificate) else {
            throw CertificateChainError.verificationFailed("Failed to get public key from certificate")
        }

        var verifyError: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(publicKey, algorithm, dataToSign, signature as CFData, &verifyError)
        guard isValid else {
            throw CertificateChainError.verificationFailed("Signature verification failed: \(verifyError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
    }
}
