import Foundation

/**
 A metric is a single piece of state that is provided by an application.
 Changes to the state can be used to update the metric,
 which will propagate the information to the collector for logging and further processing.

 The generic type can be any type that conforms to `MetricValue`,
 meaning it can be encoded/decoded and provides a description of its type.
 */
public actor Metric<T> where T: MetricValue {

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
    private weak var observer: MetricObserver?

    /// The cached last value of the metric
    private var _lastValue: Timestamped<T>? = nil


    /// Indicate if the metric can be updated by a remote user
    public nonisolated var canBeUpdatedByRemote: Bool {
        description.canBeUpdatedByRemote
    }

    public nonisolated var id: MetricId {
        description.id
    }

    public nonisolated var name: String? {
        description.name
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    init(id: String, observer: MetricObserver?, canBeUpdatedByRemote: Bool, name: String?, description: String?) async {
        let description = MetricDescription(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        await self.init(description: description,
                        observer: observer)
    }

    init(description: MetricDescription, observer: MetricObserver?) async {
        self.description = description
        self.idHash = description.id.hashed()
        self.observer = nil
        _ = await observer?.observe(metric: self)
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false) async {
        await self.init(id: id, observer: .standard, canBeUpdatedByRemote: canBeUpdatedByRemote, name: name, description: description)
    }

    /**
     Create a new metric.
     - Parameter description: A metric description
     */
    public init(_ description: MetricDescription) async {
        await self.init(description: description, observer: .standard)
    }

    init(unobserved id: String, name: String?, description: String?, canBeUpdatedByRemote: Bool) async {
        await self.init(id: id, observer: nil, canBeUpdatedByRemote: canBeUpdatedByRemote, name: name, description: description)
    }

    /**
     Fetch the last value set for this metric.

     The last value is either saved internally, or read from a special log file.
     Calls to this function should be sparse, since reading a file from disk is expensive.
     - Returns: The last value of the metric, timestamped, or nil, if no value could be provided.
     */
    public func lastValue() async -> Timestamped<T>? {
        if let _lastValue {
            return _lastValue
        }
        return await observer?.getLastValue(for: self)
    }

    /**
     Get the history of the metric values within a time period.
     - Parameter range: The date range of interest
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func getHistory(in range: ClosedRange<Date>) async throws -> [Timestamped<T>] {
        try await observer?.getHistoryFromLog(for: self, in: range) ?? []
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func getFullHistoryFromLogFile() async throws -> [Timestamped<T>] {
        try await observer?.getFullHistoryFromLog(for: self) ?? []
    }

    /**
     Remove the metric from its assigned observer to stop logging updates.
     - Note: If no observer is assigned, then this function does nothing.
     */
    public func removeFromObserver() async {
        await observer?.remove(self)
    }

    @discardableResult
    public func push(to remoteObserver: RemoteMetricObserver) async -> Bool {
        guard let observer else {
            return false
        }
        await observer.push(self, to: remoteObserver)
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
    public func update(_ value: T, timestamp: Date = Date()) async -> Bool {
        if let lastValue = await lastValue()?.value, lastValue == value {
            return true
        }
        let dataPoint = Timestamped(timestamp: timestamp, value: value)
        return await update(dataPoint)
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging to the observer.
     - Parameter value: The timestamped value to set
     - Returns: `true` if the value was stored, `false` if either no observer is registered, or the observer failed to store the value.
     */
    @discardableResult
    public func update(_ value: Timestamped<T>) async -> Bool {
        guard let observer else {
            return false
        }
        guard await observer.update(value, for: self) else {
            return false
        }
        _lastValue = value
        return true
    }
}

extension Metric: AbstractMetric {

    nonisolated var dataType: MetricType {
        T.valueType
    }

    func getObserver() -> MetricObserver? {
        observer
    }

    func set(observer: MetricObserver?) {
        self.observer = observer
    }

    func update(_ dataPoint: TimestampedValueData, decoder: BinaryDecoder) async -> Bool? {
        do {
            let value = try decoder.decode(Timestamped<T>.self, from: dataPoint)
            return await update(value)
        } catch {
            return nil
        }
    }
}
