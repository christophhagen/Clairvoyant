import Foundation
import Vapor
import Clairvoyant

public final class VaporMetricProvider {

    private let hashParameterName = "hash"

    /// The authentication manager for access to metric information
    public let accessManager: MetricRequestAccessManager

    /// The metric observer exposed through vapor
    public let observer: MetricObserver

    /// The encoder to use for the response data.
    public let encoder: BinaryEncoder

    /// The encoder to use for the request body decoding.
    public let decoder: BinaryDecoder

    /**
     - Parameter observer: The metric observer to expose through vapor
     - Parameter accessManager: The handler of authentication to access metric data
     - Parameter encoder: The encoder to use for the response data. Defaults to the encoder of the observer
     - Parameter decoder: The decoder to use for the request body decoding. Defaults to the decoder of the observer
     */
    public init(observer: MetricObserver, accessManager: MetricRequestAccessManager, encoder: BinaryEncoder? = nil, decoder: BinaryDecoder? = nil) {
        self.accessManager = accessManager
        self.observer = observer
        self.encoder = encoder ?? observer.encoder
        self.decoder = decoder ?? observer.decoder
    }

    func getAccessibleMetric(_ request: Request) throws -> GenericMetric {
        guard let metricIdHash = request.parameters.get(hashParameterName, as: String.self) else {
            throw Abort(.badRequest)
        }
        let metric = try observer.getMetricByHash(metricIdHash)
        try accessManager.metricAccess(to: metric.id, isAllowedForRequest: request)
        return metric
    }

    private func getDataOfRecordedMetricsList() throws -> Data {
        let list = observer.getListOfRecordedMetrics()
        return try encode(list)
    }

    private func getDataOfLastValuesForAllMetrics() async throws -> Data {
        let values = await observer.getLastValuesOfAllMetrics()
        return try encode(values)
    }

    private func encode<T>(_ result: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(result)
        } catch {
            observer.log("Failed to encode response: \(error)")
            throw MetricError.failedToEncode
        }
    }

    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "metrics") {
        registerMetricListRoute(app, subPath: subPath)
        registerLastValueCollectionRoute(app, subPath: subPath)
        registerLastValueRoute(app, subPath: subPath)
        registerHistoryRoute(app, subPath: subPath)
        registerRemotePushRoute(app, subPath: subPath)
    }

    /**
     The route to access the list of registered metrics.

     - Type: `POST`
     - Path: `/metrics/list`
     - Headers:
        - `token` : The access token for the client
     - Response: `[MetricDescription]`
     */
    func registerMetricListRoute(_ app: Application, subPath: String) {
        app.post(subPath, "list") { [weak self] request async throws in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricListAccess(isAllowedForRequest: request)
            return try self.getDataOfRecordedMetricsList()
        }
    }

    /**
     The route to access the last values of all metrics.

     - Type: `POST`
     - Path: `/metrics/last/all`
     - Headers:
        - `token` : The access token for the client
     - Response: `[String : Data]`, a mapping between ID hash and encoded timestamped value.
     */
    func registerLastValueCollectionRoute(_ app: Application, subPath: String) {
        app.post(subPath, "last", "all") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            try self.accessManager.metricListAccess(isAllowedForRequest: request)
            return try await self.getDataOfLastValuesForAllMetrics()
        }
    }

    /**
     The route to access the last value of a metric.

     - Type: `POST`
     - Path: `/metrics/last/<ID_HASH>`
     - Headers:
        - `token` : The access token for the client
     - Response: `Timestamped<T>`, the encoded timestamped value.
     - Errors: `410`, if no value is available
     */
    func registerLastValueRoute(_ app: Application, subPath: String) {
        app.post(subPath, "last", .parameter(hashParameterName)) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)

            guard let data = await metric.lastValueData() else {
                throw MetricError.noValueAvailable
            }
            return data
        }
    }

    /**
     The route to access historic values of a metric.

     - Type: `POST`
     - Path: `/metrics/history/<ID_HASH>`
     - Headers:
        - `token` : The access token for the client
     - Body: `MetricHistoryRequest`
     - Response: `[Timestamped<T>]`, the encoded timestamped values.
     */
    func registerHistoryRoute(_ app: Application, subPath: String) {
        app.post(subPath, "history", .parameter(hashParameterName)) { [weak self] request -> Data in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)
            let range = try request.decodeBody(as: MetricHistoryRequest.self, using: self.decoder)
            return await metric.encodedHistoryData(from: range.start, to: range.end, maximumValueCount: range.limit)
        }
    }

    /**
     The route to update a metric from a remote.

     - Type: `POST`
     - Path: `/metrics/push/<ID_HASH>`
     - Headers:
        - `token` : The access token for the client
     - Body: `[Timestamped<T>]`
     */
    func registerRemotePushRoute(_ app: Application, subPath: String) {
        app.post(subPath, "push", .parameter(hashParameterName)) { [weak self] request -> Void in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)
            guard metric.canBeUpdatedByRemote else {
                throw Abort(.expectationFailed)
            }

            guard let valueData = request.body.data?.all() else {
                throw Abort(.badRequest)
            }

            // Save value for metric
            try await metric.addDataFromRemote(valueData)
        }
    }
}
