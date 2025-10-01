import Foundation
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class CACreationTests: XCTestCase {
    func createLogger() -> RunarLogger { RunarLogger.root(component: .custom("CACreationTests")) }

    func testCreateRootCA() async throws {
        let logger = createLogger()
        logger.debug("Testing CA.createRootCA()")

        // Create a self-signed root CA
        let rootCA = try CA.createRootCA(subject: "CN=Test Root CA,O=Test,C=US")
        logger.debug("✅ Root CA created successfully")

        // Get the certificate DER
        let certDER = try await rootCA.getCertificateDER()
        logger.debug("✅ Root CA certificate DER retrieved: \(certDER.count) bytes")
        XCTAssertGreaterThan(certDER.count, 0, "Root CA certificate should not be empty")

        // Get the certificate subject
        let subject = try await rootCA.getCertificateSubject()
        logger.debug("✅ Root CA certificate subject: \(subject)")
        XCTAssertTrue(subject.contains("CN=Test Root CA"), "Subject should contain the expected CN")
        XCTAssertTrue(subject.contains("O=Test"), "Subject should contain the expected O")
        XCTAssertTrue(subject.contains("C=US"), "Subject should contain the expected C")
    }

    func testCreateIssuingCA() async throws {
        let logger = createLogger()
        logger.debug("Testing CA.createIssuingCA()")

        // Create a root CA first
        let rootCA = try CA.createRootCA(subject: "CN=Test Root CA,O=Test,C=US")
        logger.debug("✅ Root CA created")

        // Create an issuing CA signed by the root CA
        let issuingCA = try CA.createIssuingCA(
            rootCA: rootCA,
            subject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            serial: 12345
        )
        logger.debug("✅ Issuing CA created successfully")

        // Get the issuing CA certificate DER
        let issuingCertDER = try await issuingCA.getCertificateDER()
        logger.debug("✅ Issuing CA certificate DER retrieved: \(issuingCertDER.count) bytes")
        XCTAssertGreaterThan(issuingCertDER.count, 0, "Issuing CA certificate should not be empty")

        // Get the issuing CA certificate subject
        let issuingSubject = try await issuingCA.getCertificateSubject()
        logger.debug("✅ Issuing CA certificate subject: \(issuingSubject)")
        XCTAssertTrue(issuingSubject.contains("CN=Test Issuing CA"), "Subject should contain the expected CN")
        XCTAssertTrue(issuingSubject.contains("O=Test"), "Subject should contain the expected O")
        XCTAssertTrue(issuingSubject.contains("C=US"), "Subject should contain the expected C")

        // Verify the certificates are different
        let rootCertDER = try await rootCA.getCertificateDER()
        XCTAssertNotEqual(rootCertDER, issuingCertDER, "Root and issuing CA certificates should be different")
    }

    func testCAErrorHandling() async throws {
        let logger = createLogger()
        logger.debug("Testing CA error handling")

        // Test with empty subject (should fail)
        do {
            _ = try CA.createRootCA(subject: "")
            XCTFail("Should have failed with empty subject")
        } catch {
            logger.debug("✅ Correctly failed with empty subject: \(error)")
        }

        // Test with invalid subject format (should fail)
        do {
            _ = try CA.createRootCA(subject: "Invalid Subject Format")
            XCTFail("Should have failed with invalid subject format")
        } catch {
            logger.debug("✅ Correctly failed with invalid subject format: \(error)")
        }

        // Test with valid subject format
        let rootCA = try CA.createRootCA(subject: "CN=Valid Test CA,O=Test,C=US")
        logger.debug("✅ CA created with valid subject format")

        let subject = try await rootCA.getCertificateSubject()
        logger.debug("✅ Subject from valid format: \(subject)")
        XCTAssertTrue(subject.contains("CN=Valid Test CA"), "Subject should contain the expected CN")
    }

    func testCAMemoryManagement() async throws {
        let logger = createLogger()
        logger.debug("Testing CA memory management")

        // Create multiple CAs to test memory management
        var rootCAs: [CA] = []
        var issuingCAs: [CA] = []

        for i in 0 ..< 5 {
            let rootCA = try CA.createRootCA(subject: "CN=Test Root CA \(i),O=Test,C=US")
            rootCAs.append(rootCA)

            let issuingCA = try CA.createIssuingCA(
                rootCA: rootCA,
                subject: "CN=Test Issuing CA \(i),O=Test,C=US",
                validityDays: 365,
                serial: UInt64(i + 1)
            )
            issuingCAs.append(issuingCA)
        }

        logger.debug("✅ Created \(rootCAs.count) root CAs and \(issuingCAs.count) issuing CAs")

        // Verify all certificates are retrievable
        for (index, rootCA) in rootCAs.enumerated() {
            let certDER = try await rootCA.getCertificateDER()
            XCTAssertGreaterThan(certDER.count, 0, "Root CA \(index) certificate should not be empty")
        }

        for (index, issuingCA) in issuingCAs.enumerated() {
            let certDER = try await issuingCA.getCertificateDER()
            XCTAssertGreaterThan(certDER.count, 0, "Issuing CA \(index) certificate should not be empty")
        }

        logger.debug("✅ All CA certificates retrieved successfully")

        // CAs will be automatically deallocated when they go out of scope
        // This tests that the deinit properly calls rn_keys_ca_free
    }
}
