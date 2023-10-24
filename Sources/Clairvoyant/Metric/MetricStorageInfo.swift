import Foundation


/**
 A description of a metric published by a server.
 */
struct MetricStorageInfo {

    /// The unique if of the metric
    let id: MetricId
    
    let hash: MetricIdHash

    /// The data type of the values in the metric
    let dataType: MetricType

    /**
     Indicates that the metric writes values to disk locally.

     If this property is `false`, then no data will be kept apart from the last value of the metric.
     This means that calling `getHistory()` on the metric always returns an empty response.
     */
    let keepsLocalHistoryData: Bool

    /// A name to display for the metric
    let name: String?

    /// A description of the metric content
    let description: String?

    init(info: MetricInfo, hash: MetricIdHash) {
        self.id = info.id
        self.hash = hash
        self.dataType = info.dataType
        self.keepsLocalHistoryData = info.keepsLocalHistoryData
        self.name = info.name
        self.description = info.description
    }
}

extension MetricStorageInfo: Codable {
    
}
