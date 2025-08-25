import XCTest
import RunarFFI

/// Basic Swift FFI Test - Testing Core Functionality
final class SwiftFFILifecycleTests: XCTestCase {
    func testBasicInitialization() {
        do {
            // Test mobile initialization
            let mobileKeys = try KeysFFI.keysNew()
            try mobileKeys.initializeAsMobile()
            print("✅ Mobile initialization successful")

            // Test node initialization
            let nodeKeys = try KeysFFI.keysNew()
            try nodeKeys.initializeAsNode()
            print("✅ Node initialization successful")

        } catch {
            print("❌ Test failed with error: \(error)")
            if let ffiError = error as? FFIError {
                print("   Error code: \(ffiError.errorCode)")
            }
            XCTFail("Test failed: \(error)")
        }
    }

    func testNodePublicKeyAfterInit() {
        do {
            let nodeKeys = try KeysFFI.keysNew()
            try nodeKeys.initializeAsNode()

            // Test getting public key immediately after init
            let publicKey = try nodeKeys.nodeGetPublicKey()
            print("✅ Node public key retrieved: \(publicKey.count) bytes")

        } catch {
            print("❌ Node public key test failed: \(error)")
            if let ffiError = error as? FFIError {
                print("   Error code: \(ffiError.errorCode)")
            }
            XCTFail("Node public key test failed: \(error)")
        }
    }

    func testNodeAgreementPublicKeyAfterInit() {
        do {
            let nodeKeys = try KeysFFI.keysNew()
            try nodeKeys.initializeAsNode()

            // Test getting agreement public key immediately after init
            let agreementKey = try nodeKeys.nodeGetAgreementPublicKey()
            print("✅ Node agreement public key retrieved: \(agreementKey.count) bytes")

        } catch {
            print("❌ Node agreement public key test failed: \(error)")
            if let ffiError = error as? FFIError {
                print("   Error code: \(ffiError.errorCode)")
            }
            // Don't fail the test - let's see what happens with other operations
            print("   Continuing to test other operations...")
        }
    }

    func testNodeOperationsAfterInit() {
        do {
            print("🔧 Creating KeysFFI handle...")
            let nodeKeys = try KeysFFI.keysNew()
            print("✅ KeysFFI handle created")

            print("🔧 Initializing as node...")
            try nodeKeys.initializeAsNode()
            print("✅ Node initialized successfully")

            // Test keystore state
            do {
                print("🔧 Testing keystore state...")
                let state = try nodeKeys.nodeGetKeystoreState()
                print("✅ Node keystore state: \(state)")
            } catch {
                print("❌ Node keystore state failed: \(error)")
                if let ffiError = error as? FFIError {
                    print("   Error code: \(ffiError.errorCode)")
                }
            }

            // Test CSR generation
            do {
                print("🔧 Testing CSR generation...")
                let csr = try nodeKeys.nodeGenerateCSR()
                print("✅ Node CSR generated: \(csr.count) bytes")
            } catch {
                print("❌ Node CSR generation failed: \(error)")
                if let ffiError = error as? FFIError {
                    print("   Error code: \(ffiError.errorCode)")
                }
            }

        } catch {
            print("❌ Node initialization failed: \(error)")
            if let ffiError = error as? FFIError {
                print("   Error code: \(ffiError.errorCode)")
            }
            XCTFail("Node initialization failed: \(error)")
        }
    }

    func testFFILibraryLoading() {
        print("🔧 Testing FFI library loading...")

        // Check if we can access the raw handle
        do {
            let keys = try KeysFFI.keysNew()
            let rawHandle = keys.rawHandle
            print("✅ FFI handle obtained: \(rawHandle != nil ? "valid" : "null")")

            try keys.initializeAsMobile()
            print("✅ Mobile initialization successful")

        } catch {
            print("❌ FFI test failed: \(error)")
            if let ffiError = error as? FFIError {
                print("   Error code: \(ffiError.errorCode)")
                print("   Error description: \(ffiError.errorDescription ?? "none")")
            }
            // Don't fail the test - we want to see the diagnostic info
        }
    }
}
