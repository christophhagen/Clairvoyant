import Foundation
import CBORCoding
import Vapor

private typealias TimestampedValueData = Data

typealias MetricIdHash = String

public final class MetricObserver {

    /**
     The default observer, to which created metrics are added.

     Set this observer to automatically observe all metrics created using `Metric(id:)`.
     */
    public static var standard: MetricObserver?

    /// The directory where the log files and other internal data is to be stored.
    public let logFolder: URL

    /// The authentication manager for access to metric information
    public let accessManager: MetricRequestAccessManager

    /// The encoder used to convert data points to binary data for logging
    private let encoder: BinaryEncoder

    /// The decoder used to decode log entries when providing history data
    private let decoder: BinaryDecoder

    /// The internal file manager used to access files
    private let fileManager: FileManager = .default

    /// The internal metric used for logging
    private let logMetric: Metric<String>

    /// The unique random id assigned to each observer to distinguish them
    private let uniqueId: Int

    /**
     The metrics observed by this instance.

     The key is the metric `name`
     */
    private var observedMetrics: [MetricId : AbstractMetric] = [:]

    /**
     The remote observers of metrics logged with this instance.

     All updates to metrics are pushed to each remote observer.
     */
    private var remoteObservers: [MetricId : Set<RemoteMetricObserver>] = [:]

    /**
     Create a new observer.

     Each observer creates a metric with the id `logMetricId` to log internal errors.
     It is also possible to write to this metric using ``log(_:)``.

     - Parameter logFolder: The directory where the log files and other internal data is to be stored.
     - Parameter accessManager: The handler of authentication to access metric data
     - Parameter logMetricId: The id of the metric for internal log data
     */
    public init(
        logFolder: URL,
        accessManager: MetricRequestAccessManager,
        logMetricId: String,
        encoder: BinaryEncoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970),
        decoder: BinaryDecoder = CBORDecoder()) {

        self.uniqueId = .random()
        self.encoder = encoder
        self.decoder = decoder
        self.logFolder = logFolder
        self.accessManager = accessManager
        self.logMetric = .init(unobserved: logMetricId)
        observe(logMetric)
    }

    private let byteCountLength = 2

    // MARK: File paths

    private func logFileUrl(for metricLogFileId: MetricIdHash) -> URL {
        logFolder.appendingPathComponent(metricLogFileId)
    }

    private func lastValueFileUrl(for metricLogFileId: MetricIdHash) -> URL {
        logFolder.appendingPathComponent(metricLogFileId + "-last")
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func ensureExistenceOfLogFolder() -> Error? {
        guard !exists(logFolder) else {
            return nil
        }
        do {
            try fileManager.createDirectory(at: logFolder, withIntermediateDirectories: true)
        } catch {
            return error
        }
        return nil
    }

    // MARK: Adding metrics

    /**
     Create a metric and add it to the observer.
     - Parameter id: The id of the metric.
     - Returns: The created metric.
     */
    public func addMetric<T>(id: String) -> Metric<T> where T: MetricValue {
        let metric = Metric<T>(id)
        observe(metric)
        return metric
    }

    /**
     Observe a metric.

     Calling this function with a metric will cause all updates to the metric to be forwarded to this observer,
     which will log it and provide it over the web interface.
     - Parameter metric: The metric to observe.
     - Returns: `true`, if the metric was added to the observer, `false` if a metric with the same `id` already exists.
     - Note: If the metric was previously observed by another observer, then it will be removed from the old observer.
     */
    @discardableResult
    public func observe<T>(_ metric: Metric<T>) -> Bool {
        observe(metric: metric)
    }

    /**
     Observe a metric published by a remote instance.

     Observing a remote metric merely states an intent to accept updates from another instance.
     The remote instance is responsible for pushing updates to the local observer.
     - Parameter metric: The metric to observe.
     - Returns: `true`, if the metric was added to the observer, `false` if a metric with the same `id` already exists.
     - Note: If the metric was previously observed by another observer, then it will be removed from the old observer.
     */
    @discardableResult
    public func observe<T>(_ metric: RemoteMetric<T>) -> Bool {
        observe(metric: metric)
    }

    func observe(metric: AbstractMetric) -> Bool {
        guard observedMetrics[metric.id] == nil else {
            return false
        }
        if let oldObserver = metric.observer {
            oldObserver.remove(metric)
        }
        metric.observer = self
        observedMetrics[metric.id] = metric
        return true
    }

    /**
     Stop observing a metric.

     Calling this function with a metric will prevent the metric from being logged by this observer.
     - Parameter metric: The metric to remove.
     - Note: If the metric was not previously observed by this observer, then it will not be changed, and may still be assigned to a different observer.
     */
    public func remove<T>(metric: AnyMetric<T>) {
        remove(metric)
    }

    func remove(_ metric: AbstractMetric) {
        guard metric.observer == self else {
            return
        }
        observedMetrics[metric.id] = nil
        metric.observer = nil
    }

    // MARK: Logging

    /**
     Log a message to the internal log metric.
     - Parameter message: The log entry to add.
     - Returns: `true` if the message was added to the log, `false` if the message could not be saved.
     */
    @discardableResult
    public func log(_ message: String) -> Bool {
        print(message)
        return logMetric.update(message)
    }

    private func logError(_ message: String, for metric: MetricId) {
        let entry = "[\(metric)] " + message
        print(entry)

        // Prevent infinite recursions
        guard metric == logMetric.id else {
            return
        }
        logMetric.update(entry)
    }

    // MARK: Update metric values

    func getMetric(with id: MetricId) throws -> AbstractMetric {
        guard let metric = observedMetrics[id] else {
            throw MetricError.unknownMetric
        }
        return metric
    }

    func update<T>(_ value: Timestamped<T>, for metric: Metric<T>) -> Bool where T: MetricValue {
        if let error = ensureExistenceOfLogFolder() {
            logError("Failed to create log folder: \(error)", for: metric.id)
            return false
        }

        // Encode value to data
        let dataPoint: TimestampedValueData
        do {
            let data = try encoder.encode(value.value)
            let timestampData = try encoder.encode(value.timestamp.timeIntervalSince1970)
            dataPoint = timestampData + data
        } catch {
            logError("Failed to encode value \(value.value)", for: metric.id)
            return false
        }
        return update(dataPoint, for: metric)
    }

    private func update(_ dataPoint: TimestampedValueData, for metric: AbstractMetric) -> Bool {
        if let error = ensureExistenceOfLogFolder() {
            logError("Failed to create log folder: \(error)", for: metric.id)
            return false
        }

        // Save last value in separate location
        do {
            let url = lastValueFileUrl(for: metric.idHash)
            try dataPoint.write(to: url)
        } catch {
            logError("Failed to save last value: \(error)", for: metric.id)
        }

        // Write data to log file
        guard appendToLogFile(dataPoint, metric: metric) else {
            // TODO: Save point for retry?
            return false
        }

        pushValueToRemoteObservers(dataPoint, for: metric)
        return true
    }

    private func appendToLogFile(_ dataPoint: TimestampedValueData, metric: AbstractMetric) -> Bool {
        // Existence of log folder is ensured at this point
        let url = logFileUrl(for: metric.idHash)
        guard dataPoint.count <= UInt16.max else {
            logError("Data point too large to store (\(dataPoint.count) bytes)", for: metric.id)
            return false
        }
        let lengthData = UInt16(dataPoint.count).toData()
        guard exists(url) else {
            do {
                try (lengthData + dataPoint).write(to: url)
            } catch {
                logError("Failed to create log file: \(error)", for: metric.id)
                return false
            }
            return true
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            logError("Failed to open log file: \(error)", for: metric.id)
            return false
        }
        defer {
            try? handle.close()
        }
        do {
            try handle.seekToEnd()
        } catch {
            logError("Failed to move to end of log file: \(error)", for: metric.id)
            return false
        }
        do {
            try handle.write(contentsOf: (lengthData + dataPoint))
        } catch {
            logError("Failed to append to log file: \(error)", for: metric.id)
            return false
        }

        return true
    }

    // MARK: Get values

    func getLastValue<T>(for metric: AbstractMetric) -> Timestamped<T>? where T: MetricValue {
        guard let data = getLastValueData(for: metric) else {
            return nil
        }

        let timestamp: TimeInterval
        do {
            let timestampData = data.prefix(decoder.encodedTimestampLength)
            timestamp = try decoder.decode(TimeInterval.self, from: timestampData)
        } catch {
            logError("Failed to decode timestamp of last value: \(error)", for: metric.id)
            return nil
        }

        do {
            let value = try decoder.decode(T.self, from: data.advanced(by: decoder.encodedTimestampLength))
            return .init(timestamp: .init(timeIntervalSince1970: timestamp), value: value)
        } catch {
            logError("Failed to decode last value: \(error)", for: metric.id)
            try? fileManager.removeItem(at: lastValueFileUrl(for: metric.idHash))
            return nil
        }
    }

    private func getLastValueData(for metric: AbstractMetric) -> Data? {
        let lastValueUrl = lastValueFileUrl(for: metric.idHash)
        guard exists(lastValueUrl) else {
            // TODO: Read last value from history file?
            return nil
        }

        do {
            return try .init(contentsOf: lastValueUrl)
        } catch {
            logError("Failed to read last value: \(error)", for: metric.id)
            return nil
        }
    }

    func getHistoryFromLog(forMetric metric: AbstractMetric, in range: ClosedRange<Date>) throws -> Data {
        let url = logFileUrl(for: metric.idHash)
        guard exists(url) else {
            return Data()
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logError("Failed to read log file: \(error)", for: metric.id)
            return Data()
        }

        let startTime = range.lowerBound.timeIntervalSince1970
        let endTime = range.upperBound.timeIntervalSince1970

        var startIndexOfRangeResult = 0
        var endIndexOfLastElement = 0
        while endIndexOfLastElement < data.endIndex {
            let startIndexOfTimestamp = endIndexOfLastElement + byteCountLength
            guard startIndexOfTimestamp <= data.endIndex else {
                logError("Insufficient bytes for element byte count: \(data.endIndex - endIndexOfLastElement)", for: metric.id)
                throw MetricError.logFileCorrupted
            }
            guard let byteCount = UInt16(fromData: data[endIndexOfLastElement..<startIndexOfTimestamp]) else {
                logError("Invalid byte count in log file", for: metric.id)
                throw MetricError.logFileCorrupted
            }
            endIndexOfLastElement = startIndexOfTimestamp + Int(byteCount)
            guard endIndexOfLastElement <= data.endIndex else {
                logError("Insufficient bytes for timestamped value: Needed \(byteCountLength + Int(byteCount)), has \(data.endIndex - startIndexOfTimestamp)", for: metric.id)
                throw MetricError.logFileCorrupted
            }
            guard byteCount >= decoder.encodedTimestampLength else {
                logError("Log element with \(byteCount) bytes is too small to contain a timestamp", for: metric.id)
                throw MetricError.logFileCorrupted
            }
            let timestamp: TimeInterval
            do {
                let timestampData = data[startIndexOfTimestamp..<startIndexOfTimestamp+decoder.encodedTimestampLength]
                timestamp = try decoder.decode(TimeInterval.self, from: timestampData)
            } catch {
                logError("Failed to decode timestamp from log file: \(error)", for: metric.id)
                throw MetricError.logFileCorrupted
            }
            if timestamp > endTime {
                // We assume that the log is sorted, so no more values will be within the interval
                // after the current element is already after the end date
                break
            }
            if timestamp < startTime {
                // The current element is outside of the range,
                // so we move the start index to the start of the next element
                startIndexOfRangeResult = endIndexOfLastElement
            }
        }
        return data[startIndexOfRangeResult..<endIndexOfLastElement]
    }

    func getHistoryFromLog<T>(for metric: AbstractMetric, in range: ClosedRange<Date>) throws -> [Timestamped<T>] where T: MetricValue {
        guard let fileHandle = try logFileHandle(for: metric) else {
            return []
        }
        defer { try? fileHandle.close() }

        // TODO: Skip failing elements in log?
        var result = [Timestamped<T>]()
        while let value: Timestamped<T> = try getNextValue(from: fileHandle, for: metric.id) {
            guard value.timestamp >= range.lowerBound else {
                continue
            }
            guard value.timestamp <= range.upperBound else {
                break
            }
            result.append(value)
        }
        return result
    }

    func getFullHistoryFromLog<T>(for metric: AbstractMetric) throws -> [Timestamped<T>] where T: MetricValue {
        guard let fileHandle = try logFileHandle(for: metric) else {
            return []
        }
        defer { try? fileHandle.close() }

        // TODO: Option to skip failing elements in log?
        var result = [Timestamped<T>]()
        while let value: Timestamped<T> = try getNextValue(from: fileHandle, for: metric.id) {
            result.append(value)
        }
        return result
    }

    private func logFileHandle(for metric: AbstractMetric) throws -> FileHandle? {
        let url = logFileUrl(for: metric.idHash)
        guard exists(url) else {
            return nil
        }
        do {
            return try FileHandle(forReadingFrom: url)
        } catch {
            logError("Failed to read log file: \(error)", for: metric.id)
            throw MetricError.failedToOpenLogFile
        }
    }

    private func getNextValueData(from handle: FileHandle, for metric: MetricId) throws -> (timestamp: Date, data: Data)? {
        guard let byteCountData = try handle.read(upToCount: byteCountLength) else {
            return nil
        }
        guard let byteCount = UInt16(fromData: byteCountData) else {
            logError("Error reading log file: Not a valid byte count", for: metric)
            throw MetricError.logFileCorrupted
        }
        guard byteCount >= decoder.encodedTimestampLength else {
            logError("Error reading log file: Too few bytes (\(byteCount)) for timestamp", for: metric)
            throw MetricError.logFileCorrupted
        }

        guard let timestampedValueData = try handle.read(upToCount: Int(byteCount)) else {
            logError("Error reading log file: No more bytes (needed \(byteCount))", for: metric)
            throw MetricError.logFileCorrupted
        }
        guard timestampedValueData.count == byteCount else {
            logError("Error reading log file: No more bytes (needed \(byteCount))", for: metric)
            throw MetricError.logFileCorrupted
        }
        let timestamp: Date
        do {
            let timestampData = timestampedValueData[0..<decoder.encodedTimestampLength]
            let timestampValue = try decoder.decode(TimeInterval.self, from: timestampData)
            timestamp = .init(timeIntervalSince1970: timestampValue)
        } catch {
            logError("Invalid timestamp in log file: \(error)", for: metric)
            throw MetricError.logFileCorrupted
        }
        let valueData = timestampedValueData[decoder.encodedTimestampLength...]
        return (timestamp, valueData)
    }

    private func getNextValue<T>(from handle: FileHandle, for metric: MetricId) throws -> Timestamped<T>? where T: Decodable {
        guard let (timestamp, valueData) = try getNextValueData(from: handle, for: metric) else {
            return nil
        }
        do {
            let value = try decoder.decode(T.self, from: valueData)
            return .init(timestamp: timestamp, value: value)
        } catch {
            logError("Error decoding value from log file: \(error)", for: metric)
            throw MetricError.logFileCorrupted
        }
    }

    // MARK: Remote observers

    func push<T>(_ metric: AnyMetric<T>, to remote: RemoteMetricObserver) {
        if remoteObservers[metric.id] == nil {
            remoteObservers[metric.id] = [remote]
        } else {
            remoteObservers[metric.id]!.insert(remote)
        }
    }

    private func pushValueToRemoteObservers(_ data: TimestampedValueData, for metric: AbstractMetric) {
        guard let observers = remoteObservers[metric.id] else {
            return
        }

        Task {
            await withTaskGroup(of: Void.self) { group in
                for observer in observers {
                    group.addTask {
                        await self.push(_data: data, for: metric, toRemoteObserver: observer)
                    }
                }
            }
        }
    }

    private func push(_data: TimestampedValueData, for metric: AbstractMetric, toRemoteObserver remoteObserver: RemoteMetricObserver) async {

        let remoteUrl = remoteObserver.remoteUrl
        do {
            let url = remoteUrl.appendingPathComponent("push/\(metric.id)")
            var request = URLRequest(url: url)
            request.setValue(remoteObserver.authenticationToken.base64EncodedString(), forHTTPHeaderField: "token")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                logError("Invalid response pushing value to \(remoteUrl.path): \(response)", for: metric.id)
                return
            }
            guard response.statusCode == 200 else {
                logError("Failed to push value to \(remoteUrl.path): Response \(response.statusCode)", for: metric.id)
                return
            }
        } catch {
            logError("Failed to push value to \(remoteUrl.path): \(error)", for: metric.id)
        }
    }

    // MARK: Routes

    func getListOfRecordedMetrics() -> [MetricDescription] {
        observedMetrics.map { .init(id: $0.key, dataType: $0.value.dataType) }
    }

    private func getAccessibleMetric(_ request: Request) throws -> AbstractMetric {
        guard let metricId = request.parameters.get("id", as: String.self) else {
            throw Abort(.badRequest)
        }
        let metric = try getMetric(with: metricId)
        try accessManager.metricAccess(to: metricId, isAllowedForRequest: request)
        return metric
    }

    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "metrics") {

        app.post(subPath, "list") { [weak self] request async throws in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricListAccess(isAllowedForRequest: request)
            let list = self.getListOfRecordedMetrics()
            return try self.encoder.encode(list)
        }

        app.post(subPath, "last", ":id") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)

            guard let data = self.getLastValueData(for: metric) else {
                throw MetricError.noValueAvailable
            }
            return data
        }

        app.post(subPath, "history", ":id") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)
            let range = try request.decodeBody(as: ClosedRange<Date>.self)
            return try self.getHistoryFromLog(forMetric: metric, in: range)
        }

        app.post(subPath, "push", ":id") { [weak self] request -> Void in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)
            guard metric.isRemote else {
                throw Abort(.expectationFailed)
            }

            guard let valueData = request.body.data?.all() else {
                throw Abort(.badRequest)
            }

            guard metric.verifyEncoding(of: valueData, decoder: self.decoder) else {
                // Invalid data will ruin decoding of log files
                throw Abort(.notAcceptable)
            }
            
            // Save value for metric
            guard self.update(valueData, for: metric) else {
                throw Abort(.internalServerError)
            }
        }
    }
}

extension MetricObserver: Equatable {

    public static func == (lhs: MetricObserver, rhs: MetricObserver) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
}
