import Foundation

/**
 A description of a metric published by a server.
 */
public struct MetricInfo {

    /// The unique id of the metric in the group
    public let id: MetricId
    
    /// The  name of the metric
    public var name: String?
    
    /// A description of the metric content
    public var description: String?

    /// An identifier to describe the type of values encoded in a metric
    public let valueType: MetricType

    /**
     Create a new metric info.
     - Parameter id: The unique id of the metric in the group
     - Parameter group: The group to which this metric belongs
     - Parameter name: The name of the metric
     - Parameter description: A description of the metric content
     - Parameter valueType: An identifier to describe the type of values encoded in a metric
     */
    public init(id: String, group: String, valueType: MetricType, name: String? = nil, description: String? = nil) {
        self.id = .init(id: id, group: group)
        self.valueType = valueType
        self.name = name
        self.description = description
    }
    
    /**
     Create a new metric info.
     - Parameter id: The unique id of the metric
     - Parameter name: The name of the metric
     - Parameter description: A description of the metric content
     - Parameter valueType: An identifier to describe the type of values encoded in a metric
     */
    public init(id: MetricId, valueType: MetricType, name: String? = nil, description: String? = nil) {
        self.id = id
        self.valueType = valueType
        self.name = name
        self.description = description
    }
}

extension MetricInfo: Codable {
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = .init(
            id: try container.decode(String.self, forKey: .id),
            group: try container.decode(String.self, forKey: .group))
        self.valueType = try container.decode(MetricType.self, forKey: .valueType)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.id, forKey: .id)
        try container.encode(id.group, forKey: .group)
        try container.encode(valueType, forKey: .valueType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }

    enum CodingKeys: Int, CodingKey {
        case id = 1
        case group = 2
        case name = 3
        case description = 4
        case valueType = 5
    }
}

extension MetricInfo: Equatable {

    public static func == (_ lhs: MetricInfo, _ rhs: MetricInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension MetricInfo: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension MetricInfo: Comparable {
    
    public static func < (lhs: MetricInfo, rhs: MetricInfo) -> Bool {
        return lhs.id < rhs.id
    }
}

