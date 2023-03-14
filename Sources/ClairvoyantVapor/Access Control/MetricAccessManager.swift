import Foundation
import Vapor
import Clairvoyant

/**
 A protocol that can be implemented to control access to metrics via binary access tokens.

 Using a `MetricAccessManager` over a `MetricRequestAccessManager` requires the
 existence of a "`token`" header in each request containing the access token as base64 encoded data.

 On the client side, the `MetricAccessTokenProvider` protocol can be used to ensure compatibility.

 First, implement your own version of access control.

 ```
 struct MyAccessTokenManager: MetricAccessManager {

    func metricListAccess(isAllowedForToken accessToken: MetricAccessToken) throws {
        ...
    }

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: MetricAccessToken) throws {
        ...
    }
 }
 ```

 Then you can use the manager to protect access to metrics.

 ```
 let manager = MyAccessTokenManager(...)
 let observer = MetricObserver(logFolder: ..., accessManager: manager, logMetricId: ...)
 ```
 */
public protocol MetricAccessManager: MetricRequestAccessManager {

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter token: The access token provided in the request.
     - Throws: `MetricError.accessDenied`
     */
    func metricListAccess(isAllowedForToken accessToken: MetricAccessToken) throws

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter metric: The id of the metric for which access is requested.
     - Parameter token: The access token provided in the request.
     - Throws: `MetricError.accessDenied`
     */
    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: MetricAccessToken) throws
}

public extension MetricAccessManager {

    func metricListAccess(isAllowedForRequest request: Request) throws {
        let accessToken = try request.token()
        try metricListAccess(isAllowedForToken: .init(accessToken: accessToken))
    }

    func metricAccess(to metric: MetricId, isAllowedForRequest request: Request) throws {
        let accessToken = try request.token()
        try metricAccess(to: metric, isAllowedForToken: .init(accessToken: accessToken))
    }
}
