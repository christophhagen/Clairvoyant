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

extension Timestamped: TimestampedProtocol {
    
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

extension Timestamped: Equatable where Value: Equatable {
    
    public static func == (lhs: Timestamped, rhs: Timestamped) -> Bool {
        lhs.value == rhs.value && lhs.timestamp.timeIntervalSince1970 == rhs.timestamp.timeIntervalSince1970
    }
}

extension Timestamped: CustomStringConvertible where Value: CustomStringConvertible {
    
    public var description: String {
        "[\(timestamp)] \(value.description)"
    }
}

/**
 A struct to partially decode abstract timestamped values, when the contained value is unknown.
 */
public struct UnknownTimestamped: Decodable {

    public let timestamp: Date

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.timestamp = try container.decode(Date.self)
    }
}
