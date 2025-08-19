import Foundation
import CRunarFFI
import Darwin

public final class FFIKeys {
	var handle: UnsafeMutableRawPointer?

	public init() throws {
		var out: UnsafeMutableRawPointer?
		let (_, err) = withRnError { errPtr in
			rn_keys_new(&out, errPtr)
		}
		if let e = err { throw e }
		self.handle = out
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
			let msg = String(cString: buf)
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
			let msg = String(cString: buf)
			throw FFIError(code: rc, message: msg.isEmpty ? "rn_keys_set_local_node_info failed: rc=\(rc)" : msg)
		}
	}

    // Removed: per-call label resolver. Mapping-only API is used instead.

	public func nodeId() throws -> String {
		guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
		var cstr: UnsafeMutablePointer<CChar>?
		var len: Int = 0
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
		var len: Int = 0
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
		var len: Int = 0
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
		var outLen: Int = 0
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

	public func exportState() throws -> Data {
		guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
		var buf: UnsafeMutablePointer<UInt8>?
		var len: Int = 0
		let (_, err) = withRnError { errPtr in
			rn_keys_node_export_state(h, &buf, &len, errPtr)
		}
		if let e = err { throw e }
		guard let b = buf else { return Data() }
		let data = Data(bytes: b, count: len)
		rn_free(b, len)
		return data
	}

	public func importState(_ stateCBOR: Data) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
		let (_, err) = withRnError { errPtr in
			stateCBOR.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_keys_node_import_state(h, p, stateCBOR.count, errPtr)
			}
		}
		if let e = err { throw e }
	}

	public func mobileExportState() throws -> Data {
		guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
		var buf: UnsafeMutablePointer<UInt8>?
		var len: Int = 0
		let (_, err) = withRnError { errPtr in
			rn_keys_mobile_export_state(h, &buf, &len, errPtr)
		}
		if let e = err { throw e }
		guard let b = buf else { return Data() }
		let data = Data(bytes: b, count: len)
		rn_free(b, len)
		return data
	}

	public func mobileImportState(_ stateCBOR: Data) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "keys freed") }
		let (_, err) = withRnError { errPtr in
			stateCBOR.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_keys_mobile_import_state(h, p, stateCBOR.count, errPtr)
			}
		}
		if let e = err { throw e }
	}
}

