# Runar Secure Enclave Host (macOS)

This is a minimal SwiftUI macOS app you can create in Xcode and drop these files into. It hosts Secure Enclave and Keychain operations with proper entitlements.

## Steps (Xcode)

1. Open the package
   - Run: `open Package.swift` (opens Xcode)

2. Create a macOS App target
   - File → New → Project… → App → macOS
   - Product Name: `RunarSEHost`
   - Interface: SwiftUI, Language: Swift
   - Save inside the `Examples/SEHostAppMac/RunarSEHost` folder or elsewhere

3. Add the package dependency to the app
   - In the Project navigator, select the app project
   - Target `RunarSEHost` → General → Frameworks, Libraries, and Embedded Content → add the `RunarKeys` package product if you plan to call into it

4. Enable signing and entitlements
   - Target `RunarSEHost` → Signing & Capabilities → select your Team
   - Add Capability: Keychain Sharing
   - Ensure `RunarSEHost.entitlements` exists and contains a default keychain-access-group like `$(AppIdentifierPrefix)$(CFBundleIdentifier)`

5. Add the provided source files
   - Add `RunarSEHostApp.swift`, `RunarSEKeyManager.swift`, and `RunarSEHost.entitlements` into the app target

6. Build & run on “My Mac”
   - The button will generate or load a Secure Enclave P256 key and report status

7. Optional: Add a Unit Test target hosted by the app
   - File → New → Target… → macOS → Unit Testing Bundle
   - Ensure the test bundle is added under the same project with the same Team
   - Add tests that call into your `RunarKeys` Secure Enclave APIs

## Notes
- iOS Simulator has no Secure Enclave. Use a real iPhone/iPad for iOS testing.
- Running `swift test` from CLI lacks signing/entitlements, causing Keychain/SE errors.
- You can replicate the CLI tests by invoking your logic through this app or its hosted test bundle.


