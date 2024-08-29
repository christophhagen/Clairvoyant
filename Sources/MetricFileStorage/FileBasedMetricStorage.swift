import Foundation
import Clairvoyant

/**
 A storage solution for metrics based on log files.
 
 The log files are grouped by the metric id, and the metric values are encoded to binary data and stored in files.
 If the files become too large, then additional files are created.
 */
public actor FileBasedMetricStorage {
    
    static let metricListFileName = "metrics.json"
    
    static let lastValueFileName = "last"
    
    /// The directory where the log files and other internal data is to be stored.
    public let logFolder: URL
    
    /// The closure to create an encoder for metric data
    public let encoderCreator: () -> AnyBinaryEncoder

    /// The closure to create a decoder for metric data
    public let decoderCreator: () -> AnyBinaryDecoder
    
    /// The url where the list of available metrics is stored
    private let metricListUrl: URL
    
    /**
     The maximum size of the log files (in bytes).

     Log files are split into files of this size. This limit will be slightly exceeded by each file,
     since a new file is begun if the current file already larger than the limit.
     A file always contains complete data points.
     The maximum size is assigned to all new metrics, but does not affect already created ones.
     The size can be changed on a metric without affecting other metrics or the observer.
     */
    public var maximumFileSizeInBytes: Int
    
    /// The internal metric used for logging
    private var logMetric: AsyncMetric<String>!
    
    private var writers: [MetricId : Any] = [:]
    
    private var metrics: [MetricInfo] = []
    
    /// The cache for the last values
    private var lastValues: [MetricId : AnyTimestamped] = [:]
    
    /// The change callbacks for the metrics
    private var changeListeners: [MetricId : [(Any) -> Void]] = [:]
    
    /**
     Create a new file-based metric storage.

     The storage creates a metric with the id `logMetricId` to log internal errors.
     It is also possible to write to this metric using ``log(_:)``.

     - Parameter logFolder: The directory where the log files and other internal data is to be stored.
     - Parameter logMetricId: The id of the metric for internal log data
     - Parameter logMetricGroup: The group of the log metric
     - Parameter logMetricName: A name for the logging metric
     - Parameter logMetricDescription: A textual description of the logging metric
     - Parameter encoderCreator: The closure to create an encoder for metric data
     - Parameter decoderCreator: The closure to create a decoder for metric data
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(
        logFolder: URL,
        logMetricId: String,
        logMetricGroup: String,
        logMetricName: String? = nil,
        logMetricDescription: String? = nil,
        encoderCreator: @escaping () -> AnyBinaryEncoder,
        decoderCreator: @escaping () -> AnyBinaryDecoder,
        fileSize: Int = 10_000_000) async throws {
            self.encoderCreator = encoderCreator
            self.decoderCreator = decoderCreator
            self.maximumFileSizeInBytes = fileSize
            self.logFolder = logFolder
            self.metricListUrl = logFolder.appendingPathComponent(FileBasedMetricStorage.metricListFileName)
            
            try ensureExistenceOfLogFolder()
            self.metrics = try loadMetricListFromDisk()
            let logId = MetricId(id: logMetricId, group: logMetricGroup)
            self.logMetric = try getOrCreateMetric(logId, name: logMetricName, description: logMetricDescription)
        }
    
    private func ensureExistenceOfLogFolder() throws {
        guard !FileManager.default.fileExists(atPath: logFolder.path) else {
            return
        }
        try FileManager.default.createDirectory(at: logFolder, withIntermediateDirectories: true)
    }
    
    private func getOrCreateMetric<T>(_ id: MetricId, name: String?, description: String?) throws -> AsyncMetric<T> {
        guard let metric = metric(id: id) else {
            try create(metric: id, name: name, description: description, type: T.valueType)
            return .init(storage: self, id: id, name: name, description: description)
        }
        guard metric.valueType == T.valueType else {
            throw MetricError.typeMismatch
        }
        if metric.description != description || metric.name != name {
            try update(name: name, description: description, for: id)
        }
        return .init(storage: self, id: id, name: name, description: description)
    }
    
    private func hasMetric(id: MetricId) -> Bool {
        metrics.contains { $0.id == id }
    }

    private func metric(id: MetricId) -> MetricInfo? {
        metrics.first { $0.id == id }
    }
    
    private func create(metric id: MetricId, name: String?, description: String?, type: MetricType) throws {
        let info = MetricInfo(id: id, valueType: type, name: name, description: description)
        metrics.append(info)
        try writeMetricListToDisk()
    }
    
    private func update(name: String?, description: String?, for id: MetricId) throws {
        // Update `metrics`
        try writeMetricListToDisk()
    }
    
    private nonisolated func loadMetricListFromDisk() throws -> [MetricInfo] {
        let url = metricListUrl
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(from: data)
    }
    
    /**
     Save the info of all currently registered metrics to disk, in a human-readable format.
     
     - Returns: `true`, if the file was written.
     */
    @discardableResult
    private func writeMetricListToDisk() throws -> Bool {
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(metrics)
            try data.write(to: metricListUrl)
            return true
        } catch {
            print("Failed to save metric list: \(error)")
            return false
        }
    }
    
    // MARK: Files
    
    /**
     Calculate the size of the local storage dedicated to the metric.
     */
    public var localStorageSize: Int {
        logFolder.fileSize
    }
    
    private func writer<T>(for metric: AsyncMetric<T>) throws -> LogFileWriter<T> {
        let id = metric.id
        guard hasMetric(id: id) else {
            throw MetricError.notFound
        }
        if let writer = writers[id] {
            return writer as! LogFileWriter<T>
        }
        let encoder = encoderCreator()
        let decoder = decoderCreator()
        let writer = LogFileWriter<T>(
            id: id,
            folder: logFolder,
            encoder: encoder,
            decoder: decoder,
            fileSize: maximumFileSizeInBytes,
            logClosure: { [weak self] message in
                guard let self else { return }
                await self.log(message, for: id)
            })
        writers[id] = writer
        return writer
    }
    
    // MARK: Logging

    /**
     Log a message to the internal log metric.
     - Parameter message: The log entry to add.
     - Returns: `true` if the message was added to the log, `false` if the message could not be saved.
     */
    public func log(_ message: String) async {
        print(message)
        do {
            try await logMetric.update(message)
        } catch {
            print("[ERROR] Failed to update log metric: \(error)")
        }
    }
    
    func log(_ message: String, for metric: MetricId) async {
        let entry = "[\(metric)] " + message
        print(entry)

        // Prevent infinite recursions
        guard metric == logMetric.id else {
            return
        }
        do {
            try await logMetric.update(entry)
        } catch {
            print("[ERROR] Failed to update log metric: \(error)")
        }
    }
}

extension FileBasedMetricStorage: AsyncMetricStorage {
    
    public func metrics() async throws -> [MetricInfo] {
        metrics
    }
    
    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type = T.self) throws -> AsyncMetric<T> where T : MetricValue {
        try getOrCreateMetric(id, name: name, description: description)
    }
    
    public func delete(metric id: MetricId) throws {
        guard let index = metrics.firstIndex(where: { $0.id == id }) else {
            return
        }
        metrics.remove(at: index)
        try writeMetricListToDisk()
        // Remove from `writers`, which also close the file
        writers[id] = nil
        lastValues[id] = nil
        changeListeners[id] = nil
    }
    
    public func store<T>(_ value: Timestamped<T>, for metric: AsyncMetric<T>) async throws where T : MetricValue {
        let id = metric.id
        // Get writer and save value
        try await writer(for: metric).write(value)
        // Update last value cache
        lastValues[id] = value
        // Notify all listeners
        changeListeners[id]?.forEach { $0(value) }
    }
    
    public func store<S, T>(_ values: S, for metric: AsyncMetric<T>) async throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        let id = metric.id
        var last: Timestamped<T>? = nil
        let writer = try writer(for: metric)
        for value in values {
            // Get writer and save value
            try await writer.writeOnlyToLog(value)
            last = value
        }
        guard let last else {
            return
        }
        try await writer.write(lastValue: last)
        // Update last value cache
        lastValues[id] = last
        // Notify all listeners
        changeListeners[id]?.forEach { $0(last) }
    }
    
    public func lastValue<T>(for metric: AsyncMetric<T>) async throws -> Timestamped<T>? where T : MetricValue {
        let id = metric.id
        // Check last value cache
        if let value = lastValues[id] {
            return (value as! Timestamped<T>)
        }
        // Get writer and read value
        return try await writer(for: metric).lastValue()
    }
    
    public func history<T>(for metric: AsyncMetric<T>, from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) async throws -> [Timestamped<T>] where T : MetricValue {
        try await writer(for: metric).getHistory(from: start, to: end, maximumValueCount: limit)
    }
    
    public func deleteHistory<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date) async throws where T : MetricValue {
        // Get writer and remove values
        try await writer(for: metric).deleteHistory(from: start, to: end)
        // Clear last value cache
        lastValues[metric.id] = nil
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: AsyncMetric<T>) throws where T : MetricValue {
        let id = metric.id
        let existingListeners = changeListeners[id] ?? []
        let newListener = { (value: Any) in
            changeListener(value as! Timestamped<T>)
        }
        changeListeners[id] = existingListeners + [newListener]
    }
}
