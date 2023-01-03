import Foundation

public struct Timestamped<Value> {

    public let timestamp: Date

    public let value: Value

    public init(timestamp: Date = Date(), value: Value) {
        self.timestamp = timestamp
        self.value = value
    }
}

extension Timestamped: Codable where Value: Codable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(timestamp)
        try container.encode(value)
    }

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
