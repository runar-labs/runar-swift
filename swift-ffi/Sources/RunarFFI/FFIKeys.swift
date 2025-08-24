import CRunarFFI
import Darwin
import Foundation

public final class FFIKeys {
    var handle: UnsafeMutableRawPointer?

    public init() throws {
        var out: UnsafeMutableRawPointer?
        let (_, err) = withRnError { errPtr in
            rn_keys_new(&out, errPtr)
        }
        if let e = err { throw e }
        handle = out
    }

    deinit {
        if let h = handle { rn_keys_free(h) }
    }

    @inline(__always)
    func withHandle<T>(_ body: (UnsafeMutableRawPointer) -> T) throws -> T {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        return body(h)
    }

    // MARK: - Mapping-based resolver and NodeInfo (push APIs)

    // Mapping-based API: pass CBOR map<String, LabelKeyInfo>
    public func setLabelMapping(_ mappingCBOR: Data) throws {
        let rc: Int32 = try withHandle { h in
            mappingCBOR.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                return rn_keys_set_label_mapping(h, p, mappingCBOR.count)
            }
        }
        if rc != 0 {
            var buf = [CChar](repeating: 0, count: 1024)
            _ = buf.withUnsafeMutableBufferPointer { bp in rn_last_error(bp.baseAddress, bp.count) }
            let msg = String(cString: buf, encoding: .utf8) ?? "Unknown error"
            throw FFIError(code: rc, message: msg.isEmpty ? "rn_keys_set_label_mapping failed: rc=\(rc)" : msg)
        }
    }

    // Push current Local NodeInfo as CBOR into the holder on the Rust side
    public func setLocalNodeInfo(_ nodeInfoCBOR: Data) throws {
        let rc: Int32 = try withHandle { h in
            nodeInfoCBOR.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                return rn_keys_set_local_node_info(h, p, nodeInfoCBOR.count)
            }
        }
        if rc != 0 {
            var buf = [CChar](repeating: 0, count: 1024)
            _ = buf.withUnsafeMutableBufferPointer { bp in rn_last_error(bp.baseAddress, bp.count) }
            let msg = String(cString: buf, encoding: .utf8) ?? "Unknown error"
            throw FFIError(code: rc, message: msg.isEmpty ? "rn_keys_set_local_node_info failed: rc=\(rc)" : msg)
        }
    }

    // Removed: per-call label resolver. Mapping-only API is used instead.

    public func nodeId() throws -> String {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var cstr: UnsafeMutablePointer<CChar>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_node_id(h, &cstr, &len, errPtr)
        }
        if let e = err { throw e }
        defer { if let s = cstr { rn_string_free(s) } }
        return cstr.map { String(cString: $0) } ?? ""
    }

    public func publicKey() throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_public_key(h, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }

    public func generateCSR() throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_generate_csr(h, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }

    public func processSetupToken(_ setupTokenCBOR: Data) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            setupTokenCBOR.withUnsafeBytes { rawBuf in
                let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_keys_mobile_process_setup_token(h, p, setupTokenCBOR.count, &out, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let b = out else { return Data() }
        let data = Data(bytes: b, count: outLen)
        rn_free(b, outLen)
        return data
    }

    public func installCertificate(_ nodeCertificateMessageCBOR: Data) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            nodeCertificateMessageCBOR.withUnsafeBytes { rawBuf in
                let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_keys_node_install_certificate(h, p, nodeCertificateMessageCBOR.count, errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func mobileInitializeUserRootKey() throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_initialize_user_root_key(h, errPtr)
        }
        if let e = err { throw e }
    }

    public func registerAppleDeviceKeystore(label: String) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_register_apple_device_keystore(h, cLabel, errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func setPersistenceDir(_ dir: String) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            dir.withCString { cDir in
                rn_keys_set_persistence_dir(h, cDir, errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func enableAutoPersist(_ enabled: Bool) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            rn_keys_enable_auto_persist(h, enabled, errPtr)
        }
        if let e = err { throw e }
    }

    public func wipePersistence() throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            rn_keys_wipe_persistence(h, errPtr)
        }
        if let e = err { throw e }
    }

    public func flushState() throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            rn_keys_flush_state(h, errPtr)
        }
        if let e = err { throw e }
    }

    public func nodeGetKeystoreState() throws -> Int32 {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var state: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_keystore_state(h, &state, errPtr)
        }
        if let e = err { throw e }
        return state
    }

    public func mobileGetKeystoreState() throws -> Int32 {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var state: Int32 = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_get_keystore_state(h, &state, errPtr)
        }
        if let e = err { throw e }
        return state
    }

    public func mobileGenerateNetworkDataKey() throws -> String {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var nidCStr: UnsafeMutablePointer<CChar>?
        var nidLen = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_mobile_generate_network_data_key(h, &nidCStr, &nidLen, errPtr)
        }
        if let e = err { throw e }
        defer { if let c = nidCStr { rn_string_free(c) } }
        return nidCStr.map { String(cString: $0) } ?? ""
    }

    public func mobileInstallNetworkPublicKey(_ publicKey: Data) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            publicKey.withUnsafeBytes { raw in
                rn_keys_mobile_install_network_public_key(h,
                                                          raw.bindMemory(to: UInt8.self).baseAddress,
                                                          publicKey.count,
                                                          errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func mobileGetNetworkPublicKey(_ networkId: String) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            networkId.withCString { cNid in
                rn_keys_mobile_get_network_public_key(h, cNid, &out, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return data
    }

    public func encryptForNetwork(_ data: Data, networkId: String) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { raw in
                networkId.withCString { cNid in
                    rn_keys_encrypt_for_network(h,
                                                raw.bindMemory(to: UInt8.self).baseAddress,
                                                data.count,
                                                cNid,
                                                &out,
                                                &outLen,
                                                errPtr)
                }
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let cbor = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return cbor
    }

    public func decryptNetworkData(_ eedCBOR: Data) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            eedCBOR.withUnsafeBytes { raw in
                rn_keys_decrypt_network_data(h,
                                             raw.bindMemory(to: UInt8.self).baseAddress,
                                             eedCBOR.count,
                                             &out,
                                             &outLen,
                                             errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let data = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return data
    }

    public func mobileCreateNetworkKeyMessage(networkId: String, nodeAgreementPk: Data) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var outCbor: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            networkId.withCString { nidC in
                nodeAgreementPk.withUnsafeBytes { pkRaw in
                    let pkPtr = pkRaw.bindMemory(to: UInt8.self).baseAddress
                    rn_keys_mobile_create_network_key_message(h, nidC, pkPtr, nodeAgreementPk.count, &outCbor, &outLen, errPtr)
                }
            }
        }
        if let e = err { throw e }
        guard let b = outCbor else { return Data() }
        let data = Data(bytes: b, count: outLen)
        rn_free(b, outLen)
        return data
    }

    public func nodeInstallNetworkKey(_ nkmCbor: Data) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        let (_, err) = withRnError { errPtr in
            nkmCbor.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt8.self).baseAddress
                rn_keys_node_install_network_key(h, p, nkmCbor.count, errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func mobileDeriveUserProfileKey(label: String) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var outPk: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_mobile_derive_user_profile_key(h, cLabel, &outPk, &outLen, errPtr)
            }
        }
        if let e = err { throw e }
        guard let b = outPk else { return Data() }
        let data = Data(bytes: b, count: outLen)
        rn_free(b, outLen)
        return data
    }

    public func encryptLocalData(_ data: Data) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            data.withUnsafeBytes { raw in
                rn_keys_encrypt_local_data(h,
                                           raw.bindMemory(to: UInt8.self).baseAddress,
                                           data.count,
                                           &out,
                                           &outLen,
                                           errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let cipher = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return cipher
    }

    public func decryptLocalData(_ encrypted: Data) throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let (_, err) = withRnError { errPtr in
            encrypted.withUnsafeBytes { raw in
                rn_keys_decrypt_local_data(h,
                                           raw.bindMemory(to: UInt8.self).baseAddress,
                                           encrypted.count,
                                           &out,
                                           &outLen,
                                           errPtr)
            }
        }
        if let e = err { throw e }
        guard let p = out else { return Data() }
        let plain = Data(bytes: p, count: outLen)
        rn_free(p, outLen)
        return plain
    }

    /// Get the node agreement public key directly from the keystore
    /// This replaces the problematic extractAgreementPk(fromSetupTokenCBOR:) method
    public func getAgreementPublicKey() throws -> Data {
        guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { errPtr in
            rn_keys_node_get_agreement_public_key(h, &buf, &len, errPtr)
        }
        if let e = err { throw e }
        guard let b = buf else { return Data() }
        let data = Data(bytes: b, count: len)
        rn_free(b, len)
        return data
    }
}
