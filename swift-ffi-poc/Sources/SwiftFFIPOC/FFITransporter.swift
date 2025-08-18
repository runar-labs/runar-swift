import Foundation

/// FFI Transporter interface for communicating with Rust side
public class FFITransporter {
    
    // MARK: - Properties
    
    private let transporterFunction: TransporterRequestFunction
    private var pendingCompletion: ((Result<SampleObject, FFIError>) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize the FFI transporter with the Rust function pointer
    /// - Parameter functionPointer: Pointer to the Rust transporter_request function
    public init(functionPointer: UnsafeRawPointer) {
        self.transporterFunction = unsafeBitCast(functionPointer, to: TransporterRequestFunction.self)
    }
    
    // MARK: - Public Interface
    
    /// Send a request to the Rust transporter
    /// - Parameters:
    ///   - object: The SampleObject to send
    ///   - topic: The topic for the request
    ///   - peerNodeId: The peer node identifier
    ///   - profilePublicKey: The profile public key
    ///   - completion: Completion handler called with the result
    public func sendRequest(
        object: SampleObject,
        topic: String,
        peerNodeId: String,
        profilePublicKey: Data,
        completion: @escaping (Result<SampleObject, FFIError>) -> Void
    ) {
        // Store completion handler for callback
        self.pendingCompletion = completion
        
        // Set this instance as current for callback routing
        self.setAsCurrent()
        
        do {
            // Serialize object to CBOR
            let payloadData = try CBORSerialization.serialize(object)
            
            // Convert to FFI pointers
            let (payloadPointer, payloadLen) = CBORSerialization.toFFIPointer(payloadData)
            let (topicPointer, _) = CBORSerialization.toFFIPointer(topic)
            let (nodeIdPointer, _) = CBORSerialization.toFFIPointer(peerNodeId)
            let (keyPointer, keyLen) = CBORSerialization.toFFIPointer(profilePublicKey)
            
            // Call Rust function with global callback functions
            let result = transporterFunction(
                topicPointer,
                payloadPointer,
                payloadLen,
                nodeIdPointer,
                keyPointer,
                keyLen,
                globalResponseCallback,
                globalErrorCallback
            )
            
            // Check immediate result
            if result != 0 {
                let error = FFIError(code: FFIErrorCode.unknownError, message: "Rust function returned error code: \(result)")
                completion(.failure(error))
                self.clearAsCurrent()
            }
            
        } catch {
            let ffiError = FFIError(code: FFIErrorCode.serializationError, message: "Failed to serialize object: \(error)")
            completion(.failure(ffiError))
            self.clearAsCurrent()
        }
    }
    
    // MARK: - Callback Handlers
    
    /// Handle response from Rust
    /// - Parameters:
    ///   - payloadBytes: Pointer to response data
    ///   - payloadLen: Length of response data
    internal func handleResponse(payloadBytes: UnsafePointer<UInt8>, payloadLen: UInt) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Convert FFI pointer back to Data
                let data = CBORSerialization.fromFFIPointer(payloadBytes, length: payloadLen)
                
                // Deserialize to SampleObject
                let object = try CBORSerialization.deserialize(data)
                
                // Call completion handler
                self.pendingCompletion?(.success(object))
                self.pendingCompletion = nil
                
            } catch {
                let ffiError = FFIError(code: FFIErrorCode.deserializationError, message: "Failed to deserialize response: \(error)")
                self.pendingCompletion?(.failure(ffiError))
                self.pendingCompletion = nil
            }
        }
    }
    
    /// Handle error from Rust
    /// - Parameters:
    ///   - errorCode: Error code from Rust
    ///   - errorMessage: Error message from Rust
    internal func handleError(errorCode: UInt32, errorMessage: UnsafePointer<CChar>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Convert error message to String
            let message = CBORSerialization.fromFFIPointer(errorMessage)
            
            // Create FFI error
            let code = FFIErrorCode(rawValue: errorCode) ?? .unknownError
            let ffiError = FFIError(code: code, message: message)
            
            // Call completion handler
            self.pendingCompletion?(.failure(ffiError))
            self.pendingCompletion = nil
        }
    }
}

// MARK: - Global Callback Functions

/// Global response callback function for FFI
/// This function is called by Rust and dispatches to the appropriate FFITransporter instance
private func globalResponseCallback(payloadBytes: UnsafePointer<UInt8>, payloadLen: UInt) {
    // For now, we'll use a simple approach with a global transporter reference
    // In a production system, you might want to use a more sophisticated approach
    if let currentTransporter = FFITransporter.currentInstance {
        currentTransporter.handleResponse(payloadBytes: payloadBytes, payloadLen: payloadLen)
    }
}

/// Global error callback function for FFI
/// This function is called by Rust and dispatches to the appropriate FFITransporter instance
private func globalErrorCallback(errorCode: UInt32, errorMessage: UnsafePointer<CChar>) {
    if let currentTransporter = FFITransporter.currentInstance {
        currentTransporter.handleError(errorCode: errorCode, errorMessage: errorMessage)
    }
}

// MARK: - FFI Error

/// Error type for FFI communication failures
public struct FFIError: Error, LocalizedError {
    public let code: FFIErrorCode
    public let message: String
    
    public init(code: FFIErrorCode, message: String) {
        self.code = code
        self.message = message
    }
    
    public var errorDescription: String? {
        return "[\(code.description)] \(message)"
    }
}

// MARK: - Global Instance Management

extension FFITransporter {
    /// Global instance for callback routing
    /// Note: This is a simplified approach for the POC
    /// In production, consider using a more robust callback routing system
    internal static var currentInstance: FFITransporter?
    
    /// Set the current instance for callback routing
    fileprivate func setAsCurrent() {
        FFITransporter.currentInstance = self
    }
    
    /// Clear the current instance
    fileprivate func clearAsCurrent() {
        if FFITransporter.currentInstance === self {
            FFITransporter.currentInstance = nil
        }
    }
}
