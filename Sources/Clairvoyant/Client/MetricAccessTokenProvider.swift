import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 A generic protocol to provide an access token for outgoing requests of a `MetricConsumer`.
 */
public protocol MetricAccessTokenProvider: MetricRequestAccessProvider {

    /// A base64 encoded string of the access token
    var base64: String { get }
}

extension MetricAccessTokenProvider {

    public func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest, route: ServerRoute) {
        metricRequest.addValue(base64, forHTTPHeaderField: ServerRoute.headerAccessToken)
    }
}
