import Foundation
import CBORCoding
import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MetricObserver {

    private let hashParameterName = "hash"

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
        accessManager: MetricRequestAccessManager,
        logMetricId: String,
        logMetricName: String? = nil,
        logMetricDescription: String? = nil,
        encoder: BinaryEncoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970),
        decoder: BinaryDecoder = CBORDecoder()) async {

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
            try! observe(logMetric)
    }

    // MARK: Adding metrics

    /**
     Create a metric and add it to the observer.
     - Parameter id: The id of the metric.
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     - Returns: The created metric.
     */
    public func addMetric<T>(id: String, name: String? = nil, description: String? = nil, canBeUpdatedByRemote: Bool = false) async throws -> Metric<T> where T: MetricValue {
        let metric = Metric<T>(
            id: id,
            observer: self,
            canBeUpdatedByRemote: canBeUpdatedByRemote,
            name: name, description: description)
        try observe(metric)
        return metric
    }

    func observe(_ metric: AbstractMetric) throws {
        guard observedMetrics[metric.idHash] == nil else {
            throw MetricError.badMetricId
        }
        observedMetrics[metric.idHash] = metric
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

    private func getMetric(with idHash: MetricIdHash) throws -> AbstractMetric {
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

    func pushValueToRemoteObservers(_ data: TimestampedValueData, for metric: AbstractMetric) {
        guard let observers = remoteObservers[metric.idHash] else {
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

    private func getDataOfRecordedMetricsList() throws -> Data {
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

    private func getDataOfLastValuesForAllMetrics() async throws -> Data {
        let values = await getLastValuesOfAllMetrics()
        return try encode(values)
    }

    private func getAccessibleMetric(_ request: Request) throws -> AbstractMetric {
        guard let metricIdHash = request.parameters.get(hashParameterName, as: String.self) else {
            throw Abort(.badRequest)
        }
        let metric = try getMetric(with: metricIdHash)
        try accessManager.metricAccess(to: metric.id, isAllowedForRequest: request)
        return metric
    }

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            log("Failed to encode response: \(error)")
            throw MetricError.failedToEncode
        }
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
            return try await self.getDataOfRecordedMetricsList()
        }

        app.post(subPath, "last", "all") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricListAccess(isAllowedForRequest: request)
            return try await self.getDataOfLastValuesForAllMetrics()
        }

        app.post(subPath, "last", .parameter(hashParameterName)) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try await self.getAccessibleMetric(request)

            guard let data = await metric.lastValueData() else {
                throw MetricError.noValueAvailable
            }
            return data
        }

        app.post(subPath, "history", .parameter(hashParameterName)) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try await self.getAccessibleMetric(request)
            let range = try request.decodeBody(as: MetricHistoryRequest.self)
            return await metric.history(from: range.start, to: range.end, maximumValueCount: range.limit)
        }

        app.post(subPath, "push", .parameter(hashParameterName)) { [weak self] request -> Void in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try await self.getAccessibleMetric(request)
            guard metric.canBeUpdatedByRemote else {
                throw Abort(.expectationFailed)
            }

            guard let valueData = request.body.data?.all() else {
                throw Abort(.badRequest)
            }

            // Save value for metric
            try await metric.update(valueData)
        }
    }
}

extension MetricObserver: Equatable {

    public static func == (lhs: MetricObserver, rhs: MetricObserver) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
}
