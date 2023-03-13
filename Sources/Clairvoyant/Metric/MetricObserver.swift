import Foundation
import CBORCoding
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

    /// The authentication manager for access to metric information
    public var accessManager: MetricRequestAccessManager?

    /// The encoder used to convert data points to binary data for logging
    let encoder: BinaryEncoder

    /// The decoder used to decode log entries when providing history data
    let decoder: BinaryDecoder

    /// The internal metric used for logging
    private let logMetric: Metric<String>

    /// The unique random id assigned to each observer to distinguish them
    private let uniqueId: Int

    /**
     The metrics observed by this instance.

     The key is the metric `idHash`
     */
    private var observedMetrics: [MetricIdHash : AbstractMetric] = [:]

    /**
     The remote observers of metrics logged with this instance.

     All updates to metrics are pushed to each remote observer.
     */
    private var remoteObservers: [MetricIdHash : Set<RemoteMetricObserver>] = [:]

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
        accessManager: MetricRequestAccessManager? = nil,
        logMetricId: String,
        logMetricName: String? = nil,
        logMetricDescription: String? = nil,
        encoder: BinaryEncoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970),
        decoder: BinaryDecoder = CBORDecoder()) {

            self.uniqueId = .random()
            self.encoder = encoder
            self.decoder = decoder
            self.logFolder = logFolder
            self.accessManager = accessManager
            self.logMetric = .init(
                unobserved: logMetricId,
                name: logMetricName,
                description: logMetricDescription,
                canBeUpdatedByRemote: false,
                logFolder: logFolder,
                encoder: encoder,
                decoder: decoder)
            // No previous metrics, so observing can't fail
            observe(logMetric)
    }

    // MARK: Adding metrics

    /**
     Create a metric and add it to the observer.
     - Parameter id: The id of the metric.
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Returns: The created metric.
     */
    public func addMetric<T>(id: String, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false) -> Metric<T> where T: MetricValue {
        let metric = Metric<T>(
            id: id,
            observer: self,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name, description: description)
        observe(metric)
        return metric
    }

    func observe(_ metric: AbstractMetric) {
        if let old = observedMetrics[metric.idHash], old.uniqueId != metric.uniqueId {
            // Comparing unique ids prevents potential problem:
            // When the same metric is registered twice in succession,
            // then the observer would be removed after the metric is created
            Task {
                await old.set(observer: nil)
            }
        }
        observedMetrics[metric.idHash] = metric
    }

    public func getMetric<T>(id: String, type: T.Type = T.self) -> Metric<T>? where T: MetricValue {
        observedMetrics[id.hashed()] as? Metric<T>
    }

    // MARK: Logging

    /**
     Log a message to the internal log metric.
     - Parameter message: The log entry to add.
     - Returns: `true` if the message was added to the log, `false` if the message could not be saved.
     */
    public func log(_ message: String) {
        print(message)
        Task {
            try await logMetric.update(message)
        }
    }

    func log(_ message: String, for metric: MetricId) {
        let entry = "[\(metric)] " + message
        print(entry)

        // Prevent infinite recursions
        guard metric == logMetric.id else {
            return
        }
        Task {
            try await logMetric.update(entry)
        }
    }

    // MARK: Update metric values

    func getMetric(with idHash: MetricIdHash) throws -> AbstractMetric {
        guard let metric = observedMetrics[idHash] else {
            throw MetricError.badMetricId
        }
        return metric
    }

    // MARK: Remote observers

    func push<T>(_ metric: Metric<T>, to remote: RemoteMetricObserver) {
        if remoteObservers[metric.idHash] == nil {
            remoteObservers[metric.idHash] = [remote]
        } else {
            remoteObservers[metric.idHash]!.insert(remote)
        }
    }

    func pushValueToRemoteObservers(_ data: TimestampedValueData, for metric: AbstractMetric) async {
        guard let observers = remoteObservers[metric.idHash] else {
            return
        }
        await withTaskGroup(of: Void.self) { group in
            for observer in observers {
                group.addTask {
                    await self.push(_data: data, for: metric, toRemoteObserver: observer)
                }
            }
        }
    }

    private func push(_data: TimestampedValueData, for metric: AbstractMetric, toRemoteObserver remoteObserver: RemoteMetricObserver) async {

        let remoteUrl = remoteObserver.remoteUrl
        do {
            let url = remoteUrl.appendingPathComponent("push/\(metric.id)")
            var request = URLRequest(url: url)
            request.setValue(remoteObserver.authenticationToken.base64, forHTTPHeaderField: "token")
            let (_, response) = try await urlSessionData(.shared, for: request)
            guard let response = response as? HTTPURLResponse else {
                log("Invalid response pushing value to \(remoteUrl.path): \(response)", for: metric.id)
                return
            }
            guard response.statusCode == 200 else {
                log("Failed to push value to \(remoteUrl.path): Response \(response.statusCode)", for: metric.id)
                return
            }
        } catch {
            log("Failed to push value to \(remoteUrl.path): \(error)", for: metric.id)
        }
    }

    // MARK: Routes

    func getListOfRecordedMetrics() -> [MetricDescription] {
        observedMetrics.values.map { $0.description }
    }

    func getDataOfRecordedMetricsList() throws -> Data {
        let list = getListOfRecordedMetrics()
        return try encode(list)
    }

    private func getLastValuesOfAllMetrics() async -> [String : Data] {
        var result = [String : Data]()
        for (id, metric) in observedMetrics {
            result[id] = await metric.lastValueData()
        }
        return result
    }

    func getDataOfLastValuesForAllMetrics() async throws -> Data {
        let values = await getLastValuesOfAllMetrics()
        return try encode(values)
    }

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            log("Failed to encode response: \(error)")
            throw MetricError.failedToEncode
        }
    }

#if canImport(Logging)

    /**
     The logging format to use when using the observer as a logging backend.

     The format determines the detail with which log messages are converted to text when being stored in a metric.
     The logging format is applied to any new `Logger` created with the backend.
     The format can be changed without affecting previously created `Logger`s.

     Default: `.basic`
     */
    public var loggingFormat: LogOutputFormat = .basic
#endif
}

extension MetricObserver: Equatable {

    public static func == (lhs: MetricObserver, rhs: MetricObserver) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
}
