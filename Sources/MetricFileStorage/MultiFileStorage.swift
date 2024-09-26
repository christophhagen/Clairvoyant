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

    private var writers: [MetricId : GenericFileWriter] = [:]

    private var knownMetrics: [MetricInfo] = []

    /// The cache for the last values
    private var lastValues: [MetricId : AnyTimestamped] = [:]

    /// The change callbacks for the metrics
    private var changeListeners: [MetricId : [(AnyTimestamped) -> Void]] = [:]

    private var globalChangeListener: ((MetricId, Date) -> Void)?

    /// The deletion callbacks for the metrics
    private var deletionListeners: [MetricId : [(Date) -> Void]] = [:]

    private var globalDeletionListener: ((MetricId, Date) -> Void)?

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

    private func writer(for metric: MetricId) throws -> GenericFileWriter {
        guard hasMetric(metric) else {
            throw FileStorageError(.metricId, metric.description)
        }
        if let writer = writers[metric] {
            return writer
        }
        let encoder = encoderCreator()
        let decoder = decoderCreator()
        let writer = GenericFileWriter(
            id: metric,
            folder: folder,
            encoder: encoder,
            decoder: decoder,
            fileSize: maximumFileSizeInBytes)
        writers[metric] = writer
        return writer
    }

    private func removeFolder(for metric: MetricId) throws {
        let url = MultiFileStorage.folder(for: metric, in: folder)
        try rethrow(.deleteFolder, metric.description) {
            try url.removeIfPresent()
        }
    }

    // MARK: Statistics

    public func numberOfDataPoints(for metric: MetricId) throws -> Int {
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

    public func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T: MetricValue {
        try queue.sync {
            // Get writer and save value
            try writer(for: metric).write(value)
            // Update last value cache
            lastValues[metric] = value
            // Notify all listeners
            changeListeners[metric]?.forEach { $0(value) }
            globalChangeListener?(metric, value.timestamp)
        }
    }

    public func store<S, T>(_ values: S, for metric: MetricId) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        try queue.sync {
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
            lastValues[metric] = last
            // Notify all listeners
            changeListeners[metric]?.forEach { $0(last) }
            globalChangeListener?(metric, last.timestamp)
        }
    }

    public func timestampOfLastValue(for metric: MetricId) throws -> Date? {
        try queue.sync {
            try writer(for: metric).lastValueTimestamp()
        }
    }

    public func lastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T : MetricValue {
        try queue.sync {
            // Check last value cache
            if let value = lastValues[metric] {
                return (value as! Timestamped<T>)
            }
            // Get writer and read value
            return try writer(for: metric).lastValue()
        }
    }

    public func history<T>(for metric: MetricId, from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) throws -> [Timestamped<T>] where T : MetricValue {
        try queue.sync {
            try writer(for: metric).getHistory(from: start, to: end, maximumValueCount: limit)
        }
    }

    public func deleteHistory(for metric: MetricId, before date: Date) throws {
        try queue.sync {
            // Get writer and remove values
            let writer = try writer(for: metric)
            try writer.deleteHistory(before: date)

            // Clear last value cache if last value was deleted
            if let lastTimestamp = try lastValues[metric]?.timestamp ?? writer.lastValueTimestamp(),
                lastTimestamp < date {
                try writer.deleteLastValueFile()
                lastValues[metric] = nil
            }
            deletionListeners[metric]?.forEach { $0(date) }
            globalDeletionListener?(metric, date)
            // TODO: Update change listeners if current value was deleted?
        }
    }

    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) throws where T : MetricValue {
        queue.sync {
            let existingListeners = changeListeners[metric] ?? []
            let newListener = { (value: Any) in
                changeListener(value as! Timestamped<T>)
            }
            changeListeners[metric] = existingListeners + [newListener]
        }
    }

    public func setGlobalChangeListener(_ listener: @escaping (MetricId, Date) -> Void) throws {
        queue.sync {
            globalChangeListener = listener
        }
    }

    public func add(deletionListener: @escaping (Date) -> Void, for metric: MetricId) throws {
        queue.sync {
            let existingListeners = deletionListeners[metric] ?? []
            deletionListeners[metric] = existingListeners + [deletionListener]
        }
    }

    public func setGlobalDeletionListener(_ listener: @escaping (MetricId, Date) -> Void) throws {
        queue.sync {
            globalDeletionListener = listener
        }
    }
}
