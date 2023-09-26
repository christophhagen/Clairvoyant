import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    nonisolated let idHash: MetricIdHash

    /// The cached last value of the metric
    private var _lastValue: Timestamped<T>? = nil

    private let fileWriter: LogFileWriter<T>

    /// Indicate if the metric can be updated by a remote user
    public nonisolated var canBeUpdatedByRemote: Bool {
        info.canBeUpdatedByRemote
    }

    /**
     Indicates that the metric writes values to disk locally.

     If this property is `false`, then no data will be kept apart from the last value of the metric.
     This means that calling `getHistory()` on the metric always returns an empty response.

     This property is useful to create metrics that should only push values to remote observers, where the values are persisted.
     */
    public nonisolated var keepsLocalHistoryData: Bool {
        info.keepsLocalHistoryData
    }

    /// The unique if of the metric
    public nonisolated var id: MetricId {
        info.id
    }

    /// A human-readable name of the metric
    public nonisolated var name: String? {
        info.name
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
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter fileSize: The maximum size of files in bytes
     */
    init(id: String, calledFromObserver observer: MetricObserver, canBeUpdatedByRemote: Bool, keepsLocalHistoryData: Bool, name: String?, description: String?, fileSize: Int) {
        let info = MetricInfo(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
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
    init(logId id: String, name: String?, description: String?, canBeUpdatedByRemote: Bool, keepsLocalHistoryData: Bool, logFolder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder, fileSize: Int) {
        self.info = .init(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
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
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter fileSize: The maximum size of files in bytes
     - Note: This initializer crashes with a `fatalError`, if `MetricObserver.standard` has not been set.
     - Note: This initializer crashes with a `fatalError`, if a metric with the same `id` is already registered with the observer.
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false, keepsLocalHistoryData: Bool = true, fileSize: Int = 10_000_000) {
        guard let observer = MetricObserver.standard else {
            fatalError("Initialize the standard observer first by setting `MetricObserver.standard` before creating a metric")
        }
        let info = MetricInfo(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
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
    public init(_ info: MetricInfo, fileSize: Int = 10_000_000) async {
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
    public func history(in range: ClosedRange<Date>) async -> [Timestamped<T>] {
        await fileWriter.getHistory(in: range)
    }

    /**
     Get the entire history of the metric values.
     - Returns: The values logged for the metric
     - Throws: `MetricError.failedToOpenLogFile`, if the log file on disk could not be opened. `MetricError.logFileCorrupted` if data in the log file could not be decoded.
     */
    public func fullHistory() async -> [Timestamped<T>] {
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
        // TODO: Perform this on a separate queue?
        // It may greatly increase the time needed to finish updating the value
        await notifyRemoteObservers()
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
        }
        // TODO: Perform this on a separate queue?
        // It may greatly increase the time needed to finish updating the value
        await notifyRemoteObservers()
    }

    // MARK: Remote notifications

    /// The remote observers of the metric
    private var remoteObservers: Set<RemoteMetricObserver> = []

    /**
     Add a remote to receive notifications when an update to the metric occurs.

     The remote observer must be an instance of a `MetricObserver` exposed through Vapor.
     - SeeAlso: Check the documentation about `ClairvoyantVapor` on how to setup `Vapor` with `Clairvoyant`
     - Note: Observers are distinguished by their url, and only one observer can be presented for each unique url.
     - Returns: `true`, if the observer was added. `false`, if an observer for the same url already exists.
     */
    @discardableResult
    public func addRemoteObserver(_ remoteObserver: RemoteMetricObserver) -> Bool {
        remoteObservers.insert(remoteObserver).inserted
    }

    /**
     Try to send all pending values to remote observers.

     - Note: This function is called automatically when the metric value changes.
     There is usually no need to call this function manually.
     */
    public func notifyRemoteObservers() async {
        guard !remoteObservers.isEmpty else {
            return
        }
        await withTaskGroup(of: Void.self) { group in
            for observer in remoteObservers {
                group.addTask {
                    await self.push(to: observer)
                }
            }
        }
    }

    @discardableResult
    private func push(to remoteObserver: RemoteMetricObserver) async -> Bool {
        let remoteUrl = remoteObserver.remoteUrl
        do {
            let url = remoteUrl.appendingPathComponent("push/\(idHash)")
            var request = URLRequest(url: url)
            request.setValue(remoteObserver.authenticationToken, forHTTPHeaderField: "token")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                await log("Invalid response pushing value to \(remoteUrl.path): \(response)")
                return false
            }
            guard response.statusCode == 200 else {
                await log("Failed to push value to \(remoteUrl.path): Response \(response.statusCode)")
                return false
            }
            return true
        } catch {
            await log("Failed to push value to \(remoteUrl.path): \(error)")
            return false
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
}

extension Metric: AbstractMetric {

}

extension Metric: GenericMetric {

    public func lastValueData() async -> Data? {
        if let _lastValue, let data = try? await fileWriter.encode(_lastValue) {
            return data
        }
        return await fileWriter.lastValueData()
    }

    public func addDataFromRemote(_ dataPoint: Data) async throws {
        let values = try fileWriter.decodeTimestampedValues(from: dataPoint)
        try await update(values)
    }

    /**
     The history of a metric in a specific range.
     - Returns: The encoded data points, i.e. [Timestamped<T>]
     */
    public func encodedHistoryData(from startDate: Date, to endDate: Date, maximumValueCount: Int? = nil) async -> Data {
        let range = startDate < endDate ? startDate...endDate : endDate...startDate
        let values: [Timestamped<T>] = await fileWriter.getHistory(in: range, maximumValueCount: maximumValueCount)
        return (try? await fileWriter.encode(values)) ?? Data()
    }
}
