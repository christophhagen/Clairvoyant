import Foundation

typealias TimestampedValueData = Data

public struct Timestamped<Value> {

    public let timestamp: Date

    public let value: Value

    public init(value: Value, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.value = value
    }

    static func decode(from data: TimestampedValueData, using decoder: BinaryDecoder) throws -> Timestamped<Value> where Value: Decodable {
        let timestampData = data.prefix(decoder.encodedTimestampLength)
        let timestamp = try decoder.decode(TimeInterval.self, from: timestampData)
        let value = try decoder.decode(Value.self, from: data.advanced(by: decoder.encodedTimestampLength))
        return .init(value: value, timestamp: .init(timeIntervalSince1970: timestamp))
    }

    func encode(using encoder: BinaryEncoder) throws -> TimestampedValueData where Value: Encodable {
        let data = try encoder.encode(value)
        let timestampData = try encoder.encode(timestamp.timeIntervalSince1970)
        return timestampData + data
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
