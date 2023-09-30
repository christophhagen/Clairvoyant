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
     Update a metric with data received from a remote
     - Note: This function is only called if the remote allows remote updating
     - Parameter data: The encoded data points, as an array of timestamped values
     */
    func addDataFromRemote(_ data: Data) async throws

    /**
     The history of a metric in a specific range.
     - Returns: The encoded data points, i.e. [Timestamped<T>]
     */
    func encodedHistoryData(from startDate: Date, to endDate: Date, maximumValueCount: Int?) async -> Data
}
