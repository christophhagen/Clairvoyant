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

    /**
     Indicates that the metric writes values to disk locally.

     If this property is `false`, then no data will be kept apart from the last value of the metric.
     This means that calling `getHistory()` on the metric always returns an empty response.

     This property is useful to create metrics that should only push values to remote observers, where the values are persisted.
     */
    public nonisolated var keepsLocalHistoryData: Bool {
        description.keepsLocalHistoryData
    }

    /// The unique if of the metric
    public nonisolated var id: MetricId {
        description.id
    }

    /// A human-readable name of the metric
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
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter fileSize: The maximum size of files in bytes
     */
    init(id: String, observer: MetricObserver, canBeUpdatedByRemote: Bool, keepsLocalHistoryData: Bool, name: String?, description: String?, fileSize: Int) {
        let description = MetricDescription(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            keepsLocalHistoryData: keepsLocalHistoryData,
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

    init(unobserved id: String, name: String?, description: String?, canBeUpdatedByRemote: Bool, keepsLocalHistoryData: Bool, logFolder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder, fileSize: Int) {
        self.description = .init(
            id: id,
            dataType: T.valueType,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            keepsLocalHistoryData: keepsLocalHistoryData,
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
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false, keepsLocalHistoryData: Bool = true, fileSize: Int = 10_000_000) async throws {
        guard let observer = MetricObserver.standard else {
            throw MetricError.noObserver
        }
        self.init(
            id: id,
            observer: observer,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            keepsLocalHistoryData: keepsLocalHistoryData,
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
        try update(.init(value: value, timestamp: timestamp))
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
    public func update(_ value: Timestamped<T>) throws -> Bool {
        if let lastValue = lastValue() {
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
            try fileWriter.write(value)
        }
        _lastValue = value
        push(value)
        return true
    }

    public func removeFromObserver() {
        observer?.remove(self)
    }

    /**
     Update the metric with a sequence of values.

     The given sequence is sorted and added to the log. Elements older than the last value are skipped.
     */
    public func update<S>(_ values: S) throws where S: Sequence, S.Element == Timestamped<T> {
        let sorted = values.sorted { $0.timestamp }
        var lastValue = lastValue()
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
                try fileWriter.writeOnlyToLog(element)
            }
            valuesToPush.append(element)
            lastValue = element
        }
        _lastValue = lastValue
        if let lastValue {
            _ = try? fileWriter.write(lastValue: lastValue)
        }
        push(valuesToPush)
    }

    // MARK: Pushing to remotes

    /// The remote observers of the metric, with the pending data points for each
    private var remoteObservers: [RemoteMetricObserver : [Timestamped<T>]] = [:]

    /**
     Indicate if there are any values not transmitted to remote observers.
     */
    func hasPendingUpdatesForRemoteObservers() -> Bool {
        remoteObservers.values.contains { !$0.isEmpty }
    }

    /**
     Add a remote to receive all updates to the metric.

     The remote observer must be an instance of a `MetricObserver` exposed through Vapor.
     - SeeAlso: Check the documentation about `ClairvoyantVapor` on how to setup `Vapor` with `Clairvoyant`
     */
    public func addRemoteObserver(_ remoteObserver: RemoteMetricObserver) {
        guard remoteObservers[remoteObserver] == nil else {
            return
        }
        remoteObservers[remoteObserver] = []
    }

    /**
     Try to send all pending values to remote observers.
     If there are no pending values, then no request is made.
     */
    public func pushPendingDataToRemoteObservers() async {
        guard hasPendingUpdatesForRemoteObservers() else {
            return
        }
        await push([])
    }

    private func push(_ value: Timestamped<T>) {
        push([value])
    }

    private func push(_ values: [Timestamped<T>]) {
        guard !remoteObservers.isEmpty else {
            return
        }
        Task {
            await push(values)
        }
    }

    private func push(_ values: [Timestamped<T>]) async {
        await withTaskGroup(of: Void.self) { group in
            for (observer, pending) in remoteObservers {
                guard !values.isEmpty || !pending.isEmpty else {
                    continue
                }
                group.addTask {
                    await self.push(values: pending + values, to: observer)
                }
            }
        }
    }

    private func push(values: [Timestamped<T>], to remote: RemoteMetricObserver) async {
        // 1: Get all pending values
        guard let data = try? fileWriter.encode(values) else {
            remoteObservers[remote] = values
            return
        }
        // 2: Attempt transmission
        guard await self.push(_data: data, toRemoteObserver: remote) else {
            remoteObservers[remote] = values
            return
        }

        // 3: Remove successful transmissions
        remoteObservers[remote] = []
    }

    private func push(_data: Data, toRemoteObserver remoteObserver: RemoteMetricObserver) async -> Bool {
        let remoteUrl = remoteObserver.remoteUrl
        do {
            let url = remoteUrl.appendingPathComponent("push/\(idHash)")
            var request = URLRequest(url: url)
            request.setValue(remoteObserver.authenticationToken.base64, forHTTPHeaderField: "token")
            let (_, response) = try await urlSessionData(.shared, for: request)
            guard let response = response as? HTTPURLResponse else {
                log("Invalid response pushing value to \(remoteUrl.path): \(response)")
                return false
            }
            guard response.statusCode == 200 else {
                log("Failed to push value to \(remoteUrl.path): Response \(response.statusCode)")
                return false
            }
            return true
        } catch {
            log("Failed to push value to \(remoteUrl.path): \(error)")
            return false
        }
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

    public func addDataFromRemote(_ dataPoint: Data) throws {
        let values = try fileWriter.decodeTimestampedValues(from: dataPoint)
        try update(values)
    }

    /**
     The history of a metric in a specific range.
     - Returns: The encoded data points, i.e. [Timestamped<T>]
     */
    public func encodedHistoryData(from startDate: Date, to endDate: Date, maximumValueCount: Int? = nil) -> Data {
        let range = startDate < endDate ? startDate...endDate : endDate...startDate
        let values: [Timestamped<T>] = fileWriter.getHistory(in: range, maximumValueCount: maximumValueCount)
        return (try? fileWriter.encode(values)) ?? Data()
    }
}
