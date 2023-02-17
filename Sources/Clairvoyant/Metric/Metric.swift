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
    public nonisolated let description: MetricDescription

    /**
     The name of the file where the metric is logged.

     This property is the hex representation of the first 16 bytes of the SHA256 hash of the metric id, and is computed once on initialization.
     It is only available internally, since it is not required by the public interface.
     Hashing is performed to prevent special characters from creating issues with file paths.
     */
    nonisolated let idHash: MetricIdHash

    /**
     A reference to the collector of the metric for logging and processing.
     */
    private weak var observer: MetricObserver?

    /// The cached last value of the metric
    private var _lastValue: Timestamped<T>? = nil

    private let fileWriter: LogFileWriter

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
    init(id: String, observer: MetricObserver, canBeUpdatedByRemote: Bool, name: String?, description: String?) {
        let description = MetricDescription(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        self.init(description: description,
                  observer: observer)
    }

    private init(description: MetricDescription, observer: MetricObserver) {
        self.description = description
        let idHash = description.id.hashed()
        self.idHash = idHash
        self.observer = observer
        self.fileWriter = .init(
            id: description.id,
            hash: idHash,
            folder: observer.logFolder,
            encoder: observer.encoder,
            decoder: observer.decoder)
        Task {
            await fileWriter.set(metric: self)
        }
    }

    init(unobserved id: String, name: String?, description: String?, canBeUpdatedByRemote: Bool, logFolder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder) {
        self.description = .init(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        let idHash = id.hashed()
        self.idHash = idHash
        self.observer = nil
        self.fileWriter = .init(
            id: id,
            hash: idHash,
            folder: logFolder,
            encoder: encoder,
            decoder: decoder)
        Task {
            await fileWriter.set(metric: self)
        }
    }


    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false) async throws {
        guard let observer = MetricObserver.standard else {
            throw MetricError.noObserver
        }
        self.init(
            id: id,
            observer: observer,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        try await observer.observe(self)
    }

    /**
     Create a new metric.
     - Parameter description: A metric description
     */
    public init(_ description: MetricDescription) async throws {
        guard let observer = MetricObserver.standard else {
            throw MetricError.noObserver
        }
        self.init(description: description, observer: observer)
        try await observer.observe(self)
    }

    func log(_ message: String) {
        guard let observer else {
            print("[\(id)] \(message)")
            return
        }
        Task {
            await observer.log(message, for: id)
        }
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
        return await fileWriter.lastValue()
    }

    func lastValueData() async -> Data? {
        if let _lastValue {
            return try? await fileWriter.encode(_lastValue)
        }
        return await fileWriter.lastValueData()
    }

    public func history(from startDate: Date, to endDate: Date, maximumValueCount: Int? = nil) async -> Data {
        await fileWriter.getHistoryData(startingFrom: startDate, upTo: endDate, maximumValueCount: maximumValueCount)
    }

    /**
     Get the history of the metric values within a time period.
     - Parameter range: The date range of interest
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func history(in range: ClosedRange<Date>) async -> [Timestamped<T>] {
        await fileWriter.getHistory(in: range)
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func fullHistory() async -> [Timestamped<T>] {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date()
        return await history(in: start...end)
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

     This function will create a new timestamped value and forward it for logging.
     - Parameter value: The new value to set.
     - Parameter timestamp: The timestamp of the value (defaults to the current time)
     */
    public func update(_ value: T, timestamp: Date = Date()) async throws {
        if let lastValue = await lastValue()?.value, lastValue == value {
            return
        }
        let dataPoint = Timestamped(timestamp: timestamp, value: value)
        try await update(dataPoint)
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging.
     - Parameter value: The timestamped value to set
     */
    public func update(_ value: Timestamped<T>) async throws {
        let data = try await fileWriter.write(value)
        _lastValue = value
        await observer?.pushValueToRemoteObservers(data, for: self)
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

    func update(_ dataPoint: TimestampedValueData) async throws {
        let value: Timestamped<T> = try await fileWriter.decode(dataPoint)
        try await update(value)
    }
}
