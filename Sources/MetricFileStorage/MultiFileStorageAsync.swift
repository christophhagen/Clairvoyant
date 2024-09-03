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
    
    /// The directory where the log files and other internal data is to be stored.
    public let folder: URL

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
    
    private var writers: [MetricId : Any] = [:]
    
    private var metrics: [MetricInfo] = []
    
    /// The cache for the last values
    private var lastValues: [MetricId : AnyTimestamped] = [:]
    
    /// The change callbacks for the metrics
    private var changeListeners: [MetricId : [(Any) -> Void]] = [:]
    
    /**
     Create a new file-based metric storage.

     - Parameter encoderCreator: The closure to create an encoder for metric data
     - Parameter decoderCreator: The closure to create a decoder for metric data
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(
        folder: URL,
        encoderCreator: @escaping () -> AnyBinaryEncoder,
        decoderCreator: @escaping () -> AnyBinaryDecoder,
        fileSize: Int = 10_000_000) async throws {
            self.folder = folder
            self.encoderCreator = encoderCreator
            self.decoderCreator = decoderCreator
            self.maximumFileSizeInBytes = fileSize
            self.metricListUrl = folder.appendingPathComponent(MultiFileStorageAsync.metricListFileName)

            try ensureExistenceOfFolder()
            self.metrics = try loadMetricListFromDisk()
        }
    
    private func ensureExistenceOfFolder() throws {
        guard !folder.exists else {
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    
    private func getOrCreateMetric<T>(_ id: MetricId, name: String?, description: String?) throws -> AsyncMetric<T> {
        guard let metric = metric(id: id) else {
            try create(metric: id, name: name, description: description, type: T.valueType)
            return .init(storage: self, id: id, name: name, description: description)
        }
        guard metric.valueType == T.valueType else {
            throw FileStorageError(.metricType, "\(metric.valueType) != \(T.valueType)")
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
            throw FileStorageError(.metricId, metric.description)
        }
        metrics[index].name = name
        try writeMetricListToDisk()
    }

    private func update(description: String, for metric: MetricId) throws {
        guard let index = index(of: metric) else {
            throw FileStorageError(.metricId, metric.description)
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
        folder.fileSize
    }
    
    private func writer<T>(for metric: AsyncMetric<T>) throws -> FileWriter<T> {
        try writer(for: metric.id)
    }

    private func writer<T>(for metric: MetricId, type: T.Type = T.self) throws -> FileWriter<T> {
        guard hasMetric(metric) else {
            throw FileStorageError(.metricId, metric.description)
        }
        if let writer = writers[metric] {
            return writer as! FileWriter<T>
        }
        let encoder = encoderCreator()
        let decoder = decoderCreator()
        let writer = FileWriter<T>(
            id: metric,
            folder: folder,
            encoder: encoder,
            decoder: decoder,
            fileSize: maximumFileSizeInBytes)
        writers[metric] = writer
        return writer
    }
    
    private func removeFolder(for metric: MetricId) throws {
        let url = MultiFileStorageAsync.folder(for: metric, in: folder)
        try rethrow(.deleteFolder, metric.description) {
            try url.removeIfPresent()
        }
    }

    // MARK: Data

    private func store<T>(value: Timestamped<T>, for metric: MetricId) throws where T : MetricValue {
        // Get writer and save value
        try writer(for: metric).write(value)
        // Update last value cache
        lastValues[metric] = value
        // Notify all listeners
        changeListeners[metric]?.forEach { $0(value) }
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
    
    public func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T : MetricValue {
        try store(value: value, for: metric)
    }
    
    public func store<S, T>(_ values: S, for metric: MetricId) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        var last: Timestamped<T>? = nil
        let writer = try writer(for: metric, type: T.self)
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
        lastValues[metric] = last
        // Notify all listeners
        changeListeners[metric]?.forEach { $0(last) }
    }
    
    public func lastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T : MetricValue {
        // Check last value cache
        if let value = lastValues[metric] {
            return (value as! Timestamped<T>)
        }
        // Get writer and read value
        return try writer(for: metric).lastValue()
    }
    
    public func history<T>(for metric: MetricId, from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) throws -> [Timestamped<T>] where T : MetricValue {
        try writer(for: metric).getHistory(from: start, to: end, maximumValueCount: limit)
    }
    
    public func deleteHistory<T>(for metric: MetricId, type: T.Type, from start: Date, to end: Date) throws where T : MetricValue {
        // Get writer and remove values
        try writer(for: metric, type: T.self).deleteHistory(from: start, to: end)
        // Clear last value cache
        lastValues[metric] = nil
        // TODO: Update change listeners if current value was deleted?
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) throws where T : MetricValue {
        guard hasMetric(metric) else {
            throw FileStorageError(.metricId, metric.description)
        }
        let existingListeners = changeListeners[metric] ?? []
        let newListener = { (value: Any) in
            changeListener(value as! Timestamped<T>)
        }
        changeListeners[metric] = existingListeners + [newListener]
    }
}
