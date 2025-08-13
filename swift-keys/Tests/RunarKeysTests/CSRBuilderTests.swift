import XCTest
@testable import RunarKeys

final class CSRBuilderTests: XCTestCase {
    func testBuildCSRAndParse() throws {
        let label = "com.runar.keys.test.identity.\(UUID().uuidString)"
        let key: SecKey
        do { key = try NodeIdentitySigning.generateOrLoad(label: label) } catch { throw XCTSkip("SE unavailable: \(error)") }
        let cn = "node-csr-test"
        let der = try CSRBuilder.buildCSR(subjectCN: cn, signingKey: key)
        let parsed = try CertificationRequest(derEncoded: Array(der))
        XCTAssertTrue(parsed.certificationRequestInfo.subject.description.contains("CN=\(cn)"))
    }
}


