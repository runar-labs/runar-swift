import CRunarFFI
import Foundation

// MARK: - Apple-Specific Functions Extension

@available(macOS 11.0, *)
extension KeysFFI {
    /// Register Apple device keystore with the given label
    public func registerAppleDeviceKeystore(label: String) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, err) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_register_apple_device_keystore(keysHandle, cLabel, errPtr)
            }
        }
        if let error = err { throw error }
    }

    /// Register Linux device keystore with the given service and account
    public func registerLinuxDeviceKeystore(service: String, account: String) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }

        let (_, err) = withRnError { errPtr in
            service.withCString { cService in
                account.withCString { cAccount in
                    rn_keys_register_linux_device_keystore(keysHandle, cService, cAccount, errPtr)
                }
            }
        }
        if let error = err { throw error }
    }
}
