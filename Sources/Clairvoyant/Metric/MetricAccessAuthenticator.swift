import Foundation

public protocol MetricAccessAuthenticator {

    func metricListAccess(isAllowedForToken accessToken: Data) -> Bool

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: Data) -> Bool
}
