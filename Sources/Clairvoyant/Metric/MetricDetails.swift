import Foundation

/**
 A description of a metric published by a server.
 */
public struct MetricDetails {

    /// The  name of the metric
    public var name: String?

    /// A description of the metric content
    public var description: String?

    /// An identifier to describe the type of values encoded in a metric
    public let valueType: MetricType

    /**
     Create new metric details.
     - Parameter name: The name of the metric
     - Parameter description: A description of the metric content
     - Parameter valueType: An identifier to describe the type of values encoded in a metric
     */
    public init(valueType: MetricType, name: String? = nil, description: String? = nil) {
        self.valueType = valueType
        self.name = name
        self.description = description
    }
}

extension MetricDetails: Codable {

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.valueType = try container.decode(MetricType.self, forKey: .valueType)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(valueType, forKey: .valueType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }

    enum CodingKeys: Int, CodingKey {
        case name = 3
        case description = 4
        case valueType = 5
    }
}

extension MetricDetails: Equatable { }

extension MetricDetails: Hashable { }
