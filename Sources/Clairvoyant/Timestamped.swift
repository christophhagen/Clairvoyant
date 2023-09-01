import Foundation

typealias TimestampedValueData = Data

public struct Timestamped<Value> {

    public let timestamp: Date

    public let value: Value

    public init(value: Value, timestamp: Date = Date()) {
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
