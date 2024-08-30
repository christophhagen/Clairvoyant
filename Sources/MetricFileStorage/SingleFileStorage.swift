import Foundation
import Clairvoyant

public actor SingleFileStorage: FileStorageProtocol {

    static let metricListFileName = "metrics.json"

    /// The directory where the log files and other internal data is to be stored.
    public let logFolder: URL

    /// The  encoder to convert metric values to data
    public let encoder: AnyBinaryEncoder

    /// The decoder for metric data
    public let decoder: AnyBinaryDecoder

    /// The url where the list of available metrics is stored
    let metricListUrl: URL

    private var metrics: [MetricInfo] = []

    /// The cache for the timestamps of last values
    private var lastValues: [MetricId : Date] = [:]

    /// The change callbacks for the metrics
    private var changeListeners: [MetricId : [(Any) -> Void]] = [:]

    /**
     Create a new file-based metric storage.

     - Parameter logFolder: The directory where the log files and other internal data is to be stored.
     - Parameter encoder: The  encoder to convert metric values to data
     - Parameter decoder: The decoder for metric data
     */
    public init(
        logFolder: URL,
        encoder: any AnyBinaryEncoder,
        decoder: any AnyBinaryDecoder) async throws {
            self.encoder = encoder
            self.decoder = decoder
            self.logFolder = logFolder
            self.metricListUrl = logFolder.appendingPathComponent(MultiFileStorageAsync.metricListFileName)

            try ensureExistenceOfLogFolder()
            self.metrics = try loadMetricListFromDisk()
        }

    private func ensureExistenceOfLogFolder() throws {
        guard !logFolder.exists else {
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
        try createFolder(for: id)
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

    private func createFolder(for metric: MetricId) throws {
        let url = folderUrl(for: metric)
        if url.exists {
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    /**
     Calculate the size of the local storage dedicated to the metric.
     */
    public var localStorageSize: Int {
        logFolder.fileSize
    }

    private func removeFolder(for metric: MetricId) throws {
        let url = MultiFileStorageAsync.folder(for: metric, in: logFolder)
        do {
            try url.removeIfPresent()
        } catch {
            print("Failed to delete folder for metric \(metric.id) in group \(metric.group): \(error)")
            throw MetricError.failedToDeleteLogFile
        }
    }

    private func encode<T>(_ value: T) throws -> Data where T: Encodable {
        // Check if metric is a string, then save directly
        if let value = value as? String {
            guard let data = value.data(using: .utf8) else {
                throw MetricError.failedToEncode
            }
            return data
        }
        return try encoder.encode(value)
    }

    private func decode<T>(_ data: Data) throws -> T where T: Decodable {
        guard T.self == String.self else {
            return try decoder.decode(from: data)
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw MetricError.failedToDecode
        }
        return value as! T
    }

    private func filename(for date: Date) -> String {
        String(date.timeIntervalSince1970).replacingOccurrences(of: ".", with: "_")
    }

    private func date(from filename: String) -> Date? {
        guard let timeInterval = Double(filename.replacingOccurrences(of: "_", with: ".")) else {
            return nil
        }
        return Date(timeIntervalSince1970: timeInterval)
    }

    private func folderUrl(for metric: MetricId) -> URL {
        SingleFileStorage.folder(for: metric, in: logFolder)
    }

    private func url(for date: Date, of metric: MetricId) -> URL {
        let filename = filename(for: date)
        return folderUrl(for: metric)
            .appendingPathComponent(filename, isDirectory: false)
    }

    private func store<T>(file: Timestamped<T>, for metric: MetricId) throws where T: Encodable {
        let data = try encode(file.value)
        let url = url(for: file.timestamp, of: metric)
        try data.write(to: url)
    }

    private func value<T>(for date: Date, of metric: MetricId) throws -> Timestamped<T> where T: Decodable {
        let url = url(for: date, of: metric)
        let data = try Data(contentsOf: url)
        return .init(
            value: try decode(data),
            timestamp: date)
    }

    @inline(__always)
    private func unsortedTimestamps(for metric: MetricId) throws -> [Date] {
        let url = folderUrl(for: metric)
        return try FileManager.default
            .contentsOfDirectory(atPath: url.path)
            .compactMap(date)
    }

    @inline(__always)
    private func timestamps(for metric: MetricId) throws -> [Date] {
        try unsortedTimestamps(for: metric).sorted()
    }

    private func readLastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T: Decodable {
        guard let date = try timestamps(for: metric).last else {
            return nil
        }
        return try value(for: date, of: metric)
    }

    // MARK: Statistics

    public func numberOfDataPoints(for metric: MetricId) throws -> Int {
        guard hasMetric(metric) else {
            return 0
        }
        return try unsortedTimestamps(for: metric).count
    }
}

extension SingleFileStorage: AsyncMetricStorage {
    
    public func metrics() async -> [MetricInfo] {
        metrics
    }

    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) throws -> AsyncMetric<T> where T : MetricValue {
        try getOrCreateMetric(id, name: name, description: description)
    }

    public func delete(metric id: MetricId) throws {
        guard let index = index(of: id) else {
            return
        }
        metrics.remove(at: index)
        try writeMetricListToDisk()
        try removeFolder(for: id)
        // Remove from `writers`, which also close the file
        lastValues[id] = nil
        changeListeners[id] = nil
    }

    public func store<T>(_ value: Timestamped<T>, for metric: AsyncMetric<T>) throws where T : MetricValue {
        let id = metric.id

        try store(file: value, for: id)
        // Update last value cache
        lastValues[id] = value.timestamp
        // Notify all listeners
        changeListeners[id]?.forEach { $0(value) }
    }
    
    public func store<S, T>(_ values: S, for metric: AsyncMetric<T>) throws where S : Sequence, T : MetricValue, S.Element == Timestamped<T> {
        let id = metric.id

        var last: Date? = nil
        for value in values {
            try store(file: value, for: id)
            last = value.timestamp
        }
        guard let last else {
            return
        }
        // Update last value cache
        lastValues[id] = last
        // Notify all listeners
        changeListeners[id]?.forEach { $0(last) }
    }
    
    public func lastValue<T>(for metric: AsyncMetric<T>) throws -> Timestamped<T>? where T : MetricValue {
        let id = metric.id
        guard hasMetric(id) else {
            throw MetricError.notFound
        }
        // Check last value cache
        if let date = lastValues[id] {
            return try value(for: date, of: id)
        }
        guard let value: Timestamped<T> = try readLastValue(for: id) else {
            return nil
        }
        lastValues[id] = value.timestamp
        return value
    }
    
    public func history<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date, limit: Int?) throws -> [Timestamped<T>] where T : MetricValue {
        let id = metric.id
        guard hasMetric(id) else {
            throw MetricError.notFound
        }

        let count = limit ?? .max
        guard count > 0 else {
            return []
        }
        let isReversed = start > end
        let range = isReversed ? end...start : start...end
        let files = try timestamps(for: id).filter(range.contains)

        //usleep(1000 * 1000)
        guard isReversed else {
            return try files.prefix(count).map { timestamp in
                try value(for: timestamp, of: id)
            }
        }
        return try files.suffix(count).reversed().map { timestamp in
            try value(for: timestamp, of: id)
        }
    }
    
    public func deleteHistory<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date) throws where T : MetricValue {
        let id = metric.id
        let isReversed = start <= end
        let range = isReversed ? start...end : end...start
        let url = folderUrl(for: id)
        var last: Date? = nil
        try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .forEach { fileUrl in
                guard let timestamp = date(from: fileUrl.lastPathComponent) else {
                    return
                }
                guard range.contains(timestamp) else {
                    // Update last value timestamp from remaining samples
                    if last == nil || timestamp > last! {
                        last = timestamp
                    }
                    return
                }
                try fileUrl.remove()
            }
        // Update last value cache
        lastValues[metric.id] = last
        // TODO: Update change listeners if current value was deleted?
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: AsyncMetric<T>) async throws where T : MetricValue {
        let id = metric.id
        let existingListeners = changeListeners[id] ?? []
        let newListener = { (value: Any) in
            changeListener(value as! Timestamped<T>)
        }
        changeListeners[id] = existingListeners + [newListener]
    }
}
