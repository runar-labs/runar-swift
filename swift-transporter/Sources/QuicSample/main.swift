import CryptoKit
import Foundation
import Network
import RunarKeys
import Security
import SwiftCommon

@main
struct QuicSampleApp {
    static func main() async {
        do {
            let requireClientAuth = false
            var clientConnection: NWConnection?

            // CA and two nodes
            let km = RunarKeys.MobileKeyManager()
            let ca = try km.createCA(subjectCN: "Runar Test CA")

            let nodeSecS = try km.generateNodeIdentity(label: "server-\(UUID().uuidString)")
            let nodePubS = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecS)
            let nodeIdS = RunarKeys.Ids.compactId(nodePubS)
            let csrS = try km.buildCSR(signingKey: nodeSecS, subjectCN: nodeIdS, nodeIdSAN: nodeIdS)
            let certS = try km.issueLeaf(from: ca, csrDER: csrS, subjectOverrideCN: nodeIdS, sanDNS: [nodeIdS], validityDays: 180)

            let nodeSecC = try km.generateNodeIdentity(label: "client-\(UUID().uuidString)")
            let nodePubC = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: nodeSecC)
            let nodeIdC = RunarKeys.Ids.compactId(nodePubC)
            let csrC = try km.buildCSR(signingKey: nodeSecC, subjectCN: nodeIdC, nodeIdSAN: nodeIdC)
            let certC = try km.issueLeaf(from: ca, csrDER: csrC, subjectOverrideCN: nodeIdC, sanDNS: [nodeIdC], validityDays: 180)

            // Expected DERs for comparison in verify blocks
            let expectedServerLeafDER = RunarKeys.CertificateUtils.toDER(certS)
            let expectedClientLeafDER = RunarKeys.CertificateUtils.toDER(certC)
            let expectedCaDER = RunarKeys.CertificateUtils.toDER(ca.generated.certificate)

            // Note: CA export/Keychain experiments removed to avoid confusion

            func makeSecCert(_ data: Data) throws -> SecCertificate {
                guard let c = SecCertificateCreateWithData(nil, data as CFData) else {
                    throw NSError(domain: "cert", code: -1)
                }
                return c
            }

            func findIdentity(for leafDER: Data) throws -> SecIdentity {
                // Find the certificate item in Keychain by exact DER match
                let certQuery: [String: Any] = [
                    kSecClass as String: kSecClassCertificate,
                    kSecReturnRef as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]
                var certsOut: CFTypeRef?
                let cs = SecItemCopyMatching(certQuery as CFDictionary, &certsOut)
                guard cs == errSecSuccess, let certArray = certsOut as? [SecCertificate] else {
                    throw NSError(domain: "identity", code: -22)
                }
                var matchedCert: SecCertificate?
                for c in certArray {
                    let der = SecCertificateCopyData(c) as Data
                    if der == leafDER { matchedCert = c; break }
                }
                guard let foundCert = matchedCert else { throw NSError(domain: "identity", code: -23) }
                var identity: SecIdentity?
                let ist = SecIdentityCreateWithCertificate(nil, foundCert, &identity)
                guard ist == errSecSuccess, let id = identity else { throw NSError(domain: "identity", code: Int(ist)) }
                return id
            }

            func makeIdentity(from certificateDER: Data) throws -> SecIdentity {
                let secCert = try makeSecCert(certificateDER)
                var identity: SecIdentity?
                let status = SecIdentityCreateWithCertificate(nil, secCert, &identity)
                guard status == errSecSuccess, let id = identity else {
                    throw NSError(domain: "identity", code: Int(status))
                }
                return id
            }

            func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

            // No system trust modification; verify-block handles trust locally

            func buildListenerParams() throws -> NWParameters {
                let quic = NWProtocolQUIC.Options()
                // ALPN private
                "runar".utf8CString.withUnsafeBufferPointer { buf in
                    if let base = buf.baseAddress { sec_protocol_options_add_tls_application_protocol(quic.securityProtocolOptions, base) }
                }
                let sec = quic.securityProtocolOptions
                sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
                sec_protocol_options_set_peer_authentication_required(sec, requireClientAuth)
                let caSec = try makeSecCert(RunarKeys.CertificateUtils.toDER(ca.generated.certificate))
                sec_protocol_options_set_verify_block(sec, { (_: sec_protocol_metadata_t, trust: sec_trust_t, complete: @escaping sec_protocol_verify_complete_t) in
                    let nwTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    let chainArr = SecTrustCopyCertificateChain(nwTrust) as? [SecCertificate] ?? []
                    let policy = SecPolicyCreateSSL(false, nil)
                    _ = SecTrustSetPolicies(nwTrust, policy)
                    let anchors = [caSec] as CFArray
                    _ = SecTrustSetAnchorCertificates(nwTrust, anchors)
                    _ = SecTrustSetAnchorCertificatesOnly(nwTrust, true)
                    var err: CFError?
                    let ok = SecTrustEvaluateWithError(nwTrust, &err)
                    print("[S] trust=", ok, " err=", String(describing: err))
                    // Uncomment below to enable fallback CA pin in the sample if needed
                    // if !ok {
                    //     let caDER = SecCertificateCopyData(caSec) as Data
                    //     let hasCA = chainArr.contains { SecCertificateCopyData($0) as Data == caDER }
                    //     print("[S] fallback CA pin=", hasCA)
                    //     complete(hasCA)
                    //     return
                    // }
                    complete(ok)
                }, DispatchQueue.global())
                let identity = try findIdentity(for: expectedServerLeafDER)
                var certOut: SecCertificate?
                SecIdentityCopyCertificate(identity, &certOut)
                if let cert = certOut {
                    let subj = SecCertificateCopySubjectSummary(cert) as String? ?? "nil"
                    print("[S] using identity subject=", subj)
                } else {
                    print("[S] using identity subject= nil")
                }
                sec_protocol_options_set_local_identity(sec, sec_identity_create(identity)!)
                let params = NWParameters(quic: quic)
                params.requiredInterfaceType = .loopback
                params.includePeerToPeer = false
                params.allowLocalEndpointReuse = true
                return params
            }

            func buildClientParams() throws -> NWParameters {
                let quic = NWProtocolQUIC.Options()
                // ALPN private
                "runar".utf8CString.withUnsafeBufferPointer { buf in
                    if let base = buf.baseAddress { sec_protocol_options_add_tls_application_protocol(quic.securityProtocolOptions, base) }
                }
                let sec = quic.securityProtocolOptions
                sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
                sec_protocol_options_set_peer_authentication_required(sec, true)
                "localhost".utf8CString.withUnsafeBufferPointer { buf in
                    if let base = buf.baseAddress { sec_protocol_options_set_tls_server_name(sec, base) }
                }
                let caSec = try makeSecCert(expectedCaDER)
                sec_protocol_options_set_verify_block(sec, { (_: sec_protocol_metadata_t, trust: sec_trust_t, complete: @escaping sec_protocol_verify_complete_t) in
                    let nwTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    let chainArr = SecTrustCopyCertificateChain(nwTrust) as? [SecCertificate] ?? []
                    let policy = SecPolicyCreateSSL(true, "localhost" as CFString)
                    _ = SecTrustSetPolicies(nwTrust, policy)
                    let anchors = [caSec] as CFArray
                    _ = SecTrustSetAnchorCertificates(nwTrust, anchors)
                    _ = SecTrustSetAnchorCertificatesOnly(nwTrust, true)
                    var err: CFError?
                    let ok = SecTrustEvaluateWithError(nwTrust, &err)
                    print("[C] trust=", ok, " err=", String(describing: err))
                    // Uncomment below to enable fallback CA pin in the sample if needed
                    // if !ok {
                    //     let caDER = SecCertificateCopyData(caSec) as Data
                    //     let hasCA = chainArr.contains { SecCertificateCopyData($0) as Data == caDER }
                    //     let leafOk: Bool = {
                    //         guard let leaf = chainArr.first else { return false }
                    //         return (SecCertificateCopyData(leaf) as Data) == expectedServerLeafDER
                    //     }()
                    //     print("[C] fallback CA pin=", hasCA, " leaf match=", leafOk)
                    //     complete(hasCA && leafOk)
                    //     return
                    // }
                    complete(ok)
                }, DispatchQueue.global())
                let identity = try findIdentity(for: expectedClientLeafDER)
                var certOut: SecCertificate?
                SecIdentityCopyCertificate(identity, &certOut)
                if let cert = certOut {
                    let subj = SecCertificateCopySubjectSummary(cert) as String? ?? "nil"
                    print("[C] using identity subject=", subj)
                } else {
                    print("[C] using identity subject= nil")
                }
                sec_protocol_options_set_local_identity(sec, sec_identity_create(identity)!)
                let params = NWParameters(quic: quic)
                params.requiredInterfaceType = .loopback
                params.includePeerToPeer = false
                params.allowLocalEndpointReuse = true
                return params
            }

            let listener = try NWListener(using: buildListenerParams())
            listener.stateUpdateHandler = { state in print("[S] state=", state) }
            listener.newConnectionHandler = { conn in
                print("[S] new conn")
                conn.stateUpdateHandler = { state in print("[S] conn state=", state) }
                conn.start(queue: .global())
                // Proactively send a byte to kick TLS from server side as well
                let ctx = NWConnection.ContentContext.defaultMessage
                for i in 0 ..< 5 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50 * i)) {
                        conn.send(content: Data([0xA5]), contentContext: ctx, isComplete: true, completion: .contentProcessed { err in
                            print("[S] kick send #\(i) err=", String(describing: err))
                        })
                    }
                }
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, err in
                    print("[S] recv data=", data?.count as Any, "err=", String(describing: err))
                }
            }
            listener.start(queue: .global())
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let port = listener.port else { throw NSError(domain: "listen", code: -5) }

            let conn = try NWConnection(host: "localhost", port: port, using: buildClientParams())
            clientConnection = conn
            conn.stateUpdateHandler = { state in print("[C] state=", state) }
            conn.start(queue: .global())
            // Send immediately to trigger handshake
            let ctx = NWConnection.ContentContext.defaultMessage
            for i in 0 ..< 5 {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50 * i)) {
                    conn.send(content: Data([0x01, 0x02]), contentContext: ctx, isComplete: true, completion: .contentProcessed { err in
                        print("[C] send #\(i) err=", String(describing: err))
                    })
                }
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, err in
                print("[C] recv data=", data?.count as Any, "err=", String(describing: err))
            }

            try? await Task.sleep(nanoseconds: 10_000_000_000)
        } catch {
            print("Sample error:", error)
        }
    }
}
