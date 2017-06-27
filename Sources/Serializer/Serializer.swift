///A Serializer can serialize `Encodable` types to custom data formats.
///A custom `Serializer` should have a `SerializedType` `typealias`, and a `serialize` method
///which converts a `Serializable` into a `SerializedType`.
public protocol Serializer {
    ///The type returned by `serialize`.
    associatedtype SerializedType
    
    ///Serializes a `Serializable` into a `SerializedType`.
    ///- parameter value: The value to serialize.
    ///- returns: The serialized value.
    func serialize(_ value: Serializable) throws -> SerializedType
    
    ///Converts `value` into a `Serializable`.
    ///- parameter value: The value to convert.
    ///- returns: The converted value.
    func convert<T: Encodable>(_ value: T) throws -> Serializable
    
    ///Encodes an `Encodable` into a `SerializedType`.  The default implementation
    ///calls `serialize` with the result of `convert`.
    ///- parameter value: The value to encpde.
    ///- returns: The encoded value.
    func encode<T: Encodable>(_ value: T) throws -> SerializedType
}

///A Deerializer can deserialize `Decodable` types from custom data formats.
///A custom `Deserializer` should have a `SerializedType` `typealias`, and a `deserialize` method
///which converts a `SerializedType` into a `Serializable`.
public protocol Deserializer {
    ///The type accepted by `deserialize`.
    associatedtype SerializedType
    
    ///Deserializes a `SerializedType` into a `Serializable`.
    ///- parameter value: The value to deserialize.
    ///- returns: The deserialized value.
    func deserialize(_ value: SerializedType) throws -> Serializable
    
    ///Converts `value` into a `Serializable`.
    ///- parameter value: The value to convert.
    ///- returns: The converted value.
    func convert<T: Decodable>(_ value: Serializable, to: T.Type) throws -> T
    
    ///Decodes a `SerializedType` into a `Decodable`.  The default implementation
    ///calls `convert` with the result of `deserialize`.
    ///- parameter value: The value to decode.
    ///- returns: The encoded value.
    func decode<T: Decodable>(_ type: T.Type, from: SerializedType) throws -> T
}

public extension Serializer {
    public func convert<T: Encodable>(_ value: T) throws -> Serializable {
        let encoder = _Serializer()
        try value.encode(to: encoder)
        
        assert(encoder.codingPath.isEmpty, "codingPath should be empty")
        assert(encoder.storage.count == 1, "Root object did not encode anything")
        
        return encoder.storage.first!
    }
    
    
    public func encode<T: Encodable>(_ value: T) throws -> SerializedType {
        return try serialize(convert(value))
    }
}

public extension Deserializer {
    public func convert<T: Decodable>(_ value: Serializable, to: T.Type) throws -> T {
        let decoder = _Deserializer(storage: value)
        let result = try to.init(from: decoder)
        
        assert(decoder.codingPath.isEmpty, "codingPath should be empty")
        
        return result
    }
    
    public func decode<T: Decodable>(_ type: T.Type, from: SerializedType) throws -> T {
        return try convert(deserialize(from), to: type)
    }
}


///A `Serializable` stores an object in a format which may be easily serialized.
public enum Serializable {
    case null
    
    case int(Int)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint(UInt)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    
    case float(Float)
    case double(Double)
    
    case bool(Bool)
    
    case string(String)
    
    case array([Serializable])
    case dictionary([String:Serializable])
    
    
    var unboxed: Any? {
        switch self {
        case .null: return nil
            
        case .int(let v): return v
        case .int8(let v): return v
        case .int16(let v): return v
        case .int32(let v): return v
        case .int64(let v): return v
            
        case .uint(let v): return v
        case .uint8(let v): return v
        case .uint16(let v): return v
        case .uint32(let v): return v
        case .uint64(let v): return v
            
        case .string(let v): return v
            
        case .float(let v): return v
        case .double(let v): return v
            
        case .bool(let v): return v
            
        case .array(let v): return v.map { $0.unboxed }
        case .dictionary(let v):
            var result = [String:Any?]()
            for (key, value) in v {
                result[key] = value.unboxed
            }
            return result
        }
    }
}

///A `SerializableConvertible` is a type which may be converted to a `Serializable`.
public protocol SerializableConvertible {
    ///Converts this object to a `Serializable`.
    var asSerializable: Serializable { get }
}

extension Int: SerializableConvertible { public var asSerializable: Serializable { return .int(self) } }
extension Int8: SerializableConvertible { public var asSerializable: Serializable { return .int8(self) } }
extension Int16: SerializableConvertible { public var asSerializable: Serializable { return .int16(self) } }
extension Int32: SerializableConvertible { public var asSerializable: Serializable { return .int32(self) } }
extension Int64: SerializableConvertible { public var asSerializable: Serializable { return .int64(self) } }

extension UInt: SerializableConvertible { public var asSerializable: Serializable { return .uint(self) } }
extension UInt8: SerializableConvertible { public var asSerializable: Serializable { return .uint8(self) } }
extension UInt16: SerializableConvertible { public var asSerializable: Serializable { return .uint16(self) } }
extension UInt32: SerializableConvertible { public var asSerializable: Serializable { return .uint32(self) } }
extension UInt64: SerializableConvertible { public var asSerializable: Serializable { return .uint64(self) } }

extension Float: SerializableConvertible { public var asSerializable: Serializable { return .float(self) } }
extension Double: SerializableConvertible { public var asSerializable: Serializable { return .double(self) } }
extension Bool: SerializableConvertible { public var asSerializable: Serializable { return .bool(self) } }

extension String: SerializableConvertible { public var asSerializable: Serializable { return .string(self) } }
