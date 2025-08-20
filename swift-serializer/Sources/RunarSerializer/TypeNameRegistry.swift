import Foundation

public actor TypeNameRegistry {
    public static let shared = TypeNameRegistry()

    // Swift type name -> wire name
    private var swiftToWire: [String: String] = [:]
    // wire name -> Swift.Type
    private var wireToSwift: [String: Any.Type] = [:]
    // wire name -> JSON converter closure
    private var wireToJSON: [String: @Sendable (AnyValue) async throws -> Any] = [:]
    // wire name -> decoder closure (CBOR bytes -> Any)
    private var wireToDecoder: [String: @Sendable (Data) throws -> Any] = [:]
    // wire name -> Swift type name (diagnostics)
    private var wireToSwiftName: [String: String] = [:]

    public init() {}

    func preRegisterPrimitives() {
        registerBuiltin(String.self, wire: "string")
        registerBuiltin(Bool.self, wire: "bool")
        registerBuiltin(Data.self, wire: "bytes")
        registerBuiltin(Character.self, wire: "char")
        registerBuiltin(Int8.self, wire: "i8")
        registerBuiltin(Int16.self, wire: "i16")
        registerBuiltin(Int32.self, wire: "i32")
        registerBuiltin(Int64.self, wire: "i64")
        registerBuiltin(UInt8.self, wire: "u8")
        registerBuiltin(UInt16.self, wire: "u16")
        registerBuiltin(UInt32.self, wire: "u32")
        registerBuiltin(UInt64.self, wire: "u64")
        registerBuiltin(Int.self, wire: "i64")
        registerBuiltin(UInt.self, wire: "u64")
        registerBuiltin(Float.self, wire: "f32")
        registerBuiltin(Double.self, wire: "f64")
    }

    func preRegisterContainers() {
        wireToSwift["list<any>"] = [AnyValue].self
        wireToSwiftName["list<any>"] = "[AnyValue]"
        wireToSwift["map<string,any>"] = [String: AnyValue].self
        wireToSwiftName["map<string,any>"] = "[String: AnyValue]"
    }

    private func registerBuiltin(_ type: Any.Type, wire: String) {
        let swiftName = String(describing: type)
        swiftToWire[swiftName] = wire
        wireToSwift[wire] = type
        wireToSwiftName[wire] = swiftName
    }

    public func registerTypeName<T>(_: T.Type, wireName: String) {
        let swiftName = String(describing: T.self)
        if swiftToWire[swiftName] == nil {
            swiftToWire[swiftName] = wireName
        }
        if wireToSwift[wireName] == nil {
            wireToSwift[wireName] = T.self
            wireToSwiftName[wireName] = swiftName
        }
    }

    public func registerJSONConverter(for wireName: String, converter: @escaping @Sendable (AnyValue) async throws -> Any) {
        if wireToJSON[wireName] == nil {
            wireToJSON[wireName] = converter
        }
    }

    public func registerDecoder(for wireName: String, decode: @escaping @Sendable (Data) throws -> Any) {
        if wireToDecoder[wireName] == nil {
            wireToDecoder[wireName] = decode
        }
    }

    public func lookupWireName(swiftTypeName: String) -> String? { swiftToWire[swiftTypeName] }
    public func lookupSwiftTypeByWireName(_ wire: String) -> Any.Type? { wireToSwift[wire] }
    public func lookupSwiftNameByWireName(_ wire: String) -> String? { wireToSwiftName[wire] }
    public func lookupJsonByWireName(_ wire: String) -> (@Sendable (AnyValue) async throws -> Any)? { wireToJSON[wire] }
    public func lookupDecoderByWireName(_ wire: String) -> (@Sendable (Data) throws -> Any)? { wireToDecoder[wire] }
}

// Initialize built-ins at module load
let _typeNameRegistryBootstrap: Void = {
    Task {
        await TypeNameRegistry.shared.preRegisterPrimitives()
        await TypeNameRegistry.shared.preRegisterContainers()
    }
}()


