import Foundation
import CBORCoding

public struct Timestamped<Value> {

    public let timestamp: Date

    public let value: Value

    public init(timestamp: Date = Date(), value: Value) {
        self.timestamp = timestamp
        self.value = value
    }
}

extension Timestamped: Encodable where Value: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(timestamp)
        try container.encode(value)
    }
}

extension Timestamped: Decodable where Value: Decodable {

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.timestamp = try container.decode(Date.self)
        self.value = try container.decode(Value.self)
    }
}

/**
 An internal struct to partially decode abstract timestamped values
 */
struct AnyTimestamped: Decodable {

    let timestamp: Date

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.timestamp = try container.decode(Date.self)
    }
}

public protocol Timestampable {

}

extension Timestampable {

    public func timestamped() -> Timestamped<Self> {
        .init(value: self)
    }
}

public protocol AsTimestamped {

    associatedtype Value
}

extension Timestamped: AsTimestamped { }

extension Array where Element: AsTimestamped, Element: Decodable {

    public static func decode(from data: Data, using decoder: CBORDecoder = .init()) throws -> [Element] {
        var result = [Element]()
        var index = data.startIndex
        while index < data.endIndex {
            guard index + 4 <= data.endIndex else {
                throw PropertyError.failedToDecode
            }
            let byteCountData = data[index..<index+4]
            guard let byteCountRaw = UInt32(fromData: byteCountData) else {
                throw PropertyError.failedToDecode
            }
            let byteCount = Int(byteCountRaw)
            index += 4

            guard index + byteCount <= data.endIndex else {
                throw PropertyError.failedToDecode
            }
            let valueData = data[index..<index+byteCount]
            index += byteCount

            do {
                let value: Element = try decoder.decode(from: valueData)
                result.append(value)
            } catch {
                throw PropertyError.failedToDecode
            }
        }
        return result
    }

}
