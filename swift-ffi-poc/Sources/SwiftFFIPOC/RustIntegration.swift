import Foundation

/// Rust library integration for FFI POC
/// This module demonstrates how to load the Rust dynamic library
/// and integrate with the FFI functions
public class RustIntegration {
    
    // MARK: - Properties
    
    private var libraryHandle: UnsafeMutableRawPointer?
    private var transporter: FFITransporter?
    
    // MARK: - Initialization
    
    /// Initialize the Rust integration
    public init() {}
    
    /// Load the Rust dynamic library
    /// - Parameter libraryPath: Path to the Rust dynamic library
    /// - Returns: True if library loaded successfully
    public func loadLibrary(at libraryPath: String) -> Bool {
        // Close any existing library
        closeLibrary()
        
        // Load the library
        libraryHandle = dlopen(libraryPath, RTLD_NOW)
        
        guard libraryHandle != nil else {
            print("❌ Failed to load library at: \(libraryPath)")
            return false
        }
        
        print("✅ Successfully loaded Rust library")
        
        // Initialize the transporter
        return initializeTransporter()
    }
    
    /// Close the loaded library
    public func closeLibrary() {
        if let handle = libraryHandle {
            dlclose(handle)
            libraryHandle = nil
            transporter = nil
            print("🔒 Rust library closed")
        }
    }
    
    // MARK: - Transporter Initialization
    
    private func initializeTransporter() -> Bool {
        guard let handle = libraryHandle else { return false }
        
        // Get function pointers
        guard let initFunc = dlsym(handle, "transporter_init") else {
            print("❌ Failed to get transporter_init function")
            return false
        }
        
        guard let requestFunc = dlsym(handle, "transporter_request") else {
            print("❌ Failed to get transporter_request function")
            return false
        }
        
        // Initialize the transporter
        let initResult = unsafeBitCast(initFunc, to: (@convention(c) () -> Int32).self)()
        
        guard initResult == 0 else {
            print("❌ Failed to initialize transporter: \(initResult)")
            return false
        }
        
        // Create FFI transporter
        transporter = FFITransporter(functionPointer: requestFunc)
        print("✅ Transporter initialized successfully")
        
        return true
    }
    
    // MARK: - Public Interface
    
    /// Get the transporter instance
    /// - Returns: The FFI transporter if available
    public func getTransporter() -> FFITransporter? {
        return transporter
    }
    
    /// Test the Rust library by creating a test object
    /// - Returns: The created test object bytes if successful
    public func testRustLibrary() -> Data? {
        guard let handle = libraryHandle else { return nil }
        
        // Get test object creation function
        guard let createFunc = dlsym(handle, "create_test_object") else {
            print("❌ Failed to get create_test_object function")
            return nil
        }
        
        let createTestObject = unsafeBitCast(createFunc, to: (@convention(c) (
            UInt64, UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<UInt>
        ) -> Int32).self)
        
        // Create test object
        let testName = "Swift Test"
        let (namePointer, _) = CBORSerialization.toFFIPointer(testName)
        
        var outBytes: UnsafeMutablePointer<UInt8>?
        var outLen: UInt = 0
        
        let result = createTestObject(12345, namePointer, &outBytes, &outLen)
        
        guard result == 0, let bytes = outBytes else {
            print("❌ Failed to create test object: \(result)")
            return nil
        }
        
        // Convert to Data
        let data = Data(bytes: bytes, count: Int(outLen))
        
        // Free the memory allocated by Rust
        if let freeFunc = dlsym(handle, "free_test_object_bytes") {
            let freeTestObject = unsafeBitCast(freeFunc, to: (@convention(c) (UnsafeMutablePointer<UInt8>, UInt) -> Int32).self)
            _ = freeTestObject(bytes, outLen)
        }
        
        print("✅ Successfully created test object from Rust: \(data.count) bytes")
        return data
    }
    
    /// Cleanup the Rust transporter
    public func cleanup() {
        guard let handle = libraryHandle else { return }
        
        if let cleanupFunc = dlsym(handle, "transporter_cleanup") {
            let cleanup = unsafeBitCast(cleanupFunc, to: (@convention(c) () -> Int32).self)
            _ = cleanup()
            print("🧹 Rust transporter cleaned up")
        }
        
        closeLibrary()
    }
}

// MARK: - Dynamic Library Loading

/// Load a dynamic library
/// - Parameter path: Path to the dynamic library
/// - Returns: Library handle if successful
private func dlopen(_ path: String, _ mode: Int32) -> UnsafeMutableRawPointer? {
    return path.withCString { cString in
        return dlopen(cString, mode)
    }
}

/// Get a symbol from a dynamic library
/// - Parameters:
///   - handle: Library handle
///   - symbol: Symbol name
/// - Returns: Symbol pointer if found
private func dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: String) -> UnsafeMutableRawPointer? {
    return symbol.withCString { cString in
        return dlsym(handle, cString)
    }
}

/// Close a dynamic library
/// - Parameter handle: Library handle to close
private func dlclose(_ handle: UnsafeMutableRawPointer?) {
    dlclose(handle)
}
