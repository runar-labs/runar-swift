import Foundation
import CRunarFFI

// MARK: - Apple-Specific Functions Extension

@available(macOS 11.0, *)
extension KeysFFI {
    // Note: Device keystore registration functions are not available in the current Rust FFI
    // These will be implemented when the corresponding Rust FFI functions are added
}
