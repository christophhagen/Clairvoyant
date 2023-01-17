import Foundation

public protocol MetricAccessAuthenticator {

    func metricAccess(isAllowedForToken accessToken: Data) -> Bool
}
