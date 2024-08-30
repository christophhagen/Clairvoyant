import Foundation
import Clairvoyant

/**
 A storage solution for metrics based on log files.

 The log files are grouped by the metric id, and the metric values are encoded to binary data and stored in files.
 If the files become too large, then additional files are created.

 This is the synchronous version of ``MultiFileStorageAsync`` using a DispatchQueue for thread safety.
 */
public final class MultiFileStorage: FileStorageProtocol {

    static let metricListFileName = "metrics.json"

    static let lastValueFileName = "last"

    private let queue = DispatchQueue(label: "clairvoyant.multiFileStorage")

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

    private var knownMetrics: [MetricInfo] = []

    /// The cache for the last values
    private var lastValues: [MetricId : AnyTimestamped] = [:]

    /// The change callbacks for the metrics
    private var changeListeners: [MetricId : [(Any) -> Void]] = [:]

    /**
     Create a new file-based metric storage.

     The storage creates a metric with the id `logMetricId` to log internal errors.
     It is also possible to write to this metric using ``log(_:)``.

     - Parameter folder: The directory where the log files and other internal data is to be stored.
     - Parameter encoderCreator: The closure to create an encoder for metric data
     - Parameter decoderCreator: The closure to create a decoder for metric data
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(
        folder: URL,
        encoderCreator: @escaping () -> AnyBinaryEncoder,
        decoderCreator: @escaping () -> AnyBinaryDecoder,
        fileSize: Int = 10_000_000) throws {
            self.encoderCreator = encoderCreator
            self.decoderCreator = decoderCreator
            self.maximumFileSizeInBytes = fileSize
            self.folder = folder
            self.metricListUrl = folder.appendingPathComponent(MultiFileStorage.metricListFileName)

            try ensureExistenceOfLogFolder()
            self.knownMetrics = try loadMetricListFromDisk()
        }

    private func ensureExistenceOfLogFolder() throws {
        guard !folder.exists else {
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func getOrCreateMetric<T>(_ id: MetricId, name: String?, description: String?) throws -> Metric<T> {
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
        knownMetrics.contains { $0.id == id }
    }

    private func metric(id: MetricId) -> MetricInfo? {
        knownMetrics.first { $0.id == id }
    }

    private func index(of id: MetricId) -> Int? {
        knownMetrics.firstIndex { $0.id == id }
    }

    private func create(metric id: MetricId, name: String?, description: String?, type: MetricType) throws {
        let info = MetricInfo(id: id, valueType: type, name: name, description: description)
        knownMetrics.append(info)
        try writeMetricListToDisk()
    }

    private func update(name: String, for metric: MetricId) throws {
        guard let index = index(of: metric) else {
            throw FileStorageError(.metricId, metric.description)
        }
        knownMetrics[index].name = name
        try writeMetricListToDisk()
    }

    private func update(description: String, for metric: MetricId) throws {
        guard let index = index(of: metric) else {
            throw FileStorageError(.metricId, metric.description)
        }
        knownMetrics[index].description = description
        try writeMetricListToDisk()
    }

    private func writeMetricListToDisk() throws {
        try writeMetricsToDisk(knownMetrics)
    }

    // MARK: Files

    /**
     Calculate the size of the local storage dedicated to the metric.
     */
    public var localStorageSize: Int {
        folder.fileSize
    }

    private func writer<T>(for metric: Metric<T>) throws -> FileWriter<T> {
        let id = metric.id
        guard hasMetric(id) else {
            throw FileStorageError(.metricId, metric.id.description)
        }
        if let writer = writers[id] {
            return writer as! FileWriter<T>
        }
        let encoder = encoderCreator()
        let decoder = decoderCreator()
        let writer = FileWriter<T>(
            id: id,
            folder: folder,
            encoder: encoder,
            decoder: decoder,
            fileSize: maximumFileSizeInBytes)
        writers[id] = writer
        return writer
    }

    private func removeFolder(for metric: MetricId) throws {
        let url = MultiFileStorage.folder(for: metric, in: folder)
        try rethrow(.deleteFolder, metric.description) {
            try url.removeIfPresent()
        }
    }

    // MARK: Statistics

    public func numberOfDataPoints<T>(for metric: Metric<T>) throws -> Int {
        try writer(for: metric).numberOfDataPoints()
    }
}

extension MultiFileStorage: MetricStorage {

    public func metrics() -> [MetricInfo] {
        knownMetrics
    }

    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type = T.self) throws -> Metric<T> where T : MetricValue {
        try queue.sync {
            try getOrCreateMetric(id, name: name, description: description)
        }
    }

    public func delete(metric id: MetricId) throws {
        try queue.sync {
            guard let index = knownMetrics.firstIndex(where: { $0.id == id }) else {
                return
            }
            knownMetrics.remove(at: index)
            try writeMetricListToDisk()
            try removeFolder(for: id) // Also deletes last value file
            // Remove from `writers`, which also close the file
            writers[id] = nil
            lastValues[id] = nil
            changeListeners[id] = nil
        }
    }

    public func store<T>(_ value: Timestamped<T>, for metric: Metric<T>) throws where T : MetricValue {
        try queue.sync {
            let id = metric.id
            // Get writer and save value
            try writer(for: metric).write(value)
            // Update last value cache
            lastValues[id] = value
            // Notify all listeners
            changeListeners[id]?.forEach { $0(value) }
        }
    }

    public func store<S, T>(_ values: S, for metric: Metric<T>) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        try queue.sync {
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
    }

    public func lastValue<T>(for metric: Metric<T>) throws -> Timestamped<T>? where T : MetricValue {
        let id = metric.id
        return try queue.sync {
            // Check last value cache
            if let value = lastValues[id] {
                return (value as! Timestamped<T>)
            }
            // Get writer and read value
            return try writer(for: metric).lastValue()
        }
    }

    public func history<T>(for metric: Metric<T>, from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) throws -> [Timestamped<T>] where T : MetricValue {
        try queue.sync {
            try writer(for: metric).getHistory(from: start, to: end, maximumValueCount: limit)
        }
    }

    public func deleteHistory<T>(for metric: Metric<T>, from start: Date, to end: Date) throws where T : MetricValue {
        try queue.sync {
            // Get writer and remove values
            let writer = try writer(for: metric)
            try writer.deleteHistory(from: start, to: end)
            try writer.deleteLastValueFile()
            // Clear last value cache
            lastValues[metric.id] = nil
            // TODO: Update change listeners if current value was deleted?
        }
    }

    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: Metric<T>) throws where T : MetricValue {
        let id = metric.id
        queue.sync {
            let existingListeners = changeListeners[id] ?? []
            let newListener = { (value: Any) in
                changeListener(value as! Timestamped<T>)
            }
            changeListeners[id] = existingListeners + [newListener]
        }
    }
}
