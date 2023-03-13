#if canImport(Vapor)
import Foundation
import Vapor

extension MetricObserver {

    private static let hashParameterName = "hash"

    private var hashParameterName: String {
        MetricObserver.hashParameterName
    }

    func getAccessibleMetric(_ request: Request) throws -> AbstractMetric {
        guard let metricIdHash = request.parameters.get(hashParameterName, as: String.self) else {
            throw Abort(.badRequest)
        }
        let metric = try getMetric(with: metricIdHash)
        try accessManager.metricAccess(to: metric.id, isAllowedForRequest: request)
        return metric
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
            return try self.getDataOfRecordedMetricsList()
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

            let metric = try self.getAccessibleMetric(request)

            guard let data = await metric.lastValueData() else {
                throw MetricError.noValueAvailable
            }
            return data
        }

        app.post(subPath, "history", .parameter(hashParameterName)) { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let metric = try self.getAccessibleMetric(request)
            let range = try request.decodeBody(as: MetricHistoryRequest.self)
            return await metric.history(from: range.start, to: range.end, maximumValueCount: range.limit)
        }

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
            try await metric.update(valueData)
        }
    }
}

#endif
