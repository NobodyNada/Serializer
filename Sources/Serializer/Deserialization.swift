//
//  Deserialization.swift
//  Serializer
//
//  Created by NobodyNada on 6/23/17.
//
//  This file contains the `Decoder` implementation.
//  Heavily based on `JSONDecoder` (https://github.com/apple/swift/blob/master/stdlib/public/SDK/Foundation/JSONEncoder.swift#L789).

import Foundation

public enum DecodingError: Error {
    case typeMismatch(expected: Any.Type, actual: Serializable)
    case unkeyedContainerAtEnd
    case unexpectedNull
    case keyNotFound(CodingKey)
}

private var dateFormatter: DateFormatter = {
    var formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZ"
    return formatter
}()

private extension Serializable {
    var asDate: Date? {
        switch self {
        case .date(let v): return v
            
        case .int32(let v): return Date(timeIntervalSince1970: TimeInterval(v))
        case .int64(let v): return Date(timeIntervalSince1970: TimeInterval(v))
        case .int(let v): return Date(timeIntervalSince1970: TimeInterval(v))
        case .float(let v): return Date(timeIntervalSince1970: TimeInterval(v))
        case .double(let v): return Date(timeIntervalSince1970: TimeInterval(v))
            
        case .string(let v): return dateFormatter.date(from: v)
            
        default: return nil
        }
    }
    
    var asData: Data? {
        switch self {
        case .data(let d): return d
        case .array(let a):
            var result = Data(capacity: a.count)
            for item in a {
                if case .uint8(let v) = item {
                    result.append(v)
                } else {
                    return nil
                }
            }
            return result
            
        case .string(let s): return Data(base64Encoded: s)
        default: return nil
        }
    }
}

class _Deserializer: Decoder, SingleValueDecodingContainer {
    var storage: [Serializable]
    var codingPath: [CodingKey?]
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    var dateHandler: ((Serializable) throws -> Date?)?
    var dataHandler: ((Serializable) throws -> Data?)?
    
    init(storage: Serializable, at path: [CodingKey?] = []) {
        self.storage = [storage]
        self.codingPath = path
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        if case .null = (storage.last ?? .null) { throw DecodingError.unexpectedNull }
        guard case .dictionary(let dict) = storage.last! else {
            throw DecodingError.typeMismatch(expected: [String:Any].self, actual: storage.last!)
        }
        
        let container = _DeserializerKeyedDecodingContainer<Key>(decoder: self, storage: dict)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        if case .null = (storage.last ?? .null) { throw DecodingError.unexpectedNull }
        guard case .array(let array) = storage.last! else {
            throw DecodingError.typeMismatch(expected: [Any].self, actual: storage.last!)
        }
        
        return _DeserializerUnkeyedDecodingContainer(decoder: self, storage: array)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return self
    }
    
    func decodeNil() -> Bool {
        if case .null = storage.last ?? .null { return true }
        return false
    }
    
    func decode<T: Decodable & SerializableConvertible>(_ type: T.Type) throws -> T {
        if case .null = storage.last ?? .null {
            throw DecodingError.unexpectedNull
        }
        
        guard let value = storage.last?.unboxed as? T else {
            throw DecodingError.typeMismatch(expected: T.self, actual: storage.last!)
        }
        
        return value
    }
    
    func decode<T: SerializableConvertible>(_ type: T.Type) throws -> T? {
        if case .null = storage.last ?? .null {
            throw DecodingError.unexpectedNull
        }
        
        guard let value = storage.last?.unboxed as? T else {
            throw DecodingError.typeMismatch(expected: T.self, actual: storage.last!)
        }
        
        return value
    }
    
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let value = storage.last else { throw DecodingError.unexpectedNull }
        
        let containerCount = storage.count
        let pathCount = codingPath.count
        storage.append(value)
        codingPath.append(nil)
        let result = try type.init(from: self)
        assert(storage.count == containerCount + 1, "The container stack is not balanced!")
        assert(codingPath.count == pathCount + 1, "The coding path stack is not balanced!")
        storage.removeLast()
        codingPath.removeLast()
        return result
    }
    
    func decodeDate(from serializable: Serializable) throws -> Date? {
        return try dateHandler?(serializable) ?? serializable.asDate
    }
    
    func decodeData(from serializable: Serializable) throws -> Data? {
        return try dataHandler?(serializable) ?? serializable.asData
    }
}

class _DeserializerKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K
    
    var decoder: _Deserializer
    var storage: [String:Serializable]
    var codingPath: [CodingKey?]
    
    var allKeys: [K] {
        return storage.keys.flatMap { Key(stringValue: $0) }
    }
    
    init(decoder: _Deserializer, storage: [String:Serializable]) {
        self.decoder = decoder
        self.storage = storage
        codingPath = decoder.codingPath
    }
    
    func contains(_ key: K) -> Bool {
        return storage[key.stringValue] != nil
    }
    
    //This method exists since the compiler doesn't otherwise know which method to call if a type
    //conforms to *both* Decodable and SerializableConvertible.
    func decodeIfPresent<T: Decodable & SerializableConvertible>(_ type: T.Type, forKey key: K) throws -> T? {
        guard let value = storage[key.stringValue] else { return nil }
        return value.unboxed as? T
    }
    
    func decodeIfPresent<T: SerializableConvertible>(_ type: T.Type, forKey key: K) throws -> T? {
        guard let value = storage[key.stringValue] else { return nil }
        return value.unboxed as? T
    }
    
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
        guard let value = storage[key.stringValue] else { return nil }
        
        if type == Data.self, let data = try decoder.decodeData(from: value) {
            return data as? T
        } else if type == Date.self, let date = try decoder.decodeDate(from: value) {
            return date as? T
        }
        
        let containerCount = decoder.storage.count
        let pathCount = decoder.codingPath.count
        decoder.storage.append(value)
        decoder.codingPath.append(nil)
        let result = try type.init(from: decoder)
        assert(decoder.storage.count == containerCount + 1, "The container stack is not balanced!")
        assert(decoder.codingPath.count == pathCount + 1, "The coding path stack is not balanced!")
        decoder.storage.removeLast()
        decoder.codingPath.removeLast()
        return result
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> {
        guard let value = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key)
        }
        
        guard case .dictionary(let dict) = value else {
            throw DecodingError.typeMismatch(expected: [String:Any].self, actual: value)
        }
        
        decoder.codingPath.append(key)
        let container = _DeserializerKeyedDecodingContainer<NestedKey>(decoder: decoder, storage: dict)
        decoder.codingPath.removeLast()
        return KeyedDecodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        guard let value = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key)
        }
        
        guard case .array(let array) = value else {
            throw DecodingError.typeMismatch(expected:[Any].self, actual: value)
        }
        
        decoder.codingPath.append(key)
        let container = _DeserializerUnkeyedDecodingContainer(decoder: decoder, storage: array)
        decoder.codingPath.removeLast()
        return container
    }
    
    func superDecoder() throws -> Decoder {
        return try superDecoder(forKey: _SuperKey.`super`)
    }
    
    func superDecoder(forKey key: K) throws -> Decoder {
        return try superDecoder(forKey: key as CodingKey)
    }
    
    func superDecoder(forKey key: CodingKey) throws -> Decoder {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }
        
        guard let value = storage[key.stringValue] else {
            throw DecodingError.keyNotFound(key)
        }
        
        return _Deserializer(storage: value, at: decoder.codingPath)
    }
}

class _DeserializerUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var decoder: _Deserializer
    var storage: [Serializable]
    var codingPath: [CodingKey?]
    var count: Int? { return storage.count }
    var isAtEnd: Bool { return index >= storage.count }
    var index = 0
    
    func next() -> Serializable? {
        guard !isAtEnd else { return nil }
        let value = storage[index]
        index += 1
        return value
    }
    
    init(decoder: _Deserializer, storage: [Serializable]) {
        self.decoder = decoder
        self.storage = storage
        self.codingPath = decoder.codingPath
    }
    
    func decodeIfPresent<T: Decodable & SerializableConvertible>(_ type: T.Type) throws -> T? {
        return next()?.unboxed as? T
    }
    
    func decodeIfPresent<T: SerializableConvertible>(_ type: T.Type) throws -> T? {
        return next()?.unboxed as? T
    }
    
    func decodeIfPresent<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let value = next() else { return nil }
        
        let containerCount = decoder.storage.count
        let pathCount = decoder.codingPath.count
        decoder.storage.append(value)
        decoder.codingPath.append(nil)
        let result = try type.init(from: decoder)
        assert(decoder.storage.count == containerCount + 1, "The container stack is not balanced!")
        assert(decoder.codingPath.count == pathCount + 1, "The coding path stack is not balanced!")
        decoder.storage.removeLast()
        decoder.codingPath.removeLast()
        return result
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        guard let value = next() else {
            throw DecodingError.unkeyedContainerAtEnd
        }
        
        guard case .dictionary(let dict) = value else {
            throw DecodingError.typeMismatch(expected: [String:Any].self, actual: value)
        }
        
        decoder.codingPath.append(nil)
        let container = _DeserializerKeyedDecodingContainer<NestedKey>(decoder: decoder, storage: dict)
        decoder.codingPath.removeLast()
        return KeyedDecodingContainer(container)
    }
    
    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard let value = next() else {
            throw DecodingError.unkeyedContainerAtEnd
        }
        
        guard case .array(let array) = value else {
            throw DecodingError.typeMismatch(expected: [Any].self, actual: value)
        }
        
        decoder.codingPath.append(nil)
        let container = _DeserializerUnkeyedDecodingContainer(decoder: decoder, storage: array)
        decoder.codingPath.removeLast()
        return container
    }
    
    func superDecoder() throws -> Decoder {
        decoder.codingPath.append(nil)
        defer { decoder.codingPath.removeLast() }
        
        guard let value = next() else {
            throw DecodingError.unkeyedContainerAtEnd
        }
        
        if case .null = value { throw DecodingError.unexpectedNull }
        
        return _Deserializer(storage: value, at: decoder.codingPath)
    }
    
    
}
