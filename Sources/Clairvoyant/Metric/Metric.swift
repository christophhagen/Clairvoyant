import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias MetricChangeCallback<T> = (Timestamped<T>) -> Void

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
    public nonisolated let info: MetricInfo

    /**
     The name of the file where the metric is logged.

     This property is the hex representation of the first 16 bytes of the SHA256 hash of the metric id, and is computed once on initialization.
     It is only available internally, since it is not required by the public interface.
     Hashing is performed to prevent special characters from creating issues with file paths.
     */
    public nonisolated let idHash: MetricIdHash

    /// The cached last value of the metric
    private var _lastValue: Timestamped<T>? = nil

    private let fileWriter: LogFileWriter<T>

    private var changeCallbacks: [MetricChangeCallback<T>] = []

    /**
     Indicates that the metric writes values to disk locally.

     If this property is `false`, then no data will be kept apart from the last value of the metric.
     This means that calling `getHistory()` on the metric always returns an empty response.

     This property is useful to create metrics that should only push values to remote observers, where the values are persisted.
     */
    public nonisolated var keepsLocalHistoryData: Bool {
        info.keepsLocalHistoryData
    }

    /// The unique id of the metric
    public nonisolated var id: MetricId {
        info.id
    }

    /// A human-readable name of the metric
    public nonisolated var name: String? {
        info.name
    }
    
    /// The number of bytes used for the metric history on disk
    public var sizeOnDisk: Int {
        fileWriter.usedDiskSpace
    }

    /**
     The maximum size of the log files (in bytes).

     Log files are split into files of this size. This limit will be slightly exceeded by each file,
     since a new file is begun if the current file already larger than the limit.
     A file always contains complete data points.
     The size can be changed on a metric without affecting other metrics or the observer.
     */
    public var maximumFileSizeInBytes: Int {
        fileWriter.maximumFileSizeInBytes
    }
    
    /**
     Set the maximum size of the log files (in bytes).

     Log files are split into files of this size. This limit will be slightly exceeded by each file,
     since a new file is begun if the current file already larger than the limit.
     A file always contains complete data points.
     The size can be changed on a metric without affecting other metrics or the observer.
     */
    public func setMaximumFileSize(_ bytes: Int) {
        fileWriter.maximumFileSizeInBytes = bytes
    }

    /**
     Create a new metric from an observer.

     This function is only called from within a `MetricObserver`, because it doesn't register the metric with the provided observer.

     - Parameter id: The unique id of the metric.
     - Parameter observer: The metric observer calling this initializer
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter fileSize: The maximum size of files in bytes
     */
    init(id: String, calledFromObserver observer: MetricObserver, keepsLocalHistoryData: Bool, name: String?, description: String?, fileSize: Int) {
        let info = MetricInfo(
            id: id,
            dataType: T.valueType,
            keepsLocalHistoryData: keepsLocalHistoryData,
            name: name,
            description: description)
        self.init(info: info,
                  observer: observer,
                  fileSize: fileSize)
    }

    /**
     Internal constructor, does not register with metric observer.
     - Parameter info: A metric info
     - Parameter fileSize: The maximum size of files in bytes
     */
    private init(info: MetricInfo, observer: MetricObserver, fileSize: Int) {
        self.info = info
        let idHash = info.id.hashed()
        self.idHash = idHash
        self.fileWriter = .init(
            id: info.id,
            hash: idHash,
            folder: observer.logFolder,
            encoder: observer.encoder,
            decoder: observer.decoder,
            fileSize: fileSize,
            logClosure: { [weak observer] message in
                guard let observer else {
                    print("[\(info.id)] " + message)
                    return
                }
                await observer.log(message, for: info.id)
            })
    }

    /**
     Create a new log metric for a `MetricObserver`
     - Note: This constructor does not link back to an observer for logging errors, since this would just divert back to the this metric again.
     */
    init(logId id: String, name: String?, description: String?, keepsLocalHistoryData: Bool, logFolder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder, fileSize: Int) {
        self.info = .init(
            id: id,
            dataType: T.valueType,
            keepsLocalHistoryData: keepsLocalHistoryData,
            name: name,
            description: description)
        let idHash = id.hashed()
        self.idHash = idHash
        self.fileWriter = .init(
            id: id,
            hash: idHash,
            folder: logFolder,
            encoder: encoder,
            decoder: decoder,
            fileSize: fileSize,
            logClosure: { message in
                print("[\(id)] " + message)
            })
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter fileSize: The maximum size of files in bytes
     - Note: This initializer crashes with a `fatalError`, if `MetricObserver.standard` has not been set.
     - Note: This initializer crashes with a `fatalError`, if a metric with the same `id` is already registered with the observer.
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, keepsLocalHistoryData: Bool = true, fileSize: Int = 10_000_000) {
        guard let observer = MetricObserver.standard else {
            fatalError("Initialize the standard observer first by setting `MetricObserver.standard` before creating a metric")
        }
        let info = MetricInfo(
            id: id,
            dataType: T.valueType,
            keepsLocalHistoryData: keepsLocalHistoryData,
            name: name,
            description: description)
        self.init(info: info, observer: observer, fileSize: fileSize)
        observer.observe(self)
    }

    /**
     Create a new metric.
     - Parameter info: A metric info
     - Parameter fileSize: The maximum size of files in bytes
     - Note: This initializer crashes with a `fatalError`, if `MetricObserver.standard` has not been set.
     - Note: This initializer crashes with a `fatalError`, if `info.dataType` does not match `T.valueType`
     - Note: This initializer crashes with a `fatalError`, if a metric with the same `id` is already registered with the observer.
     */
    public init(_ info: MetricInfo, fileSize: Int = 10_000_000) {
        guard info.dataType == T.valueType else {
            fatalError("Creating metric of type `\(T.self)` with mismatching data type '\(info.dataType)'")
        }
        guard let observer = MetricObserver.standard else {
            fatalError("Initialize the standard observer first by setting `MetricObserver.standard` before creating a metric")
        }
        self.init(info: info, observer: observer, fileSize: fileSize)
        observer.observe(self)
    }

    private func log(_ message: String) async {
        await fileWriter.logClosure(message)
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

    /**
     Get the history of the metric values within a time period.
     - Parameter range: The date range of interest
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func history(in range: ClosedRange<Date>, limit: Int? = nil) async -> [Timestamped<T>] {
        await history(from: range.lowerBound, to: range.upperBound, limit: limit)
    }
    
    /**
     Get the history of the metric values within a time period.
     - Parameter start: The start date
     - Parameter end: The end date of the range
     - Returns: The values logged within the given date range.
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func history(from start: Date, to end: Date, limit: Int? = nil) async -> [Timestamped<T>] {
        await fileWriter.getHistory(from: start, to: end, maximumValueCount: limit)
    }
    
    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    @available(*, deprecated, renamed: "history", message: "Renamed to history()")
    public func fullHistory() async -> [Timestamped<T>] {
        await history()
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func history() async -> [Timestamped<T>] {
        await fileWriter.getFullHistory()
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
    public func update(_ value: T, timestamp: Date = Date()) async throws -> Bool {
        try await update(.init(value: value, timestamp: timestamp))
    }

    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging.
     - Note: The value is only written to the log, if it is different to and more recent than the previous one.
     - Parameter value: The timestamped value to set
     - Returns: `true`, if the value was written, `false`, if it was equal to the last value.
     - Throws: MetricErrors of type `failedToOpenLogFile` or `failedToEncode`
     */
    @discardableResult
    public func update(_ value: Timestamped<T>) async throws -> Bool {
        if let lastValue = await lastValue() {
            guard value.value != lastValue.value else {
                // Skip duplicate elements to save space
                return false
            }
            guard value.timestamp >= lastValue.timestamp else {
                // Skip older data points to ensure that log is always sorted
                return false
            }
        }
        if keepsLocalHistoryData {
            try await fileWriter.write(value)
        }
        _lastValue = value
        changeCallbacks.forEach { $0(value) }
        return true
    }

    /**
     Update the metric with a sequence of values.

     The given sequence is sorted and added to the log. Elements older than the last value are skipped.
     */
    public func update<S>(_ values: S) async throws where S: Sequence, S.Element == Timestamped<T> {
        let sorted = values.sorted { $0.timestamp }
        var lastValue = await lastValue()
        var valuesToPush: [Timestamped<T>] = []
        for element in sorted {
            if let lastValue {
                guard element.value != lastValue.value else {
                    // Skip duplicate elements to save space
                    continue
                }
                guard element.timestamp >= lastValue.timestamp else {
                    // Skip older data points to ensure that log is always sorted
                    continue
                }
            }
            if keepsLocalHistoryData {
                try await fileWriter.writeOnlyToLog(element)
            }
            valuesToPush.append(element)
            lastValue = element
        }
        _lastValue = lastValue
        if let lastValue {
            _ = try? await fileWriter.write(lastValue: lastValue)
            changeCallbacks.forEach { $0(lastValue) }
        }
    }

    // MARK: Deleting history

    /**
     Delete all historic values before a specific date.
     - Parameter date: The date before which all values should be deleted.
     - Throws: `MetricError`
     */
    public func deleteHistory(before date: Date) async throws {
        try await fileWriter.deleteHistory(before: date)
        if let last = await lastValue()?.timestamp, last < date {
            try await fileWriter.deleteLastValueFile()
            _lastValue = nil
        }
    }

    // MARK: Change callbacks

    public func onChange(perform callback: @escaping MetricChangeCallback<T>) {
        changeCallbacks.append(callback)
    }

    public func removeAllChangeListeners() {
        changeCallbacks.removeAll()
    }
}

extension Metric: AbstractMetric {

}

extension Metric: GenericMetric {

    public func lastUpdate() async -> Date? {
        await lastValue()?.timestamp
    }

    public func lastValueData() async -> Data? {
        if let _lastValue, let data = try? await fileWriter.encode(_lastValue) {
            return data
        }
        return await fileWriter.lastValueData()
    }

    /**
     The history of a metric in a specific range.
     - Returns: The encoded data points, i.e. [Timestamped<T>]
     */
    public func encodedHistoryData(from startDate: Date, to endDate: Date, maximumValueCount: Int? = nil) async -> Data {
        let values: [Timestamped<T>] = await fileWriter.getHistory(from: startDate, to: endDate, maximumValueCount: maximumValueCount)
        return (try? await fileWriter.encode(values)) ?? Data()
    }
}
