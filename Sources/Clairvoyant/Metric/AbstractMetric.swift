import Foundation

protocol AbstractMetric: AnyObject {

    /**
     The description of the metric.
     */
    var description: MetricDescription { get }

    /**
     The name of the file where the metric is logged.

     This property is the hex representation of the first 16 bytes of the SHA256 hash of the metric id, and is computed once on initialization.
     It is only available internally, since it is not required by the public interface.
     Hashing is performed to prevent special characters from creating issues with file paths.
     */
    var idHash: MetricIdHash { get }

    var dataType: MetricType { get }

    var canBeUpdatedByRemote: Bool { get }

    func getObserver() async -> MetricObserver?

    func set(observer: MetricObserver?) async

    func update(_ dataPoint: TimestampedValueData) async throws

    func lastValueData() async -> Data?

    func history(from startDate: Date, to endDate: Date, maximumValueCount: Int?) async -> Data

    func log(_ message: String) async
}

extension AbstractMetric {

    /**
     The unique id of the metric.

     The id should be globally unique, so that there are no conflicts when metrics from multiple systems are collected
     */
    var id: MetricId {
        description.id
    }
}
