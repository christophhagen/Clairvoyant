import Foundation

public protocol MetricAccessTokenProvider: MetricRequestAccessProvider {

    var accessToken: Data { get }
}

extension MetricAccessTokenProvider {

    public func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest) {
        metricRequest.addValue(accessToken.base64EncodedString(), forHTTPHeaderField: "token")
    }
}
