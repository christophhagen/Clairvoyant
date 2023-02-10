import Foundation

/**
 An metric to observe. A metric can either be local (i.e. the application updates it),
 or remote (i.e. updates are received from some other metric provider.

 This class provides the common set of functionality for both cases.
 */
public class AnyMetric<T> where T: MetricValue {

    /**
     The main info about the metric.
     */
    public let description: MetricDescription

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

    /// Indicate if the metric is a remote metric
    var isRemote: Bool {
        false
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    convenience init(id: String, observer: MetricObserver?, name: String?, description: String?) {
        self.init(description: .init(id: id, dataType: T.valueType, name: name, description: description),
                  observer: observer)
    }

    init(description: MetricDescription, observer: MetricObserver?) {
        self.description = description
        self.idHash = description.id.hashed()
        self.observer = nil
        _ = observer?.observe(metric: self)
    }

    /**
     Create a new metric.
     - Parameter description: A metric description
     */
    public convenience init(_ description: MetricDescription) {
        self.init(description: description, observer: .standard)
    }

    /**
     Fetch the last value set for this metric.

     The last value is either saved internally, or read from a special log file.
     Calls to this function should be sparse, since reading a file from disk is expensive.
     - Returns: The last value of the metric, timestamped, or nil, if no value could be provided.
     */
    public func lastValue() -> Timestamped<T>? {
        observer?.getLastValue(for: self)
    }

    /**
     Get the history of the metric values within a time period.
     - Parameter range: The date range of interest
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func getHistory(in range: ClosedRange<Date>) throws -> [Timestamped<T>] {
        try observer?.getHistoryFromLog(for: self, in: range) ?? []
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func getFullHistoryFromLogFile() throws -> [Timestamped<T>] {
        try observer?.getFullHistoryFromLog(for: self) ?? []
    }

    /**
     Remove the metric from its assigned observer to stop logging updates.
     - Note: If no observer is assigned, then this function does nothing.
     */
    public func removeFromObserver() {
        observer?.remove(self)
    }

    @discardableResult
    public func push(to remoteObserver: RemoteMetricObserver) -> Bool {
        guard let observer else {
            return false
        }
        observer.push(self, to: remoteObserver)
        return true
    }
}

extension AnyMetric: AbstractMetric {

    var dataType: MetricType {
        T.valueType
    }

    func verifyEncoding(of data: Data, decoder: BinaryDecoder) -> Bool {
        (try? decoder.decode(T.self, from: data)) != nil
    }
}
