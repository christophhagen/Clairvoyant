import Foundation

/**
 A description of a metric published by a server.
 */
public struct MetricDescription {

    /// The unique if of the metric
    public let id: String

    /// The data type of the values in the metric
    public let dataType: MetricType

    /**
     Create a new metric description.
     - Parameter id: The unique if of the metric
     - Parameter dataType: The data type of the values in the metric
     */
    public init(id: String, dataType: MetricType) {
        self.id = id
        self.dataType = dataType
    }
}

extension MetricDescription: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(dataType.stringDescription)
    }
}

extension MetricDescription: Decodable {

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.id = try container.decode(String.self)
        self.dataType = .init(stringDescription: try container.decode(String.self))
    }
}

extension MetricDescription: Equatable {

    public static func == (_ lhs: MetricDescription, _ rhs: MetricDescription) -> Bool {
        lhs.id == rhs.id
    }
}

extension MetricDescription: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
