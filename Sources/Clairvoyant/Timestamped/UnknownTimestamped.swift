import Foundation

/**
 A struct to partially decode abstract timestamped values, when the contained value is unknown.
 */
public struct UnknownTimestamped: Decodable {

    /// The timestamp of the value
    public let timestamp: Date

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.timestamp = try container.decode(Date.self)
    }
}
