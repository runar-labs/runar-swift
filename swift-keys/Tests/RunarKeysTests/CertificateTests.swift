import XCTest
import X509
@testable import RunarKeys

final class CertificateTests: XCTestCase {
    func testCreateCAAndLeaf() throws {
        let ca = try CertificateAuthority.createCA(subjectCN: "Runar Test CA")
        XCTAssertTrue(ca.certificate.subject.description.contains("Runar Test CA"))

        // Serial: big-endian of UInt64
        var serial = withUnsafeBytes(of: UInt64(1).bigEndian, Array.init)
        while serial.first == 0 && serial.count > 1 { serial.removeFirst() }

        let leaf = try CertificateIssuer.signLeaf(
            ca: ca,
            subjectCN: "node-1",
            sanDNS: ["node-1"],
            validityDays: 90,
            serialBytes: serial
        )
        XCTAssertTrue(leaf.subject.description.contains("node-1"))
        XCTAssertLessThan(leaf.notValidBefore, leaf.notValidAfter)
    }
}


