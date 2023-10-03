import Foundation

public protocol GenericMetric {

    /**
     The unique id of the metric.

     The id should be globally unique, so that there are no conflicts when metrics from multiple systems are collected
     */
    var id: MetricId { get }

    /// The information about the metric
    var info: MetricInfo { get }

    /**
     Get the last value data of the metric.

     The data contains a `Timestamped<T>`, where T is the Swift type associated with `info.dataType`.
     - Returns: The encoded data of the last timestamped value.
     */
    func lastValueData() async -> Data?

    /**
     Get the timestamp of the current last value.
     - Returns: The timestamp of the last value
     */
    func lastUpdate() async -> Date?

    /**
     The history of a metric in a specific range.
     - Returns: The encoded data points, i.e. [Timestamped<T>]
     */
    func encodedHistoryData(from startDate: Date, to endDate: Date, maximumValueCount: Int?) async -> Data
}
