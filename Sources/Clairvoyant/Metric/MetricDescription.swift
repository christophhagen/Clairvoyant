import Foundation

/**
 A description of a metric published by a server.
 */
public struct MetricDescription {

    /// The unique if of the metric
    public let id: String

    /// The data type of the values in the metric
    public let dataType: MetricType

    /// A name to display for the metric
    public let name: String?

    /// A description of the metric content
    public let description: String?

    /**
     Create a new metric description.
     - Parameter id: The unique if of the metric
     - Parameter dataType: The data type of the values in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    public init(id: String, dataType: MetricType, name: String? = nil, description: String? = nil) {
        self.id = id
        self.dataType = dataType
        self.name = name
        self.description = description
    }
}

extension MetricDescription: Codable {

    enum CodingKeys: Int, CodingKey {
        case id = 1
        case dataType = 2
        case name = 3
        case description = 4
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
