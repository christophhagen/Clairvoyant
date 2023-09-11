import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class MetricObserver {

    /**
     The default observer, to which created metrics are added.

     Set this observer to automatically observe all metrics created using `Metric(id:)`.
     */
    public static var standard: MetricObserver?

    /// The directory where the log files and other internal data is to be stored.
    public let logFolder: URL

    /// The encoder used to convert data points to binary data for logging
    public let encoder: BinaryEncoder

    /// The decoder used to decode log entries when providing history data
    public let decoder: BinaryDecoder

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
    private let logMetric: Metric<String>

    /**
     The metrics observed by this instance.

     The key is the metric `idHash`
     */
    private var observedMetrics: [MetricIdHash : AbstractMetric] = [:]

    /**
     Create a new observer.

     Each observer creates a metric with the id `logMetricId` to log internal errors.
     It is also possible to write to this metric using ``log(_:)``.

     - Parameter logFolder: The directory where the log files and other internal data is to be stored.
     - Parameter logMetricId: The id of the metric for internal log data
     - Parameter logMetricName: A name for the logging metric
     - Parameter logMetricDescription: A textual description of the logging metric
     - Parameter encoder: The encoder to use for log files
     - Parameter decoder: The decoder to use for log files
     - Parameter fileSize: The maximum size of files in bytes
     */
    public init(
        logFolder: URL,
        logMetricId: String,
        logMetricName: String? = nil,
        logMetricDescription: String? = nil,
        encoder: BinaryEncoder,
        decoder: BinaryDecoder,
        fileSize: Int = 10_000_000) {

            self.encoder = encoder
            self.decoder = decoder
            self.maximumFileSizeInBytes = fileSize
            self.logFolder = logFolder
            self.logMetric = .init(
                logId: logMetricId,
                name: logMetricName,
                description: logMetricDescription,
                canBeUpdatedByRemote: false,
                keepsLocalHistoryData: true,
                logFolder: logFolder,
                encoder: encoder,
                decoder: decoder,
                fileSize: fileSize)
            observedMetrics[logMetric.idHash] = logMetric
    }

    // MARK: Adding metrics

    /**
     Create a metric and add it to the observer.
     - Parameter id: The id of the metric.
     - Parameter type: The type of the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Parameter keepsLocalHistoryData: Indicate if the metric should persist the history to disk
     - Parameter canBeUpdatedByRemote: Indicate if the metric can be set through the Web API
     - Returns: The created or existing metric.
     - Note: If a metric with the same `id` and `type` already exists, then this one is returned. Other properties (`name`, `description`, ...) are then ignored.
     */
    public func addMetric<T>(id: String, containing type: T.Type = T.self, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false, keepsLocalHistoryData: Bool = true) -> Metric<T> where T: MetricValue {
        if let existing = observedMetrics[id.hashed()] {
            guard let same = existing as? Metric<T> else {
                fatalError("Two metrics with same id '\(id)' but different types where added to the same observer")
            }
            return same
        }
        let metric = Metric<T>(
            id: id,
            calledFromObserver: self,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            keepsLocalHistoryData: keepsLocalHistoryData,
            name: name, description: description,
            fileSize: maximumFileSizeInBytes)
        observedMetrics[metric.idHash] = metric
        return metric
    }

    func observe<T>(_ metric: Metric<T>) where T: MetricValue {
        guard observedMetrics[metric.idHash] == nil else {
            fatalError("Two metrics with same id '\(metric.id)' where added to the same observer")
        }
        observedMetrics[metric.idHash] = metric
    }

    /**
     Remove a metric from this observer
     - Parameter id: The id of the metric to remove
     - Returns: `true`, if the metric was removed, or `false`, if no metric with the id existed.
     */
    @discardableResult
    public func remove<T>(_ metric: Metric<T>) -> Bool {
        remove(hash: metric.idHash)
    }

    /**
     Remove a metric from this observer
     - Parameter id: The id of the metric to remove
     - Returns: `true`, if the metric was removed, or `false`, if no metric with the id existed.
     */
    @discardableResult
    public func removeMetric(with id: MetricId) -> Bool {
        remove(hash: id.hashed())
    }

    private func remove(hash: MetricIdHash) -> Bool {
        if observedMetrics[hash] == nil {
            return false
        }
        observedMetrics[hash] = nil
        return true
    }

    /**
     Get the info of a registered metric
     - Parameter id: The id of the metric
     - Returns: The info of the metric, or `nil`, if the metric doesn't exist
     */
    public func metricInfo(for id: MetricId) -> MetricInfo? {
        observedMetrics[id.hashed()]?.info
    }

    /**
     Get a metric registered with the observer.

     - Parameter id: The string id of the metric
     - Parameter type: The type of the metric
     - Returns: The metric, or `nil`, if no metric with the given id exists, or the type doesn't match
     */
    public func getMetric<T>(id: MetricId, type: T.Type = T.self) -> Metric<T>? where T: MetricValue {
        observedMetrics[id.hashed()] as? Metric<T>
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

    // MARK: Update metric values

    public func getMetricByHash(_ idHash: MetricIdHash) throws -> GenericMetric {
        guard let metric = observedMetrics[idHash] else {
            throw MetricError.badMetricId
        }
        return metric
    }

    // MARK: Routes

    /**
     Access a list of all metric id hashes currently observed by this instance.
     */
    public func getAllMetricHashes() -> [MetricIdHash] {
        return Array(observedMetrics.keys)
    }

    /**
     Get a mapping of all metric hashes to the associated metric info.
     */
    public func getListOfRecordedMetrics() -> [MetricIdHash : MetricInfo] {
        observedMetrics.mapValues { $0.info }
    }

    /**
     Get a mapping of all metric hashes to the associated extended metric info (inkluding last value).
     */
    public func getExtendedDataOfAllRecordedMetrics() async -> [MetricIdHash : ExtendedMetricInfo] {
        await observedMetrics.asyncMap { metric in
            let lastValue = await metric.value.lastValueData()
            let info = ExtendedMetricInfo(info: metric.value.info, lastValueData: lastValue)
            return (hash: metric.key, info: info)
        }.reduce(into: [:]) { $0[$1.hash] = $1.info }
    }

    /**
     Get a mapping of all metric hashes to the associated last value data.
     */
    public func getLastValuesOfAllMetrics() async -> [MetricIdHash : Data] {
        var result = [MetricIdHash : Data]()
        for (id, metric) in observedMetrics {
            result[id] = await metric.lastValueData()
        }
        return result
    }
}
