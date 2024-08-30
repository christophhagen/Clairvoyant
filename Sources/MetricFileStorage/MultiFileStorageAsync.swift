import Foundation
import Clairvoyant

/**
 A storage solution for metrics based on log files.
 
 The log files are grouped by the metric id, and the metric values are encoded to binary data and stored in files.
 If the files become too large, then additional files are created.

 This is the asynchronous version of ``MultiFileStorage`` using Swift `actor`s for thread safety.
 */
public actor MultiFileStorageAsync: FileStorageProtocol {
    
    static let metricListFileName = "metrics.json"
    
    static let lastValueFileName = "last"

    private let logQueue = DispatchQueue(label: "clairvoyant.MultiFileStorageAsync")

    /// The directory where the log files and other internal data is to be stored.
    public let logFolder: URL
    
    /// The closure to create an encoder for metric data
    public let encoderCreator: () -> AnyBinaryEncoder

    /// The closure to create a decoder for metric data
    public let decoderCreator: () -> AnyBinaryDecoder
    
    /// The url where the list of available metrics is stored
    let metricListUrl: URL
    
    /**
     The maximum size of the log files (in bytes).

     Log files are split into files of this size. This limit will be slightly exceeded by each file,
     since a new file is begun if the current file already larger than the limit.
     A file always contains complete data points.
     The maximum size is assigned to all new metrics, but does not affect already created files.
     */
    public var maximumFileSizeInBytes: Int
    
    /// The internal metric used for logging
    private nonisolated let logMetric: FileWriter<String>

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
     - Parameter encoderCreator: The closure to create an encoder for metric data
     - Parameter decoderCreator: The closure to create a decoder for metric data
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(
        logFolder: URL,
        logMetricId: MetricId,
        encoderCreator: @escaping () -> AnyBinaryEncoder,
        decoderCreator: @escaping () -> AnyBinaryDecoder,
        fileSize: Int = 10_000_000) async throws {
            self.encoderCreator = encoderCreator
            self.decoderCreator = decoderCreator
            self.maximumFileSizeInBytes = fileSize
            self.logFolder = logFolder
            self.metricListUrl = logFolder.appendingPathComponent(MultiFileStorageAsync.metricListFileName)
            
            self.logMetric = FileWriter(
                id: logMetricId,
                folder: logFolder,
                encoder: encoderCreator(),
                decoder: decoderCreator(),
                fileSize: fileSize,
                logClosure: { msg in
                    print(msg)
                })

            try ensureExistenceOfLogFolder()
            self.metrics = try loadMetricListFromDisk()
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
        if let name, name != metric.name {
            try update(name: name, for: id)
        }
        if let description, description != metric.description {
            try update(description: description, for: id)
        }

        return .init(
            storage: self,
            id: id,
            name: name ?? metric.name,
            description: description ?? metric.description)
    }
    
    private func hasMetric(_ id: MetricId) -> Bool {
        metrics.contains { $0.id == id }
    }

    private func metric(id: MetricId) -> MetricInfo? {
        metrics.first { $0.id == id }
    }
    
    private func index(of id: MetricId) -> Int? {
        metrics.firstIndex { $0.id == id }
    }

    private func create(metric id: MetricId, name: String?, description: String?, type: MetricType) throws {
        let info = MetricInfo(id: id, valueType: type, name: name, description: description)
        metrics.append(info)
        try writeMetricListToDisk()
    }
    
    private func update(name: String, for metric: MetricId) throws {
        guard let index = index(of: metric) else {
            throw MetricError.notFound
        }
        metrics[index].name = name
        try writeMetricListToDisk()
    }

    private func update(description: String, for metric: MetricId) throws {
        guard let index = index(of: metric) else {
            throw MetricError.notFound
        }
        metrics[index].description = description
        try writeMetricListToDisk()
    }

    private func writeMetricListToDisk() throws {
        try writeMetricsToDisk(metrics)
    }
    
    // MARK: Files
    
    /**
     Calculate the size of the local storage dedicated to the metric.
     */
    public var localStorageSize: Int {
        logFolder.fileSize
    }
    
    private func writer<T>(for metric: AsyncMetric<T>) throws -> FileWriter<T> {
        try writer(for: metric.id)
    }

    private func writer<T>(for metric: MetricId, type: T.Type = T.self) throws -> FileWriter<T> {
        guard hasMetric(metric) else {
            throw MetricError.notFound
        }
        if let writer = writers[metric] {
            return writer as! FileWriter<T>
        }
        let encoder = encoderCreator()
        let decoder = decoderCreator()
        let writer = FileWriter<T>(
            id: metric,
            folder: logFolder,
            encoder: encoder,
            decoder: decoder,
            fileSize: maximumFileSizeInBytes,
            logClosure: { [weak self] message in
                guard let self else { return }
                self.logQueue.sync {
                    self.log(message, for: metric)
                }
            })
        writers[metric] = writer
        return writer
    }
    
    private func removeFolder(for metric: MetricId) throws {
        let url = MultiFileStorageAsync.folder(for: metric, in: logFolder)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete folder for metric \(metric.id) in group \(metric.group): \(error)")
            throw MetricError.failedToDeleteLogFile
        }
    }

    // MARK: Data

    private func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T : MetricValue {
        // Get writer and save value
        try writer(for: metric).write(value)
        // Update last value cache
        lastValues[metric] = value
        // Notify all listeners
        changeListeners[metric]?.forEach { $0(value) }
    }

    // MARK: Logging

    private nonisolated func log(_ message: String, for metric: MetricId) {
        let entry = Timestamped.init(value: "[\(metric)] " + message)
        print(entry.value)

        let lastLogEntry = logMetric.lastValue()
        guard entry.shouldUpdate(currentValue: lastLogEntry) else {
            return
        }

        do {
            try logMetric.write(entry)
        } catch {
            print("[ERROR] Failed to update log metric: \(error)")
        }
    }

    public func getLogHistory(from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) -> [Timestamped<String>] {
        logMetric.getHistory(from: start, to: end, maximumValueCount: limit)
    }
}

extension MultiFileStorageAsync: AsyncMetricStorage {
    
    public func metrics() async -> [MetricInfo] {
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
        try removeFolder(for: id)
        // Remove from `writers`, which also close the file
        writers[id] = nil
        lastValues[id] = nil
        changeListeners[id] = nil
    }
    
    public func store<T>(_ value: Timestamped<T>, for metric: AsyncMetric<T>) throws where T : MetricValue {
        try store(value, for: metric.id)
    }
    
    public func store<S, T>(_ values: S, for metric: AsyncMetric<T>) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        let id = metric.id
        var last: Timestamped<T>? = nil
        let writer = try writer(for: metric)
        for value in values {
            // Get writer and save value
            try writer.writeOnlyToLog(value)
            last = value
        }
        guard let last else {
            return
        }
        try writer.write(lastValue: last)
        // Update last value cache
        lastValues[id] = last
        // Notify all listeners
        changeListeners[id]?.forEach { $0(last) }
    }
    
    public func lastValue<T>(for metric: AsyncMetric<T>) throws -> Timestamped<T>? where T : MetricValue {
        let id = metric.id
        // Check last value cache
        if let value = lastValues[id] {
            return (value as! Timestamped<T>)
        }
        // Get writer and read value
        return try writer(for: metric).lastValue()
    }
    
    public func history<T>(for metric: AsyncMetric<T>, from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) throws -> [Timestamped<T>] where T : MetricValue {
        try writer(for: metric).getHistory(from: start, to: end, maximumValueCount: limit)
    }
    
    public func deleteHistory<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date) throws where T : MetricValue {
        // Get writer and remove values
        try writer(for: metric).deleteHistory(from: start, to: end)
        // Clear last value cache
        lastValues[metric.id] = nil
        // TODO: Update change listeners if current value was deleted?
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: AsyncMetric<T>) throws where T : MetricValue {
        let id = metric.id
        guard hasMetric(id) else {
            throw MetricError.notFound
        }
        let existingListeners = changeListeners[id] ?? []
        let newListener = { (value: Any) in
            changeListener(value as! Timestamped<T>)
        }
        changeListeners[id] = existingListeners + [newListener]
    }
}
