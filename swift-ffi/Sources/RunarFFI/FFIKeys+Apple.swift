import Foundation

// MARK: - Apple-Specific Functions Extension

extension KeysFFI {
    
    /// Register Apple device keystore with Keychain integration
    public func registerAppleDeviceKeystore(label: String) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            label.withCString { cLabel in
                rn_keys_register_apple_device_keystore(keysHandle, cLabel, errPtr)
            }
        }
        if let error = error { throw error }
        
        logger.info("Apple device keystore registered with label: \(label)")
    }

    /// Register Linux device keystore with keyring integration
    public func registerLinuxDeviceKeystore(service: String, account: String) throws {
        guard let keysHandle = handle else {
            throw FFIError.invalidHandle("Keys handle not initialized")
        }
        
        let (_, error) = withRnError { errPtr in
            service.withCString { cService in
                account.withCString { cAccount in
                    rn_keys_register_linux_device_keystore(keysHandle, cService, cAccount, errPtr)
                }
            }
        }
        if let error = error { throw error }
        
        logger.info("Linux device keystore registered with service: \(service), account: \(account)")
    }
}
