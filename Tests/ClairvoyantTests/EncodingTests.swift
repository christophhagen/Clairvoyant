import XCTest
@testable import Clairvoyant

final class EncodingTests: XCTestCase {

    func testDoubleEncoding() {
        let value = 3.14
        let encoded = value.toData()
        guard let decoded = Double(fromData: encoded) else {
            XCTFail("Failed to decode double (\(encoded.count) bytes)")
            return
        }
        XCTAssertEqual(value, decoded)
    }

    func testEncodeTimestamped() throws {
        try encode(123)
        try encode(3.14)
        try encode("test")
    }

    private func encode<T>(_ value: T) throws where T: Codable, T: Equatable {
        let timestamped = Timestamped(value: value)
        let encoded = try JSONEncoder().encode(timestamped)
        let decoded: Timestamped<T> = try JSONDecoder().decode(from: encoded)
        XCTAssertEqual(timestamped.timestamp, decoded.timestamp)
        XCTAssertEqual(value, decoded.value)
    }

    func testDecodeAnyTimestamped() throws {
        let value = Timestamped(value: 123)
        let encoded = try JSONEncoder().encode(value)
        
        let decoded: UnknownTimestamped = try JSONDecoder().decode(from: encoded)
        XCTAssertEqual(value.timestamp, decoded.timestamp)
    }
}
