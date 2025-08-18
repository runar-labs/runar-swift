import Foundation
import CRunarFFI

public struct FFIError: Error, CustomStringConvertible {
	public let code: Int32
	public let message: String

	public var description: String { "FFIError(\(code)): \(message)" }
}

@inline(__always)
func withRnError<T>(_ body: (UnsafeMutablePointer<RNAPIRnError>) -> T) -> (T, FFIError?) {
	var err = RNAPIRnError(code: 0, message: nil)
	let result = withUnsafeMutablePointer(to: &err) { ptr in
		body(ptr)
	}
	if err.code != 0 {
		let msg = err.message.map { String(cString: $0) } ?? "Unknown error"
		if let cstr = err.message { rn_string_free(cstr) }
		return (result, FFIError(code: err.code, message: msg))
	}
	return (result, nil)
}


