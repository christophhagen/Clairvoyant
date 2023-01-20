import Foundation
import Vapor

public protocol MetricAccessManager: MetricRequestAccessManager {

    func metricListAccess(isAllowedForToken accessToken: AccessToken) throws

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: AccessToken) throws
}

public extension MetricAccessManager {

    func metricListAccess(isAllowedForRequest request: Request) throws {
        let accessToken = try request.token()
        try metricListAccess(isAllowedForToken: accessToken)
    }

    func metricAccess(to metric: MetricId, isAllowedForRequest request: Request) throws {
        let accessToken = try request.token()
        try metricAccess(to: metric, isAllowedForToken: accessToken)
    }
}
