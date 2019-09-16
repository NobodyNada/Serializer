//
//  Serialization.swift
//  Serializer
//
//  Created by NobodyNada on 6/23/17.
//
//  This file contains the `Encoder` implementation.
//  Heavily based on `JSONEncoder` (https://github.com/apple/swift/blob/master/stdlib/public/SDK/Foundation/JSONEncoder.swift).

internal class _Serializer: Encoder, SingleValueEncodingContainer {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey : Any]
    var storage: [Serializable] = []
    
    init(userInfo: [CodingUserInfoKey : Any]) {
        self.userInfo = userInfo
    }
    
    var canEncodeNewElement: Bool { return storage.count == codingPath.count }
    
    func assertCanEncodeNewElement() {
        precondition(canEncodeNewElement, "Only one container may be requested")
    }
    
    /*func assertCanEncodeSingleValue() {
     assertCanEncodeNewElement()
     switch storage.last! {
     case .array, .dictionary: break
     default: preconditionFailure("Attempt to encode multiple single values")
     }
     }*/
    
    func encodeNil() throws {
        assertCanEncodeNewElement()
        storage.append(.null)
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        assertCanEncodeNewElement()
        if let v = value as? SerializableConvertible {
            storage.append(v.asSerializable)
        } else {
            try value.encode(to: self)
        }
    }
    
    /// Converts a value to a Serializable.
    internal func convert<T: Encodable>(_ value: T, forKey key: @autoclosure () -> CodingKey) throws -> Serializable? {
        if let v = value as? SerializableConvertible {
            return v.asSerializable
        }
        
        codingPath.append(key())
        defer { codingPath.removeLast() }
        
        let initialCount = storage.count
        
        if let v = value as? Array<Encodable> {
            // Array's encoder can be slow because it doesn't use `encode(contentsOf:)`.
            var container = unkeyedContainer()
            try container.encode(contentsOf: v.lazy.map(_AnyEncodable.init))
        } else {
            try value.encode(to: self)
        }
        
        if storage.count == initialCount {
            //The value didn't encode anything.
            return nil
        } else {
            return storage.removeLast()
        }
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        if canEncodeNewElement {
            storage.append(.dictionary([:]))
        } else {
            guard case .dictionary(_)? = storage.last else {
                preconditionFailure("Cannot push multiple containers of different types")
            }
        }
        return KeyedEncodingContainer<Key>(
            _SerializerKeyedEncodingContainer(encoder: self, codingPath: codingPath, storageIndex: storage.indices.last!)
        )
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if canEncodeNewElement {
            storage.append(.array([]))
        } else {
            guard case .array(_)? = storage.last else {
                preconditionFailure("Cannot push multiple containers of different types")
            }
        }
        return _SerializerUnkeyedEncodingContainer(encoder: self, codingPath: codingPath, storageIndex: storage.indices.last!)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return self
    }
}

struct _AnyEncodable: Encodable {
    var value: Encodable
    
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

//A _Serializer which writes into another _Serializer's storage.
private class _SuperSerializer: _Serializer {
    enum ReferenceItem {
        case array(index: Int)
        case dictionary(key: CodingKey)
    }
    
    let target: _Serializer
    let referenceIndex: Int
    let referenceItem: ReferenceItem
    
    init(referencing target: _Serializer, storageIndex: Int, item: ReferenceItem, userInfo: [CodingUserInfoKey : Any]) {
        self.target = target
        referenceIndex = storageIndex
        referenceItem = item
        
        super.init(userInfo: userInfo)
        
        switch item {
        case .dictionary(let key): codingPath = target.codingPath + [key]
        case .array(let index): codingPath = target.codingPath + [_SerializerKey(intValue: index)]
        }
    }
    
    override var canEncodeNewElement: Bool {
        //Traverse the _SuperSerializer chain and count the items in the coding path.
        var targetPathCount: Int = 0
        var currentSerializer: _Serializer = self
        while let next = currentSerializer as? _SuperSerializer {
            targetPathCount += next.target.codingPath.count
            currentSerializer = next.target
        }
        
        return storage.count == codingPath.count - targetPathCount - 1
    }
    
    //Write the storage into the target encoder
    deinit {
        let value: Serializable
        switch storage.count {
        case 0: value = .null
        case 1: value = storage[0]
        default: preconditionFailure("superEncoder deallocated with multiple containers on stack")
        }
        
        let targetItem = target.storage[referenceIndex]
        switch referenceItem {
        case .array(let index):
            guard case .array(var array) = targetItem else {
                fatalError("_SuperEncoder references an array, but target is \(targetItem)")
            }
            array.insert(value, at: index)
            target.storage[referenceIndex] = .array(array)
        case .dictionary(let key):
            guard case .dictionary(var dict) = targetItem else {
                fatalError("_SuperEncoder references an dictionary, but target is \(targetItem)")
            }
            dict[key.stringValue] = value
            target.storage[referenceIndex] = .dictionary(dict)
        }
    }
}


internal struct _SerializerKey: CodingKey {
    private var _stringValue: String?
    var intValue: Int?
    
    var stringValue: String { return _stringValue ?? String(intValue!) }
    
    init(stringValue: String) {
        self._stringValue = stringValue
    }
    
    init(intValue: Int) {
        self.intValue = intValue
    }
    
    static let `super` = _SerializerKey(stringValue: "super")
}

private class _SerializerKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K
    
    let encoder: _Serializer
    let codingPath: [CodingKey]
    let storageIndex: Int
    
    var storage: [String:Serializable] {
        get {
            let storageItem = encoder.storage[storageIndex]
            guard case .dictionary(let dict) = storageItem else {
                fatalError("storage container is not a dictionary")
            }
            return dict
        } set {
            encoder.storage[storageIndex] = .dictionary(newValue)
        }
    }
    
    init(encoder: _Serializer, codingPath: [CodingKey], storageIndex: Int) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.storageIndex = storageIndex
    }
    
    func encodeNil(forKey key: K) throws {
        storage[key.stringValue] = .null
    }
    
    func encode<T>(_ value: T, forKey key: K) throws where T : Encodable {
        storage[key.stringValue] = try encoder.convert(value, forKey: key)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> {
        let container = _SerializerReferencingKeyedEncodingContainer<NestedKey>(
            encoder: encoder, codingPath: codingPath + [key],
            getter: { self.storage[key.stringValue] }, setter: { self.storage[key.stringValue] = $0 }
        )
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        return  _SerializerReferencingUnkeyedEncodingContainer(
            encoder: encoder, codingPath: codingPath + [key],
            getter: { self.storage[key.stringValue] }, setter: { self.storage[key.stringValue] = $0 }
        )
    }
    
    func superEncoder() -> Encoder {
        return _SuperSerializer(
            referencing: encoder, storageIndex: storageIndex,
            item: .dictionary(key: _SerializerKey.super),
            userInfo: encoder.userInfo
        )
    }
    
    func superEncoder(forKey key: Key) -> Encoder {
        return _SuperSerializer(
            referencing: encoder, storageIndex: storageIndex,
            item: .dictionary(key: key),
            userInfo: encoder.userInfo
        )
    }
}

//A keyed container which uses a custom getter and setter to access its storage.
//Used to implement nested containers.
private class _SerializerReferencingKeyedEncodingContainer<K: CodingKey>: _SerializerKeyedEncodingContainer<K> {
    let getter: () -> Serializable?
    let setter: (Serializable) -> ()
    
    init(encoder: _Serializer, codingPath: [CodingKey],
         getter: @escaping () -> Serializable?, setter: @escaping (Serializable) -> ()) {
        self.getter = getter
        self.setter = setter
        super.init(
            encoder: encoder,
            codingPath: codingPath,
            storageIndex: -1
        )
    }
    
    override var storage: [String : Serializable] {
        get {
            let storageItem = getter() ?? .dictionary([:])
            guard case .dictionary(let dict) = storageItem else {
                fatalError("storage container is not a dictionary")
            }
            return dict
        } set {
            setter(.dictionary(newValue))
        }
    }
}

//Workaround to avoid a compiler crash when making _SerializerUnkeyedEncodingContainer non-final
private protocol _SerializerUnkeyedEncodingContainerProtocol: class, UnkeyedEncodingContainer {
    var encoder: _Serializer { get }
    var storage: [Serializable] { get set }
    var storageIndex: Int { get }
}

extension _SerializerUnkeyedEncodingContainerProtocol {
    func encodeNil() throws {
        storage.append(.null)
    }
    
    func encode<T: Sequence>(contentsOf sequence: T) throws where T.Element: Encodable {
        var index = count
        func nextKey() -> _SerializerKey {
            defer { index += 1 }
            return .init(intValue: index)
        }
        
        storage.reserveCapacity(count + sequence.underestimatedCount)
        try storage.append(contentsOf: sequence.lazy.compactMap { try encoder.convert($0, forKey: nextKey()) })
    }
    
    func encode<T>(_ value: T) throws where T: Encodable {
        try encoder.convert(value, forKey: _SerializerKey(intValue: count)).map { storage.append($0) }
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let index = storage.count
        storage.insert(.dictionary([:]), at: index)
        let container = _SerializerReferencingKeyedEncodingContainer<NestedKey>(
            encoder: encoder, codingPath: codingPath,
            getter: { self.storage[index] }, setter: { self.storage[index] = $0 }
        )
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let index = storage.count
        storage.insert(.array([]), at: index)
        return  _SerializerReferencingUnkeyedEncodingContainer(
            encoder: encoder, codingPath: codingPath,
            getter: { self.storage[index] }, setter: { self.storage[index] = $0 }
        )
    }
    
    func superEncoder() -> Encoder {
        return _SuperSerializer(
            referencing: encoder, storageIndex: storageIndex,
            item: .array(index: storage.count),
            userInfo: encoder.userInfo
        )
    }
    
    var count: Int { return storage.count }
}


private final class _SerializerUnkeyedEncodingContainer: _SerializerUnkeyedEncodingContainerProtocol {
    final let encoder: _Serializer
    final let codingPath: [CodingKey]
    final let storageIndex: Int
    
    final var storage: [Serializable] {
        get {
            let storageItem = encoder.storage[storageIndex]
            guard case .array(let array) = storageItem else {
                fatalError("storage container is not an array")
            }
            return array
        } set {
            encoder.storage[storageIndex] = .array(newValue)
        }
    }
    
    init(encoder: _Serializer, codingPath: [CodingKey], storageIndex: Int) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.storageIndex = storageIndex
    }
}

//An unkeyed container which uses a custom getter and setter to access its storage.
//Used to implement nested containers.
private final class _SerializerReferencingUnkeyedEncodingContainer: _SerializerUnkeyedEncodingContainerProtocol {
    let encoder: _Serializer
    var storageIndex: Int { return -1 }
    let codingPath: [CodingKey]
    
    let getter: () -> Serializable?
    let setter: (Serializable) -> ()
    
    init(encoder: _Serializer, codingPath: [CodingKey],
         getter: @escaping () -> Serializable?, setter: @escaping (Serializable) -> ()) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.getter = getter
        self.setter = setter
    }
    
    var storage: [Serializable] {
        get {
            let storageItem = getter() ?? .array([])
            guard case .array(let array) = storageItem else {
                fatalError("storage container is not an array")
            }
            return array
        } set {
            setter(.array(newValue))
        }
    }
}
