import XCTest
@testable import Serializer

class SerializerTests: XCTestCase {
    public class PassthroughSerializer: Serializer {
        public func serialize(_ serializable: Serializable) -> Serializable {
            return serializable
        }
    }
    
    public class PassthroughDeserializer: Deserializer {
        public func deserialize(_ value: Serializable) throws -> Serializable {
            return value
        }
    }
    
    func testBasic() throws {
        class Test: Codable {
            var i: Int?
            var s: String
            var test2: Test2
            init(i: Int?, s: String, test2: Test2) {
                self.i = i
                self.s = s
                self.test2 = test2
            }
        }
        
        struct Test2: Codable {
            var f: Float
            var a: [String]
            init(f: Float, a: [String]) {
                self.f = f
                self.a = a
            }
        }
        
        let test = Test(i: 10, s: "Hello, world!", test2: Test2(f: 4.5, a: ["String 1", "String 2"]))
        
        let serializedTest = try PassthroughSerializer().encode(test)
        let errorMessage = "serializedTest is invalid: \(serializedTest)"
        
        if let t = serializedTest.unboxed as? [String:Any?] {
            XCTAssertEqual(t.count, 3, errorMessage)
            XCTAssertEqual(t["i"] as? Int, 10, errorMessage)
            XCTAssertEqual(t["s"] as? String, "Hello, world!", errorMessage)
            
            if let t2 = t["test2"] as? [String:Any] {
                XCTAssertEqual(t2.count, 2, errorMessage)
                XCTAssertEqual(t2["f"] as? Float, 4.5, errorMessage)
                
                XCTAssertEqual((t2["a"] as? [String])?.count, 2, errorMessage)
                XCTAssertEqual((t2["a"] as? [String])?[0], "String 1", errorMessage)
                XCTAssertEqual((t2["a"] as? [String])?[1],  "String 2", errorMessage)
            } else {
                XCTFail(errorMessage)
            }
        } else {
            XCTFail(errorMessage)
        }
        
        let deserializedTest = try PassthroughDeserializer().decode(Test.self, from: serializedTest)
        let deserializedErrorMessage = "deserializedTest is invalid: \(deserializedTest)"
        XCTAssert(deserializedTest.i == test.i, deserializedErrorMessage)
        XCTAssert(deserializedTest.s == test.s, deserializedErrorMessage)
        XCTAssert(deserializedTest.test2.f == test.test2.f, deserializedErrorMessage)
        XCTAssert(deserializedTest.test2.a == test.test2.a, deserializedErrorMessage)
        
    }
    
    func testNestedContainer() throws {
        struct Test: Codable {
            private enum CodingKeys: String, CodingKey {
                case a
                case b
                case c
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
                var nested2 = nested.nestedUnkeyedContainer(forKey: .b)
                var nested3 = nested2.nestedUnkeyedContainer()
                var nested4 = nested3.nestedContainer(keyedBy: CodingKeys.self)
                try nested4.encode("Hello, world!", forKey: .c)
            }
            
            init() { }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
                var nested2 = try nested.nestedUnkeyedContainer(forKey: .b)
                var nested3 = try nested2.nestedUnkeyedContainer()
                let nested4 = try nested3.nestedContainer(keyedBy: CodingKeys.self)
                XCTAssertEqual(try nested4.decode(String.self, forKey: .c), "Hello, world!")
            }
        }
        
        let test = Test()
        let serialized = try PassthroughSerializer().encode(test)
        let errorMessage = "serialized is invalid: \(serialized)"
        
        guard let unboxed = serialized.unboxed as? [String:[String:[[[String:String]]]]] else {
            XCTFail(errorMessage)
            return
        }
        guard unboxed.count == 1, unboxed.first?.value.count == 1,
            unboxed.first?.value.first?.value.count == 1,
            unboxed.first?.value.first?.value.first?.count == 1,
            unboxed.first?.value.first?.value.first?.first?.count == 1,
            unboxed.first?.value.first?.value.first?.first?.first?.value == "Hello, world!"
            else {
                XCTFail(errorMessage)
                return
        }
    }
    
    func testSuperEncoder() throws {
        struct Test: Codable {
            private enum CodingKeys: String, CodingKey {
                case a
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("Test", forKey: .a)
                let superEncoder = container.superEncoder()
                var superContainer = superEncoder.singleValueContainer()
                try superContainer.encodeNil()
            }
            
            init() { }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                XCTAssertEqual(try container.decode(String.self, forKey: .a), "Test")
                let superDecoder = try container.superDecoder()
                let superContainer = try superDecoder.singleValueContainer()
                XCTAssert(superContainer.decodeNil())
            }
        }
        
        let t = Test()
        let encoder = PassthroughSerializer()
        let serialized = try encoder.encode(t)
        guard let unboxed = serialized.unboxed as? [String:Any?],
            unboxed.count == 2,
            unboxed["a"] as? String == "Test",
            unboxed["super"] ?? nil == nil
            else {
                XCTFail("Serialized is invalid: \(serialized)")
                return
        }
        
        let decoder = PassthroughDeserializer()
        _ = try decoder.decode(Test.self, from: serialized)
    }
    
    static var allTests = [
        ("testBasic", testBasic),
        ("testNestedContainer", testNestedContainer),
        ("testSuperEncoder", testSuperEncoder)
    ]
}
