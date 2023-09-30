import Foundation

/**
 A description of a metric published by a server.
 */
public struct MetricInfo {

    /// The unique if of the metric
    public let id: String

    /// The data type of the values in the metric
    public let dataType: MetricType

    /**
     Indicates that the metric writes values to disk locally.

     If this property is `false`, then no data will be kept apart from the last value of the metric.
     This means that calling `getHistory()` on the metric always returns an empty response.
     */
    public let keepsLocalHistoryData: Bool

    /// A name to display for the metric
    public let name: String?

    /// A description of the metric content
    public let description: String?

    /**
     Create a new metric info.
     - Parameter id: The unique if of the metric
     - Parameter dataType: The data type of the values in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     */
    public init(id: String, dataType: MetricType, keepsLocalHistoryData: Bool = true, name: String? = nil, description: String? = nil) {
        self.id = id
        self.dataType = dataType
        self.keepsLocalHistoryData = keepsLocalHistoryData
        self.name = name
        self.description = description
    }
}

extension MetricInfo: Codable {

    enum CodingKeys: Int, CodingKey {
        case id = 1
        case dataType = 2
        case name = 3
        case description = 4
        case keepsLocalHistoryData = 6
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
