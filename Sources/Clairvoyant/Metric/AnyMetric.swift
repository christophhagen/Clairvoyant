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

    /// The cached last value of the metric
    private var _lastValue: Timestamped<T>? = nil

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
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    public convenience init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil) {
        self.init(id: id, observer: .standard, name: name, description: description)
    }

    /**
     Create a new metric.
     - Parameter description: A metric description
     */
    public convenience init(_ description: MetricDescription) {
        self.init(description: description, observer: .standard)
    }

    convenience init(unobserved id: String, name: String?, description: String?) {
        self.init(id: id, observer: nil, name: name, description: description)
    }

    /**
     Fetch the last value set for this metric.

     The last value is either saved internally, or read from a special log file.
     Calls to this function should be sparse, since reading a file from disk is expensive.
     - Returns: The last value of the metric, timestamped, or nil, if no value could be provided.
     */
    public func lastValue() -> Timestamped<T>? {
        _lastValue ?? observer?.getLastValue(for: self)
    }

    func didUpdate(with value: Timestamped<T>) {
        _lastValue = value
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

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging to the observer.
     - Parameter value: The new value to set.
     - Parameter timestamp: The timestamp of the value (defaults to the current time)
     - Returns: `true` if the value was stored, `false` if either no observer is registered, or the observer failed to store the value.
     */
    @discardableResult
    public func update(_ value: T, timestamp: Date = Date()) -> Bool {
        if let lastValue = lastValue()?.value, lastValue == value {
            return true
        }
        let dataPoint = Timestamped(timestamp: timestamp, value: value)
        return update(dataPoint)
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging to the observer.
     - Parameter value: The timestamped value to set
     - Returns: `true` if the value was stored, `false` if either no observer is registered, or the observer failed to store the value.
     */
    @discardableResult
    public func update(_ value: Timestamped<T>) -> Bool {
        guard let observer else {
            return false
        }
        guard observer.update(value, for: self) else {
            return false
        }
        _lastValue = value
        return true
    }
}

extension AnyMetric: AbstractMetric {

    var dataType: MetricType {
        T.valueType
    }

    func update(_ dataPoint: TimestampedValueData, decoder: BinaryDecoder) -> Bool? {
        do {
            let value = try decoder.decode(Timestamped<T>.self, from: dataPoint)
            return update(value)
        } catch {
            return nil
        }
    }
}
