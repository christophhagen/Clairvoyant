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

    private let fileWriter: LogFileWriter<T>

    /// The unique random id assigned to each metric to distinguish them
    let uniqueId: Int

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
     The maximum size of the log files (in bytes).

     Log files are split into files of this size. This limit will be slightly exceeded by each file,
     since a new file is begun if the current file already larger than the limit.
     A file always contains complete data points.
     The size can be changed on a metric without affecting other metrics or the observer.
     */
    public var maximumFileSizeInBytes: Int {
        set {
            fileWriter.maximumFileSizeInBytes = newValue
        }
        get {
            fileWriter.maximumFileSizeInBytes
        }
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter fileSize: The maximum size of files in bytes
     */
    init(id: String, observer: MetricObserver, canBeUpdatedByRemote: Bool, name: String?, description: String?, fileSize: Int) {
        let description = MetricDescription(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        self.init(description: description,
                  observer: observer,
                  fileSize: fileSize)
    }

    private init(description: MetricDescription, observer: MetricObserver, fileSize: Int) {
        self.description = description
        let idHash = description.id.hashed()
        self.idHash = idHash
        self.uniqueId = .random()
        self.observer = observer
        self.fileWriter = .init(
            id: description.id,
            hash: idHash,
            folder: observer.logFolder,
            encoder: observer.encoder,
            decoder: observer.decoder,
            fileSize: fileSize)
        fileWriter.set(metric: self)
    }

    init(unobserved id: String, name: String?, description: String?, canBeUpdatedByRemote: Bool, logFolder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder, fileSize: Int) {
        self.description = .init(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description)
        let idHash = id.hashed()
        self.idHash = idHash
        self.uniqueId = .random()
        self.observer = nil
        self.fileWriter = .init(
            id: id,
            hash: idHash,
            folder: logFolder,
            encoder: encoder,
            decoder: decoder,
            fileSize: fileSize)
        fileWriter.set(metric: self)
    }


    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false, fileSize: Int = 10_000_000) async throws {
        guard let observer = MetricObserver.standard else {
            throw MetricError.noObserver
        }
        self.init(
            id: id,
            observer: observer,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name,
            description: description,
            fileSize: fileSize)
        observer.observe(self)
    }

    /**
     Create a new metric.
     - Parameter description: A metric description
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(_ description: MetricDescription, fileSize: Int = 10_000_000) async throws {
        guard let observer = MetricObserver.standard else {
            throw MetricError.noObserver
        }
        self.init(description: description, observer: observer, fileSize: fileSize)
        observer.observe(self)
    }

    func log(_ message: String) {
        guard let observer else {
            print("[\(id)] \(message)")
            return
        }
        observer.log(message, for: id)
    }

    /**
     Fetch the last value set for this metric.

     The last value is either saved internally, or read from a special log file.
     Calls to this function should be sparse, since reading a file from disk is expensive.
     - Returns: The last value of the metric, timestamped, or nil, if no value could be provided.
     */
    public func lastValue() -> Timestamped<T>? {
        if let _lastValue {
            return _lastValue
        }
        return fileWriter.lastValue()
    }

    /**
     Get the history of the metric values within a time period.
     - Parameter range: The date range of interest
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func history(in range: ClosedRange<Date>) -> [Timestamped<T>] {
        fileWriter.getHistory(in: range)
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func fullHistory() -> [Timestamped<T>] {
        fileWriter.getFullHistory()
    }

    @discardableResult
    public func push(to remoteObserver: RemoteMetricObserver) async -> Bool {
        guard let observer else {
            return false
        }
        observer.push(self, to: remoteObserver)
        return true
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging.

     - Note: The value is only written to the log, if it is different to the previous one.
     - Parameter value: The new value to set.
     - Parameter timestamp: The timestamp of the value (defaults to the current time)
     - Returns: `true`, if the value was written, `false`, if it was equal to the last value.
     - Throws: MetricErrors of type `failedToOpenLogFile` or `failedToEncode`
     */
    @discardableResult
    public func update(_ value: T, timestamp: Date = Date()) throws -> Bool {
        try update(.init(timestamp: timestamp, value: value))
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging.
     - Note: The value is only written to the log, if it is different to the previous one.
     - Parameter value: The timestamped value to set
     - Returns: `true`, if the value was written, `false`, if it was equal to the last value.
     - Throws: MetricErrors of type `failedToOpenLogFile` or `failedToEncode`
     */
    @discardableResult
    public func update(_ value: Timestamped<T>) throws -> Bool {
        if let lastValue = lastValue()?.value, lastValue == value.value {
            return false
        }
        let data = try fileWriter.write(value)
        _lastValue = value
        Task {
            await observer?.pushValueToRemoteObservers(data, for: self)
        }
        return true
    }

    public func removeFromObserver() {
        observer?.remove(self)
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
}

extension Metric: GenericMetric {

    public func lastValueData() -> Data? {
        if let _lastValue, let data = try? fileWriter.encode(_lastValue) {
            return data
        }
        return fileWriter.lastValueData()
    }

    public func update(_ dataPoint: Data) throws {
        let value = try fileWriter.decodeTimestampedValue(from: dataPoint)
        try update(value)
    }

    public func history(from startDate: Date, to endDate: Date, maximumValueCount: Int? = nil) -> Data {
        let range = startDate < endDate ? startDate...endDate : endDate...startDate
        let values: [Timestamped<T>] = fileWriter.getHistory(in: range, maximumValueCount: maximumValueCount)
        return (try? fileWriter.encode(values)) ?? Data()
    }
}
