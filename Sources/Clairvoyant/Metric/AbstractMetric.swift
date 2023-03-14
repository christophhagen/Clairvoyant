import Foundation

protocol AbstractMetric: AnyObject, GenericMetric {

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

    var uniqueId: Int { get }

    var dataType: MetricType { get }

    func getObserver() async -> MetricObserver?

    func set(observer: MetricObserver?) async

    func log(_ message: String) async
}
