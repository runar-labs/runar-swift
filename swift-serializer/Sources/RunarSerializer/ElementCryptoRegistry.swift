import Foundation

public actor ElementCryptoRegistry {
    public static let shared = ElementCryptoRegistry()

    public typealias EncryptFn = @Sendable (_ elementCBOR: Data, _ context: SerializationContext) throws -> Data
    public typealias DecryptFn = @Sendable (_ encryptedElementCBOR: Data, _ keystore: KeyStore) throws -> Data

    private var encryptorsByWire: [String: EncryptFn] = [:]
    private var decryptorsByWire: [String: DecryptFn] = [:]

    public func register(wireName: String, encrypt: @escaping EncryptFn, decrypt: @escaping DecryptFn) {
        if encryptorsByWire[wireName] == nil { encryptorsByWire[wireName] = encrypt }
        if decryptorsByWire[wireName] == nil { decryptorsByWire[wireName] = decrypt }
    }

    public func lookupEncryptor(wireName: String) -> EncryptFn? { encryptorsByWire[wireName] }
    public func lookupDecryptor(wireName: String) -> DecryptFn? { decryptorsByWire[wireName] }
}


