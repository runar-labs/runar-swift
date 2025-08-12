import Foundation
import CryptoKit
import Security
import X509
import SwiftASN1



// MARK: - Certificate Types

/// X.509 Certificate wrapper for swift-certificates
public struct X509Certificate: Codable {
    internal let certificate: Certificate
    
    public init(certificate: Certificate) {
        self.certificate = certificate
    }
    
    public init(derData: Data) throws {
        let certificate = try Certificate(derEncoded: Array(derData))
        self.certificate = certificate
    }
    
    public func toDER() -> Data {
        var serializer = DER.Serializer()
        try! certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
    
    // Codable
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let derData = try container.decode(Data.self)
        self = try X509Certificate(derData: derData)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.toDER())
    }
    
    public var subject: String {
        return certificate.subject.description
    }
    
    public var issuer: String {
        return certificate.issuer.description
    }
    
    public var notValidBefore: Date {
        return certificate.notValidBefore
    }
    
    public var notValidAfter: Date {
        return certificate.notValidAfter
    }
    
    public var publicKey: Certificate.PublicKey {
        return certificate.publicKey
    }
    
    public var subjectPublicKeyInfoBytes: Data {
        return Data(certificate.publicKey.subjectPublicKeyInfoBytes)
    }
}

// MARK: - Certificate Authority

/// Certificate Authority for creating and managing certificates
public class CertificateAuthority {
    private let keyPair: ECDHKeyPair
    internal let certificate: X509Certificate
    
    public init(keyPair: ECDHKeyPair, certificate: X509Certificate) {
        self.keyPair = keyPair
        self.certificate = certificate
    }
    
    /// Create a new CA with a self-signed certificate
    public static func create(subject: String) throws -> CertificateAuthority {
        let keyPair = try ECDHKeyPair()
        let certificate = try createSelfSignedCertificate(keyPair: keyPair, subject: subject)
        return CertificateAuthority(keyPair: keyPair, certificate: certificate)
    }
    
    /// Create a new CA with a self-signed certificate using P-384
    public static func create384(subject: String) throws -> CertificateAuthority {
        let keyPair = try ECDHKeyPair()
        let certificate = try createSelfSignedCertificate(keyPair: keyPair, subject: subject)
        return CertificateAuthority(keyPair: keyPair, certificate: certificate)
    }
    
    /// Get the CA certificate
    public func getCertificate() -> X509Certificate {
        return certificate
    }
    
    /// Get the CA key pair
    public func getKeyPair() -> ECDHKeyPair {
        return keyPair
    }
    
    /// Sign a certificate request (CSR) to create a leaf certificate
    public func signCertificateRequest(csrDer: Data, validityDays: Int) throws -> X509Certificate {
        let csr = try CertificateRequest(derData: csrDer)
        let leafCertificate = try createLeafCertificate(
            caCertificate: getCertificate(),
            caPrivateKey: try keyPair.toECDSASigningKey(),
            csr: csr,
            validityDays: validityDays
        )
        return X509Certificate(certificate: leafCertificate)
    }
    
    /// Create a leaf certificate directly from a public key (for Keychain integration)
    public func createCertificateFromPublicKey(publicKeyData: Data, subject: String, validityDays: Int) throws -> X509Certificate {
        let publicKey = try P384.Signing.PublicKey(x963Representation: publicKeyData)
        let leafCertificate = try createLeafCertificateFromPublicKey(
            caCertificate: getCertificate(),
            caPrivateKey: try keyPair.toECDSASigningKey(),
            publicKey: publicKey,
            subject: subject,
            validityDays: validityDays
        )
        return X509Certificate(certificate: leafCertificate)
    }
    
    /// Get the underlying certificate for internal operations
    internal func getCertificate() -> Certificate {
        return certificate.certificate
    }
    
    // MARK: - Helper Functions
    
    /// Create self-signed CA certificate
    private static func createSelfSignedCertificate(keyPair: ECDHKeyPair, subject: String) throws -> X509Certificate {
        let certificate = try createSelfSignedCACertificate(
            subject: subject,
            privateKey: try keyPair.toECDSASigningKey(),
            publicKey: try keyPair.toECDSAVerifyingKey()
        )
        
        return X509Certificate(certificate: certificate)
    }
}

// MARK: - Certificate Request

/// Certificate Signing Request (CSR)
public struct CertificateRequest {
    internal let csr: CertificateSigningRequest
    
    public init(derData: Data) throws {
        self.csr = try CertificateSigningRequest(derEncoded: Array(derData))
    }
    
    public init(csr: CertificateSigningRequest) {
        self.csr = csr
    }
    
    public var subject: String {
        return csr.subject.description
    }
    
    public var publicKey: Certificate.PublicKey {
        return csr.publicKey
    }
    
    /// Create a CSR from a key pair and subject
    public static func create(keyPair: ECDHKeyPair, subject: String, subjectAltNames: [String] = []) throws -> Data {
        let subjectDN = try parseDistinguishedName(subject)
        let publicKey = try keyPair.toECDSAVerifyingKey()
        let privateKey = try keyPair.toECDSASigningKey()
        
        let csr = try CertificateSigningRequest(
            version: .v1,
            subject: subjectDN,
            privateKey: Certificate.PrivateKey(privateKey),
            attributes: CertificateSigningRequest.Attributes(),
            signatureAlgorithm: .ecdsaWithSHA384
        )
        
        var serializer = DER.Serializer()
        try csr.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
    

}

// MARK: - Certificate Validator

/// Certificate validation utilities
public struct CertificateValidator {
    private let trustedCaCertificates: [X509Certificate]
    
    public init(trustedCaCertificates: [X509Certificate]) {
        self.trustedCaCertificates = trustedCaCertificates
    }
    
    /// Return the trusted CA certificates used by this validator
    public func getTrustedCACertificates() -> [X509Certificate] {
        return trustedCaCertificates
    }
    
    /// Validate a certificate against trusted CAs
    public func validateCertificate(_ certificate: X509Certificate) throws {
        // Basic validation - check if certificate is valid
        let now = Date()
        guard certificate.notValidBefore <= now && now <= certificate.notValidAfter else {
            throw KeyError.certificateError("Certificate is not valid at current time")
        }
        
        // Check if certificate is issued by a trusted CA
        let isTrusted = trustedCaCertificates.contains { caCert in
            return certificate.issuer == caCert.issuer
        }
        
        guard isTrusted else {
            throw KeyError.certificateError("Certificate is not issued by a trusted CA")
        }
    }
    
    /// Validate certificate chain using SecTrust (comprehensive validation)
    public func validateCertificateChainWithSecTrust(leaf: X509Certificate, ca: X509Certificate) throws {
        guard let secLeafCertificate = leaf.toSecCertificate() else {
            throw KeyError.secTrustError("Failed to create SecCertificate from leaf certificate")
        }
        
        guard let secCACertificate = ca.toSecCertificate() else {
            throw KeyError.secTrustError("Failed to create SecCertificate from CA certificate")
        }
        
        let policy = SecPolicyCreateSSL(true, nil) // SSL policy for TLS validation
        
        let certificates = [secLeafCertificate, secCACertificate] as CFArray
        var trust: SecTrust?
        let createStatus = SecTrustCreateWithCertificates(certificates, policy, &trust)
        guard createStatus == errSecSuccess, let secTrust = trust else {
            throw KeyError.secTrustError("Failed to create SecTrust: \(createStatus)")
        }
        
        // Set CA as anchor
        let anchors = [secCACertificate] as CFArray
        let anchorStatus = SecTrustSetAnchorCertificates(secTrust, anchors)
        guard anchorStatus == errSecSuccess else {
            throw KeyError.secTrustError("Failed to set anchor certificates: \(anchorStatus)")
        }
        
        // Evaluate trust
        var error: CFError?
        guard SecTrustEvaluateWithError(secTrust, &error) else {
            throw KeyError.secTrustError("Chain validation failed: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    /// Validate SecIdentity by performing sign/verify operation
    public func validateSecIdentity(_ identity: SecIdentity) throws {
        var privateKey: SecKey?
        let keyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard keyStatus == errSecSuccess, let secPrivateKey = privateKey else {
            throw KeyError.secIdentityError("Failed to get private key from identity: \(keyStatus)")
        }
        
        var certificate: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certStatus == errSecSuccess, let secCertificate = certificate else {
            throw KeyError.secIdentityError("Failed to get certificate from identity: \(certStatus)")
        }
        
        let dataToSign = "Test validation data".data(using: .utf8)! as CFData
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA384
        
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secPrivateKey, algorithm, dataToSign, &signError) as Data? else {
            throw KeyError.secIdentityError("Failed to sign data: \(signError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        
        guard let publicKey = SecCertificateCopyKey(secCertificate) else {
            throw KeyError.secIdentityError("Failed to get public key from certificate")
        }
        
        var verifyError: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(publicKey, algorithm, dataToSign, signature as CFData, &verifyError)
        guard isValid else {
            throw KeyError.secIdentityError("Signature verification failed: \(verifyError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
    }
}

// MARK: - X509Certificate Extensions

extension X509Certificate {
    /// Convert to SecCertificate for Keychain integration
    public func toSecCertificate() -> SecCertificate? {
        return SecCertificateCreateWithData(nil, toDER() as CFData)
    }
    
    /// Create a SecIdentity from this certificate and a Keychain-stored private key
    public func createSecIdentity(privateKeySecKey: SecKey) throws -> SecIdentity {
        guard let secCertificate = toSecCertificate() else {
            throw KeyError.secIdentityError("Failed to create SecCertificate")
        }
        
        var maybeIdentity: SecIdentity?
        let idStatus = SecIdentityCreateWithCertificate(nil, secCertificate, &maybeIdentity)
        guard idStatus == errSecSuccess, let secIdentity = maybeIdentity else {
            throw KeyError.secIdentityError("Failed to create SecIdentity: \(idStatus)")
        }
        return secIdentity
    }
    
    /// Import this certificate to the Keychain
    public func importToKeychain(label: String) throws -> SecCertificate {
        guard let secCertificate = toSecCertificate() else {
            throw KeyError.keychainOperationFailed("Failed to create SecCertificate from DER data")
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: secCertificate
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeyError.keychainOperationFailed("Failed to import certificate to Keychain: \(status)")
        }
        
        return secCertificate
    }
}

// MARK: - Helper Functions

/// Create a self-signed CA certificate using swift-certificates (P-384)
private func createSelfSignedCACertificate(
    subject: String,
    privateKey: P384.Signing.PrivateKey,
    publicKey: P384.Signing.PublicKey
) throws -> Certificate {
    // Parse the subject DN
    let subjectDN = try parseDistinguishedName(subject)
    
    // Create certificate template
    let certificate = try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: Certificate.PublicKey(publicKey),
        notValidBefore: Date().addingTimeInterval(-60), // Start 1 minute ago to avoid timing issues
        notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60 * 10), // 10 years
        issuer: subjectDN,
        subject: subjectDN,
        signatureAlgorithm: .ecdsaWithSHA384,
        extensions: try createCAExtensions(publicKey: publicKey),
        issuerPrivateKey: Certificate.PrivateKey(privateKey)
    )
    
    return certificate
}

/// Create a certificate from a CSR using swift-certificates
private func createLeafCertificate(
    caCertificate: Certificate,
    caPrivateKey: P384.Signing.PrivateKey,
    csr: CertificateRequest,
    validityDays: Int
) throws -> Certificate {
    let validityDuration: TimeInterval = TimeInterval(validityDays * 24 * 60 * 60)
    
    let certificate = try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: csr.publicKey,
        notValidBefore: Date().addingTimeInterval(-60), // Start 1 minute ago to avoid timing issues
        notValidAfter: Date().addingTimeInterval(validityDuration),
        issuer: caCertificate.subject,
        subject: csr.csr.subject,
        signatureAlgorithm: .ecdsaWithSHA384,
        extensions: try createEndEntityExtensions(
            publicKey: csr.publicKey,
            issuerPublicKey: caCertificate.publicKey,
            subject: csr.csr.subject
        ),
        issuerPrivateKey: Certificate.PrivateKey(caPrivateKey)
    )
    
    return certificate
}

/// Create a certificate directly from a public key (for Keychain integration)
private func createLeafCertificateFromPublicKey(
    caCertificate: Certificate,
    caPrivateKey: P384.Signing.PrivateKey,
    publicKey: P384.Signing.PublicKey,
    subject: String,
    validityDays: Int
) throws -> Certificate {
    let validityDuration: TimeInterval = TimeInterval(validityDays * 24 * 60 * 60)
    let subjectDN = try parseDistinguishedName(subject)
    
    let certificate = try Certificate(
        version: .v3,
        serialNumber: Certificate.SerialNumber(),
        publicKey: Certificate.PublicKey(publicKey),
        notValidBefore: Date().addingTimeInterval(-60), // Start 1 minute ago to avoid timing issues
        notValidAfter: Date().addingTimeInterval(validityDuration),
        issuer: caCertificate.subject,
        subject: subjectDN,
        signatureAlgorithm: .ecdsaWithSHA384,
        extensions: try createEndEntityExtensions(
            publicKey: Certificate.PublicKey(publicKey),
            issuerPublicKey: caCertificate.publicKey,
            subject: subjectDN
        ),
        issuerPrivateKey: Certificate.PrivateKey(caPrivateKey)
    )
    
    return certificate
}

/// Parse distinguished name string to X509 DistinguishedName
private func parseDistinguishedName(_ dn: String) throws -> DistinguishedName {
    var components: [RelativeDistinguishedName] = []
    let parts = dn.components(separatedBy: ",")
    
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        
        let keyValue = trimmed.components(separatedBy: "=")
        guard keyValue.count == 2 else {
            throw KeyError.certificateError("Invalid DN component: \(trimmed)")
        }
        
        let key = keyValue[0].trimmingCharacters(in: .whitespaces).uppercased()
        let value = keyValue[1].trimmingCharacters(in: .whitespaces)
        
        let attribute: RelativeDistinguishedName.Attribute?
        switch key {
        case "CN":
            attribute = .init(type: .RDNAttributeType.commonName, utf8String: value)
        case "C":
            attribute = try .init(type: .RDNAttributeType.countryName, printableString: value)
        case "O":
            attribute = .init(type: .RDNAttributeType.organizationName, utf8String: value)
        case "OU":
            attribute = .init(type: .RDNAttributeType.organizationalUnitName, utf8String: value)
        case "ST":
            attribute = .init(type: .RDNAttributeType.stateOrProvinceName, utf8String: value)
        case "L":
            attribute = .init(type: .RDNAttributeType.localityName, utf8String: value)
        default:
            // Ignore unknown attributes for robustness
            attribute = nil
        }
        
        if let attribute {
            components.append(RelativeDistinguishedName([attribute]))
        }
    }
    
    return DistinguishedName(components)
}

/// Create CA certificate extensions
private func createCAExtensions(publicKey: P384.Signing.PublicKey) throws -> Certificate.Extensions {
    return try Certificate.Extensions {
        Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
        Critical(KeyUsage(keyCertSign: true, cRLSign: true))
        AuthorityKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.x963Representation))))
        SubjectKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.x963Representation))))
    }
}

/// Create end entity certificate extensions
private func createEndEntityExtensions(
    publicKey: Certificate.PublicKey,
    issuerPublicKey: Certificate.PublicKey,
    subject: DistinguishedName
) throws -> Certificate.Extensions {
    let sanEntries = buildDNSSubjectAlternativeNames(from: subject)
    return try Certificate.Extensions {
        Critical(BasicConstraints.notCertificateAuthority)
        // For ECDSA TLS server/client certs, digitalSignature is sufficient. Avoid keyEncipherment for ECDSA.
        Critical(KeyUsage(digitalSignature: true))
        Critical(try ExtendedKeyUsage([.serverAuth, .clientAuth]))
        AuthorityKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: issuerPublicKey.subjectPublicKeyInfoBytes))))
        SubjectKeyIdentifier(keyIdentifier: ArraySlice(Data(SHA256.hash(data: publicKey.subjectPublicKeyInfoBytes))))
        // SANs are required by policy; include entries
        SubjectAlternativeNames(sanEntries)
        // No AIA/CRLDP URIs are included. Revocation/distribution by URL is not intended in this environment.
    }
}

/// Extract SANs from CSR extensionRequest if present
// Unused placeholder (kept for potential future use)
private func extractSansFromCsr(_ csr: CertificateSigningRequest) throws -> [GeneralName] { [] }

/// Build Subject Alternative Names based on the subject CN, normalized to DNS-safe
private func buildDNSSubjectAlternativeNames(from subject: DistinguishedName) -> [GeneralName] {
    guard let cn = extractCommonName(subject) else { return [] }
    let safe = dnsSafeName(cn)
    return [.dnsName(safe)]
}

/// Extract commonName value from a DistinguishedName
private func extractCommonName(_ subject: DistinguishedName) -> String? {
    for rdn in subject { // RelativeDistinguishedName
        for attr in rdn {
            if attr.type == .RDNAttributeType.commonName {
                // Fallback to description rendering of DirectoryString-like value
                return String(describing: attr.value)
            }
        }
    }
    return nil
}

/// Normalize arbitrary input into a DNS-safe label
private func dnsSafeName(_ input: String) -> String {
    let lowered = input.lowercased()
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
    let filtered = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    var result = String(filtered)
    while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return result.isEmpty ? "node" : result
}