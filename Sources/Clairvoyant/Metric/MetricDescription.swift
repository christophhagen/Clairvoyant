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
     Indicates that this metric allows receiving updates from remotes.

     If this property is `true`, then the metric can be updated externally through the `push` route of a Vapor observer.
     - Note: This property is only relevant if the functionality of `ClairvoyantVapor` is used.
     */
    public let canBeUpdatedByRemote: Bool

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
     Create a new metric description.
     - Parameter id: The unique if of the metric
     - Parameter dataType: The data type of the values in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     */
    public init(id: String, dataType: MetricType, canBeUpdatedByRemote: Bool = false, keepsLocalHistoryData: Bool = true, name: String? = nil, description: String? = nil) {
        self.id = id
        self.dataType = dataType
        self.canBeUpdatedByRemote = canBeUpdatedByRemote
        self.keepsLocalHistoryData = keepsLocalHistoryData
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
        case canBeUpdatedByRemote = 5
        case keepsLocalHistoryData = 6
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
