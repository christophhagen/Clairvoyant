import Foundation

/**
 A metric is a single piece of state that is provided by an application.
 Changes to the state can be used to update the metric,
 which will propagate the information to the collector for logging and further processing.

 The generic type can be any type that conforms to `MetricValue`,
 meaning it can be encoded/decoded and provides a description of its type.
 */
public final class Metric<T> where T: MetricValue {

    /**
     The unique id of the metric.

     The id should be globally unique, so that there are no conflicts when metrics from multiple systems are collected
     */
    public let id: String

    /**
     The name of the file where the metric is logged.

     This property is the hex representation of the first 16 bytes of the SHA256 hash of the metric id, and is computed once on initialization.
     It is only available internally, since it is not required by the public interface.
     Hashing is performed to prevent special characters from creating issues with file paths.
     */
    let idHash: MetricIdHash

    /**
     A reference to the collector of the metric for logging and processing.
     */
    weak var observer: MetricObserver?

    private var _lastValue: Timestamped<T>? = nil

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     */
    public init(_ id: String) {
        self.id = id
        self.observer = MetricObserver.standard
        self.idHash = InternalMetricId.hash(id)
        _lastValue = observer?.getLastValue(for: self)
    }

    init(unobserved id: String) {
        self.id = id
        self.observer = nil
        self.idHash = InternalMetricId.hash(id)
    }

    @discardableResult
    public func update(_ value: T, timestamp: Date = Date()) -> Bool {
        guard let observer else {
            return false
        }
        if let lastValue = _lastValue?.value, lastValue == value {
            return true
        }
        let dataPoint = Timestamped(timestamp: timestamp, value: value)
        guard observer.update(dataPoint, for: self) else {
            return false
        }
        _lastValue = dataPoint
        return true
    }

    public func lastValue() -> Timestamped<T>? {
        _lastValue ?? observer?.getLastValue(for: self)
    }

    public func getHistory(in range: ClosedRange<Date>) throws -> [Timestamped<T>] {
        try observer?.getHistoryFromLog(for: self, in: range) ?? []
    }

    public func getFullHistoryFromLogFile() throws -> [Timestamped<T>] {
        try observer?.getFullHistoryFromLog(for: self) ?? []
    }
}

extension Metric: AbstractMetric {

}
