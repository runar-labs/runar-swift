@testable import RunarKeys
import XCTest

final class CertificateTests: XCTestCase {
    func testX509CertificateCreation() throws {
        // Test basic X509Certificate creation with real certificate
        let keyPair = try ECDHKeyPair()
        let ca = try CertificateAuthority.create(subject: "CN=Test CA, O=Runar, C=US")

        let certificate = ca.certificate
        XCTAssertFalse(certificate.toDER().isEmpty, "Certificate should have real DER data")
        XCTAssertNotEqual(certificate.subject, "CN=Placeholder")
        XCTAssertNotEqual(certificate.issuer, "CN=Placeholder CA")
    }

    func testCertificateAuthorityCreation() throws {
        // Test CertificateAuthority creation
        let ca = try CertificateAuthority.create(subject: "CN=Test CA, O=Runar, C=US")

        XCTAssertNotNil(ca.certificate)
        XCTAssertNotNil(try? ca.getKeyPair().toECDSAVerifyingKey())
        // Verify the certificate has real data
        let cert = ca.certificate
        XCTAssertFalse(cert.toDER().isEmpty)
    }

    func testCertificateValidatorCreation() throws {
        // Test CertificateValidator creation
        let ca = try CertificateAuthority.create(subject: "CN=Test CA, O=Runar, C=US")
        let validator = CertificateValidator(trustedCaCertificates: [ca.certificate])
        // XCTAssertEqual(validator.trustedCaCertificates.count, 1) // REMOVE THIS LINE
        // Instead, check that validation does not throw
        XCTAssertNoThrow(try validator.validateCertificate(ca.certificate))
    }

    func testCertificateRequestCreation() throws {
        // Test CertificateRequest creation
        let keyPair = try ECDHKeyPair()
        let csrData = try CertificateRequest.create(keyPair: keyPair, subject: "CN=Test Subject, O=Runar, C=US")

        // Verify it creates real CSR data
        XCTAssertFalse(csrData.isEmpty, "CSR should have real data")
    }

    func testCertificateSigning() throws {
        // Test certificate signing workflow
        let ca = try CertificateAuthority.create(subject: "CN=Test CA, O=Runar, C=US")
        let keyPair = try ECDHKeyPair()
        let csrData = try CertificateRequest.create(keyPair: keyPair, subject: "CN=Test Subject, O=Runar, C=US")

        let signedCert = try ca.signCertificateRequest(csrDer: csrData, validityDays: 365)

        XCTAssertNotNil(signedCert)
        XCTAssertFalse(signedCert.toDER().isEmpty, "Signed certificate should have real DER data")
    }
}
