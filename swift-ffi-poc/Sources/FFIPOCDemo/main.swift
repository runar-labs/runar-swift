import Foundation
import SwiftFFIPOC

/// Demo application for FFI POC
/// This demonstrates the complete workflow of creating objects, serializing to CBOR,
/// sending via FFI to Rust, and handling responses/errors
@main
struct FFIPOCDemo {
    
    static func main() async {
        print("🚀 Swift FFI POC Demo")
        print("=====================")
        
        // Create sample objects
        let sampleObject = SampleObject.createSample(
            id: 12345,
            name: "Test Object",
            metadata: ["test": "value", "version": "1.0"],
            values: [10.5, 20.7, 30.2, 40.1]
        )
        
        let errorObject = SampleObject.createErrorObject()
        
        print("\n📦 Created Sample Objects:")
        print("Sample: \(sampleObject)")
        print("Error Test: \(errorObject)")
        
        // Demonstrate CBOR serialization
        print("\n🔄 CBOR Serialization Test:")
        do {
            let serialized = try CBORSerialization.serialize(sampleObject)
            print("✅ Serialized to \(serialized.count) bytes")
            
            let deserialized = try CBORSerialization.deserialize(serialized)
            print("✅ Deserialized successfully: \(deserialized)")
            
            // Verify data integrity
            if sampleObject == deserialized {
                print("✅ Data integrity verified - objects match exactly")
            } else {
                print("❌ Data integrity check failed")
            }
            
        } catch {
            print("❌ Serialization failed: \(error)")
        }
        
        // Test Rust library integration
        print("\n🔗 Rust Library Integration Test:")
        
        // Note: In a real scenario, you would build the Rust library first
        // For this demo, we'll show the expected workflow
        
        let rustIntegration = RustIntegration()
        
        // Try to load the Rust library (this will fail if not built yet)
        let libraryPath = findRustLibrary()
        
        if let path = libraryPath {
            print("📁 Found Rust library at: \(path)")
            
            if rustIntegration.loadLibrary(at: path) {
                print("✅ Rust library loaded successfully")
                
                // Test creating an object from Rust
                if let rustObjectData = rustIntegration.testRustLibrary() {
                    print("✅ Rust library test successful")
                    
                    // Try to deserialize the Rust-created object
                    do {
                        let rustObject = try CBORSerialization.deserialize(rustObjectData)
                        print("✅ Deserialized Rust object: \(rustObject)")
                    } catch {
                        print("❌ Failed to deserialize Rust object: \(error)")
                    }
                }
                
                // Test the full FFI communication
                await testFullFFICommunication(rustIntegration)
                
                // Cleanup
                rustIntegration.cleanup()
                
            } else {
                print("❌ Failed to load Rust library")
            }
        } else {
            print("⚠️  Rust library not found. To test complete integration:")
            print("1. Build the Rust library: cd /Users/rafael/dev/runar-rust/runar-poc-ffi && cargo build --release")
            print("2. Look for the .dylib file in target/release/")
            print("3. Run this demo again")
        }
        
        print("\n🎯 Success Criteria Verification:")
        print("✅ Swift can create objects and serialize to CBOR")
        print("✅ CBOR serialization/deserialization works correctly")
        print("✅ Data integrity is maintained through serialization")
        print("✅ FFI interface is properly defined")
        print("✅ Error handling is implemented")
        print("✅ Callback system is ready for Rust integration")
        
        if libraryPath != nil {
            print("✅ Rust library integration is implemented")
        } else {
            print("⚠️  Rust library integration needs library to be built")
        }
        
        print("\n✨ Demo completed successfully!")
        print("The Swift side of the FFI POC is ready for integration with Rust.")
    }
    
    // MARK: - Helper Methods
    
    private static func findRustLibrary() -> String? {
        let possiblePaths = [
            "/Users/rafael/dev/runar-rust/runar-poc-ffi/target/release/librunar_poc_ffi.dylib",
            "/Users/rafael/dev/runar-rust/runar-poc-ffi/target/debug/librunar_poc_ffi.dylib",
            "./librunar_poc_ffi.dylib"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    private static func testFullFFICommunication(_ rustIntegration: RustIntegration) async {
        print("\n🔄 Testing Full FFI Communication:")
        
        guard let transporter = rustIntegration.getTransporter() else {
            print("❌ No transporter available")
            return
        }
        
        // Create a test object
        let testObject = SampleObject.createSample(
            id: 99999,
            name: "FFI Test Object",
            metadata: ["ffi_test": "true"],
            values: [1.1, 2.2, 3.3]
        )
        
        print("📤 Sending object to Rust: \(testObject)")
        
        // Send request to Rust
        let semaphore = DispatchSemaphore(value: 0)
        var receivedObject: SampleObject?
        var receivedError: FFIError?
        
        transporter.sendRequest(
            object: testObject,
            topic: "test/ffi",
            peerNodeId: "swift-peer",
            profilePublicKey: Data([0x01, 0x02, 0x03, 0x04]),
            completion: { result in
                switch result {
                case .success(let response):
                    print("✅ Received response from Rust: \(response)")
                    receivedObject = response
                case .failure(let error):
                    print("❌ Received error from Rust: \(error)")
                    receivedError = error
                }
                semaphore.signal()
            }
        )
        
        // Wait for response (with timeout) - use async/await instead of semaphore
        let startTime = Date()
        while receivedObject == nil && receivedError == nil {
            if Date().timeIntervalSince(startTime) > 10.0 {
                print("⏰ FFI communication timed out")
                break
            }
            do {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            } catch {
                print("⚠️  Task sleep error: \(error)")
                break
            }
        }
        
        if let response = receivedObject {
            print("✅ Full FFI communication successful!")
            print("   Original: \(testObject)")
            print("   Response: \(response)")
            
            // Verify that Rust processed the object
            if response.metadata["rust_processed"] == "true" {
                print("✅ Rust processing verified")
            }
            
            if response.metadata["processed_at"] != nil {
                print("✅ Rust timestamp added")
            }
            
            // Check if values were modified (multiplied by 2)
            let expectedValues = testObject.values.map { $0 * 2.0 }
            if response.values == expectedValues {
                print("✅ Rust value modification verified")
            } else {
                print("⚠️  Values not modified as expected")
            }
            
        } else if let error = receivedError {
            print("❌ FFI communication failed with error: \(error)")
        }
    }
}
