import XCTest
@testable import RunarKeys

final class CertificateValidatorTests: XCTestCase {
    func testValidateChain() throws {
        let ca = try CertificateAuthority.createCA(subjectCN: "Runar Test CA")
        var serial = withUnsafeBytes(of: UInt64(2).bigEndian, Array.init)
        while serial.first == 0 && serial.count > 1 { serial.removeFirst() }
        let leaf = try CertificateIssuer.signLeaf(ca: ca, subjectCN: "node-1", sanDNS: ["node-1"], validityDays: 90, serialBytes: serial)
        try CertificateValidator.validateChain(leaf: leaf, ca: ca.certificate, sniHost: "node-1")
    }
}


